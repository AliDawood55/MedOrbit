"""
Virtual Doctor — typed values crossing the Python/Prolog boundary.

Two directions, both typed, neither ever a raw string blob:

  Fact            Python -> Prolog. Frozen, and re-validated in __post_init__
                  so a hand-built Fact cannot smuggle an unchecked atom past
                  fact_builder. prolog_engine renders these and nothing else.
  ReasoningResult Prolog -> Python. What the engine concluded, plus enough
                  provenance to explain it and enough timing to measure it.

Phase 1 intentionally models only what rules/base.pl can actually answer:
urgency (echoed from the deterministic floor, over the canonical lattice) and
knowledge state. Question candidates, contradictions and differential
hypotheses arrive with the rule files that produce them, in their own phases.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Tuple, Union

from . import vocabulary

FactArg = Union[str, int]


@dataclass(frozen=True)
class Fact:
    """One validated symbolic fact: vd_fact(Session, Predicate, Subject, Value).

    A deliberately narrow shape. Rather than one Prolog predicate per concept
    — which is how a rule base turns into a thousand special cases — every
    fact is the same 4-tuple, and rules/base.pl projects readable accessors
    (symptom/2, slot_value/3, answered/2 ...) on top of it. Adding a new kind
    of fact is then a vocabulary entry plus an accessor clause, never a new
    Python code path.

    Validation is repeated here even though fact_builder already validated:
    this is the last point before a goal string is built, and the cost is a
    regex match on a handful of short atoms.
    """

    session: str
    predicate: str
    subject: str
    value: FactArg

    def __post_init__(self) -> None:
        vocabulary.require_atom(self.session, field="session")
        vocabulary.require_atom(self.predicate, field="predicate")
        vocabulary.require_atom(self.subject, field="subject")
        if isinstance(self.value, bool) or not isinstance(self.value, (str, int)):
            raise vocabulary.OutOfVocabulary(f"value: unsupported type: {self.value!r}")
        if isinstance(self.value, str):
            vocabulary.require_atom(self.value, field="value")


@dataclass(frozen=True)
class StatedFact:
    """One value a patient stated for a slot, with its position in the session.

    A separate shape from Fact rather than squeezed into vd_fact/4, because
    provenance genuinely has a dimension ordinary facts do not: a turn index.
    Rendered as vd_stated(Session, Slot, Value, Turn).

    `value` is never raw text. It is an int (an age), a canonical atom (a slot
    value like `severe`), or an opaque `v_<hex>` token standing in for free text
    such as a name — see vocabulary.value_token for why a token is sufficient.
    """

    session: str
    slot: str
    value: FactArg
    turn: int

    def __post_init__(self) -> None:
        vocabulary.require_atom(self.session, field="session")
        vocabulary.require_atom(self.slot, field="slot")
        if isinstance(self.value, bool) or not isinstance(self.value, (str, int)):
            raise vocabulary.OutOfVocabulary(f"value: unsupported type: {self.value!r}")
        if isinstance(self.value, str):
            vocabulary.require_atom(self.value, field="value")
        if isinstance(self.turn, bool) or not isinstance(self.turn, int) or self.turn < 0:
            raise vocabulary.OutOfVocabulary(f"turn: not a turn index: {self.turn!r}")


@dataclass(frozen=True)
class Contradiction:
    """A single-valued slot whose stored value has been superseded."""

    slot: str
    old_value: FactArg
    new_value: FactArg
    old_turn: int
    new_turn: int
    kind: str

    def as_log_fields(self) -> Dict[str, Any]:
        return {
            "field": self.slot, "old_value": self.old_value,
            "new_value": self.new_value, "old_turn": self.old_turn,
            "new_turn": self.new_turn, "kind": self.kind,
        }


@dataclass(frozen=True)
class CorrectionDecision:
    """What symbolic reasoning concluded about corrections this turn.

    `available` False is kept distinct from "nothing found", for the same reason
    as everywhere else in this package: a reasoner that could not run has said
    nothing, and silence must not read as "no correction needed".

    `kinds` maps slot -> classification, one of: single_value_conflict,
    clinical_state_update, no_contradiction, ambiguous_correction,
    uncertain_correction. Mutually exclusive by construction in
    contradictions.pl, so Python never arbitrates between them.
    """

    available: bool
    contradictions: Tuple[Contradiction, ...] = ()
    kinds: Tuple[Tuple[str, str], ...] = ()
    query_ms: float = 0.0
    degraded_reason: Optional[str] = None

    @staticmethod
    def unavailable(reason: str) -> "CorrectionDecision":
        return CorrectionDecision(available=False, degraded_reason=reason)

    @property
    def profile_correction_slot(self) -> Optional[str]:
        """The identity slot this turn corrects, if any. The symbolic answer to
        the question the Python layer answers with regexes."""
        for contradiction in self.contradictions:
            if contradiction.kind == "single_value_conflict":
                return contradiction.slot
        return None

    def kind_for(self, slot: str) -> Optional[str]:
        for candidate, kind in self.kinds:
            if candidate == slot:
                return kind
        return None

    def as_log_fields(self) -> Dict[str, Any]:
        """Canonical slots, opaque value tokens and turn indices only."""
        return {
            "available": self.available,
            "contradictions": [c.as_log_fields() for c in self.contradictions],
            "kinds": [list(k) for k in self.kinds],
            "profile_correction_slot": self.profile_correction_slot,
            "query_ms": round(self.query_ms, 3),
            "degraded_reason": self.degraded_reason,
        }


@dataclass(frozen=True)
class RejectedValue:
    """A value that did not survive the allow-list, kept for structured logs.

    `raw` is truncated at construction: it can contain patient speech, and a
    rejection log line is not a place to spill a whole utterance.
    """

    field: str
    reason: str
    raw: str = ""

    @staticmethod
    def of(field: str, reason: str, raw: object) -> "RejectedValue":
        text = raw if isinstance(raw, str) else repr(raw)
        return RejectedValue(field=field, reason=reason, raw=text[:40])


@dataclass(frozen=True)
class FactSet:
    """Facts for one turn, plus what was dropped getting there."""

    facts: Tuple[Fact, ...] = ()
    rejected: Tuple[RejectedValue, ...] = ()
    # Provenance (Phase 4). Separate from `facts` because vd_stated/4 carries a
    # turn index that vd_fact/4 has no room for.
    stated: Tuple[StatedFact, ...] = ()

    def __len__(self) -> int:
        return len(self.facts) + len(self.stated)


@dataclass(frozen=True)
class UrgencyVerdict:
    """An urgency level with the evidence for it.

    `level` is always one of vocabulary.URGENCY_LEVELS — never "normal", which
    is translated at the compatibility boundary. `rules` names the rules that
    fired, so a verdict is auditable rather than a bare label.
    """

    level: str
    rules: Tuple[str, ...] = ()

    @property
    def rank(self) -> int:
        return vocabulary.URGENCY_RANK.get(self.level, 0)


@dataclass(frozen=True)
class KnowledgeState:
    """What the interview knows, does not know, and is unsure about."""

    symptoms: Tuple[str, ...] = ()
    denied: Tuple[str, ...] = ()
    uncertain: Tuple[str, ...] = ()
    answered: Tuple[str, ...] = ()
    unanswered: Tuple[str, ...] = ()


@dataclass(frozen=True)
class RedFlag:
    """One safety rule that fired, with the facts that made it fire.

    `rule_id` is an application-owned constant from rules/safety.pl. It is
    audit/debug material and is never shown to a patient — the patient-facing
    warning wording stays in Python templates, unchanged since before Phase 3.
    """

    rule_id: str
    urgency: str
    evidence: Tuple[str, ...] = ()

    @property
    def rank(self) -> int:
        return vocabulary.URGENCY_RANK.get(self.urgency, 0)


@dataclass(frozen=True)
class SafetyVerdict:
    """What symbolic safety reasoning concluded this turn.

    `available` False is kept strictly distinct from "nothing fired". An
    unavailable verdict carries urgency None — never "routine" — because a
    reasoner that could not run has said nothing about the patient, and
    recording silence as reassurance is the one failure this layer must not
    have.

    `symbolic_urgency` is what safety.pl concluded ON ITS OWN, without the
    deterministic floor. Reported separately so shadow logs can show what the
    symbolic layer actually contributed rather than what the floor already knew.
    """

    available: bool
    urgency: Optional[str] = None
    symbolic_urgency: Optional[str] = None
    red_flags: Tuple[RedFlag, ...] = ()
    query_ms: float = 0.0
    degraded_reason: Optional[str] = None

    @staticmethod
    def unavailable(reason: str) -> "SafetyVerdict":
        return SafetyVerdict(available=False, degraded_reason=reason)

    @property
    def top(self) -> Optional[RedFlag]:
        """The most severe rule that fired; ties break on rule id."""
        if not self.red_flags:
            return None
        return sorted(self.red_flags, key=lambda f: (-f.rank, f.rule_id))[0]

    def escalates_over(self, baseline: Optional[str]) -> bool:
        """Would this verdict raise `baseline`? Never true for a lower verdict."""
        if not self.available or self.urgency is None:
            return False
        return vocabulary.URGENCY_RANK.get(self.urgency, 0) > vocabulary.URGENCY_RANK.get(
            baseline or "routine", 0
        )

    def as_log_fields(self) -> Dict[str, Any]:
        """Canonical atoms and counts only — never patient text."""
        return {
            "available": self.available,
            "urgency": self.urgency,
            "symbolic_urgency": self.symbolic_urgency,
            "rules": [f.rule_id for f in self.red_flags],
            "evidence": [list(f.evidence) for f in self.red_flags],
            "query_ms": round(self.query_ms, 3),
            "degraded_reason": self.degraded_reason,
        }


@dataclass(frozen=True)
class InterviewDecision:
    """What the symbolic layer concluded about the interview this turn.

    `topic` is a canonical clinical topic (`duration`, `radiation`, ...) and
    NEVER a sentence — the Phase 2 split is that Prolog decides what is asked
    and the LLM only decides how it is worded.

    `available` False means the engine could not answer. It is kept distinct
    from "no topic left": a caller must be able to tell "the interview is
    finished" from "the reasoner is down", because those demand opposite
    actions. An unavailable decision never claims completeness.
    """

    available: bool
    topic: Optional[str] = None
    complete: bool = False
    ranked: Tuple[str, ...] = ()
    unanswered: Tuple[str, ...] = ()
    asked_unanswered: Tuple[str, ...] = ()
    priority: Optional[int] = None
    query_ms: float = 0.0
    degraded_reason: Optional[str] = None

    @staticmethod
    def unavailable(reason: str) -> "InterviewDecision":
        return InterviewDecision(available=False, degraded_reason=reason)

    def as_log_fields(self) -> Dict[str, Any]:
        return {
            "available": self.available,
            "topic": self.topic,
            "complete": self.complete,
            "ranked": list(self.ranked),
            "unanswered": list(self.unanswered),
            "asked_unanswered": list(self.asked_unanswered),
            "priority": self.priority,
            "query_ms": round(self.query_ms, 3),
            "degraded_reason": self.degraded_reason,
        }


@dataclass(frozen=True)
class ReasoningResult:
    """One turn's symbolic conclusion.

    In Phase 1 this is built, logged, measured and discarded — nothing reads it
    to make a decision. It is modelled properly anyway because the shadow logs
    are the evidence later phases will be reviewed against, and a shape that
    cannot express its own provenance produces logs nobody can audit.
    """

    available: bool
    urgency: Optional[UrgencyVerdict] = None
    knowledge: KnowledgeState = field(default_factory=KnowledgeState)
    fact_count: int = 0
    rejected: Tuple[RejectedValue, ...] = ()
    build_ms: float = 0.0
    query_ms: float = 0.0
    degraded_reason: Optional[str] = None

    @staticmethod
    def unavailable(reason: str) -> "ReasoningResult":
        """No engine, no result — and explicitly no urgency.

        Never a fabricated verdict: `urgency` stays None so a caller that
        forgets to check `available` gets an obvious absence rather than a
        confident-looking "routine".
        """
        return ReasoningResult(available=False, degraded_reason=reason)

    def as_log_fields(self) -> Dict[str, Any]:
        """Flat, greppable shape for the shadow-mode log line."""
        return {
            "available": self.available,
            "urgency": self.urgency.level if self.urgency else None,
            "urgency_rules": list(self.urgency.rules) if self.urgency else [],
            "symptoms": list(self.knowledge.symptoms),
            "denied": list(self.knowledge.denied),
            "answered": list(self.knowledge.answered),
            "unanswered": list(self.knowledge.unanswered),
            "facts": self.fact_count,
            "rejected": len(self.rejected),
            "build_ms": round(self.build_ms, 3),
            "query_ms": round(self.query_ms, 3),
            "degraded_reason": self.degraded_reason,
        }
