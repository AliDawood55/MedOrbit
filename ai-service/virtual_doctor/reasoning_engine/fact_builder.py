"""
Virtual Doctor — session state -> validated symbolic facts.

Rebuilt from scratch every turn out of the authoritative Python/PostgreSQL
state. Prolog is never the memory: whatever it knows this turn came from the
session row, so a restarted process, a new worker or a replayed consultation
all reconstruct the same facts.

Every value crosses the allow-list on its way in (see vocabulary). A value with
no canonical mapping is dropped and reported as a RejectedValue rather than
guessed at, except where "present but unrecognised" is itself the useful fact —
a free-text slot answer becomes UNKNOWN_VALUE so `answered/2` stays true
without any rule being able to read meaning into patient prose.

This module makes no clinical decisions. It records what is known; it does not
rank, prioritise, or conclude.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple  # noqa: F401

from chatbot.nlu.safety import MedicalSafetyLayer

from . import vocabulary
from .result_models import Fact, FactSet, RejectedValue, StatedFact

logger = logging.getLogger("medorbit-ai.virtual_doctor.reasoning_engine")

_NON_CLINICAL_PROFILE_KEYS = frozenset({
    "name", "age", "chief_complaint_description", "associated_symptoms_detected",
    "pending_confirmation", "pending_correction", "confirmed_fields",
    "uncertain_fields", "correction_history", "safety_warning_shown_for",
    "safety_flags_detected", "name_repeat_attempts", "other",
    "symbolic_asked_topics",
})

_SYMPTOM_STATE_PRECEDENCE = {"present": 3, "uncertain": 2, "absent": 1}


def _safety_rule_index() -> Dict[str, str]:
    """Map each MedicalSafetyLayer regex to a stable, atom-safe rule id.

    The matched TEXT is Arabic patient speech and can never be an atom, but a
    verdict still has to be explainable. The pattern's position in the safety
    layer's own list is stable, auditable and maps straight back to the source
    line, so `safety_urgent_04` identifies exactly which red flag fired.
    """
    index: Dict[str, str] = {}
    for tier, patterns in (
        ("emergency", MedicalSafetyLayer.EMERGENCY_PATTERNS_AR),
        ("urgent", MedicalSafetyLayer.URGENT_PATTERNS_AR),
    ):
        for position, pattern in enumerate(patterns):
            index[pattern] = f"safety_{tier}_{position:02d}"
    return index


_SAFETY_RULE_IDS = _safety_rule_index()


class _Accumulator:
    """Collects facts with one state per (predicate, subject), plus rejections."""

    def __init__(self, session: str) -> None:
        self._session = session
        self._facts: Dict[Tuple[str, str], Fact] = {}
        self._rejected: List[RejectedValue] = []

    def add(self, predicate: str, subject: str, value: Any) -> None:
        try:
            fact = Fact(session=self._session, predicate=predicate,
                        subject=subject, value=value)
        except vocabulary.OutOfVocabulary as exc:
            self._rejected.append(RejectedValue.of(predicate, str(exc), subject))
            return
        key = (predicate, subject)
        existing = self._facts.get(key)
        if existing is None:
            self._facts[key] = fact
            return
        if predicate == "symptom":
            if _SYMPTOM_STATE_PRECEDENCE.get(str(fact.value), 0) > _SYMPTOM_STATE_PRECEDENCE.get(
                str(existing.value), 0
            ):
                self._facts[key] = fact

    def reject(self, field: str, reason: str, raw: Any) -> None:
        self._rejected.append(RejectedValue.of(field, reason, raw))

    def result(self) -> FactSet:
        return FactSet(facts=tuple(self._facts.values()), rejected=tuple(self._rejected))


def _iter_strings(raw: Any) -> Iterable[Any]:
    """Yield elements of a list-ish value; yield nothing for anything else."""
    if isinstance(raw, (list, tuple, set, frozenset)):
        return list(raw)
    return ()


def _add_symptoms(acc: _Accumulator, raw_symptoms: Any, state: str, field: str) -> None:
    for raw in _iter_strings(raw_symptoms):
        canonical = vocabulary.canonical_symptom(raw)
        if canonical is None:
            acc.reject(field, "symptom not in vocabulary", raw)
            continue
        acc.add("symptom", canonical, state)


def _add_flow_slots(acc: _Accumulator, flow_slots: Sequence[Any]) -> None:
    """The active complaint's slots, in declared order, as required/optional.

    flows/*.json stays the single source of truth: the slot vocabulary and its
    ORDER are carried in as facts rather than restated in interview.pl, so
    editing a flow file still changes the interview.

    The `required` flag is honoured even though every slot in every flow is
    currently required — that is what the schema says, and reading it means
    an optional slot would behave correctly the day one is added.
    """
    for position, slot in enumerate(flow_slots):
        if isinstance(slot, Mapping):
            raw_key, required = slot.get("key"), slot.get("required", True)
        else:
            raw_key, required = slot, True
        topic = vocabulary.canonical_slot(raw_key)
        if topic is None:
            acc.reject("flow_slot", "slot not in vocabulary", raw_key)
            continue
        acc.add("required_slot" if required else "optional_slot", topic, position)


def _add_interview_state(
    acc: _Accumulator, profile: Mapping[str, Any], asked_topics: Sequence[Any],
) -> None:
    """Intake completeness and which topics have already been put to the patient.

    Intake is recorded as a BOOLEAN, never the name itself: whether a name
    exists is all the rules need, and a patient's name has no business being
    an atom in a reasoning store.
    """
    name = profile.get("name")
    if isinstance(name, str) and name.strip():
        acc.add("intake", "name", "true")

    for raw in asked_topics:
        topic = vocabulary.canonical_slot(raw)
        if topic is None:
            acc.reject("asked_topic", "topic not in vocabulary", raw)
            continue
        acc.add("asked", topic, "true")


SAFETY_FOLLOW_UP_TOPIC = "associated_symptoms"


def safety_topics_for(safety_result: Optional[Mapping[str, Any]]) -> Tuple[str, ...]:
    """Topics to prioritise given a deterministic safety verdict.

    ORDERING ONLY. This reads the verdict; it cannot contribute to it. Making
    the red-flag follow-up deterministic is exactly what PlannerInput
    .safety_hint previously only nudged the LLM towards.
    """
    if not isinstance(safety_result, Mapping):
        return ()
    level = vocabulary.canonical_urgency(safety_result.get("severity"))
    return (SAFETY_FOLLOW_UP_TOPIC,) if level in ("urgent", "emergency") else ()


def _add_safety_topics(acc: _Accumulator, safety_topics: Sequence[Any]) -> None:
    for raw in safety_topics:
        topic = vocabulary.canonical_slot(raw)
        if topic is None:
            acc.reject("safety_topic", "topic not in vocabulary", raw)
            continue
        acc.add("safety_topic", topic, "true")


def _add_slots(acc: _Accumulator, profile: Mapping[str, Any]) -> None:
    """Clinical slots from the profile, plus the answered/expected knowledge state.

    `other` is walked too: the LLM planner files off-vocabulary findings there,
    and one of them occasionally IS a canonical slot under a reworded key.
    """
    sources: List[Tuple[str, Any]] = [
        (key, value) for key, value in profile.items()
        if key not in _NON_CLINICAL_PROFILE_KEYS
    ]
    other = profile.get("other")
    if isinstance(other, Mapping):
        sources.extend(other.items())

    for key, value in sources:
        slot = vocabulary.canonical_slot(key)
        if slot is None:
            acc.reject("slot", "slot not in vocabulary", key)
            continue
        if not isinstance(value, str) or not value.strip():
            continue
        acc.add("slot", slot, vocabulary.canonical_slot_value(value) or vocabulary.UNKNOWN_VALUE)
        acc.add("answered", slot, "true")

    for slot in sorted(vocabulary.CLINICAL_SLOTS):
        acc.add("expected_slot", slot, "true")


def _add_patient_attrs(acc: _Accumulator, profile: Mapping[str, Any]) -> None:
    age = vocabulary.canonical_age(profile.get("age"))
    if age is not None:
        acc.add("patient_attr", "age", age)
    elif profile.get("age") is not None:
        acc.reject("patient_attr.age", "age out of range or not numeric", profile.get("age"))

    sex = vocabulary.canonical_sex(profile.get("sex"))
    if sex is not None:
        acc.add("patient_attr", "sex", sex)


def _add_safety(acc: _Accumulator, safety_result: Optional[Mapping[str, Any]]) -> None:
    """The deterministic Python floor, asserted as fact — never as a rule.

    MedicalSafetyLayer keeps running on raw patient text exactly as it does
    today; this only mirrors its verdict into the symbolic store so Prolog can
    read it. Prolog may raise the level (final_urgency/2 is a maximum) and has
    no way to lower it. Invariants S1, S13.
    """
    if not safety_result:
        return
    level = vocabulary.canonical_urgency(safety_result.get("severity"))
    if level is None:
        acc.reject("deterministic_urgency", "unknown severity", safety_result.get("severity"))
        return
    if level == "routine":
        return

    matched = safety_result.get("matched_patterns") or []
    rule_ids = []
    for entry in matched:
        if not isinstance(entry, Mapping):
            continue
        rule_id = _SAFETY_RULE_IDS.get(entry.get("pattern"))
        if rule_id is None:
            rule_id = f"safety_{entry.get('type', 'unknown')}"
        if vocabulary.is_safe_atom(rule_id):
            rule_ids.append(rule_id)

    for rule_id in rule_ids or [f"safety_{level}_unattributed"]:
        acc.add("deterministic_urgency", rule_id, level)


PROVENANCE_IDENTITY_SLOTS = ("name", "age", "sex", "chief_complaint")


def _slot_history(correction_history: Any, slot: str) -> List[Any]:
    """The value timeline for one slot, oldest first.

    Built from correction_history, which records (old_value, new_value) per
    correction. The first entry's old_value is the original statement; each
    entry then contributes its new_value. That yields 23 -> 24 -> 25 for two
    successive age corrections, rather than double-counting the pivot.

    ONLY field/old_value/new_value are read. correction_history entries also
    carry `source_text` — raw patient speech — which must never reach Prolog and
    is deliberately not touched here.
    """
    entries = [e for e in (correction_history or [])
               if isinstance(e, Mapping) and e.get("field") == slot]
    if not entries:
        return []
    timeline = [entries[0].get("old_value")]
    timeline.extend(e.get("new_value") for e in entries)
    return timeline


def _add_provenance(
    session: str,
    profile: Mapping[str, Any],
    candidate: Optional[Mapping[str, Any]],
    acc: "_Accumulator",
) -> Tuple[List[StatedFact], List[RejectedValue]]:
    """stated/4 facts for every tracked slot, plus this turn's candidate.

    Turn indices are logical ordinals over correction_history, not wall-clock
    times: the same session rebuilt from the database must produce the same
    ordering every time.
    """
    statements: List[StatedFact] = []
    rejected: List[RejectedValue] = []
    history = profile.get("correction_history")

    tracked = list(PROVENANCE_IDENTITY_SLOTS) + sorted(vocabulary.CLINICAL_SLOTS)
    for slot in tracked:
        if vocabulary.canonical_slot(slot) is None and slot not in PROVENANCE_IDENTITY_SLOTS:
            continue
        timeline = _slot_history(history, slot)
        if not timeline:
            current = profile.get(slot)
            timeline = [current] if current not in (None, "") else []

        seen = set()
        turn = 0
        for raw in timeline:
            token = vocabulary.value_token(raw)
            if token is None:
                continue
            if token in seen:
                continue
            seen.add(token)
            try:
                statements.append(StatedFact(session=session, slot=slot,
                                             value=token, turn=turn))
            except vocabulary.OutOfVocabulary as exc:
                rejected.append(RejectedValue.of(f"stated.{slot}", str(exc), raw))
                continue
            turn += 1

        if candidate and candidate.get("field") == slot:
            token = vocabulary.value_token(candidate.get("new_value"))
            acc.add("correction_candidate", slot, "true")
            if token is None:
                acc.add("correction_intent", "unresolved", slot)
            elif token not in seen:
                try:
                    statements.append(StatedFact(session=session, slot=slot,
                                                 value=token, turn=turn))
                except vocabulary.OutOfVocabulary as exc:
                    rejected.append(
                        RejectedValue.of(f"candidate.{slot}", str(exc),
                                         candidate.get("new_value")))

    if candidate and not candidate.get("field"):
        acc.add("correction_intent", "ambiguous", "true")

    return statements, rejected


def build_facts(
    session_id: Any,
    *,
    profile: Optional[Mapping[str, Any]] = None,
    entities: Optional[Mapping[str, Any]] = None,
    chief_complaint: Optional[str] = None,
    safety_result: Optional[Mapping[str, Any]] = None,
    present_symptoms: Sequence[Any] = (),
    denied_symptoms: Sequence[Any] = (),
    uncertain_symptoms: Sequence[Any] = (),
    flow_slots: Sequence[Any] = (),
    asked_topics: Sequence[Any] = (),
    safety_topics: Optional[Sequence[Any]] = None,
    correction_candidate: Optional[Mapping[str, Any]] = None,
) -> FactSet:
    """Build one turn's validated facts. Never raises on bad input.

    Every argument is optional and every one tolerates the wrong type: this
    runs on a live consultation path, and malformed state must degrade to
    fewer facts, never to an exception.

    `present_symptoms`, `denied_symptoms` and `uncertain_symptoms` are the
    Phase 6 understanding layer's channel. They are ADDITIVE — the legacy
    extractor's `entities` still contributes exactly as before, and the
    precedence in _Accumulator.add resolves any overlap upward, so a structured
    denial can never cancel a symptom the extractor reported. That direction is
    deliberate: the understanding layer may add what the extractor cannot see,
    but it may not retract what the extractor did see.
    """
    session_key = vocabulary.slug_session_key(session_id)
    acc = _Accumulator(session_key)

    profile = profile if isinstance(profile, Mapping) else {}
    entities = entities if isinstance(entities, Mapping) else {}

    _add_symptoms(acc, entities.get("symptoms"), "present", "entities.symptoms")
    _add_symptoms(acc, profile.get("associated_symptoms_detected"), "present",
                  "profile.associated_symptoms_detected")
    _add_symptoms(acc, present_symptoms, "present", "present_symptoms")
    _add_symptoms(acc, denied_symptoms, "absent", "denied_symptoms")
    _add_symptoms(acc, uncertain_symptoms, "uncertain", "uncertain_symptoms")

    uncertain_fields = profile.get("uncertain_fields")
    if isinstance(uncertain_fields, Mapping):
        _add_symptoms(acc, uncertain_fields.get("clinical_terms"), "uncertain",
                      "profile.uncertain_fields.clinical_terms")

    _add_slots(acc, profile)
    _add_patient_attrs(acc, profile)

    if chief_complaint:
        complaint = vocabulary.canonical_complaint(chief_complaint)
        if complaint is None:
            acc.reject("complaint", "complaint not in vocabulary", chief_complaint)
        else:
            acc.add("complaint", complaint, "active")

    _add_safety(acc, safety_result)

    _add_flow_slots(acc, flow_slots)
    _add_interview_state(acc, profile, asked_topics)
    _add_safety_topics(
        acc, safety_topics if safety_topics is not None else safety_topics_for(safety_result)
    )

    statements, provenance_rejected = _add_provenance(
        session_key, profile,
        correction_candidate if isinstance(correction_candidate, Mapping) else None,
        acc)

    result = acc.result()
    return FactSet(facts=result.facts,
                   rejected=result.rejected + tuple(provenance_rejected),
                   stated=tuple(statements))
