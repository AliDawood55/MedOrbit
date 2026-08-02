"""
Virtual Doctor — interview planners.

One decision per turn: given everything known about a consultation, what does
the doctor say next, and is the interview finished? Two implementations sit
behind one interface:

  StaticPlanner  the original JSON-flow slot machine, moved here verbatim.
                 Deterministic, instant, and the fallback for everything.
  LLMPlanner     asks a small local model for the next question, grounded in
                 the RAG passages retrieved for this turn.

WHY AN INTERFACE RATHER THAN A REWRITE
--------------------------------------
The static flow is not legacy to be deleted — it is the safety net. Any LLM
failure (timeout, malformed JSON, wrong language, an off-vocabulary complaint)
falls back to it *for that turn*, so a consultation degrades to the old
behaviour instead of breaking. That is only possible if both live behind the
same contract.

WHAT PLANNERS DO NOT DO
-----------------------
  * They never see a turn that MedicalSafetyLayer flagged. interview_engine
    runs the safety check first and short-circuits before any planner is
    consulted, so no model output can suppress a red flag.
  * They never decide urgency or specialty. Those stay with the DB-backed
    rule engine in reasoning.py, which owns the specialty foreign key.
  * They never write to the database. They return a description of what
    changed and the engine persists it.

Intake (name, then age) is deliberately NOT delegated to a model in either
planner: regex extraction is instant, deterministic and already handles Arabic
numerals and spelled-out ages. An LLM there would add seconds per turn and a
language-drift risk for no benefit.
"""

from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import requests

from . import retrieval

logger = logging.getLogger("medorbit-ai.virtual_doctor.planner")

# Which planner the engine uses. The dynamic planner is now the default — the
# static flow is demoted to the emergency fallback it was always meant to
# become. Set VD_PLANNER=static to pin the old deterministic behaviour, which
# is also exactly what every consultation degrades to if Ollama is unreachable.
PLANNER_NAME = os.environ.get("VD_PLANNER", "llm").strip().lower()

# The per-turn planner is deliberately NOT the diagnosis model. qwen2:7b is
# 4.4GB and does not fit a 4GB card (it partially offloads and costs ~5s a
# call); a 3B model fits alongside Whisper and answers in a fraction of that.
# reasoning.py keeps qwen2:7b for the single final differential, where one
# slower, stronger pass is worth paying for.
PLANNER_MODEL = os.environ.get("VD_PLANNER_MODEL", "qwen2.5:3b")

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
PLANNER_CHAT_URL = os.environ.get(
    "OLLAMA_CHAT_URL", OLLAMA_URL.replace("/api/generate", "/api/chat")
)
PLANNER_TIMEOUT = float(os.environ.get("VD_PLANNER_TIMEOUT", "25"))
PLANNER_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "1h")

# Hard stop on CLINICAL questions (intake excluded). A JSON flow cannot run
# away — it has N slots and then it is done. A model can, and qwen2.5:3b
# observably does: left to itself it kept interviewing past turn 8 and asked
# "does the pain happen while sleeping?" three times in a row.
#
# 6 is roughly what the static flows ask (3-4 slots) plus room for the planner
# to follow a thread, and it keeps a voice consultation to a sane length.
MAX_INTERVIEW_TURNS = int(os.environ.get("VD_PLANNER_MAX_TURNS", "6"))

# A question is "already asked" if it normalises identically or overlaps this
# much by token. Small models re-ask with trivial rewording, which the prompt
# instruction alone does not prevent.
# 0.6, not 0.7: observed "ما إذا كان الألم يزداد عند الاستلقاء أو الجلوس؟" followed
# by "هل الألم يزداد عند الاستلقاء أو الجلوس؟" — the same question with a different
# interrogative — scoring exactly 0.60 and slipping through a 0.7 gate. A false
# positive here only costs one static fallback question, so erring tight is
# cheap; a false negative is a visibly repetitive doctor.
_REPEAT_SIMILARITY = float(os.environ.get("VD_PLANNER_REPEAT_SIMILARITY", "0.6"))

# Natural termination, not the turn cap. Root-caused by direct A/B probing
# (5 runs per variant, same underlying facts throughout):
#
#   ALREADY ESTABLISHED: {...4 findings...} + abstract rule text   -> ready 0/5
#   the SAME facts + one explicit sentence "you now have a complete
#   picture, this is enough for a preliminary assessment"          -> ready 5/5
#
# A 3B model does not reliably infer "I have enough" from a JSON dict plus an
# abstract instruction — it needs to be told, in a sentence, that the picture
# is complete. Wording the turn-limit line as a "backstop, not a target" was
# tested too and made no measurable difference (4/5 vs 5/5) — the limit framing
# was never the blocker, the missing narrative cue was.
#
# So termination is now driven by two independent things:
#   1. This nudge: once COMPLETENESS_MIN_FINDINGS distinct findings exist (and
#      at least COMPLETENESS_MIN_TURNS clinical questions have been asked, so a
#      lucky first answer can't end the interview instantly), the prompt states
#      outright that the picture looks complete and invites the model to stop.
#      The model still decides — it can ask one more if it judges that
#      necessary — so this encourages rather than forces.
#   2. MAX_INTERVIEW_TURNS: the hard, code-enforced backstop for whatever the
#      nudge does not catch (an unusual complaint, a model that keeps
#      declining). This never depended on the model at all and is unchanged.
COMPLETENESS_MIN_FINDINGS = int(os.environ.get("VD_PLANNER_COMPLETENESS_MIN_FINDINGS", "3"))
COMPLETENESS_MIN_TURNS = int(os.environ.get("VD_PLANNER_COMPLETENESS_MIN_TURNS", "2"))

# Findings are clamped to this vocabulary before they are stored. The PDF's
# _SLOT_LABELS and the frontend's profile panel both render by key, so an
# invented key would degrade to a raw identifier in the report. Anything the
# model reports outside this set is kept, but namespaced under "other".
KNOWN_FINDING_KEYS = {
    "duration", "severity", "location", "location_character", "character",
    "radiation", "triggers", "appearance", "exposure", "associated_symptoms",
}

# The planner may only ever choose a complaint the rest of the system knows:
# the flows, the RAG anchors and the VARCHAR(100) column all assume these.
CANONICAL_COMPLAINTS = set(retrieval.COMPLAINT_ANCHORS)


# ---------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------

@dataclass
class PlannerInput:
    """Everything a planner may look at. Read-only."""
    message: str
    lang: str
    phase: str
    chief_complaint: Optional[str]
    profile: Dict[str, Any]
    entities: Dict[str, Any]
    history: List[Dict[str, str]] = field(default_factory=list)
    chunks: List[Dict[str, Any]] = field(default_factory=list)
    context_block: str = ""
    # Doctor turns so far, counted over the WHOLE transcript rather than the
    # memory window — see memory.doctor_turns for why that distinction is
    # load-bearing for the turn cap.
    turn_index: int = 0
    asked_questions: List[str] = field(default_factory=list)


@dataclass
class PlannerResult:
    """What the engine should do with this turn."""
    reply: Optional[str]                                   # None when ready
    phase: str
    profile_updates: Dict[str, Any] = field(default_factory=dict)
    chief_complaint: Optional[str] = None
    ready_for_diagnosis: bool = False
    source: str = "static"                                 # for logging/telemetry


class PlannerError(Exception):
    """The planner could not produce a usable turn; the caller must fall back."""


# ---------------------------------------------------------------------------
# Shared intake (identity questions, deterministic in both planners)
# ---------------------------------------------------------------------------

def _intake_turn(ctx: PlannerInput, texts: Dict[str, Dict[str, str]],
                 extract_name, extract_age) -> Optional[PlannerResult]:
    """Handle name/age. Returns None once intake is finished."""
    if ctx.phase != "intake":
        return None
    updates: Dict[str, Any] = {}
    if not ctx.profile.get("name"):
        updates["name"] = extract_name(ctx.message)
        return PlannerResult(
            reply=texts["ASK_AGE"][ctx.lang].format(name=updates["name"]),
            phase="intake", profile_updates=updates, source="intake",
        )
    age = extract_age(ctx.message)
    if age is None:
        # Re-ask rather than store a bad value; the patient stays in intake.
        return PlannerResult(reply=texts["ASK_AGE_RETRY"][ctx.lang], phase="intake",
                             source="intake")
    updates["age"] = age
    return PlannerResult(
        reply=texts["ASK_COMPLAINT"][ctx.lang], phase="greeting",
        profile_updates=updates, source="intake",
    )


# ---------------------------------------------------------------------------
# StaticPlanner — the JSON flow, unchanged
# ---------------------------------------------------------------------------

class StaticPlanner:
    """The original slot machine. Behaviour is intentionally identical to the
    pre-planner implementation: same slot order, same questions, same phase
    transitions, same wrap-up."""

    name = "static"

    def __init__(self, flows, texts, helpers):
        self._flows = flows
        self._texts = texts
        self._h = helpers  # detect_chief_complaint, next_unfilled_slot, extract_name/age

    def _flow(self, complaint: Optional[str]) -> dict:
        return self._flows.get(complaint or "generic", self._flows["generic"])

    async def plan(self, ctx: PlannerInput) -> PlannerResult:
        intake = _intake_turn(ctx, self._texts, self._h["extract_name"], self._h["extract_age"])
        if intake is not None:
            return intake

        updates: Dict[str, Any] = {}
        complaint = ctx.chief_complaint
        phase = ctx.phase

        if phase == "greeting":
            complaint = self._h["detect_chief_complaint"](ctx.entities)
            phase = "interviewing"
            updates["chief_complaint_description"] = ctx.message
            if ctx.entities.get("symptoms"):
                updates["associated_symptoms_detected"] = list(ctx.entities["symptoms"])
        elif phase == "interviewing":
            merged = {**ctx.profile, **updates}
            slot = self._h["next_unfilled_slot"](self._flow(complaint), merged)
            if slot:
                updates[slot["key"]] = ctx.message
            if ctx.entities.get("symptoms"):
                detected = set(ctx.profile.get("associated_symptoms_detected", []))
                detected.update(ctx.entities["symptoms"])
                updates["associated_symptoms_detected"] = list(detected)
        else:
            # Already 'reasoning' or 'complete' — nothing left to fill.
            return PlannerResult(reply=self._texts["WRAP_UP"][ctx.lang], phase=phase,
                                 source=self.name)

        merged = {**ctx.profile, **updates}
        nxt = self._h["next_unfilled_slot"](self._flow(complaint), merged)
        if nxt:
            return PlannerResult(
                reply=nxt[f"question_{ctx.lang}"], phase="interviewing",
                profile_updates=updates, chief_complaint=complaint, source=self.name,
            )
        return PlannerResult(
            reply=None, phase="interviewing", profile_updates=updates,
            chief_complaint=complaint, ready_for_diagnosis=True, source=self.name,
        )


# ---------------------------------------------------------------------------
# LLMPlanner — dynamic questioning grounded in retrieved context
# ---------------------------------------------------------------------------

_SYSTEM = {
    "en": (
        "You are a medical AI conducting a patient interview. "
        "Base every question on the provided Medical Context and the conversation so far. "
        "Do not hallucinate information outside the context. "
        "Ask exactly ONE short question at a time, in English only, using Latin script only. "
        "Do not use Chinese, Japanese, Korean, Arabic or any other script. "
        "Return only a valid JSON object, with no text outside the JSON and no markdown."
    ),
    "ar": (
        "أنت ذكاء اصطناعي طبي يجري مقابلة مع مريض. "
        "اعتمد في كل سؤال على السياق الطبي المزوّد وعلى سياق المحادثة. "
        "لا تختلق أي معلومات خارج هذا السياق. "
        "اطرح سؤالاً واحداً قصيراً فقط في كل مرة، باللغة العربية فقط وبالحروف العربية فقط. "
        "ممنوع استخدام أي حروف صينية أو يابانية أو كورية أو لاتينية. "
        "أعد فقط كائن JSON صالح، بدون أي نص خارج الـ JSON وبدون علامات markdown."
    ),
}

# A DEDICATED, minimal call for the readiness decision — not folded into the
# main question-asking call above. Root-caused via direct A/B (repeated 5-6x
# per variant, same underlying facts throughout):
#
#   minimal 2-field schema (next_question + ready_for_diagnosis)   ready 6/6
#   + a "chief_complaint" field                                    ready 0/6
#   + a "findings" field + the Rules block                         ready 0/6
#   + chief_complaint AND Rules together                           ready 0/6
#
# Each addition ALONE was enough to collapse readiness to 0/6, even with the
# exact same underlying facts and the exact same completeness cue that gets
# 6/6 in isolation. A 3B model's readiness judgement does not survive sharing
# a call with question-generation, finding-extraction and complaint selection
# — there is not enough of it left once those compete for the same output.
# Splitting the decision into this small, separate call is what makes it
# trustworthy: 8/8 on genuinely sufficient info, 5/5-15/15 declining on sparse
# info across several probes, discrimination confirmed in both directions —
# not a degenerate always-true shortcut.
#
# Reuses _SYSTEM (the existing, already-proven persona) rather than a fresh
# system message. A purpose-written minimal system prompt was tried first and
# measured WORSE (1/8) than the unrelated production _SYSTEM['ar'] (8/8) on
# the identical user content — evidently what matters here is which system
# prompt the model responds to reliably at all, not lexical relevance to the
# readiness task specifically.
_READINESS_USER = {
    "en": (
        "Information collected so far: {summary}\n\n"
        'Return ONLY this JSON object:\n{{"ready": <true or false>}}\n'
        'Set "ready" to true if this is generally enough for a preliminary '
        "differential diagnosis (most complaints need: duration, "
        "character/severity, and at least one more sign such as radiation, "
        "triggers, or associated symptoms). Otherwise false."
    ),
    "ar": (
        "المعلومات التي تم جمعها حتى الآن: {summary}\n\n"
        'أعد فقط كائن JSON التالي:\n{{"ready": <true أو false>}}\n'
        'اجعل "ready" تساوي true إذا كانت هذه المعلومات كافية عموماً لتقييم '
        "تفريقي أولي (تحتاج معظم الشكاوى: المدة، والشدة أو الطبيعة، وعلامة "
        "واحدة إضافية على الأقل مثل الانتشار أو المحفزات أو الأعراض المرافقة). "
        "وإلا فاجعلها false."
    ),
}


def _known_summary(profile: Dict[str, Any]) -> Dict[str, str]:
    """Every clinical fact captured so far, as {key: readable value}.

    Was `isinstance(v, str)` only inside _ask() itself, which silently dropped
    every list-typed field — in particular associated_symptoms_detected,
    populated by the entity extractor rather than the planner. The model then
    had no way to know a symptom was already captured and kept re-asking about
    it (observed: "do you have nausea?" after the patient had already said "no
    nausea" and it was sitting, unseen, in the profile). Shared by _ask()
    (what to show the model) and the readiness gate (whether there is enough
    to evaluate) so the two can never disagree about what is "known".
    """
    known: Dict[str, str] = {}
    for key, value in profile.items():
        if key in ("chief_complaint_description", "other"):
            continue
        if isinstance(value, str) and value.strip():
            known[key] = value
        elif isinstance(value, list) and value:
            known[key] = ", ".join(str(v) for v in value)
    for key, value in (profile.get("other") or {}).items():
        if isinstance(value, str) and value.strip():
            known[key] = value
    return known


class LLMPlanner:
    """Asks a small local model for the next question.

    Every failure mode raises PlannerError so the engine can fall back to the
    static flow for that turn: a timeout, unparseable JSON, an empty question,
    a question in the wrong script, or incoherent output.
    """

    name = "llm"

    def __init__(self, texts, helpers, validators):
        self._texts = texts
        self._h = helpers
        self._v = validators  # text_matches_language, looks_coherent

    async def plan(self, ctx: PlannerInput) -> PlannerResult:
        intake = _intake_turn(ctx, self._texts, self._h["extract_name"], self._h["extract_age"])
        if intake is not None:
            return intake

        # The backstop that a JSON flow gets for free.
        if ctx.turn_index >= MAX_INTERVIEW_TURNS:
            logger.info("Planner hit the %d-turn cap — forcing diagnosis", MAX_INTERVIEW_TURNS)
            return PlannerResult(
                reply=None, phase="interviewing",
                profile_updates=self._store_answer(ctx, {}),
                chief_complaint=ctx.chief_complaint or "generic",
                ready_for_diagnosis=True, source=f"{self.name}:turn-cap",
            )

        parsed = self._ask(ctx)
        complaint = self._clamp_complaint(parsed.get("chief_complaint"), ctx)
        updates = self._store_answer(ctx, parsed.get("findings") or {})

        # Readiness is decided by a SEPARATE, minimal call — see _READINESS_*
        # above for why folding it into the call that also asks/extracts/
        # classifies collapses its reliability to 0/6. Gated on the merged,
        # post-this-turn state (ctx.profile + what was just extracted), so a
        # finding reported in the SAME turn that crosses the threshold counts
        # immediately rather than one turn late.
        merged_known = _known_summary({**ctx.profile, **updates})
        if (len(merged_known) >= COMPLETENESS_MIN_FINDINGS
                and ctx.turn_index >= COMPLETENESS_MIN_TURNS
                and self._check_readiness(ctx, merged_known)):
            return PlannerResult(
                reply=None, phase="interviewing", profile_updates=updates,
                chief_complaint=complaint, ready_for_diagnosis=True, source=self.name,
            )

        question = (parsed.get("next_question") or "").strip()

        if not question:
            raise PlannerError("planner returned no question")

        question = _first_question_only(question)
        if _is_repeat(question, ctx.asked_questions, ctx.lang):
            # Deterministic guard, not a prompt plea. Falling back hands this
            # turn to the static flow, which always advances to an unfilled
            # slot — so a repetitive model cannot stall the interview.
            raise PlannerError("planner repeated a question it had already asked")

        if not self._v["text_matches_language"](question, ctx.lang):
            raise PlannerError(f"question failed the {ctx.lang} script check")
        if not self._v["looks_coherent"](question, ctx.lang):
            raise PlannerError("question did not look like coherent language")

        return PlannerResult(
            reply=question, phase="interviewing", profile_updates=updates,
            chief_complaint=complaint, source=self.name,
        )

    # -- helpers ------------------------------------------------------------

    def _clamp_complaint(self, proposed: Any, ctx: PlannerInput) -> str:
        """Never let a model invent a complaint the rest of the system cannot use."""
        if isinstance(proposed, str):
            candidate = proposed.strip().lower().replace(" ", "_").replace("-", "_")
            if candidate in CANONICAL_COMPLAINTS:
                return candidate
            if proposed.strip():
                logger.info("Planner proposed off-vocabulary complaint %r — clamped", proposed)
        return ctx.chief_complaint or "generic"

    def _store_answer(self, ctx: PlannerInput, findings: Any) -> Dict[str, Any]:
        """Merge the model's extracted findings, keeping the report's vocabulary.

        The patient's raw answer is always recorded too — the report and the
        final differential are built from the profile, so a turn must never be
        lost just because the model declined to label it.
        """
        updates: Dict[str, Any] = {}
        if ctx.phase == "greeting" and not ctx.profile.get("chief_complaint_description"):
            updates["chief_complaint_description"] = ctx.message

        if isinstance(findings, dict):
            extras: Dict[str, Any] = dict(ctx.profile.get("other") or {})
            for key, value in findings.items():
                if not isinstance(value, str) or not value.strip():
                    continue
                slug = str(key).strip().lower().replace(" ", "_").replace("-", "_")
                if slug in KNOWN_FINDING_KEYS:
                    updates[slug] = value.strip()
                elif slug not in ("name", "age"):
                    extras[slug] = value.strip()
            if extras:
                updates["other"] = extras

        if ctx.entities.get("symptoms"):
            detected = set(ctx.profile.get("associated_symptoms_detected", []))
            detected.update(ctx.entities["symptoms"])
            updates["associated_symptoms_detected"] = list(detected)
        return updates

    def _ask(self, ctx: PlannerInput) -> Dict[str, Any]:
        known = _known_summary(ctx.profile)
        language_name = "Arabic" if ctx.lang == "ar" else "English"
        transcript = "\n".join(
            f"{'Patient' if m['role'] == 'patient' else 'Doctor'}: {m['text']}"
            for m in ctx.history
        )

        # Listed explicitly, not left implicit in the transcript: the transcript
        # is a truncated window, so once an interview runs long the earliest
        # questions drop out of it and a small model happily asks them again.
        # Observed doing exactly that — the same question four times in one
        # consultation — before this block existed.
        already_asked = "\n".join(f"- {q}" for q in ctx.asked_questions) or "- (none yet)"

        # No readiness field here — see _READINESS_* above for why. This call
        # has exactly one job: the next question, plus what the patient just
        # said. Readiness is a separate, dedicated call (_check_readiness).
        user = f"""{ctx.context_block}
CONVERSATION SO FAR:
{transcript}

QUESTIONS YOU HAVE ALREADY ASKED — do NOT ask any of these again, or anything
that means the same thing:
{already_asked}

ALREADY ESTABLISHED: {json.dumps(known, ensure_ascii=False) if known else "nothing yet"}
PATIENT'S LATEST ANSWER: {ctx.message}

Return ONLY this JSON object:
{{
  "chief_complaint": "one of: {', '.join(sorted(CANONICAL_COMPLAINTS))}",
  "findings": {{"<one of: {', '.join(sorted(KNOWN_FINDING_KEYS))}>": "<what the patient just told you>"}},
  "next_question": "<the single most useful next question, in {language_name}>"
}}

Rules:
- Put anything the patient just told you into "findings". Leave it {{}} if they said nothing new.
- Never repeat a question that has already been answered in ALREADY ESTABLISHED.
- Ask EXACTLY ONE question. Never combine two questions into one sentence.
- "next_question" must be one short sentence in {language_name}, addressed to the patient.
"""

        try:
            response = requests.post(
                PLANNER_CHAT_URL,
                json={
                    "model": PLANNER_MODEL,
                    "messages": [
                        {"role": "system", "content": _SYSTEM[ctx.lang]},
                        {"role": "user", "content": user},
                    ],
                    "stream": False,
                    "format": "json",
                    "keep_alive": PLANNER_KEEP_ALIVE,
                    "options": {"temperature": 0.3},
                },
                timeout=PLANNER_TIMEOUT,
            )
            response.raise_for_status()
            content = response.json().get("message", {}).get("content", "")
        except Exception as exc:  # noqa: BLE001
            raise PlannerError(f"planner call failed: {exc}") from exc

        parsed = _extract_json(content)
        if not isinstance(parsed, dict):
            raise PlannerError("planner returned unparseable JSON")
        return parsed

    def _check_readiness(self, ctx: PlannerInput, known: Dict[str, str]) -> bool:
        """Dedicated, minimal call: is this picture complete enough to stop?

        See _READINESS_* above for the A/B evidence behind splitting this out
        of _ask(). Failure (timeout, bad JSON, unreachable Ollama) resolves to
        False, not an exception — an unavailable readiness check should cost
        one extra question, never abort the turn the way a genuine PlannerError
        does elsewhere.
        """
        summary = ", ".join(k.replace("_", " ") for k in known)
        try:
            response = requests.post(
                PLANNER_CHAT_URL,
                json={
                    "model": PLANNER_MODEL,
                    "messages": [
                        {"role": "system", "content": _SYSTEM[ctx.lang]},
                        {"role": "user", "content": _READINESS_USER[ctx.lang].format(summary=summary)},
                    ],
                    "stream": False,
                    "format": "json",
                    "keep_alive": PLANNER_KEEP_ALIVE,
                    "options": {"temperature": 0.2},
                },
                timeout=PLANNER_TIMEOUT,
            )
            response.raise_for_status()
            content = response.json().get("message", {}).get("content", "")
        except Exception as exc:  # noqa: BLE001
            logger.info("Readiness check call failed (%s) — treating as not ready", exc)
            return False

        parsed = _extract_json(content)
        return bool(isinstance(parsed, dict) and parsed.get("ready"))


def _first_question_only(text: str) -> str:
    """Trim a compound reply down to its first question.

    The prompt asks for exactly one question and the model mostly complies, but
    it does occasionally staple two together ("When did it start? Was it before
    or after a meal?"). Truncating keeps the useful dynamic question instead of
    discarding the whole turn.
    """
    cleaned = " ".join((text or "").split())
    for mark in ("؟", "?"):
        first = cleaned.find(mark)
        if first != -1 and first + 1 < len(cleaned):
            trimmed = cleaned[:first + 1]
            # Only trim if something substantive actually followed.
            if len(cleaned) - len(trimmed) > 3:
                return trimmed
    return cleaned


def _is_repeat(question: str, asked: List[str], lang: str) -> bool:
    """Has this question already been asked, allowing for rewording?"""
    if not asked:
        return False
    norm = retrieval.normalize_utterance(question, lang)
    if not norm:
        return False
    tokens = set(norm.split())
    if not tokens:
        return False
    for prior in asked:
        prior_norm = retrieval.normalize_utterance(prior, lang)
        if not prior_norm:
            continue
        if prior_norm == norm:
            return True
        prior_tokens = set(prior_norm.split())
        if not prior_tokens:
            continue
        overlap = len(tokens & prior_tokens) / len(tokens | prior_tokens)
        if overlap >= _REPEAT_SIMILARITY:
            return True
    return False


def _extract_json(text: str) -> Optional[dict]:
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        pass
    match = re.search(r"\{.*\}", text or "", re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            return None
    return None


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

def warm() -> None:
    """Ask Ollama to load the planner model now, without blocking a caller.

    Measured: the first planner call of a session cost 7.48s against ~1.8s
    warm, because it included the model load. Firing this when the session
    starts moves that cost into the greeting, where nobody is waiting on it.
    Best-effort — a failure here is invisible and the first real call simply
    pays the load as before.
    """
    if PLANNER_NAME != "llm":
        return
    try:
        requests.post(
            PLANNER_CHAT_URL,
            json={"model": PLANNER_MODEL,
                  "messages": [{"role": "user", "content": "ok"}],
                  "stream": False, "keep_alive": PLANNER_KEEP_ALIVE,
                  "options": {"num_predict": 1}},
            timeout=PLANNER_TIMEOUT,
        )
    except Exception as exc:  # noqa: BLE001
        logger.info("Planner warm-up skipped (%s)", exc)


def build(flows, texts, helpers, validators):
    """Return (primary, fallback). The fallback is always the static flow."""
    static = StaticPlanner(flows, texts, helpers)
    if PLANNER_NAME == "llm":
        logger.info("Interview planner: LLM (%s), falling back to the static flow",
                    PLANNER_MODEL)
        return LLMPlanner(texts, helpers, validators), static
    if PLANNER_NAME != "static":
        logger.warning("Unknown VD_PLANNER=%r — using the static flow", PLANNER_NAME)
    else:
        logger.info("Interview planner: static JSON flow")
    return static, static
