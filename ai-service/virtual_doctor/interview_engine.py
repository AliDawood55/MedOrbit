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

import json
import os
import re
import uuid
from typing import Any, Dict, Optional

from chatbot.entities.extractor import EntityExtractor
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.utils.text_normalizer import detect_language, normalize_text
from db import get_pool

from . import reasoning

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

    # Intake replies are produced here rather than by the slot machinery below,
    # because name/age are identity questions, not symptom slots — they are not
    # tied to any chief-complaint flow.
    intake_reply: Optional[str] = None

    if phase == "intake":
        if not profile.get("name"):
            profile["name"] = _extract_name(message)
            intake_reply = ASK_AGE[lang].format(name=profile["name"])
        else:
            age = _extract_age(message)
            if age is None:
                # Re-ask rather than store a bad value; the patient stays in intake.
                intake_reply = ASK_AGE_RETRY[lang]
            else:
                profile["age"] = age
                phase = "greeting"
                intake_reply = ASK_COMPLAINT[lang]
    elif phase == "greeting":
        chief_complaint = _detect_chief_complaint(entities)
        phase = "interviewing"
        profile["chief_complaint_description"] = message
        if entities.get("symptoms"):
            profile["associated_symptoms_detected"] = list(entities["symptoms"])
    elif phase == "interviewing":
        flow = FLOWS.get(chief_complaint, FLOWS["generic"])
        slot = _next_unfilled_slot(flow, profile)
        if slot:
            profile[slot["key"]] = message
        if entities.get("symptoms"):
            detected = set(profile.get("associated_symptoms_detected", []))
            detected.update(entities["symptoms"])
            profile["associated_symptoms_detected"] = list(detected)
    # else: phase is already 'reasoning' or 'complete' — interview has ended,
    # nothing left to fill; fall through to the wrap-up reply below.

    urgency_level = session["urgency_level"]
    recommended_specialty_id = session["recommended_specialty_id"]
    differential = _load_jsonb(session["differential"]) if session["differential"] else None
    reasoning_result: Optional[dict] = None

    if intake_reply is not None:
        reply = intake_reply
    elif phase == "interviewing":
        flow = FLOWS.get(chief_complaint, FLOWS["generic"])
        next_slot = _next_unfilled_slot(flow, profile)
        if next_slot:
            reply = next_slot[f"question_{lang}"]
        else:
            # All required slots are filled — run the reasoning phase now,
            # in the same turn, rather than leaving it as a separate step.
            reasoning_result = await reasoning.run_reasoning(chief_complaint, profile, lang)
            phase = "complete"
            urgency_level = reasoning_result["urgency_level"]
            recommended_specialty_id = reasoning_result["recommended_specialty_id"]
            differential = reasoning_result["differential"]
            reply = reasoning_result["reply"]
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
