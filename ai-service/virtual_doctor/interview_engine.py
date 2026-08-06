"""
Virtual Doctor — interview engine (Track A, Phases 1-2).

State machine: chief-complaint detection -> ordered slot filling -> hand-off
to reasoning.run_reasoning() once every required slot is filled, all within
the same turn. A safety check runs on every patient message and short-circuits
the interview immediately if a red flag fires.

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
from typing import Any, Dict, Optional

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

    # Safety check runs on every turn, before anything else.
    safety_result = _check_safety(message, lang)

    if safety_result["severity"] in ("emergency", "urgent"):
        reply = safety_result["response"]
        await pool.execute(
            """
            UPDATE virtual_doctor_sessions
            SET phase = 'complete', urgency_level = $2, updated_at = CURRENT_TIMESTAMP
            WHERE session_id = $1
            """,
            session_id,
            safety_result["severity"],
        )
        await _log_message(pool, session["id"], "doctor", reply)
        return {
            "session_id": session_id,
            "reply": reply,
            "phase": "complete",
            "chief_complaint": session["chief_complaint"],
            "urgency_level": safety_result["severity"],
            "profile_snapshot": _load_jsonb(session["patient_profile"]),
        }

    entities = _extractor.extract(message)
    profile = _load_jsonb(session["patient_profile"])
    phase = session["phase"]
    chief_complaint = session["chief_complaint"]

    # --- memory -> embedding -> RAG -------------------------------------
    # Runs only once the emergency short-circuit above has declined to fire, so
    # a red flag still ends the consultation immediately without waiting on
    # Ollama. Both stages are best-effort: they return empty on any failure and
    # can never fail a turn.
    turn_context = await _build_turn_context(session, message, chief_complaint, lang)

    # --- planner --------------------------------------------------------
    # Reached only after the safety layer has declined to fire, so no planner
    # can ever suppress a red flag. The planner decides what to say next and
    # what the answer told us; the engine below owns persistence, the rule
    # engine and the final diagnosis, none of which are delegated.
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
    ))

    profile.update(plan.profile_updates)
    phase = plan.phase
    if plan.chief_complaint:
        chief_complaint = plan.chief_complaint

    urgency_level = session["urgency_level"]
    recommended_specialty_id = session["recommended_specialty_id"]
    differential = _load_jsonb(session["differential"]) if session["differential"] else None
    reasoning_result: Optional[dict] = None

    if plan.ready_for_diagnosis:
        # The interview is finished — run the reasoning phase now, in the same
        # turn, exactly as before. Urgency, specialty and the differential all
        # still come from reasoning.run_reasoning(); the planner only decided
        # *when* to stop asking, never what the answer is.
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
        urgency_level = reasoning_result["urgency_level"]
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
