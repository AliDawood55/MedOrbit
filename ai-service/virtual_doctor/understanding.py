"""
Virtual Doctor — structured clinical understanding (Phase 6).

    patient text -> LLM -> JSON -> schema -> allow-list -> typed objects

WHAT THIS LAYER IS FOR
----------------------
The legacy EntityExtractor is a keyword matcher, and a keyword matcher cannot
represent polarity. tests/test_characterization_understanding.py pins what it
actually does today — all four of these produce ['fever']:

    "I have a fever"                      a report
    "I do not have a fever"               a DENIAL, read as present
    "I am not sure if I have a fever"     hedging, read as present
    "I had a fever last week"             resolved, read as present

Four different clinical statements, one fact. That is the gap this module
closes: the LLM's job here is to read LANGUAGE — negation, hedging, tense — and
report what was said, in a fixed structure. It is a parser, not a clinician.

WHAT THIS LAYER IS NOT FOR
--------------------------
It does not diagnose, and structurally it cannot. The prompt forbids
conditions, and the validator refuses them: a `condition`/`diagnosis`/
`differential` key in the model's JSON is dropped and counted, never read
(_FORBIDDEN_KEYS). Phase 5 was deferred because MedOrbit has no grounded
symptom-to-condition source; asking this model for conditions would route
around that decision rather than respect it.

THE TRUST BOUNDARY IS UNCHANGED
-------------------------------
Model output is untrusted input — as untrusted as the patient text it was
derived from, and in one way worse, because it arrives already shaped like
data. So nothing here widens vocabulary.py. The model is handed the allow-list
in its prompt and its answer is checked against that same allow-list; a term
outside it is rejected and counted, never mapped by guesswork and never added.
The vocabulary is application code, and a model returning a new word is not a
reason to change application code.

    LLM JSON -> parse -> schema -> canonical mapping -> allow-list -> objects
                                                                       |
                                            fact_builder <-------------+
                                                  |
                                                Prolog

No branch of that path passes a model-authored string to Prolog. Symptoms
become canonical atoms already in vocabulary.SYMPTOMS or they are dropped;
free-text answers become vocabulary.UNKNOWN_VALUE.

REACHABILITY, NOT NEW KNOWLEDGE
-------------------------------
Four rules in rules/safety.pl have been latent since Phase 3 — hematuria,
seizure, unconscious, severe_bleeding — because the extractor has no key for
any of them (its 15 keys are the whole of medical_entities.json["symptoms"]).
Each is already in vocabulary.SYMPTOMS and each traces to two approved MedOrbit
sources; the provenance is recorded in LATENT_SAFETY_ATOMS below. This module
makes them reachable. It adds no symptom that was not already vocabulary.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

import requests

from .reasoning_engine import vocabulary
from .reasoning_engine.result_models import RejectedValue
from .config import env_float

logger = logging.getLogger("medorbit-ai.virtual_doctor.understanding")

MODES: Tuple[str, ...] = ("off", "shadow", "active")
MODE_DEFAULT = "off"


def mode() -> str:
    """Resolved rollout mode. An unrecognised setting is never `active`."""
    raw = os.environ.get("VD_STRUCTURED_UNDERSTANDING", MODE_DEFAULT).strip().lower()
    if raw not in MODES:
        logger.warning(
            "Unknown VD_STRUCTURED_UNDERSTANDING=%r — falling back to %r", raw, MODE_DEFAULT
        )
        return MODE_DEFAULT
    return raw


def enabled() -> bool:
    return mode() != "off"


def active() -> bool:
    return mode() == "active"


MODEL = os.environ.get("VD_UNDERSTANDING_MODEL", "qwen2.5:3b")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
CHAT_URL = os.environ.get("OLLAMA_CHAT_URL", OLLAMA_URL.replace("/api/generate", "/api/chat"))
TIMEOUT = env_float("VD_UNDERSTANDING_TIMEOUT", 20.0, minimum=0.0,
                    exclusive_min=True)
KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "1h")

MAX_SYMPTOMS = 24
MAX_FINDINGS = 24
MAX_CORRECTIONS = 6
MAX_VALUE_CHARS = 200
MAX_PAYLOAD_CHARS = 20000

ALLOWED_SYMPTOMS: Tuple[str, ...] = tuple(sorted(vocabulary.SYMPTOMS))
ALLOWED_SLOTS: Tuple[str, ...] = tuple(sorted(vocabulary.CLINICAL_SLOTS))
ALLOWED_STATUSES: Tuple[str, ...] = ("present", "absent", "uncertain")

IDENTITY_CORRECTION_FIELDS: Tuple[str, ...] = ("name", "age", "sex", "chief_complaint")
ALLOWED_CORRECTION_FIELDS: Tuple[str, ...] = tuple(sorted(
    set(IDENTITY_CORRECTION_FIELDS) | set(vocabulary.CLINICAL_SLOTS)
))

LATENT_SAFETY_ATOMS: Dict[str, Tuple[str, ...]] = {
    "hematuria": (
        "MedicalSafetyLayer.URGENT_PATTERNS_AR[4] (four Arabic variants)",
        "MedicalSafetyLayer.URGENT_PATTERNS_AR[12] blood in (vomit|stool|urine)",
        "db/07_triage_tables.sql: ('blood in urine', Nephrology, 4.00)",
    ),
    "seizure": (
        "MedicalSafetyLayer.URGENT_PATTERNS_AR[8] seizure/convulsion (Arabic)",
        "MedicalSafetyLayer.URGENT_PATTERNS_AR[14] seizure|convulsion|fitting",
        "db/07_triage_tables.sql: ('seizure', Neurology, 4.00)",
    ),
    "unconscious": (
        "MedicalSafetyLayer.EMERGENCY_PATTERNS_AR[3] loss of consciousness (Arabic)",
        "MedicalSafetyLayer.EMERGENCY_PATTERNS_AR[14] unconscious|passed out|fainted",
        "db/07_triage_tables.sql: ('unconscious', Emergency Medicine, 5.00)",
    ),
    "severe_bleeding": (
        "MedicalSafetyLayer.EMERGENCY_PATTERNS_AR[5] severe bleeding (Arabic)",
        "MedicalSafetyLayer.EMERGENCY_PATTERNS_AR[12] ...|severe bleeding",
        "db/07_triage_tables.sql: ('severe bleeding', Emergency Medicine, 5.00)",
    ),
}

FORBIDDEN_KEYS = frozenset({
    "condition", "conditions", "diagnosis", "diagnoses", "differential",
    "rule", "rules", "predicate", "predicates", "prolog", "goal", "query",
    "urgency", "severity_level", "red_flag", "red_flags", "emergency",
    "is_emergency", "triage", "assessment",
})

KNOWN_KEYS = frozenset({"symptoms", "findings", "corrections", "language"})

_STATUS_SURFACE: Dict[str, str] = {
    "present": "present", "yes": "present", "true": "present",
    "positive": "present", "confirmed": "present", "reported": "present",
    "absent": "absent", "no": "absent", "false": "absent",
    "negative": "absent", "denied": "absent", "denies": "absent",
    "negated": "absent",
    "uncertain": "uncertain", "unsure": "uncertain", "unknown": "uncertain",
    "maybe": "uncertain", "possible": "uncertain", "suspected": "uncertain",
    "unclear": "uncertain",
}

_HISTORICAL_VALUES = frozenset({"historical", "past", "resolved", "previous", "old"})

_STATE_PRECEDENCE = {"present": 3, "uncertain": 2, "absent": 1}



@dataclass(frozen=True)
class SymptomObservation:
    """One symptom the patient mentioned, with the polarity they used.

    `symptom` is always a canonical atom already in vocabulary.SYMPTOMS,
    re-validated in __post_init__ so a hand-built observation cannot smuggle an
    unchecked term past the validator any more than a hand-built Fact can.
    """

    symptom: str
    status: str
    certainty: str = "confirmed"

    def __post_init__(self) -> None:
        if self.symptom not in vocabulary.SYMPTOMS:
            raise vocabulary.OutOfVocabulary(f"symptom: not in vocabulary: {self.symptom!r}")
        if self.status not in ALLOWED_STATUSES:
            raise vocabulary.OutOfVocabulary(f"status: not a status: {self.status!r}")


@dataclass(frozen=True)
class SlotFinding:
    """A clinical slot the patient answered.

    `value` is a canonical slot value (`severe`, `sudden`, ...) or
    vocabulary.UNKNOWN_VALUE when the answer was free text. `canonical` says
    which, so a caller can tell "answered with something the rules can read"
    from "answered, meaning unavailable" without re-deriving it.
    """

    slot: str
    value: str
    canonical: bool

    def __post_init__(self) -> None:
        if self.slot not in vocabulary.CLINICAL_SLOTS:
            raise vocabulary.OutOfVocabulary(f"slot: not in vocabulary: {self.slot!r}")
        vocabulary.require_atom(self.value, field="slot_value")


@dataclass(frozen=True)
class CorrectionCandidate:
    """A correction the patient appears to be making.

    Phase 6 produces these; it does not act on them. The deterministic Python
    parser still runs, the Phase 4 symbolic reasoner still classifies, and
    Python still owns every profile mutation. `new_value` stays as text because
    the correction layer needs text — it is passed through
    vocabulary.value_token before anything reaches Prolog, and this object is
    never rendered into a goal.
    """

    field: str
    new_value: str
    old_value: Optional[str] = None
    explicit: bool = False

    def __post_init__(self) -> None:
        if self.field not in ALLOWED_CORRECTION_FIELDS:
            raise vocabulary.OutOfVocabulary(f"correction field: {self.field!r}")


@dataclass(frozen=True)
class ClinicalUnderstanding:
    """One turn of structured understanding, or an explicit absence of one.

    `available` False is kept distinct from "found nothing", for the same
    reason it is everywhere else in this codebase: a layer that could not run
    has said nothing, and silence must never read as a denial. A caller
    treating unavailable-as-empty would let a model timeout look like a patient
    denying every symptom.
    """

    symptoms: Tuple[SymptomObservation, ...] = ()
    findings: Tuple[SlotFinding, ...] = ()
    corrections: Tuple[CorrectionCandidate, ...] = ()
    language: Optional[str] = None
    available: bool = True
    malformed: bool = False
    reason: Optional[str] = None
    rejected: Tuple[RejectedValue, ...] = ()
    conflicts: Tuple[str, ...] = ()
    forbidden_keys: Tuple[str, ...] = ()
    unknown_keys: Tuple[str, ...] = ()
    elapsed_ms: float = 0.0

    @classmethod
    def unavailable(cls, reason: str, *, malformed: bool = False,
                    elapsed_ms: float = 0.0) -> "ClinicalUnderstanding":
        return cls(available=False, malformed=malformed, reason=reason,
                   elapsed_ms=elapsed_ms)

    def _by_status(self, status: str) -> Tuple[str, ...]:
        return tuple(sorted({o.symptom for o in self.symptoms if o.status == status}))

    @property
    def present_symptoms(self) -> Tuple[str, ...]:
        return self._by_status("present")

    @property
    def denied_symptoms(self) -> Tuple[str, ...]:
        return self._by_status("absent")

    @property
    def uncertain_symptoms(self) -> Tuple[str, ...]:
        return self._by_status("uncertain")

    def as_log_fields(self) -> Dict[str, Any]:
        """PHI-free. Canonical atoms and counts only — never raw speech, never
        a name, never a free-text value. Corrections are reported as field
        names; their values are patient data and stay out."""
        return {
            "available": self.available,
            "malformed": self.malformed,
            "reason": self.reason,
            "present": list(self.present_symptoms),
            "denied": list(self.denied_symptoms),
            "uncertain": list(self.uncertain_symptoms),
            "findings": sorted(f.slot for f in self.findings),
            "correction_fields": sorted({c.field for c in self.corrections}),
            "n_rejected": len(self.rejected),
            "conflicts": list(self.conflicts),
            "forbidden_keys": list(self.forbidden_keys),
            "unknown_keys": list(self.unknown_keys),
            "elapsed_ms": round(self.elapsed_ms, 1),
        }



_BIDI_CONTROLS = frozenset(
    list(range(0x200E, 0x2010)) + list(range(0x202A, 0x202F)) + list(range(0x2066, 0x206A))
)


def _text(raw: Any) -> Optional[str]:
    """A bounded, control-character-free string, or None.

    Rejects the whole family of payloads that are dangerous precisely because
    they are not obviously dangerous: NULs, Unicode bidi controls, embedded
    newlines and oversized values. This runs before any canonical lookup, so
    none of them reach the allow-list, let alone a goal.
    """
    if isinstance(raw, bool) or not isinstance(raw, str):
        return None
    if len(raw) > MAX_VALUE_CHARS:
        return None
    if "\x00" in raw or any(ord(ch) in _BIDI_CONTROLS for ch in raw):
        return None
    cleaned = " ".join(raw.split()).strip()
    return cleaned or None


def _status_of(raw: Any) -> Optional[str]:
    text = _text(raw)
    if text is None:
        return None
    return _STATUS_SURFACE.get(text.lower())


def _is_historical(entry: Mapping[str, Any]) -> bool:
    if entry.get("historical") is True or entry.get("resolved") is True:
        return True
    timing = _text(entry.get("timing")) or _text(entry.get("tense"))
    return bool(timing and timing.lower() in _HISTORICAL_VALUES)


def _parse_symptoms(raw: Any, rejected: List[RejectedValue]) -> List[SymptomObservation]:
    """Model symptom entries -> validated observations.

    Accepts both shapes a small model produces: a bare string ("fever", which
    means present) and an object ({"symptom": "fever", "status": "absent"}).
    Anything else is a rejection, not a guess.
    """
    if not isinstance(raw, (list, tuple)):
        if raw is not None:
            rejected.append(RejectedValue.of("symptoms", "not a list", type(raw).__name__))
        return []

    observations: List[SymptomObservation] = []
    for entry in list(raw)[:MAX_SYMPTOMS]:
        if isinstance(entry, Mapping):
            label = entry.get("symptom") or entry.get("name") or entry.get("label")
            status = _status_of(entry.get("status")) or "present"
            certainty = _text(entry.get("certainty")) or "confirmed"
            historical = _is_historical(entry)
        elif isinstance(entry, str):
            label, status, certainty, historical = entry, "present", "confirmed", False
        else:
            rejected.append(RejectedValue.of("symptom", "unsupported entry type",
                                             type(entry).__name__))
            continue

        text = _text(label)
        if text is None:
            rejected.append(RejectedValue.of("symptom", "unusable label", label))
            continue

        canonical = vocabulary.canonical_symptom(text)
        if canonical is None:
            rejected.append(RejectedValue.of("symptom", "not in vocabulary", text))
            continue

        if historical:
            rejected.append(RejectedValue.of("symptom", "historical, not current", canonical))
            continue

        safe_certainty = certainty.lower() if vocabulary.is_safe_atom(certainty.lower()) else "confirmed"
        observations.append(SymptomObservation(symptom=canonical, status=status,
                                               certainty=safe_certainty))
    return observations


def _collapse(observations: Sequence[SymptomObservation]) -> Tuple[
    Tuple[SymptomObservation, ...], Tuple[str, ...]
]:
    """One observation per symptom, with contradictions recorded.

    Returns the collapsed observations and the symptoms the model gave
    conflicting polarities for. A conflict is resolved upward (see
    _STATE_PRECEDENCE) so this can only ever escalate, never suppress.
    """
    best: Dict[str, SymptomObservation] = {}
    conflicts: List[str] = []
    for obs in observations:
        existing = best.get(obs.symptom)
        if existing is None:
            best[obs.symptom] = obs
            continue
        if existing.status != obs.status and obs.symptom not in conflicts:
            conflicts.append(obs.symptom)
        if _STATE_PRECEDENCE[obs.status] > _STATE_PRECEDENCE[existing.status]:
            best[obs.symptom] = obs
    ordered = tuple(sorted(best.values(), key=lambda o: o.symptom))
    return ordered, tuple(sorted(conflicts))


def _parse_findings(raw: Any, rejected: List[RejectedValue]) -> List[SlotFinding]:
    """Model findings -> validated slot answers.

    An off-vocabulary slot name is rejected outright: attribute names are
    application vocabulary (flows/*.json, planner.KNOWN_FINDING_KEYS) and a
    model does not get to add one. An off-vocabulary VALUE is different — the
    slot really was answered, so it becomes UNKNOWN_VALUE, exactly as
    fact_builder does for free-text profile values.
    """
    if not isinstance(raw, Mapping):
        if raw is not None:
            rejected.append(RejectedValue.of("findings", "not an object", type(raw).__name__))
        return []

    findings: List[SlotFinding] = []
    for key, value in list(raw.items())[:MAX_FINDINGS]:
        slot = vocabulary.canonical_slot(key)
        if slot is None:
            rejected.append(RejectedValue.of("finding", "slot not in vocabulary", key))
            continue
        text = _text(value)
        if text is None:
            rejected.append(RejectedValue.of(f"finding.{slot}", "unusable value", value))
            continue
        canonical = vocabulary.canonical_slot_value(text)
        findings.append(SlotFinding(slot=slot,
                                    value=canonical or vocabulary.UNKNOWN_VALUE,
                                    canonical=canonical is not None))
    return findings


def _parse_corrections(raw: Any, rejected: List[RejectedValue]) -> List[CorrectionCandidate]:
    if not isinstance(raw, (list, tuple)):
        if raw is not None:
            rejected.append(RejectedValue.of("corrections", "not a list", type(raw).__name__))
        return []

    corrections: List[CorrectionCandidate] = []
    for entry in list(raw)[:MAX_CORRECTIONS]:
        if not isinstance(entry, Mapping):
            rejected.append(RejectedValue.of("correction", "unsupported entry type",
                                             type(entry).__name__))
            continue
        raw_field = _text(entry.get("field"))
        field_name = (raw_field or "").lower().replace(" ", "_").replace("-", "_")
        if field_name not in ALLOWED_CORRECTION_FIELDS:
            rejected.append(RejectedValue.of("correction", "field not correctable", raw_field))
            continue
        new_value = _text(entry.get("new_value"))
        if new_value is None:
            rejected.append(RejectedValue.of(f"correction.{field_name}",
                                             "no usable new value", entry.get("new_value")))
            continue
        corrections.append(CorrectionCandidate(
            field=field_name,
            new_value=new_value,
            old_value=_text(entry.get("old_value")),
            explicit=entry.get("explicit") is True,
        ))
    return corrections


def parse_understanding(payload: Any, *, elapsed_ms: float = 0.0) -> ClinicalUnderstanding:
    """Untrusted model output -> a validated ClinicalUnderstanding.

    Pure and synchronous: no I/O, no model, no clock. That is what makes the
    hostile-payload tests meaningful — every red-team case is exercised right
    here, with no network in the way.

    Never raises. A payload this cannot make sense of yields
    ClinicalUnderstanding.unavailable(), which callers treat as "said nothing",
    not as "found nothing".
    """
    if not isinstance(payload, Mapping):
        return ClinicalUnderstanding.unavailable("payload is not an object",
                                                 malformed=True, elapsed_ms=elapsed_ms)

    forbidden = tuple(sorted(k for k in payload if isinstance(k, str) and k.lower() in FORBIDDEN_KEYS))
    unknown = tuple(sorted(
        k for k in payload
        if isinstance(k, str) and k.lower() not in KNOWN_KEYS and k.lower() not in FORBIDDEN_KEYS
    ))
    if forbidden:
        logger.warning("Structured understanding returned forbidden keys %s — ignored", list(forbidden))

    rejected: List[RejectedValue] = []
    observations = _parse_symptoms(payload.get("symptoms"), rejected)
    collapsed, conflicts = _collapse(observations)

    language = _text(payload.get("language"))
    if language is not None:
        language = language.lower()[:2]
        if language not in ("ar", "en"):
            language = None

    return ClinicalUnderstanding(
        symptoms=collapsed,
        findings=tuple(_parse_findings(payload.get("findings"), rejected)),
        corrections=tuple(_parse_corrections(payload.get("corrections"), rejected)),
        language=language,
        available=True,
        malformed=False,
        rejected=tuple(rejected),
        conflicts=conflicts,
        forbidden_keys=forbidden,
        unknown_keys=unknown,
        elapsed_ms=elapsed_ms,
    )



_SYSTEM = {
    "ar": (
        "You extract structured clinical observations from what a patient said. "
        "You are a language parser, not a doctor. You never diagnose."
    ),
    "en": (
        "You extract structured clinical observations from what a patient said. "
        "You are a language parser, not a doctor. You never diagnose."
    ),
}

_USER_TEMPLATE = """Patient said (language: {language}):
{message}

Extract ONLY what the patient explicitly stated or clearly implied by their own words.

ALLOWED symptom values — you may use NO other symptom word:
{symptoms}

ALLOWED finding keys — you may use NO other key:
{slots}

status must be exactly one of: present, absent, uncertain
  present    the patient says they have it
  absent     the patient says they do NOT have it
  uncertain  the patient is unsure, hedging, or says "maybe"

Set "historical": true for something the patient says is over ("last week", "it stopped").

Return ONLY this JSON object:
{{
  "symptoms": [{{"symptom": "<allowed symptom>", "status": "<present|absent|uncertain>", "historical": false}}],
  "findings": {{"<allowed finding key>": "<what the patient said about it>"}},
  "corrections": [{{"field": "name|age|sex|chief_complaint", "old_value": "", "new_value": "", "explicit": true}}],
  "language": "{language}"
}}

Rules:
- NEVER output a disease, condition, or diagnosis. Not in any field.
- NEVER invent a symptom the patient did not mention.
- NEVER use a symptom word outside the allowed list. If what they said is not
  on the list, leave it out entirely.
- A denial is NOT the same as no mention. "I do not have a fever" is
  {{"symptom": "fever", "status": "absent"}}.
- Use empty list / empty object when the patient said nothing of that kind.
- Return JSON only. No explanation."""


def build_prompt(message: str, lang: str) -> str:
    """The user-side prompt. Split out so a test can assert what the model is
    told — that the allow-list is actually in it, and that the forbidden
    instruction is actually stated."""
    return _USER_TEMPLATE.format(
        language="ar" if lang == "ar" else "en",
        message=message,
        symptoms=", ".join(ALLOWED_SYMPTOMS),
        slots=", ".join(ALLOWED_SLOTS),
    )


def _extract_json(text: Any) -> Optional[dict]:
    """Model text -> dict, tolerating the prose a small model wraps JSON in.

    Same two-step as planner._extract_json: parse the whole string, then fall
    back to the outermost {...}. Prose AROUND valid JSON is recoverable and
    recovering it is the difference between a working turn and a wasted model
    call; prose INSTEAD of JSON is not, and yields None.
    """
    if not isinstance(text, str):
        return None
    if len(text) > MAX_PAYLOAD_CHARS:
        text = text[:MAX_PAYLOAD_CHARS]
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else None
    except (json.JSONDecodeError, TypeError, ValueError):
        pass
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        parsed = json.loads(match.group())
    except (json.JSONDecodeError, ValueError):
        return None
    return parsed if isinstance(parsed, dict) else None


async def understand(message: str, lang: str = "ar") -> ClinicalUnderstanding:
    """Read one patient message into structured observations.

    Never raises and never blocks the consultation: every failure mode —
    timeout, connection refused, HTTP error, prose instead of JSON, a payload
    of the wrong shape — resolves to ClinicalUnderstanding.unavailable(), and
    the caller carries on with the legacy extractor.
    """
    if not enabled():
        return ClinicalUnderstanding.unavailable("disabled")
    if not isinstance(message, str) or not message.strip():
        return ClinicalUnderstanding.unavailable("empty message")

    started = time.perf_counter()
    try:
        response = await asyncio.to_thread(
            requests.post,
            CHAT_URL,
            json={
                "model": MODEL,
                "messages": [
                    {"role": "system", "content": _SYSTEM.get(lang, _SYSTEM["en"])},
                    {"role": "user", "content": build_prompt(message, lang)},
                ],
                "stream": False,
                "format": "json",
                "keep_alive": KEEP_ALIVE,
                "options": {"temperature": 0.1},
            },
            timeout=TIMEOUT,
        )
        response.raise_for_status()
        content = response.json().get("message", {}).get("content", "")
    except Exception as exc:  # noqa: BLE001 - every failure degrades, none propagates
        elapsed = (time.perf_counter() - started) * 1000
        logger.info("Structured understanding unavailable (%s) — legacy extraction stands", exc)
        return ClinicalUnderstanding.unavailable(f"call failed: {type(exc).__name__}",
                                                 elapsed_ms=elapsed)

    elapsed = (time.perf_counter() - started) * 1000
    payload = _extract_json(content)
    if payload is None:
        logger.info("Structured understanding returned unparseable output — legacy extraction stands")
        return ClinicalUnderstanding.unavailable("unparseable output", malformed=True,
                                                elapsed_ms=elapsed)
    return parse_understanding(payload, elapsed_ms=elapsed)



def legacy_canonical_symptoms(entities: Optional[Mapping[str, Any]]) -> Tuple[str, ...]:
    """What the legacy extractor found, in canonical form, for comparison."""
    if not isinstance(entities, Mapping):
        return ()
    found = {
        canonical
        for raw in (entities.get("symptoms") or [])
        if (canonical := vocabulary.canonical_symptom(raw)) is not None
    }
    return tuple(sorted(found))


def divergence(understanding: ClinicalUnderstanding,
               entities: Optional[Mapping[str, Any]]) -> Dict[str, Any]:
    """PHI-free comparison of the two extractors.

    Deliberately reports `denied` and `uncertain` separately from the set
    arithmetic: the legacy extractor cannot express either, so they are not
    disagreements about a symptom, they are information it has no way to hold.
    Counting them as "structured only" would understate the point.
    """
    legacy = set(legacy_canonical_symptoms(entities))
    structured = set(understanding.present_symptoms)
    newly_reachable = sorted(structured & set(LATENT_SAFETY_ATOMS))
    return {
        "mode": mode(),
        "available": understanding.available,
        "legacy": sorted(legacy),
        "structured": sorted(structured),
        "agree": sorted(legacy & structured),
        "structured_only": sorted(structured - legacy),
        "legacy_only": sorted(legacy - structured),
        "denied": list(understanding.denied_symptoms),
        "uncertain": list(understanding.uncertain_symptoms),
        "conflicts": list(understanding.conflicts),
        "n_rejected": len(understanding.rejected),
        "malformed": understanding.malformed,
        "forbidden_keys": list(understanding.forbidden_keys),
        "newly_reachable_safety": newly_reachable,
        "elapsed_ms": round(understanding.elapsed_ms, 1),
    }
