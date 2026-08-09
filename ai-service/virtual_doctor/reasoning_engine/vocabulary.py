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

# A Prolog atom we are willing to emit: lowercase ASCII, digits, underscore.
# Nothing else. This single expression rejects uppercase (unbound variable)
# payloads, quotes, parentheses, operators, newlines, NUL bytes, Unicode bidi
# controls and every compound term, before a goal is ever built.
_SAFE_ATOM_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# Long atoms have no legitimate source in this vocabulary and are a cheap way
# to stress the parser, so length is capped well above the longest real entry
# ("associated_symptoms" is 19).
MAX_ATOM_CHARS = 64

# Substituted where a slot is genuinely present but its value carries no
# canonical meaning (free-text answers, mostly). Keeps "the patient answered
# this" true without asserting a value the rules could misread.
UNKNOWN_VALUE = "unknown_value"

# --- the one canonical urgency lattice --------------------------------------
# routine < urgent < emergency. MedicalSafetyLayer speaks "normal" where this
# scale says "routine"; that translation happens ONLY in canonical_urgency(),
# the compatibility boundary, and nowhere else. There is exactly one ranking in
# the symbolic layer, and rules/base.pl mirrors it as urgency_rank/2.
URGENCY_LEVELS: Tuple[str, ...] = ("routine", "urgent", "emergency")
URGENCY_RANK: Dict[str, int] = {level: i + 1 for i, level in enumerate(URGENCY_LEVELS)}
_LEGACY_URGENCY = {"normal": "routine"}

# --- canonical symptoms -----------------------------------------------------
# Keys of medical_entities.json["symptoms"], which is what EntityExtractor
# already emits, plus red-flag symptoms the safety layer names that the
# extractor has no key for.
SYMPTOMS: FrozenSet[str] = frozenset({
    "headache", "fever", "cough", "fatigue", "dizziness", "nausea",
    "chest_pain", "shortness_of_breath", "stomach_pain", "stomach_ache",
    "diarrhea", "back_pain", "insomnia", "anxiety", "skin_rash",
    "hematuria", "flank_pain", "unconscious", "severe_bleeding", "seizure",
})

# Arabic and English surface forms -> canonical symptom. Sourced from
# medical_entities.json's own "ar"/"en" lists so the symbolic layer and the
# entity extractor cannot drift apart. Keys are stored already folded through
# the project's existing normalizer (hamza / ta-marbuta folding), which is why
# entries read e.g. "حكه" rather than "حكة".
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

# --- canonical clinical slots ----------------------------------------------
# Mirrors planner.KNOWN_FINDING_KEYS. Kept as a literal rather than imported
# from planner, which would pull retrieval -> db into a module that must stay
# import-cheap; a test asserts the two sets are equal so they cannot drift.
CLINICAL_SLOTS: FrozenSet[str] = frozenset({
    "duration", "severity", "location", "location_character", "character",
    "radiation", "triggers", "appearance", "exposure", "associated_symptoms",
})

PATIENT_ATTRS: FrozenSet[str] = frozenset({"age", "sex"})

# Mirrors retrieval.COMPLAINT_ANCHORS; a test asserts equality.
COMPLAINTS: FrozenSet[str] = frozenset({
    "headache", "chest_pain", "abdominal_pain", "rash", "fever_cough", "generic",
})

SYMPTOM_STATES: FrozenSet[str] = frozenset({"present", "absent", "uncertain"})

SEX_VALUES: FrozenSet[str] = frozenset({"male", "female"})

# Values a slot may take when the answer is recognisable. Anything else that is
# genuinely present becomes UNKNOWN_VALUE — the slot still counts as answered,
# but no rule can read meaning into free text.
_SLOT_VALUE_SURFACE: Dict[str, str] = {
    "خفيف": "mild", "بسيط": "mild", "mild": "mild", "slight": "mild",
    "متوسط": "moderate", "moderate": "moderate",
    "شديد": "severe", "قوي": "severe", "لا يحتمل": "severe",
    "severe": "severe", "intense": "severe", "unbearable": "severe",
    "مفاجئ": "sudden", "فجاه": "sudden", "sudden": "sudden", "abrupt": "sudden",
    "تدريجي": "gradual", "gradual": "gradual",
}

MIN_AGE, MAX_AGE = 1, 120

# --- topic anchors, for clamping generated wording to the chosen topic ------
# Phase 2 splits the interview into "Prolog picks the topic, the LLM words it".
# That split is only real if wording that drifts to a DIFFERENT clinical topic
# is caught, so a generated question is checked for at least one anchor of the
# topic it was supposed to be about.
#
# Same shape and rationale as retrieval.TOPIC_LEXICON (substring matching,
# because Arabic prefixes inflect: الألم / بالألم / للألم). Kept here rather
# than imported from retrieval, which would pull `db` into a module that must
# stay import-cheap.
#
# Calibrated against the flow files themselves: a test asserts every
# question_ar and question_en in flows/*.json passes its own slot's anchors.
# Those strings are the deterministic fallback, so if one failed its own check
# the fallback would be rejected too.
TOPIC_ANCHORS: Dict[str, Tuple[str, ...]] = {
    # Anchors are stored ALREADY FOLDED, because that is what they are matched
    # against: normalize_arabic maps ى->ي, ة->ه and أإآ->ا, so an anchor written
    # in surface form ("منذ متى") can never match the folded text ("منذ متي").
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
    # "دم في", not bare "دم": substring matching would otherwise fire on the
    # everyday word "عندما".
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


# --- opaque tokens for unrestricted free-text values (Phase 4) --------------
# Contradiction reasoning needs to compare a patient's stored name with a newly
# stated one. A name is arbitrary free text, so it can never be an atom — and
# the allow-list is not going to be widened to admit it.
#
# It does not need to be. The only question the rules ask of such a value is
# "is this the same as that one?", which a stable opaque token answers exactly
# as well as the text would. So Python hashes the normalised value into
# `v_<hex>` and keeps the mapping on its side; Prolog compares tokens and never
# sees a name.
#
# Same-length prefix of SHA-256, so tokens are fixed-width, always valid atoms,
# and stable across processes and restarts — the last property matters because
# provenance is rebuilt from the database every turn and must produce the same
# token for the same stored value.
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
        # Integers are already safe to compare directly, carry no free text and
        # are far more useful than a hash in an evidence trace, so they pass
        # through untokenised. An age of 23 really is `23` in the reasoning.
        return raw
    if isinstance(raw, str) and is_safe_atom(raw):
        # Already a canonical atom (a slot value like `severe`): keep it
        # readable rather than hashing meaning away.
        return raw
    if not isinstance(raw, str):
        return None
    # Fold first, so "أحمد " and "أحمد" collapse to one token and a trailing
    # space is not mistaken for a correction.
    #
    # Fall back to the raw (whitespace-stripped) value when folding erases
    # everything: normalize_english strips every non-[a-z0-9] character, so a
    # name written entirely in a script the normalizer does not handle — CJK,
    # for instance — would otherwise produce no token at all, and a patient
    # with such a name would silently get no contradiction detection. The
    # fallback keeps every non-empty value representable; it only loses the
    # variant-collapsing, which is the lesser property.
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
