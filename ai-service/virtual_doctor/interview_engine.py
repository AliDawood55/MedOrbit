"""
Virtual Doctor — interview engine (Track A, Phases 1-2).

State machine: chief-complaint detection -> ordered slot filling -> hand-off
to reasoning.run_reasoning() once every required slot is filled, all within
the same turn. A safety check runs on every patient message.

SAFETY-CONTINUATION MODE (Virtual Doctor Safety-Continuation Interview Mode)
-----------------------------------------------------------------------------
Urgent/emergency severity no longer hard-stops the interview. Instead:
  - the deterministic safety layer's severity is escalated into the session's
    urgency_level (escalate-only — reuses reasoning._more_urgent, the same
    invariant that already governs the final rule-engine-vs-LLM decision, so
    urgency can never be silently downgraded by a later, milder turn);
  - a short, deterministic warning (never delegated to the LLM) is prepended
    to the reply, in full on first reaching a severity tier and as a brief
    reminder on repeat turns at the same tier;
  - the planner still runs and still produces the next question, optionally
    nudged (never overridden) toward a red-flag-relevant topic via
    PlannerInput.safety_hint.
See _apply_safety_continuation() below.

Reuses, without modifying:
  - chatbot.entities.extractor.EntityExtractor  (chief-complaint + symptom detection)
  - chatbot.nlu.safety.MedicalSafetyLayer       (emergency / urgent detection)
  - chatbot.utils.text_normalizer.normalize_text (Arabic hamza/diacritic normalization,
    applied before the safety check — MedicalSafetyLayer's patterns are written
    without hamza, e.g. "الم" not "ألم", so normalizing first is required for
    Arabic red flags to match)
  - db.get_pool                                  (asyncpg pool, medorbit schema)
"""

import asyncio
import json
import logging
import os
import re
import time
import uuid
from typing import Any, Dict, Optional, Tuple

from chatbot.entities.extractor import EntityExtractor
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.utils.text_normalizer import detect_language, normalize_text
from db import get_pool

from . import memory, planner, reasoning, retrieval
from .planner import PlannerError, PlannerInput

# Per-turn conversation memory + RAG retrieval, in the pipeline order the
# dynamic planner will consume them:
#
#   patient -> safety -> memory -> embedding -> RAG -> (planner) -> question
#
# Phase 2 wires the stages in and proves they run on every turn; the planner
# that consumes them arrives in Phase 3. Until then the retrieved context is
# observable (logs + retrieval.get_stats()) but does not steer the interview,
# so the JSON flow behaviour below is byte-for-byte unchanged.
#
# Off switch: the work is pure overhead until Phase 3 lands, and an operator
# who is not running Ollama should not pay ~0.3s per turn for nothing.
PER_TURN_CONTEXT = os.environ.get("VD_PER_TURN_CONTEXT", "1") not in ("0", "false", "False")

logger = logging.getLogger("medorbit-ai.virtual_doctor.interview")

_FLOWS_DIR = os.path.join(os.path.dirname(__file__), "flows")

# A real consultation establishes identity before symptoms, so the session now
# opens with an "intake" phase (name, then age) and only afterwards asks the
# chief complaint — at which point the pre-existing 'greeting' branch takes over
# unchanged.
GREETING = {
    "en": "Hello, I'm the MedOrbit virtual doctor assistant. Before we begin, what is your name?",
    "ar": "مرحباً، أنا مساعد الطبيب الافتراضي في MedOrbit. قبل أن نبدأ، ما اسمك؟",
}

ASK_AGE = {
    "en": "Nice to meet you, {name}. How old are you?",
    "ar": "تشرّفت بمعرفتك يا {name}. كم عمرك؟",
}

ASK_AGE_RETRY = {
    "en": "Sorry, I didn't catch a number. How old are you, in years?",
    "ar": "عذراً، لم ألتقط رقماً. كم عمرك بالسنوات؟",
}

ASK_COMPLAINT = {
    "en": "Thank you. Now, what's bothering you today?",
    "ar": "شكراً لك. الآن، ما الذي يزعجك اليوم؟",
}

WRAP_UP = {
    "en": "Thank you, I've noted everything you've told me.",
    "ar": "شكراً لك، سجّلت كل ما أخبرتني به.",
}

# Safety-continuation reply prefixes. Shown IN FULL the first time a severity
# tier is reached (or on escalation to a higher tier); a short reminder
# replaces the full text on repeat turns at the same tier, so the interview
# does not repeat a long warning every turn while still never dropping the
# danger signal entirely (requirement: "do not ignore the danger signal").
#
# Emergency reuses safety_result["response"] verbatim (the existing canned
# Red Crescent/101 message from chatbot.nlu.safety) rather than a rewritten
# text — that message must never be removed or weakened — and only ADDS a
# short continuation lead-in after it.
SAFETY_URGENT_WARNING = {
    "ar": (
        "هذا العرض قد يحتاج تقييمًا طبيًا عاجلًا، لكن سأطرح عليك أسئلة سريعة ومهمة "
        "لتوثيق الحالة بشكل أدق. إذا كان الألم شديدًا جدًا أو لديك إغماء أو ضيق تنفس "
        "أو ضعف مفاجئ، توجه للطوارئ فورًا أو اتصل بالإسعاف. "
    ),
    "en": (
        "This symptom may need urgent medical evaluation, but I'll ask a few quick, "
        "important questions to document your case more accurately. If the pain is "
        "very severe, or you have fainting, shortness of breath, or sudden weakness, "
        "go to the emergency room immediately or call an ambulance. "
    ),
}

SAFETY_URGENT_REMINDER = {
    "ar": "(تذكير: ما زلت بحاجة لتقييم طبي عاجل.) ",
    "en": "(Reminder: this still needs urgent medical evaluation.) ",
}

SAFETY_EMERGENCY_CONTINUATION = {
    "ar": " إذا استطعت، أجبني بسرعة على سؤال واحد فقط: ",
    "en": " If you can, please quickly answer just one question: ",
}

SAFETY_EMERGENCY_REMINDER = {
    "ar": "(تذكير: هذه حالة قد تكون طارئة — توجه للطوارئ إن لم تكن قد فعلت بعد.) ",
    "en": "(Reminder: this may be an emergency — seek emergency care now if you have not already.) ",
}

# Leading politeness the patient is likely to speak before their actual name;
# stripped so the profile stores "Ali" rather than "my name is Ali".
_NAME_PREFIXES = re.compile(
    r"^\s*(?:"
    r"my\s+name\s+is|my\s+name'?s|i\s+am|i'm|it'?s|this\s+is|name\s+is|call\s+me|"
    r"اسمي|إسمي|انا|أنا|اسمى|اسمي\s+هو"
    r")\s*[:,]?\s*",
    re.IGNORECASE,
)

_ARABIC_INDIC = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")

# Ones digits for Arabic compound ages ("أربعة وثلاثون" = 4 + 30 = 34). Arabic
# states compounds ones-then-tens, joined by و ("and") glued directly onto the
# tens word with no space — "أربعة" + " " + "وثلاثون", never "وأربعة ثلاثون".
# Both the "-a" (feminine/counting) and bare forms are listed, since Whisper
# emits either depending on how the sentence ran.
_ARABIC_ONES = {
    "واحد": 1, "واحدة": 1,
    "اثنان": 2, "إثنان": 2, "اثنين": 2, "إثنين": 2,
    "ثلاثة": 3, "ثلاث": 3,
    "أربعة": 4, "اربعة": 4, "أربع": 4, "اربع": 4,
    "خمسة": 5, "خمس": 5,
    "ستة": 6, "ست": 6,
    "سبعة": 7, "سبع": 7,
    "ثمانية": 8, "ثمان": 8, "ثمانى": 8,
    "تسعة": 9, "تسع": 9,
}

# Spelled-out ages, for patients who answer "thirty" / "ثلاثين" instead of "30".
#
# Arabic tens have two case forms and Whisper emits either depending on how the
# sentence ran — nominative "أربعون" and genitive/accusative "أربعين" are the
# same number. Both are listed for every ten; omitting the -oon forms silently
# broke age capture until a real recording said "أربعون" out loud.
_SPELLED_AGES = {
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    "seventy": 70, "eighty": 80, "ninety": 90,
    "عشرة": 10, "احدعشر": 11, "اثناعشر": 12,
    "عشرين": 20, "عشرون": 20,
    "ثلاثين": 30, "ثلاثون": 30,
    "اربعين": 40, "أربعين": 40, "اربعون": 40, "أربعون": 40,
    "خمسين": 50, "خمسون": 50,
    "ستين": 60, "ستون": 60,
    "سبعين": 70, "سبعون": 70,
    "ثمانين": 80, "ثمانون": 80,
    "تسعين": 90, "تسعون": 90,
    "مية": 100, "مائة": 100, "ماية": 100,
}

# Arabic tens (20-90) that can take a ones digit in front of them to form a
# compound age, e.g. "أربعة وثلاثون" = 4 + 30 = 34. Filtered out of
# _SPELLED_AGES rather than re-listed, so the two can never drift apart.
_ARABIC_TENS = {
    word: value for word, value in _SPELLED_AGES.items()
    if value >= 20 and value % 10 == 0 and not word.isascii()
}

# "<ones> <tens>", ones-then-tens per Arabic grammar, و glued onto the tens
# word with no space ("أربعة" + " " + "وثلاثون"). Longer words are tried first
# within each alternation so e.g. "ثمانية" does not partially match on a
# shorter, unrelated prefix.
_COMPOUND_AGE_RE = re.compile(
    r"\b(" + "|".join(sorted(_ARABIC_ONES, key=len, reverse=True)) + r")"
    r"\s+و\s*"
    r"(" + "|".join(sorted(_ARABIC_TENS, key=len, reverse=True)) + r")\b"
)

MIN_AGE, MAX_AGE = 1, 120


def _extract_name(message: str) -> str:
    """Best-effort name from a spoken answer; never rejects, only tidies."""
    cleaned = _NAME_PREFIXES.sub("", message.strip())
    cleaned = cleaned.strip(" .،,!?؟\"'").strip()
    if not cleaned:
        cleaned = message.strip()
    # Keep it short — STT sometimes appends a stray clause.
    words = cleaned.split()
    return " ".join(words[:4])[:80]


def _extract_age(message: str) -> Optional[int]:
    text = message.translate(_ARABIC_INDIC)
    # Word-bounded so a year like "1755" yields nothing rather than being
    # mined for a stray in-range "5".
    for match in re.findall(r"\b\d{1,3}\b", text):
        age = int(match)
        if MIN_AGE <= age <= MAX_AGE:
            return age

    # Compound BEFORE single-word: "أربعة وثلاثون" contains "ثلاثون" (30) as a
    # substring, so checking the plain _SPELLED_AGES table first would silently
    # return 30 and drop the "أربعة" (4) — confirmed happening live (patient
    # said 34, the app recorded 30). Trying the compound pattern first fixes
    # that without touching the exact-round-ten case ("ثلاثين" alone), which
    # falls through to the loop below exactly as before.
    compound = _COMPOUND_AGE_RE.search(text)
    if compound:
        age = _ARABIC_ONES[compound.group(1)] + _ARABIC_TENS[compound.group(2)]
        if MIN_AGE <= age <= MAX_AGE:
            return age

    lowered = text.lower()
    for word, value in _SPELLED_AGES.items():
        if word in lowered:
            return value
    return None

def _load_flows() -> Dict[str, dict]:
    flows: Dict[str, dict] = {}
    for fname in sorted(os.listdir(_FLOWS_DIR)):
        if not fname.endswith(".json"):
            continue
        with open(os.path.join(_FLOWS_DIR, fname), "r", encoding="utf-8") as f:
            flow = json.load(f)
            flows[flow["complaint"]] = flow
    return flows


FLOWS = _load_flows()

_extractor = EntityExtractor()
_safety = MedicalSafetyLayer()

_SEVERITY_RANK = {"emergency": 2, "urgent": 1, "normal": 0}


def _check_safety(message: str, lang: str) -> dict:
    """
    Run the safety layer on both the raw and the normalized message and keep
    whichever is more severe. Normalizing helps Arabic hamza variants match
    (safety.py's patterns are written without hamza, e.g. "الم" not "ألم"),
    but normalize_english() strips punctuation like apostrophes, which would
    otherwise cause English patterns such as "can't breathe" to be missed on
    the normalized text alone.
    """
    raw_result = _safety.check(message)
    normalized_result = _safety.check(normalize_text(message, lang))
    if _SEVERITY_RANK[normalized_result["severity"]] > _SEVERITY_RANK[raw_result["severity"]]:
        return normalized_result
    return raw_result


def _safety_hint_text(safety_result: dict) -> Optional[str]:
    """A short, deterministic description of what the safety layer matched,
    for the planner to (optionally) prioritize — see PlannerInput.safety_hint.
    This only ever describes WHAT matched; it never decides severity, urgency,
    or whether to warn, all of which stay entirely inside
    _apply_safety_continuation()/the safety layer itself."""
    if safety_result["severity"] not in ("emergency", "urgent"):
        return None
    matched = [m.get("matched") for m in safety_result.get("matched_patterns", []) if m.get("matched")]
    return ", ".join(matched) if matched else None


def _apply_safety_continuation(
    safety_result: dict, session, profile: Dict[str, Any], lang: str,
) -> Tuple[str, Optional[str], Dict[str, Any]]:
    """Turn one turn's safety-layer result into (reply_prefix, session_urgency,
    updated_profile) instead of hard-stopping the interview.

    Deterministic and safety-layer-driven only: the LLM planner never sees or
    influences severity/urgency here, only (optionally) the topic of the next
    question via safety_hint. Never downgrades: session_urgency is always the
    more severe of whatever the session already had and what this turn found,
    via reasoning._more_urgent() — the same escalate-only invariant that
    already governs the final rule-engine-vs-LLM decision in reasoning.py,
    reused rather than reimplemented.

    Once the session has ever reached "emergency", every later safety-
    triggering turn keeps the emergency-tier framing (full text first time,
    short reminder after) even if that turn's own phrase only matched an
    "urgent" pattern on its own — this is what keeps urgency "sticky" at the
    worst level ever seen, matching the same escalate-only spirit as
    session_urgency itself. A profile flag (safety_warning_shown_for) tracks
    the highest tier already shown so repeat turns get a short reminder
    instead of the full warning again, unless the tier escalates.
    """
    severity = safety_result["severity"]
    prior_session_urgency = session["urgency_level"]

    if severity not in ("emergency", "urgent"):
        return "", prior_session_urgency, profile

    session_urgency = (
        reasoning._more_urgent(prior_session_urgency, severity)
        if prior_session_urgency else severity
    )

    already_shown = profile.get("safety_warning_shown_for")
    escalated = (
        already_shown is None
        or _SEVERITY_RANK.get(session_urgency, 0) > _SEVERITY_RANK.get(already_shown, 0)
    )

    if session_urgency == "emergency":
        prefix = (
            safety_result["response"] + SAFETY_EMERGENCY_CONTINUATION[lang]
            if escalated else SAFETY_EMERGENCY_REMINDER[lang]
        )
    else:
        prefix = SAFETY_URGENT_WARNING[lang] if escalated else SAFETY_URGENT_REMINDER[lang]

    profile = dict(profile)
    if escalated:
        profile["safety_warning_shown_for"] = session_urgency

    # Lightweight, additive audit trail of what triggered escalation this
    # session — lives entirely inside the existing patient_profile JSONB
    # column, no schema/migration change needed. Not a substitute for the
    # audit's proposed structured red_flags field (see Section 6 of
    # docs/virtual_doctor_clinical_voice_improvement_plan.md) — that would
    # need per-flag categorization this file does not attempt to add here.
    matched = [m.get("matched") for m in safety_result.get("matched_patterns", []) if m.get("matched")]
    if matched:
        flags = list(profile.get("safety_flags_detected", []))
        for m in matched:
            if m not in flags:
                flags.append(m)
        profile["safety_flags_detected"] = flags

    return prefix, session_urgency, profile


def _lang(text: str, requested: Optional[str] = None) -> str:
    if requested in ("ar", "en"):
        return requested
    detected = detect_language(text)
    return detected if detected in ("ar", "en") else "en"


def _detect_chief_complaint(entities: dict) -> str:
    symptoms = entities.get("symptoms") or []
    for complaint, flow in FLOWS.items():
        if complaint == "generic":
            continue
        if any(s in symptoms for s in flow.get("match_symptoms", [])):
            return complaint
    return "generic"


def _next_unfilled_slot(flow: dict, profile: dict) -> Optional[dict]:
    for slot in flow["slots"]:
        if not profile.get(slot["key"]):
            return slot
    return None


# The planner strategy pair. The static JSON flow is both a selectable planner
# and the permanent fallback, which is why it is never removed.
_planner, _fallback_planner = planner.build(
    flows=FLOWS,
    texts={"ASK_AGE": ASK_AGE, "ASK_AGE_RETRY": ASK_AGE_RETRY,
           "ASK_COMPLAINT": ASK_COMPLAINT, "WRAP_UP": WRAP_UP},
    helpers={
        "extract_name": _extract_name,
        "extract_age": _extract_age,
        "detect_chief_complaint": _detect_chief_complaint,
        "next_unfilled_slot": _next_unfilled_slot,
    },
    # Reused verbatim from reasoning.py rather than reimplemented: these are the
    # guards that already catch qwen2's Chinese/letter-salad drift, and a
    # patient-facing question needs them at least as much as a JSON field does.
    validators={
        "text_matches_language": reasoning._text_matches_language,
        "looks_coherent": reasoning._looks_coherent,
    },
)

def _as_uuid(value: Any) -> Optional[uuid.UUID]:
    """Accept either a str or an already-parsed uuid.UUID (asyncpg returns
    UUID columns as uuid.UUID objects, but reasoning.run_reasoning returns
    a plain str), and normalize to uuid.UUID or None."""
    if value is None or isinstance(value, uuid.UUID):
        return value
    return uuid.UUID(value)


def _load_jsonb(value: Any) -> dict:
    if isinstance(value, str):
        return json.loads(value) if value else {}
    return value or {}


async def _log_message(pool, session_row_id, role: str, text: str, entities: Optional[dict] = None) -> None:
    await pool.execute(
        """
        INSERT INTO virtual_doctor_messages (session_id, role, message_text, extracted_entities)
        VALUES ($1, $2, $3, $4)
        """,
        session_row_id,
        role,
        text,
        json.dumps(entities, ensure_ascii=False) if entities else None,
    )


def _intake_questions(profile: dict) -> int:
    """Doctor turns spent on setup rather than on the medical interview.

    THREE fixed prompts precede any real clinical question, not two: the
    name greeting, ASK_AGE, and ASK_COMPLAINT ("what brings you in today?").
    Undercounting this at two let ASK_COMPLAINT masquerade as the interview's
    first clinical turn, inflating turn_index by one — observed causing the
    completeness gate (turn_index >= COMPLETENESS_MIN_TURNS) to open after
    just ONE real dynamically-generated clinical question instead of two,
    ending a live consultation prematurely. chief_complaint_description is
    set exactly once, right after ASK_COMPLAINT is answered, so its presence
    is a reliable proxy for "that canned prompt has already been asked."
    """
    return (
        (1 if profile.get("name") else 0)
        + (1 if profile.get("age") is not None else 0)
        + (1 if profile.get("chief_complaint_description") else 0)
    )


async def _run_planner(ctx: PlannerInput):
    """Run the configured planner, falling back to the static flow on failure.

    The fallback is per-turn, not per-session: one bad LLM response costs a
    single dynamically-generated question, and the consultation carries on. A
    static-flow question is always a valid thing to ask next, because the flow
    is driven by which slots are still empty rather than by conversation state.
    """
    if _planner is _fallback_planner:
        return await _planner.plan(ctx)

    started = time.monotonic()
    try:
        result = await _planner.plan(ctx)
        logger.info("planner=%s %.0fms complaint=%s ready=%s reply=%r",
                    result.source, (time.monotonic() - started) * 1000,
                    result.chief_complaint, result.ready_for_diagnosis,
                    (result.reply or "")[:60])
        return result
    except PlannerError as exc:
        logger.warning("Planner '%s' failed (%s) after %.0fms — falling back to the "
                       "static flow for this turn", _planner.name, exc,
                       (time.monotonic() - started) * 1000)
    except Exception as exc:  # noqa: BLE001 - never let a planner break a turn
        logger.exception("Planner '%s' raised unexpectedly (%s) — falling back", _planner.name, exc)

    result = await _fallback_planner.plan(ctx)
    result.source = f"{_planner.name}->static"
    return result


async def _build_turn_context(
    session, message: str, chief_complaint: Optional[str], lang: str,
) -> Dict[str, Any]:
    """Assemble the per-turn context the planner will consume in Phase 3.

    Returns history + retrieved passages + timings. Never raises: memory and
    retrieval are independent (neither reads the other's result), so they run
    concurrently and are degraded to empty INDEPENDENTLY on failure — one
    branch failing no longer discards the other branch's already-successful
    result.
    """
    empty: Dict[str, Any] = {"history": [], "chunks": [], "context_block": "",
                             "memory_ms": 0.0, "rag_ms": 0.0}
    if not PER_TURN_CONTEXT:
        return empty

    timings: Dict[str, float] = {"memory_ms": 0.0, "rag_ms": 0.0}

    async def _timed_load_recent():
        t0 = time.monotonic()
        try:
            return await memory.load_recent(session["id"])
        finally:
            timings["memory_ms"] = (time.monotonic() - t0) * 1000

    async def _timed_retrieve_for_turn():
        t0 = time.monotonic()
        try:
            return await retrieval.retrieve_for_turn(message, chief_complaint, lang)
        finally:
            timings["rag_ms"] = (time.monotonic() - t0) * 1000

    history_result, chunks_result = await asyncio.gather(
        _timed_load_recent(), _timed_retrieve_for_turn(), return_exceptions=True,
    )

    if isinstance(history_result, Exception):
        logger.warning(
            "Per-turn memory lookup failed (%s) — continuing with empty history",
            type(history_result).__name__,
        )
        history = []
    else:
        history = history_result

    if isinstance(chunks_result, Exception):
        logger.warning(
            "Per-turn RAG retrieval failed (%s) — continuing with empty chunks",
            type(chunks_result).__name__,
        )
        chunks = []
    else:
        chunks = chunks_result

    logger.info(
        "turn context: history=%d msg(s) rag=%d passage(s) pages=%s "
        "memory=%.0fms rag=%.0fms complaint=%s topics=%s",
        len(history), len(chunks),
        [retrieval.cite(c) for c in chunks] or "-",
        timings["memory_ms"], timings["rag_ms"], chief_complaint or "-",
        retrieval.infer_topics(message) or "-",
    )

    return {
        "history": history,
        "chunks": chunks,
        "context_block": retrieval.format_context(chunks),
        "memory_ms": round(timings["memory_ms"], 1),
        "rag_ms": round(timings["rag_ms"], 1),
    }


async def start_session(language: Optional[str], user_id: Optional[str]) -> dict:
    lang = language if language in ("ar", "en") else "en"
    session_id = str(uuid.uuid4())
    pool = await get_pool()

    row = await pool.fetchrow(
        """
        INSERT INTO virtual_doctor_sessions (user_id, session_id, language, phase, patient_profile)
        VALUES ($1, $2, $3, 'intake', '{}'::jsonb)
        RETURNING id
        """,
        uuid.UUID(user_id) if user_id else None,
        session_id,
        lang,
    )

    reply = GREETING[lang]
    await _log_message(pool, row["id"], "doctor", reply)

    # Load the planner model while the patient reads the greeting and types
    # their name, rather than on their first medical answer. Fire-and-forget:
    # /start must not wait on Ollama.
    asyncio.get_running_loop().run_in_executor(None, planner.warm)

    return {"session_id": session_id, "reply": reply, "phase": "intake", "language": lang}


async def handle_message(session_id: str, message: str) -> dict:
    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1", session_id
    )
    if not session:
        raise ValueError("session_not_found")

    lang = session["language"] or _lang(message)
    await _log_message(pool, session["id"], "patient", message)

    # Safety check runs on every turn, before anything else. It remains the
    # sole, deterministic source of truth for severity — nothing below (the
    # LLM planner, the reasoning phase) can override or downgrade what it
    # decides here. Unlike before, urgent/emergency no longer hard-stops the
    # interview: see _apply_safety_continuation()'s docstring for the design.
    safety_result = _check_safety(message, lang)

    entities = _extractor.extract(message)
    profile = _load_jsonb(session["patient_profile"])
    phase = session["phase"]
    chief_complaint = session["chief_complaint"]

    safety_prefix, session_urgency, profile = _apply_safety_continuation(
        safety_result, session, profile, lang,
    )

    # --- memory -> embedding -> RAG -------------------------------------
    # Both stages are best-effort: they return empty on any failure and can
    # never fail a turn.
    turn_context = await _build_turn_context(session, message, chief_complaint, lang)

    # --- planner --------------------------------------------------------
    # The planner decides what to say next and what the answer told us; the
    # engine below owns persistence, the rule engine, the final diagnosis, and
    # the safety wrap, none of which are delegated. safety_hint may nudge
    # *which* question the LLM planner asks next toward a red-flag-relevant
    # topic (requirement: prioritize red-flag questions) but never decides
    # whether to warn or what severity/urgency to report — that stays entirely
    # inside _apply_safety_continuation() above, driven only by the
    # deterministic safety layer.
    # Counted over the whole transcript, not the memory window: the window is
    # capped at HISTORY_LIMIT, so counting doctor turns inside it stops rising
    # once the interview outgrows it — and the turn cap that guarantees every
    # consultation terminates would then never fire.
    asked = await memory.doctor_turns(session["id"])
    plan = await _run_planner(PlannerInput(
        message=message,
        lang=lang,
        phase=phase,
        chief_complaint=chief_complaint,
        profile=profile,
        entities=entities,
        history=turn_context["history"],
        chunks=turn_context["chunks"],
        context_block=turn_context["context_block"],
        turn_index=max(0, len(asked) - _intake_questions(profile)),
        asked_questions=asked,
        safety_hint=_safety_hint_text(safety_result),
    ))

    profile.update(plan.profile_updates)
    phase = plan.phase
    if plan.chief_complaint:
        chief_complaint = plan.chief_complaint

    urgency_level = session_urgency
    recommended_specialty_id = session["recommended_specialty_id"]
    differential = _load_jsonb(session["differential"]) if session["differential"] else None
    reasoning_result: Optional[dict] = None

    if plan.ready_for_diagnosis:
        # The interview is finished — run the reasoning phase now, in the same
        # turn, exactly as before. Specialty and the differential come from
        # reasoning.run_reasoning(); the planner only decided *when* to stop
        # asking, never what the answer is.
        #
        # Full transcript, not the per-turn memory window: this call happens
        # once per consultation (not once per turn), so it can afford every
        # message rather than the last HISTORY_LIMIT. Best-effort — memory.
        # load_recent() already degrades to [] on any DB hiccup rather than
        # raising, so a failure here costs the transcript detail, never the
        # diagnosis itself.
        full_history = await memory.load_recent(session["id"], limit=memory.FULL_HISTORY_LIMIT)
        reasoning_result = await reasoning.run_reasoning(
            chief_complaint, profile, lang, history=full_history
        )
        phase = "complete"
        # Escalate-only merge against session_urgency: a safety-layer signal
        # from an earlier turn in THIS interview (which continued instead of
        # hard-stopping) must never be silently downgraded by a later,
        # milder reasoning pass — the same invariant reasoning.py already
        # applies internally between its own rule-engine and LLM opinions.
        urgency_level = (
            reasoning._more_urgent(urgency_level, reasoning_result["urgency_level"])
            if urgency_level else reasoning_result["urgency_level"]
        )
        recommended_specialty_id = reasoning_result["recommended_specialty_id"]
        differential = reasoning_result["differential"]
        reply = reasoning_result["reply"]

        # reasoning.run_reasoning() just called qwen2:7b (2.31GB), which does
        # not fit in 4GB of VRAM alongside the ~2.16GB planner model — measured,
        # loading it evicts the planner outright, not merely idles it out. That
        # eviction is what turned into a 5-6s cold hit on the FIRST clinical
        # question of the next consultation. Re-warming here, in the background,
        # right as this consultation ends rather than waiting for the next
        # session's first clinical question, moves that reload off the critical
        # path in the normal case: a new patient still has to open the app,
        # start a session and get through name/age before their first symptom
        # question, which is generally enough time for this to finish quietly.
        # Fire-and-forget: this response must not wait on it, and a failure
        # here is invisible — the next call simply reloads as it did before.
        asyncio.get_running_loop().run_in_executor(None, planner.warm)
    elif plan.reply is not None:
        reply = plan.reply
    else:
        reply = WRAP_UP[lang]

    # Combine: safety warning (if any) + the planner's one focused question —
    # deterministic string composition, never delegated to the LLM. Applied
    # after the reasoning branch too, so a same-turn "ready for diagnosis"
    # response on a safety-flagged turn still carries the warning.
    if safety_prefix:
        reply = f"{safety_prefix}{reply}"

    await pool.execute(
        """
        UPDATE virtual_doctor_sessions
        SET phase = $2, chief_complaint = $3, patient_profile = $4::jsonb,
            urgency_level = $5, recommended_specialty_id = $6, differential = $7::jsonb,
            updated_at = CURRENT_TIMESTAMP
        WHERE session_id = $1
        """,
        session_id,
        phase,
        chief_complaint,
        json.dumps(profile, ensure_ascii=False),
        urgency_level,
        _as_uuid(recommended_specialty_id),
        json.dumps(differential, ensure_ascii=False) if differential else None,
    )
    await _log_message(pool, session["id"], "doctor", reply, entities)

    result = {
        "session_id": session_id,
        "reply": reply,
        "phase": phase,
        "chief_complaint": chief_complaint,
        "urgency_level": urgency_level,
        "profile_snapshot": profile,
    }
    if reasoning_result:
        result["recommended_specialty_id"] = reasoning_result["recommended_specialty_id"]
        result["recommended_specialty_name_en"] = reasoning_result["recommended_specialty_name_en"]
        result["recommended_specialty_name_ar"] = reasoning_result["recommended_specialty_name_ar"]
        result["confidence"] = reasoning_result["confidence"]
        result["differential"] = reasoning_result["differential"]
    return result


async def get_session_state(session_id: str) -> Optional[dict]:
    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1", session_id
    )
    if not session:
        return None

    messages = await pool.fetch(
        """
        SELECT role, message_text FROM virtual_doctor_messages
        WHERE session_id = $1 ORDER BY created_at
        """,
        session["id"],
    )

    return {
        "session_id": session["session_id"],
        "language": session["language"],
        "chief_complaint": session["chief_complaint"],
        "phase": session["phase"],
        "patient_profile": _load_jsonb(session["patient_profile"]),
        "urgency_level": session["urgency_level"],
        "recommended_specialty_id": str(session["recommended_specialty_id"]) if session["recommended_specialty_id"] else None,
        "differential": _load_jsonb(session["differential"]) if session["differential"] else None,
        "messages": [{"role": m["role"], "text": m["message_text"]} for m in messages],
    }
