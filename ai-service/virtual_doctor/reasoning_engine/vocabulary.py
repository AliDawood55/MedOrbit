"""
Virtual Doctor — the symbolic layer's allow-list.

THE TRUST BOUNDARY LIVES HERE. Everything that reaches Prolog passes through
this module first, and nothing else in the package may invent an atom. The
rule is not "escape the string well enough" — escaping arbitrary Prolog source
is not a defence, because two of the dangerous payloads are syntactically
valid Prolog that no escaper would flag:

    "chest_pain), halt, f(p,symptom,x"   parsed as source; the goal still ran
    "Evil"                               became an UNBOUND VARIABLE, unified
                                         with anything, and fired a clinical
                                         rule that must not have fired

Both were reproduced against pyswip 0.3.3 during the Phase 0 audit. The second
is why a blocklist can never be sufficient: the payload contains no
metacharacter at all. So the boundary is a positive allow-list —

    raw value -> normalization -> allow-list lookup -> canonical atom -> fact

— and a value with no canonical mapping is either dropped (with structured
logging) or replaced by UNKNOWN_VALUE where a placeholder is semantically
meaningful. It is never passed through.

The canonical vocabulary is deliberately NOT invented here. It is the
vocabulary the rest of the service already uses: symptom keys from
chatbot/entities/medical_entities.json, slot keys matching
planner.KNOWN_FINDING_KEYS and flows/*.json, and complaints matching
retrieval.COMPLAINT_ANCHORS.
"""

from __future__ import annotations

import hashlib
import re
from typing import Dict, FrozenSet, Optional, Tuple, Union

from chatbot.utils.text_normalizer import normalize_text

_SAFE_ATOM_RE = re.compile(r"^[a-z][a-z0-9_]*$")

MAX_ATOM_CHARS = 64

UNKNOWN_VALUE = "unknown_value"

URGENCY_LEVELS: Tuple[str, ...] = ("routine", "urgent", "emergency")
URGENCY_RANK: Dict[str, int] = {level: i + 1 for i, level in enumerate(URGENCY_LEVELS)}
_LEGACY_URGENCY = {"normal": "routine"}

SYMPTOMS: FrozenSet[str] = frozenset({
    "headache", "fever", "cough", "fatigue", "dizziness", "nausea",
    "chest_pain", "shortness_of_breath", "stomach_pain", "stomach_ache",
    "diarrhea", "back_pain", "insomnia", "anxiety", "skin_rash",
    "hematuria", "flank_pain", "unconscious", "severe_bleeding", "seizure",
})

_SYMPTOM_SURFACE: Dict[str, str] = {
    "صداع": "headache", "وجع راس": "headache", "الم راس": "headache",
    "صداع نصفي": "headache", "headache": "headache", "migraine": "headache",
    "head pain": "headache",
    "حراره": "fever", "حمي": "fever", "سخونه": "fever", "fever": "fever",
    "high temperature": "fever",
    "كحه": "cough", "سعال": "cough", "cough": "cough", "coughing": "cough",
    "تعب": "fatigue", "ارهاق": "fatigue", "ضعف": "fatigue", "خمول": "fatigue",
    "كسل": "fatigue", "fatigue": "fatigue", "tired": "fatigue",
    "exhaustion": "fatigue", "weakness": "fatigue",
    "دوخه": "dizziness", "دوار": "dizziness", "دوران": "dizziness",
    "dizziness": "dizziness", "dizzy": "dizziness", "vertigo": "dizziness",
    "غثيان": "nausea", "استفراغ": "nausea", "ترجيع": "nausea", "قيء": "nausea",
    "nausea": "nausea", "vomiting": "nausea",
    "الم صدر": "chest_pain", "وجع صدر": "chest_pain",
    "الم في الصدر": "chest_pain", "ضيق صدر": "chest_pain",
    "chest pain": "chest_pain", "chest discomfort": "chest_pain",
    "chest tightness": "chest_pain",
    "ضيق تنفس": "shortness_of_breath", "صعوبه تنفس": "shortness_of_breath",
    "نهجان": "shortness_of_breath", "كتمه": "shortness_of_breath",
    "shortness of breath": "shortness_of_breath",
    "difficulty breathing": "shortness_of_breath",
    "breathless": "shortness_of_breath",
    "الم معده": "stomach_pain", "وجع معده": "stomach_pain",
    "الم بطن": "stomach_pain", "وجع بطن": "stomach_pain", "مغص": "stomach_pain",
    "stomach pain": "stomach_pain", "abdominal pain": "stomach_pain",
    "cramps": "stomach_pain", "stomach ache": "stomach_ache",
    "اسهال": "diarrhea", "diarrhea": "diarrhea", "loose stools": "diarrhea",
    "الم ظهر": "back_pain", "وجع ظهر": "back_pain", "الام الظهر": "back_pain",
    "back pain": "back_pain", "backache": "back_pain",
    "ارق": "insomnia", "صعوبه نوم": "insomnia", "سهر": "insomnia",
    "insomnia": "insomnia", "sleepless": "insomnia",
    "قلق": "anxiety", "توتر": "anxiety", "خوف": "anxiety",
    "anxiety": "anxiety", "anxious": "anxiety", "nervous": "anxiety",
    "طفح جلدي": "skin_rash", "حساسيه": "skin_rash", "هرش": "skin_rash",
    "حكه": "skin_rash", "rash": "skin_rash", "skin rash": "skin_rash",
    "itching": "skin_rash", "hives": "skin_rash",
    "دم في البول": "hematuria", "دم بالبول": "hematuria",
    "blood in urine": "hematuria", "hematuria": "hematuria",
    "الخاصره": "flank_pain", "خاصره": "flank_pain", "flank pain": "flank_pain",
}

CLINICAL_SLOTS: FrozenSet[str] = frozenset({
    "duration", "severity", "location", "location_character", "character",
    "radiation", "triggers", "appearance", "exposure", "associated_symptoms",
})

PATIENT_ATTRS: FrozenSet[str] = frozenset({"age", "sex"})

COMPLAINTS: FrozenSet[str] = frozenset({
    "headache", "chest_pain", "abdominal_pain", "rash", "fever_cough", "generic",
})

SYMPTOM_STATES: FrozenSet[str] = frozenset({"present", "absent", "uncertain"})

SEX_VALUES: FrozenSet[str] = frozenset({"male", "female"})

_SLOT_VALUE_SURFACE: Dict[str, str] = {
    "خفيف": "mild", "بسيط": "mild", "mild": "mild", "slight": "mild",
    "متوسط": "moderate", "moderate": "moderate",
    "شديد": "severe", "قوي": "severe", "لا يحتمل": "severe",
    "severe": "severe", "intense": "severe", "unbearable": "severe",
    "مفاجئ": "sudden", "فجاه": "sudden", "sudden": "sudden", "abrupt": "sudden",
    "تدريجي": "gradual", "gradual": "gradual",
}

MIN_AGE, MAX_AGE = 1, 120

TOPIC_ANCHORS: Dict[str, Tuple[str, ...]] = {
    "duration": ("منذ متي", "متي", "مده", "المده", "ساعات", "ايام", "اسبوع", "يوم",
                 "بدا", "ظهر", "how long", "when did", "since", "hours", "days"),
    "severity": ("شده", "شدت", "قوه", "خفيف", "متوسط", "شديد", "درجه حرارت",
                 "كم بلغت", "how bad", "how high", "rate it", "mild", "moderate",
                 "severe", "temperature"),
    "location": ("اين", "مكان", "جانب", "الجانبين", "جسمك", "الراس",
                 "where", "which side", "one side", "both sides"),
    "location_character": ("اين", "مكان", "بالضبط", "حاد", "مغص", "خفيف",
                           "where", "exactly", "sharp", "cramping", "dull"),
    "character": ("تصف", "طبيعه", "حاد", "ضغط", "ضيق", "خفيف", "حرقه",
                  "describe", "sharp", "dull", "pressure", "tightness", "burning"),
    "radiation": ("ينتشر", "تنتشر", "انتشار", "ذراع", "فك", "ظهر", "رقبه",
                  "spread", "radiat", "arm", "jaw", "back", "neck"),
    "triggers": ("يزيد", "يخفف", "الاكل", "الطعام", "سبق", "محفز", "مجهود",
                 "better", "worse", "eating", "trigger", "before", "exertion"),
    "appearance": ("يبدو", "شكل", "احمر", "بارز", "حكه", "بثور", "مظهر",
                   "look like", "red", "raised", "itchy", "blister", "appear"),
    "exposure": ("خالطت", "مخالطه", "سافرت", "سفر", "مريض", "تعرضت",
                 "contact", "sick", "travel", "expos"),
    "associated_symptoms": ("اعراض", "اخري", "مرافقه", "غثيان", "تقيؤ", "حمي",
                            "ضيق تنفس", "دم في", "تعرق", "دوخه", "مفاصل",
                            "other symptoms", "alongside", "nausea", "vomiting",
                            "fever", "shortness of breath", "blood", "sweating",
                            "dizziness", "sore throat", "joint pain"),
}


class OutOfVocabulary(ValueError):
    """A value has no canonical mapping and must not reach Prolog."""


def is_safe_atom(value: object) -> bool:
    """True only for a value we are willing to write into a Prolog goal.

    Deliberately strict and deliberately positive: an uppercase first letter
    makes it a variable, a dot or parenthesis makes it a term, whitespace or a
    control character makes it a parse error. All of those fail here.
    """
    return (
        isinstance(value, str)
        and len(value) <= MAX_ATOM_CHARS
        and bool(_SAFE_ATOM_RE.match(value))
    )


def require_atom(value: object, *, field: str) -> str:
    if not is_safe_atom(value):
        raise OutOfVocabulary(f"{field}: not a safe atom: {value!r}")
    return value  # type: ignore[return-value]


def _fold(raw: object) -> str:
    """Normalise a surface form for allow-list lookup.

    Reuses the service's own normalizer so Arabic folds exactly the way the
    safety layer and the RAG cache key already fold it, then collapses
    whitespace and case.
    """
    if not isinstance(raw, str):
        return ""
    try:
        folded = normalize_text(raw, None)
    except Exception:  # noqa: BLE001 - normalisation must never break the boundary
        folded = raw
    return " ".join(str(folded).split()).strip().lower()


def _lookup(raw: object, table: Dict[str, str], direct: FrozenSet[str]) -> Optional[str]:
    folded = _fold(raw)
    if not folded:
        return None
    if folded in table:
        return table[folded]
    underscored = folded.replace(" ", "_").replace("-", "_")
    if underscored in direct:
        return underscored
    return table.get(underscored)


def canonical_symptom(raw: object) -> Optional[str]:
    """Arabic or English surface form -> canonical symptom atom, or None."""
    return _lookup(raw, _SYMPTOM_SURFACE, SYMPTOMS)


def canonical_slot(raw: object) -> Optional[str]:
    folded = _fold(raw).replace(" ", "_").replace("-", "_")
    return folded if folded in CLINICAL_SLOTS else None


def canonical_complaint(raw: object) -> Optional[str]:
    folded = _fold(raw).replace(" ", "_").replace("-", "_")
    return folded if folded in COMPLAINTS else None


def canonical_slot_value(raw: object) -> Optional[str]:
    """Recognised slot value, or None when the answer is free text.

    None is not a rejection — fact_builder turns it into UNKNOWN_VALUE so the
    slot still counts as answered. Only recognised values become atoms that
    rules could reason over.
    """
    folded = _fold(raw)
    if not folded:
        return None
    if folded in _SLOT_VALUE_SURFACE:
        return _SLOT_VALUE_SURFACE[folded]
    for surface, canonical in _SLOT_VALUE_SURFACE.items():
        if surface in folded:
            return canonical
    return None


def question_matches_topic(text: object, topic: str) -> bool:
    """Does this generated question still concern the topic it was chosen for?

    The Phase 2 guarantee is that Prolog decides WHAT is asked and the LLM only
    decides HOW. Without this check that guarantee is unenforced: a model asked
    to phrase `duration` can answer with a shortness-of-breath question, and
    nothing downstream would notice.

    Deliberately permissive — one anchor is enough. The job is to catch a
    question that wandered to a different clinical topic, not to police
    phrasing; a false rejection costs one deterministic template question,
    while a false accept silently breaks the split.
    """
    if not isinstance(text, str) or not text.strip():
        return False
    anchors = TOPIC_ANCHORS.get(topic)
    if not anchors:
        return False
    folded = _fold(text)
    return any(anchor in folded for anchor in anchors)


def infer_topic(text: object) -> Optional[str]:
    """Best guess at which topic a question sentence is about, or None.

    Used only to compare the existing planner's choice with the symbolic one in
    shadow-mode divergence logs. Never used to build a fact or drive a
    decision, so an imprecise answer costs an inaccurate log line and nothing
    more — which is why "most anchors matched" is good enough, and why a tie
    resolves to None rather than to a guess.
    """
    if not isinstance(text, str) or not text.strip():
        return None
    folded = _fold(text)
    scores = {
        topic: sum(1 for anchor in anchors if anchor in folded)
        for topic, anchors in TOPIC_ANCHORS.items()
    }
    best = max(scores.values(), default=0)
    if best == 0:
        return None
    winners = [topic for topic, score in scores.items() if score == best]
    return winners[0] if len(winners) == 1 else None


def canonical_urgency(raw: object) -> Optional[str]:
    """The one compatibility boundary: MedicalSafetyLayer's "normal" -> routine.

    Everything downstream of this function speaks routine/urgent/emergency and
    nothing else.
    """
    folded = _fold(raw)
    folded = _LEGACY_URGENCY.get(folded, folded)
    return folded if folded in URGENCY_RANK else None


def canonical_age(raw: object) -> Optional[int]:
    """A plausible integer age, or None.

    Bools are rejected explicitly: isinstance(True, int) is True in Python, and
    an age of `true` is not a fact.
    """
    if isinstance(raw, bool):
        return None
    try:
        age = int(raw)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return age if MIN_AGE <= age <= MAX_AGE else None


def canonical_sex(raw: object) -> Optional[str]:
    folded = _fold(raw)
    return folded if folded in SEX_VALUES else None


VALUE_TOKEN_HEX = 16
_VALUE_TOKEN_RE = re.compile(r"^v_[0-9a-f]{%d}$" % VALUE_TOKEN_HEX)


def value_token(raw: object) -> Optional[Union[str, int]]:
    """A safe, stable, opaque representation of an arbitrary value.

    Returns None for an empty value — absence is not a value, and a token for
    "" would make two unanswered fields look equal.

    Normalisation runs first, so "أحمد " and "أحمد" collapse to one token and a
    trailing space is not mistaken for a correction.
    """
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str) and is_safe_atom(raw):
        return raw
    if not isinstance(raw, str):
        return None
    basis = _fold(raw) or raw.strip()
    if not basis:
        return None
    digest = hashlib.sha256(basis.encode("utf-8")).hexdigest()[:VALUE_TOKEN_HEX]
    return f"v_{digest}"


def is_value_token(value: object) -> bool:
    return isinstance(value, str) and bool(_VALUE_TOKEN_RE.match(value))


def slug_session_key(raw: object) -> str:
    """A safe atom identifying one consultation inside the shared fact store.

    Session ids are UUIDs, whose hyphens make them invalid atoms, so the hex
    digits are prefixed rather than escaped. Anything unusable falls back to a
    digest instead of being passed through.
    """
    text = raw if isinstance(raw, str) else str(raw)
    cleaned = re.sub(r"[^a-z0-9]", "", text.lower())[: MAX_ATOM_CHARS - 2]
    if not cleaned:
        cleaned = hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:32]
    return require_atom(f"s_{cleaned}", field="session_key")
