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
  * They never decide severity, urgency, or whether to warn the patient. As
    of the Safety-Continuation Interview Mode batch, a turn MedicalSafetyLayer
    flagged as urgent/emergency still reaches the planner (the interview no
    longer hard-stops) — but only PlannerInput.safety_hint, a plain string
    describing what matched, is passed in, purely to nudge LLMPlanner toward
    a relevant question. The planner cannot see or influence the safety
    layer's severity decision, and interview_engine composes the warning text
    entirely outside any planner call — see interview_engine
    ._apply_safety_continuation().
  * They never decide urgency or specialty. Those stay with the DB-backed
    rule engine in reasoning.py, which owns the specialty foreign key, plus
    (for urgent/emergency reached mid-interview) the safety layer itself.
  * They never write to the database. They return a description of what
    changed and the engine persists it.

Intake (name, then age) is deliberately NOT delegated to a model in either
planner: regex extraction is instant, deterministic and already handles Arabic
numerals and spelled-out ages. An LLM there would add seconds per turn and a
language-drift risk for no benefit.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from dataclasses import dataclass, field, replace
from typing import Any, Dict, List, Optional

import requests

from . import retrieval
from .config import env_float, env_int

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
# exclusive_min=0: passed to requests(timeout=), which rejects <= 0.
PLANNER_TIMEOUT = env_float("VD_PLANNER_TIMEOUT", 25.0, minimum=0.0,
                            exclusive_min=True)
PLANNER_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "1h")

# Hard stop on CLINICAL questions (intake excluded). A JSON flow cannot run
# away — it has N slots and then it is done. A model can, and qwen2.5:3b
# observably does: left to itself it kept interviewing past turn 8 and asked
# "does the pain happen while sleeping?" three times in a row.
#
# 6 is roughly what the static flows ask (3-4 slots) plus room for the planner
# to follow a thread, and it keeps a voice consultation to a sane length.
# minimum=1: compared as `turn_index >= MAX_INTERVIEW_TURNS`, so 0 would
# force diagnosis before a single clinical question was asked.
MAX_INTERVIEW_TURNS = env_int("VD_PLANNER_MAX_TURNS", 6, minimum=1)

# A question is "already asked" if it normalises identically or overlaps this
# much by token. Small models re-ask with trivial rewording, which the prompt
# instruction alone does not prevent.
# 0.6, not 0.7: observed "ما إذا كان الألم يزداد عند الاستلقاء أو الجلوس؟" followed
# by "هل الألم يزداد عند الاستلقاء أو الجلوس؟" — the same question with a different
# interrogative — scoring exactly 0.60 and slipping through a 0.7 gate. A false
# positive here only costs one static fallback question, so erring tight is
# cheap; a false negative is a visibly repetitive doctor.
# Bounded to [0, 1]: compared against a token-overlap ratio whose codomain
# is exactly that. Outside it, repeat detection becomes a constant — and at
# the permissive end that silently disables it.
_REPEAT_SIMILARITY = env_float("VD_PLANNER_REPEAT_SIMILARITY", 0.6,
                               minimum=0.0, maximum=1.0)

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
# minimum=0 on both: zero is meaningful (the nudge applies immediately).
COMPLETENESS_MIN_FINDINGS = env_int("VD_PLANNER_COMPLETENESS_MIN_FINDINGS", 3, minimum=0)
COMPLETENESS_MIN_TURNS = env_int("VD_PLANNER_COMPLETENESS_MIN_TURNS", 2, minimum=0)

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

# Deterministic uncertainty/non-answer vocabulary. Matching is deliberately
# whole-utterance after the service's existing normalization: "not sure, but it
# is severe" still contains useful information and must not be erased merely
# because it includes an uncertainty phrase. Compact forms cover common Arabic
# ASR spacing differences ("ما بتذكر" / "مابتذكر") without fuzzy semantics.
_NON_ANSWER_SURFACES = (
    "لا أعرف", "ما بعرف", "مش عارف", "لا أعلم", "مش متأكد", "غير متأكد",
    "ما بتذكر", "لا أتذكر", "نسيت", "مش قادر أحدد", "ما بقدر أحدد", "يمكن",
    "مش متأكد شو أقول",
    "I don't know", "don't know", "not sure", "unsure", "I can't remember",
    "can't remember", "I don't recall", "no idea", "hard to say", "can't tell",
)


def _normalise_answer(text: object, lang: Optional[str] = None) -> str:
    if not isinstance(text, str):
        return ""
    effective_lang = lang or ("ar" if re.search(r"[\u0600-\u06ff]", text) else "en")
    normalised = retrieval.normalize_utterance(text, effective_lang)
    return normalised.strip(" .،,!?؟;:")


_NON_ANSWERS = frozenset(_normalise_answer(value) for value in _NON_ANSWER_SURFACES)
_NON_ANSWERS_COMPACT = frozenset(value.replace(" ", "") for value in _NON_ANSWERS)


def _is_non_answer(text: object, lang: Optional[str] = None) -> bool:
    """True only for a bounded, whole-utterance inability/uncertainty answer."""
    normalised = _normalise_answer(text, lang)
    if not normalised:
        return False
    return (
        normalised in _NON_ANSWERS
        or normalised.replace(" ", "") in _NON_ANSWERS_COMPACT
    )


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
    # Optional, deterministic-safety-layer-derived hint of what red-flag text
    # this turn matched (see interview_engine._safety_hint_text). Nudges
    # LLMPlanner toward asking about it next; never used to decide severity,
    # urgency, or whether to warn — that stays entirely in interview_engine's
    # _apply_safety_continuation(). None on every turn with no safety match,
    # and ignored entirely by StaticPlanner.
    safety_hint: Optional[str] = None
    # Phase 2: the canonical clinical TOPIC symbolic reasoning selected for this
    # turn (e.g. "radiation"), never a sentence. Set only in
    # VD_SYMBOLIC_INTERVIEW=active. When present, LLMPlanner may choose the
    # wording but not the subject: a question that drifts to another clinical
    # topic is replaced by the deterministic template for THIS topic.
    # None everywhere else, so every other mode builds a byte-identical prompt.
    required_topic: Optional[str] = None
    # Doctor turns so far, as canonical topics rather than question text.
    # Feeds asked/2. Empty unless the symbolic interview layer is running.
    asked_topics: List[str] = field(default_factory=list)
    # Public session id, for correlating symbolic facts and divergence logs
    # with a consultation. Never used as a clinical input.
    session_id: Optional[str] = None


@dataclass
class PlannerResult:
    """What the engine should do with this turn."""
    reply: Optional[str]                                   # None when ready
    phase: str
    profile_updates: Dict[str, Any] = field(default_factory=dict)
    chief_complaint: Optional[str] = None
    ready_for_diagnosis: bool = False
    source: str = "static"                                 # for logging/telemetry
    # False means extraction completed and profile_updates contains only the
    # accepted, fail-closed subset, but no model wording may reach a patient.
    # SymbolicPlanner can still use those updates to choose and template the
    # real post-turn topic. Non-symbolic callers retain the static fallback.
    wording_valid: bool = True


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

    Provider and parsing failures raise PlannerError so the engine can fall
    back to the static flow. Once extraction has produced a nonempty,
    fail-closed accepted update set, a later wording failure instead returns a
    typed result with ``wording_valid=False``; active symbolic mode can advance
    from those real updates while every other mode retains the same fallback.
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

        parsed = await self._ask(ctx)
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
                and await self._check_readiness(ctx, merged_known)):
            return PlannerResult(
                reply=None, phase="interviewing", profile_updates=updates,
                chief_complaint=complaint, ready_for_diagnosis=True, source=self.name,
            )

        question = (parsed.get("next_question") or "").strip()

        if not question:
            return self._wording_failure_result(
                ctx, updates, complaint, "planner returned no question")

        question = _first_question_only(question)
        if _is_repeat(question, ctx.asked_questions, ctx.lang):
            # Deterministic guard, not a prompt plea. Falling back hands this
            # turn to the static flow, which always advances to an unfilled
            # slot — so a repetitive model cannot stall the interview.
            return self._wording_failure_result(
                ctx, updates, complaint,
                "planner repeated a question it had already asked")

        if not self._v["text_matches_language"](question, ctx.lang):
            return self._wording_failure_result(
                ctx, updates, complaint,
                f"question failed the {ctx.lang} script check")
        if not self._v["looks_coherent"](question, ctx.lang):
            return self._wording_failure_result(
                ctx, updates, complaint,
                "question did not look like coherent language")

        return PlannerResult(
            reply=question, phase="interviewing", profile_updates=updates,
            chief_complaint=complaint, source=self.name,
        )

    # -- helpers ------------------------------------------------------------

    def _wording_failure_result(
        self, ctx: PlannerInput, updates: Dict[str, Any], complaint: str,
        reason: str,
    ) -> PlannerResult:
        """Carry accepted updates across a post-extraction wording failure.

        This helper is called only after `_ask()` parsed a JSON object and
        `_store_answer()` ran. It deliberately applies a second, fail-closed
        boundary for the partial-result path: only known clinical finding
        slots and deterministic non-LLM observations can survive. In
        particular, the successful-call `other` compatibility bucket is not
        promoted when there is no otherwise-valid planner turn.

        With no preservable update, retain the historical PlannerError
        contract. This keeps malformed/empty extraction indistinguishable from
        no accepted extraction and prevents a wording failure from inventing a
        partial success.
        """
        accepted = self._preservable_updates(updates)
        if not accepted:
            raise PlannerError(reason)
        logger.info(
            "Planner wording rejected after %d accepted update(s) (%s)",
            len(accepted), reason,
        )
        return PlannerResult(
            reply=None,
            phase="interviewing",
            profile_updates=accepted,
            chief_complaint=complaint,
            source=f"{self.name}:wording-invalid",
            wording_valid=False,
        )

    @staticmethod
    def _preservable_updates(updates: Dict[str, Any]) -> Dict[str, Any]:
        """Return the already-accepted subset safe without trusted wording."""
        accepted: Dict[str, Any] = {}
        for key in KNOWN_FINDING_KEYS:
            value = updates.get(key)
            if isinstance(value, str) and value.strip():
                accepted[key] = value

        description = updates.get("chief_complaint_description")
        if isinstance(description, str) and description.strip():
            accepted["chief_complaint_description"] = description

        detected = updates.get("associated_symptoms_detected")
        if (isinstance(detected, list)
                and all(isinstance(item, str) and item.strip() for item in detected)):
            accepted["associated_symptoms_detected"] = list(detected)
        return accepted

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

    async def _ask(self, ctx: PlannerInput) -> Dict[str, Any]:
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

        # Deterministic-safety-layer-derived, never LLM-derived: this only
        # ever nudges WHICH topic the next question covers. It cannot change
        # severity/urgency or suppress/alter the warning text, both of which
        # are composed entirely in interview_engine.py outside this call.
        safety_priority = (
            f"URGENT PRIORITY: the patient's answer may contain a red-flag symptom "
            f"(matched: {ctx.safety_hint}). Your next question MUST specifically "
            f"explore this red flag before anything else.\n\n"
            if ctx.safety_hint else ""
        )

        # Arabic conversation-style guidance (Virtual Doctor Formal Arabic
        # Voice Quality batch). Added HERE, in this per-turn user prompt,
        # deliberately NOT in _SYSTEM["ar"] above: that system prompt is
        # reused verbatim by _check_readiness() (see _READINESS_USER's own
        # comment — adding fields there measurably collapsed a different
        # call's reliability from 8/8 to 0/6). This block only ever reaches
        # the question-generation call, never readiness, so it carries none
        # of that documented regression risk.
        #
        # SUPERSEDES an earlier version of this same rule that explicitly
        # endorsed "a light Levantine/Palestinian tone" — the later, explicit
        # product decision was simplified formal Arabic (فصحى مبسطة) instead,
        # after the dialect phrasing itself drew the same "not real" feedback
        # the dialect pass was originally meant to fix.
        arabic_style_rule = (
            "- Since the target language here is Arabic, write \"next_question\" in "
            "simplified Modern Standard Arabic (فصحى مبسطة): clear, calm, and easy "
            "to understand, but formal — NOT Levantine/Palestinian dialect, NOT slang "
            "(avoid dialect words such as شو، بتشعر، احكيلي، تمام، مش، خليني). Keep it "
            "short. Do not repeat emergency/ER-referral wording in your question (that "
            "is handled separately), and never state a definitive diagnosis.\n"
            if ctx.lang == "ar" else ""
        )

        # Phase 2, active mode only: symbolic reasoning has already decided
        # WHICH clinical topic this question must cover, so the model's job
        # narrows to wording it. Emitted only when ctx.required_topic is set,
        # which keeps the prompt byte-identical in every other mode — and the
        # instruction is not trusted on its own: plan() clamps the result back
        # to the topic afterwards regardless of what the model does with it.
        topic_rule = (
            f"REQUIRED TOPIC: your next question MUST be about \"{ctx.required_topic}\" "
            f"and nothing else. Do not choose a different clinical topic.\n\n"
            if ctx.required_topic else ""
        )

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

{safety_priority}{topic_rule}Return ONLY this JSON object:
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
{arabic_style_rule}"""

        try:
            response = await asyncio.to_thread(
                requests.post,
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

    async def _check_readiness(self, ctx: PlannerInput, known: Dict[str, str]) -> bool:
        """Dedicated, minimal call: is this picture complete enough to stop?

        See _READINESS_* above for the A/B evidence behind splitting this out
        of _ask(). Failure (timeout, bad JSON, unreachable Ollama) resolves to
        False, not an exception — an unavailable readiness check should cost
        one extra question, never abort the turn the way a genuine PlannerError
        does elsewhere.
        """
        summary = ", ".join(k.replace("_", " ") for k in known)
        try:
            response = await asyncio.to_thread(
                requests.post,
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


# ---------------------------------------------------------------------------
# SymbolicPlanner — Prolog picks the topic, the wrapped planner words it
# ---------------------------------------------------------------------------

# Profile key holding the canonical topics already put to this patient. A LIST,
# deliberately: report_generator renders every *string* profile value as a
# clinical row, so bookkeeping stored as a string would appear in the PDF.
ASKED_TOPICS_KEY = "symbolic_asked_topics"


class SymbolicPlanner:
    """Thin adapter: ask Prolog WHAT to cover, let the inner planner say it HOW.

    Deliberately thin. It owns no clinical knowledge — the rules live in
    rules/interview.pl and the slot vocabulary in flows/*.json — and it owns no
    wording, which stays with LLMPlanner and the flow templates. Its whole job
    is to carry a canonical topic across the boundary and refuse to let the
    other side change it.

    Three ways a turn can go:

      symbolic decision available, interview_complete  -> ready for diagnosis
      symbolic decision available, topic chosen        -> inner planner words
                                                          it, clamped to topic
      symbolic decision unavailable                    -> inner planner, exactly
                                                          as before Phase 2

    The last case is why this wraps rather than replaces: if Prolog is down,
    the pre-Phase-2 pipeline is what runs, unchanged and unaware.
    """

    name = "symbolic"

    def __init__(self, inner, flows, texts, helpers):
        self._inner = inner
        self._flows = flows
        self._texts = texts
        self._h = helpers

    def _flow(self, complaint: Optional[str]) -> dict:
        return self._flows.get(complaint or "generic", self._flows["generic"])

    def _filter_active_updates(
        self, ctx: PlannerInput, result: PlannerResult,
    ) -> Dict[str, Any]:
        """Apply the active interview's final extraction trust boundary.

        The wrapped planner has already parsed JSON and run `_store_answer()`.
        This layer adds only evidence already available here: the selected
        complaint flow, the topic actually asked last turn, and the existing
        deterministic topic anchors. It never moves a value to another slot.
        """
        updates = result.profile_updates or {}
        accepted: Dict[str, Any] = {}

        # These values are produced deterministically outside raw LLM findings.
        for key in ("chief_complaint_description", "associated_symptoms_detected"):
            if key in updates:
                accepted[key] = updates[key]

        flow = self._flow(result.chief_complaint or ctx.chief_complaint)
        allowed = {
            slot.get("key") for slot in flow.get("slots", [])
            if slot.get("key") in KNOWN_FINDING_KEYS
        }
        current_topic = ctx.asked_topics[-1] if ctx.asked_topics else None
        if current_topic not in allowed:
            current_topic = None

        raw_is_non_answer = _is_non_answer(ctx.message, ctx.lang)
        correction_history = ctx.profile.get("correction_history") or []
        current_is_correction = bool(
            isinstance(correction_history, list)
            and correction_history
            and isinstance(correction_history[-1], dict)
            and _normalise_answer(correction_history[-1].get("source_text"), ctx.lang)
            == _normalise_answer(ctx.message, ctx.lang)
        )
        from . import reasoning_engine

        for key, value in updates.items():
            if key not in allowed:
                continue
            if current_is_correction or raw_is_non_answer or _is_non_answer(value, ctx.lang):
                continue
            # Sessions created before active topic bookkeeping (and the first
            # complaint turn) have no authoritative current topic. Preserve
            # the existing accepted flow-slot behavior rather than guessing.
            if current_topic is None:
                accepted[key] = value
                continue
            if key == current_topic:
                accepted[key] = value
                continue
            # Additional multi-fill slots need independent evidence in the raw
            # utterance. One of the already-established anchors is sufficient;
            # absence is fail-closed and the value is dropped, never reassigned.
            if reasoning_engine.vocabulary.question_matches_topic(ctx.message, key):
                accepted[key] = value

        dropped = sorted(set(updates) - set(accepted))
        if dropped:
            logger.info(
                "Symbolic extraction filter dropped unsupported update key(s): %s",
                ", ".join(dropped),
            )
        return accepted

    @staticmethod
    def _wording_matches_topic(reply: object, topic: str) -> bool:
        """Reject wording whose strongest known topic is a different one."""
        from . import reasoning_engine

        vocabulary = reasoning_engine.vocabulary
        if not vocabulary.question_matches_topic(reply, topic):
            return False
        inferred = vocabulary.infer_topic(reply)
        return inferred is None or inferred == topic

    def template_for(self, topic: str, complaint: Optional[str], lang: str) -> Optional[str]:
        """The flow's own question text for a topic — today's exact wording.

        The deterministic fallback is not a new string written for the purpose:
        it is the question the static flow has always asked, which is why
        falling back to it cannot regress the interview.
        """
        for flow in (self._flow(complaint), *self._flows.values()):
            for slot in flow.get("slots", []):
                if slot.get("key") == topic:
                    question = slot.get(f"question_{lang}")
                    if question:
                        return question
        return None

    async def decide(self, ctx: PlannerInput, profile: Dict[str, Any]):
        """Ask Prolog which topic comes next, against `profile`.

        `profile` must be the state as it will ACTUALLY be once this turn is
        stored — ctx.profile merged with whatever profile_updates the inner
        planner's extraction actually accepted — never a guess at which slot
        the raw message fills. `plan()` builds that merge from the inner
        planner's real output before calling this; see its docstring for why
        a prediction (next_unfilled_slot against the raw message) could
        disagree with what the inner planner actually wrote, and the bug that
        came from asking Prolog against a profile state that never existed.
        Never raises.
        """
        from . import reasoning_engine

        return await reasoning_engine.decide_interview_async(
            ctx.session_id or "planner",
            profile=profile,
            entities=ctx.entities,
            chief_complaint=ctx.chief_complaint,
            flow_slots=self._flow(ctx.chief_complaint).get("slots", []),
            asked_topics=ctx.asked_topics,
            # safety_hint is non-None only when the deterministic layer already
            # flagged this turn urgent/emergency (interview_engine
            # ._safety_hint_text), so it is a sufficient signal to prioritise
            # the red-flag follow-up. The VERDICT itself is not reconstructed
            # here — this planner has no business holding one.
            safety_topics=(
                (reasoning_engine.fact_builder.SAFETY_FOLLOW_UP_TOPIC,)
                if ctx.safety_hint else ()
            ),
        )

    def enforce_topic(self, ctx: PlannerInput, result: PlannerResult,
                      topic: str) -> PlannerResult:
        """Keep the wording, replace it if it wandered to another topic.

        This is where the Phase 2 guarantee is actually enforced. The LLM may
        phrase `duration` however it likes; it may not answer with a
        shortness-of-breath question. On failure the deterministic template for
        THE SAME topic is used — a wording failure must never become a
        different clinical question.
        """
        from . import reasoning_engine

        if result.ready_for_diagnosis:
            return result
        if self._wording_matches_topic(result.reply, topic):
            return result

        template = self.template_for(topic, ctx.chief_complaint, ctx.lang)
        if not template:
            logger.warning(
                "Symbolic topic %r has no template for lang=%s — keeping generated wording",
                topic, ctx.lang,
            )
            return result

        logger.info(
            "Symbolic clamp: generated question was off-topic for %r — using the "
            "deterministic template", topic,
        )
        result.reply = template
        result.source = f"{result.source}:clamped"
        return result

    async def plan(self, ctx: PlannerInput) -> PlannerResult:
        """Run the inner planner FIRST, decide the topic against what it
        ACTUALLY reports, then clamp the wording to that topic.

        Phase 2 asked Prolog for the topic before running the inner planner,
        against a PREDICTED post-turn profile (next_unfilled_slot against the
        raw message). That prediction assumed the inner planner would fill
        the same slot the static flow's own rule would have — but the inner
        planner (an LLM) writes whatever slot key its extraction actually
        names, which regularly disagreed. The Prolog decision then reflected
        a profile state that never existed, and the clamp enforced the WRONG
        topic just as faithfully as it enforces the right one — observed
        end-to-end (Phase 9.1) as the same question asked twice in a row.

        Fixed at the source: the topic is now decided against ctx.profile
        merged with the inner planner's real, accepted profile_updates —
        never a guess. See test_symbolic_planner_phase2
        .TestPredictionWriteConsistency for the reproduction and the fix.
        """
        intake = _intake_turn(ctx, self._texts, self._h["extract_name"], self._h["extract_age"])
        if intake is not None:
            return intake

        error: Optional[PlannerError] = None
        result: Optional[PlannerResult] = None
        try:
            result = await self._inner.plan(ctx)
        except PlannerError as exc:
            error = exc

        # Once a complaint is established (including by Python correction), an
        # LLM may not silently move the session to another canonical flow. On
        # the first complaint turn there is no established value, so the
        # planner's already-clamped complaint remains available.
        active_ctx = ctx
        original_updates: Dict[str, Any] = {}
        original_complaint: Optional[str] = None
        if result is not None:
            original_updates = result.profile_updates
            original_complaint = result.chief_complaint
            complaint = ctx.chief_complaint or result.chief_complaint or "generic"
            result.chief_complaint = complaint
            active_ctx = replace(ctx, chief_complaint=complaint)
            result.profile_updates = self._filter_active_updates(active_ctx, result)

        accepted_updates = result.profile_updates if result is not None else {}
        effective_profile = {**ctx.profile, **accepted_updates}

        decision = await self.decide(active_ctx, effective_profile)

        if not decision.available:
            # Prolog down or the query failed: run exactly the pre-Phase-2
            # pipeline. The inner planner already ran; there is nothing to
            # redo, and never fabricate a topic to fall back onto.
            if result is None:
                raise error
            # Degraded active mode is the pre-symbolic planner exactly: no
            # active-only filtering or complaint stabilization may leak into
            # the PrologUnavailable fallback contract.
            result.profile_updates = original_updates
            result.chief_complaint = original_complaint
            logger.info(
                "Symbolic interview unavailable (%s) — falling back to %s",
                decision.degraded_reason, self._inner.name,
            )
            return result

        if decision.complete:
            if result is None:
                raise error
            # Symbolic readiness is authoritative in active mode: the
            # interview is over when every required slot is answered, not
            # when the inner planner feels it has enough.
            result.reply = None
            result.ready_for_diagnosis = True
            result.chief_complaint = (
                result.chief_complaint or active_ctx.chief_complaint or "generic")
            result.source = f"{self.name}:complete"
            result.wording_valid = True
            return result

        if decision.topic is None:
            if result is None:
                raise error
            return result

        if result is None:
            # The inner planner could not produce wording. The TOPIC is still
            # valid, so answer it deterministically rather than discarding the
            # symbolic decision and letting a fallback pick a different one.
            template = self.template_for(
                decision.topic, active_ctx.chief_complaint, active_ctx.lang)
            if not template:
                raise error
            return self._record_asked(ctx, PlannerResult(
                reply=template, phase="interviewing",
                profile_updates=accepted_updates,
                chief_complaint=ctx.chief_complaint or "generic",
                source=f"{self.name}:template",
            ), decision.topic)

        if not result.wording_valid:
            # Extraction succeeded but the model's wording did not. Decide was
            # already run against the accepted post-turn updates above, so ask
            # that exact Prolog-selected topic with its deterministic template.
            template = self.template_for(
                decision.topic, active_ctx.chief_complaint, active_ctx.lang)
            if not template:
                # Bubble the typed invalid state to the engine, which preserves
                # the pre-symbolic static fallback contract.
                return result
            result.reply = template
            result.wording_valid = True
            result.source = f"{self.name}:template-after-wording-failure"
            return self._record_asked(ctx, result, decision.topic)

        # Symbolic readiness is authoritative in active mode: the interview
        # is over when every required slot is answered, not when a 3B model
        # feels it has enough. Only _check_readiness is overridden — the
        # inner planner's TURN CAP is a backstop against a runaway
        # interview and must keep firing, so it is honoured as-is.
        if result.ready_for_diagnosis and not result.source.endswith("turn-cap"):
            logger.info(
                "Symbolic readiness overrides %s: %d required topic(s) still "
                "unanswered (%s) — continuing the interview",
                result.source, len(decision.unanswered),
                ", ".join(decision.unanswered) or "-",
            )
            result.ready_for_diagnosis = False
            result.reply = self.template_for(
                decision.topic, active_ctx.chief_complaint, active_ctx.lang) or result.reply
            result.source = f"{result.source}:symbolic-continue"

        result = self.enforce_topic(active_ctx, result, decision.topic)
        return self._record_asked(ctx, result, decision.topic)

    @staticmethod
    def _record_asked(ctx: PlannerInput, result: PlannerResult, topic: str) -> PlannerResult:
        """Remember which TOPIC was put to the patient, not the sentence used.

        Feeds asked/2 on later turns. Stored as a list so report_generator's
        "every string profile value is a clinical row" rendering leaves it
        alone — a symbolic bookkeeping key must never surface in a patient's
        PDF.
        """
        if result.ready_for_diagnosis or not result.reply:
            return result
        asked = list(ctx.profile.get(ASKED_TOPICS_KEY) or [])
        if topic not in asked:
            asked.append(topic)
        result.profile_updates[ASKED_TOPICS_KEY] = asked
        return result


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


def build_symbolic(inner, flows, texts, helpers):
    """Wrap a planner so Prolog chooses the topic and `inner` words it.

    Constructed unconditionally but consulted only in
    VD_SYMBOLIC_INTERVIEW=active — building it costs nothing (it boots no
    engine) and keeps the selection in one place, at the call site.
    """
    return SymbolicPlanner(inner=inner, flows=flows, texts=texts, helpers=helpers)
