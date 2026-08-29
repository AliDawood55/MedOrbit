"""
Virtual Doctor — symbolic reasoning layer (Phase 1: shadow mode).

    session state -> fact_builder -> prolog_engine -> ReasoningResult

PHASE 1 IS OBSERVATION ONLY. `observe_turn()` builds facts, queries the base
rules, times both, logs the outcome and returns it. Nothing in the Virtual
Doctor reads the return value: urgency, the next question, the planner,
corrections, the differential, the patient-facing reply and TTS all behave
exactly as they did before this package existed. With VD_SYMBOLIC unset or 0
the layer does not even boot.

That is the point. The shadow logs are the evidence base for deciding whether
the symbolic layer is trustworthy enough to influence anything in Phase 2.

WHAT THIS LAYER MAY NEVER DO — now or later
-------------------------------------------
Lower an urgency verdict. The deterministic MedicalSafetyLayer runs first on
raw patient text and enters the store as a fact; final_urgency/2 is a maximum
over the canonical lattice, so a symbolic rule can only ever raise the level.
An unavailable engine yields ReasoningResult.unavailable(), which carries no
urgency at all rather than a fabricated "routine".
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Mapping, Optional, Sequence, Tuple

from . import fact_builder, prolog_engine, vocabulary
from .prolog_engine import (
    PrologBudgetExceeded,
    PrologUnavailable,
    available,
    correction_active,
    correction_mode,
    enabled,
    interview_active,
    interview_mode,
    safety_active,
    safety_mode,
    status,
)
from .result_models import (
    Contradiction,
    CorrectionDecision,
    Fact,
    FactSet,
    InterviewDecision,
    KnowledgeState,
    ReasoningResult,
    RedFlag,
    RejectedValue,
    SafetyVerdict,
    StatedFact,
    UrgencyVerdict,
)

__all__ = [
    "Contradiction",
    "CorrectionDecision",
    "Fact",
    "FactSet",
    "InterviewDecision",
    "KnowledgeState",
    "PrologBudgetExceeded",
    "PrologUnavailable",
    "ReasoningResult",
    "RedFlag",
    "RejectedValue",
    "SafetyVerdict",
    "StatedFact",
    "UrgencyVerdict",
    "available",
    "correction_active",
    "correction_mode",
    "decide_corrections",
    "decide_corrections_async",
    "decide_interview",
    "decide_interview_async",
    "decide_safety",
    "decide_safety_async",
    "enabled",
    "fact_builder",
    "interview_active",
    "interview_mode",
    "merge_urgency",
    "observe_turn",
    "reason",
    "safety_active",
    "safety_mode",
    "status",
    "vocabulary",
]

logger = logging.getLogger("medorbit-ai.virtual_doctor.reasoning_engine")


def _column(rows: Sequence[Mapping[str, Any]], key: str) -> Tuple[str, ...]:
    """Distinct atom values of one query variable, order preserved."""
    seen: list = []
    for row in rows:
        value = row.get(key)
        if isinstance(value, bytes):
            value = value.decode("utf-8", "replace")
        text = str(value)
        if text and text not in seen:
            seen.append(text)
    return tuple(seen)


def reason(fact_set: FactSet, session_key: str) -> ReasoningResult:
    """Run the base queries over one turn's facts. Synchronous; never raises.

    Every failure — no SWI-Prolog, a rule that will not load, a malformed goal
    — resolves to ReasoningResult.unavailable() with the reason recorded. The
    caller gets an explicit absence, never a guess.
    """
    started = time.perf_counter()
    try:
        with prolog_engine.session_scope(session_key, fact_set.facts) as session:
            urgency_rows = session.query("final_urgency({s}, U)")
            evidence_rows = session.query("urgency_evidence({s}, _, Rule)")
            symptom_rows = session.query("symptom({s}, X)")
            denied_rows = session.query("denies({s}, X)")
            uncertain_rows = session.query("uncertain_symptom({s}, X)")
            answered_rows = session.query("answered({s}, Slot)")
            unanswered_rows = session.query("unanswered({s}, Slot)")
    except PrologUnavailable as exc:
        return ReasoningResult.unavailable(str(exc))
    except Exception as exc:  # noqa: BLE001 - shadow reasoning must never break a turn
        logger.warning("Symbolic reasoning failed (%s: %s)", type(exc).__name__, exc)
        return ReasoningResult.unavailable(f"{type(exc).__name__}: {exc}")

    levels = _column(urgency_rows, "U")
    urgency = UrgencyVerdict(
        level=levels[0] if levels else "routine",
        rules=_column(evidence_rows, "Rule"),
    )

    return ReasoningResult(
        available=True,
        urgency=urgency,
        knowledge=KnowledgeState(
            symptoms=_column(symptom_rows, "X"),
            denied=_column(denied_rows, "X"),
            uncertain=_column(uncertain_rows, "X"),
            answered=_column(answered_rows, "Slot"),
            unanswered=_column(unanswered_rows, "Slot"),
        ),
        fact_count=len(fact_set.facts),
        rejected=fact_set.rejected,
        query_ms=(time.perf_counter() - started) * 1000,
    )


def merge_urgency(*levels: Optional[str]) -> str:
    """The canonical monotonic merge: the most severe level wins.

    THE one place urgency sources are combined. Every input is normalised
    through canonical_urgency first, so the legacy "normal" that
    MedicalSafetyLayer speaks becomes "routine" here and nowhere else, and no
    caller has to remember which vocabulary it holds.

    Unknown and None inputs contribute nothing rather than defaulting to
    routine — "I have no opinion" and "I judge this routine" must not be the
    same value, or an unavailable reasoner would silently vote for calm.
    """
    best, best_rank = "routine", 0
    for level in levels:
        canonical = vocabulary.canonical_urgency(level)
        if canonical is None:
            continue
        rank = vocabulary.URGENCY_RANK[canonical]
        if rank > best_rank:
            best, best_rank = canonical, rank
    return best


def decide_safety(fact_set: FactSet, session_key: str) -> SafetyVerdict:
    """Symbolic red flags for one turn. Synchronous; never raises.

    Every failure — no engine, a blown inference budget, a malformed row —
    resolves to SafetyVerdict.unavailable(), which carries no urgency at all.
    The caller keeps whatever the deterministic layer decided.
    """
    started = time.perf_counter()
    try:
        with prolog_engine.session_scope(session_key, fact_set.facts) as session:
            flag_rows = session.query("safety_evidence({s}, RuleId, Urgency, Evidence)")
            symbolic_rows = session.query("symbolic_urgency({s}, U)")
            final_rows = session.query("final_urgency({s}, U)")
    except prolog_engine.PrologBudgetExceeded as exc:
        logger.warning("Symbolic safety reasoning exceeded its budget (%s)", exc)
        return SafetyVerdict.unavailable(f"budget_exceeded: {exc}")
    except PrologUnavailable as exc:
        return SafetyVerdict.unavailable(str(exc))
    except Exception as exc:  # noqa: BLE001 - safety reasoning must not end a turn
        logger.warning("Symbolic safety reasoning failed (%s: %s)", type(exc).__name__, exc)
        return SafetyVerdict.unavailable(f"{type(exc).__name__}: {exc}")

    red_flags = []
    for row in flag_rows:
        rule_id = _atom(row.get("RuleId"))
        urgency = vocabulary.canonical_urgency(_atom(row.get("Urgency")))
        evidence = tuple(e for e in _atom_list(row.get("Evidence"))
                         if vocabulary.is_safe_atom(e))
        if not rule_id or not vocabulary.is_safe_atom(rule_id) or urgency is None:
            logger.warning("Discarding malformed symbolic safety row: %r", row)
            continue
        red_flags.append(RedFlag(rule_id=rule_id, urgency=urgency, evidence=evidence))

    red_flags.sort(key=lambda f: (-f.rank, f.rule_id))

    symbolic = vocabulary.canonical_urgency(
        _atom(symbolic_rows[0].get("U"))) if symbolic_rows else None
    final = vocabulary.canonical_urgency(
        _atom(final_rows[0].get("U"))) if final_rows else None

    return SafetyVerdict(
        available=True,
        urgency=final,
        symbolic_urgency=symbolic,
        red_flags=tuple(red_flags),
        query_ms=(time.perf_counter() - started) * 1000,
    )


async def decide_safety_async(
    session_id: Any,
    *,
    profile: Optional[Mapping[str, Any]] = None,
    entities: Optional[Mapping[str, Any]] = None,
    chief_complaint: Optional[str] = None,
    safety_result: Optional[Mapping[str, Any]] = None,
    present_symptoms: Sequence[Any] = (),
    denied_symptoms: Sequence[Any] = (),
    uncertain_symptoms: Sequence[Any] = (),
) -> SafetyVerdict:
    """Build this turn's facts and reason about safety, off the event loop.

    The three symptom sequences are the Phase 6 understanding layer's channel
    into safety reasoning, and they are additive only — see build_facts. They
    are what makes rules/safety.pl's hematuria, seizure, unconscious and
    severe_bleeding clauses reachable, since the legacy extractor has no key
    for any of the four.
    """
    try:
        fact_set = fact_builder.build_facts(
            session_id,
            profile=profile,
            entities=entities,
            chief_complaint=chief_complaint,
            safety_result=safety_result,
            present_symptoms=present_symptoms,
            denied_symptoms=denied_symptoms,
            uncertain_symptoms=uncertain_symptoms,
        )
        session_key = vocabulary.slug_session_key(session_id)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Symbolic safety fact building failed (%s: %s)",
                       type(exc).__name__, exc)
        return SafetyVerdict.unavailable(f"{type(exc).__name__}: {exc}")

    return await asyncio.to_thread(decide_safety, fact_set, session_key)


def _atom(raw: Any) -> Optional[str]:
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", "replace")
    if raw is None:
        return None
    text = str(raw)
    return text or None


def decide_corrections(fact_set: FactSet, session_key: str) -> CorrectionDecision:
    """Contradictions and correction classification for one turn.

    Synchronous; never raises. Every failure resolves to
    CorrectionDecision.unavailable(), which asserts nothing about the turn —
    the Python correction layer keeps its own answer.
    """
    started = time.perf_counter()
    try:
        with prolog_engine.session_scope(session_key, fact_set) as session:
            contradiction_rows = session.query(
                "contradiction({s}, Slot, Old, New, OldTurn, NewTurn)")
            kind_rows = session.query("correction_kind({s}, Slot, Kind)")
    except prolog_engine.PrologBudgetExceeded as exc:
        logger.warning("Symbolic correction reasoning exceeded its budget (%s)", exc)
        return CorrectionDecision.unavailable(f"budget_exceeded: {exc}")
    except PrologUnavailable as exc:
        return CorrectionDecision.unavailable(str(exc))
    except Exception as exc:  # noqa: BLE001 - correction reasoning must not end a turn
        logger.warning("Symbolic correction reasoning failed (%s: %s)",
                       type(exc).__name__, exc)
        return CorrectionDecision.unavailable(f"{type(exc).__name__}: {exc}")

    kinds = {}
    for row in kind_rows:
        slot, kind = _atom(row.get("Slot")), _atom(row.get("Kind"))
        if slot and kind and vocabulary.is_safe_atom(slot) and vocabulary.is_safe_atom(kind):
            kinds[slot] = kind

    contradictions = []
    for row in contradiction_rows:
        slot = _atom(row.get("Slot"))
        if not slot or not vocabulary.is_safe_atom(slot):
            logger.warning("Discarding malformed contradiction row: %r", row)
            continue
        try:
            contradictions.append(Contradiction(
                slot=slot,
                old_value=row.get("Old"), new_value=row.get("New"),
                old_turn=int(row.get("OldTurn")), new_turn=int(row.get("NewTurn")),
                kind=kinds.get(slot, "single_value_conflict"),
            ))
        except (TypeError, ValueError):
            logger.warning("Discarding contradiction row with a bad turn index: %r", row)

    contradictions.sort(key=lambda c: (c.slot, c.new_turn))

    return CorrectionDecision(
        available=True,
        contradictions=tuple(contradictions),
        kinds=tuple(sorted(kinds.items())),
        query_ms=(time.perf_counter() - started) * 1000,
    )


async def decide_corrections_async(
    session_id: Any,
    *,
    profile: Optional[Mapping[str, Any]] = None,
    correction_candidate: Optional[Mapping[str, Any]] = None,
) -> CorrectionDecision:
    """Build provenance and reason about corrections, off the event loop."""
    try:
        fact_set = fact_builder.build_facts(
            session_id, profile=profile, correction_candidate=correction_candidate)
        session_key = vocabulary.slug_session_key(session_id)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Symbolic correction fact building failed (%s: %s)",
                       type(exc).__name__, exc)
        return CorrectionDecision.unavailable(f"{type(exc).__name__}: {exc}")

    return await asyncio.to_thread(decide_corrections, fact_set, session_key)


def decide_interview(fact_set: FactSet, session_key: str) -> InterviewDecision:
    """Which clinical TOPIC to ask next, and whether the interview is finished.

    Synchronous; never raises. Any failure resolves to
    InterviewDecision.unavailable(), which carries no topic and does not claim
    completeness — a caller must never mistake "the reasoner is down" for "we
    have everything we need", because those demand opposite actions.
    """
    started = time.perf_counter()
    try:
        with prolog_engine.session_scope(session_key, fact_set.facts) as session:
            ranked_rows = session.query("ranked_questions({s}, Topics)")
            priority_rows = session.query("question_priority({s}, T, P)")
            outstanding_rows = session.query("outstanding({s}, Slot)")
            asked_unanswered_rows = session.query("asked_unanswered({s}, Slot)")
            complete_rows = session.query("interview_complete({s})")
    except PrologUnavailable as exc:
        return InterviewDecision.unavailable(str(exc))
    except Exception as exc:  # noqa: BLE001 - a reasoning fault must not end a turn
        logger.warning("Symbolic interview reasoning failed (%s: %s)", type(exc).__name__, exc)
        return InterviewDecision.unavailable(f"{type(exc).__name__}: {exc}")

    ranked = _atom_list(ranked_rows[0].get("Topics")) if ranked_rows else ()
    topic = ranked[0] if ranked else None
    priorities = {
        str(row.get("T")): row.get("P") for row in priority_rows
        if isinstance(row.get("P"), int)
    }

    return InterviewDecision(
        available=True,
        topic=topic,
        complete=bool(complete_rows),
        ranked=ranked,
        unanswered=_column(outstanding_rows, "Slot"),
        asked_unanswered=_column(asked_unanswered_rows, "Slot"),
        priority=priorities.get(topic) if topic else None,
        query_ms=(time.perf_counter() - started) * 1000,
    )


def _atom_list(raw: Any) -> Tuple[str, ...]:
    """A Prolog list of atoms as a tuple of str, dropping anything unexpected."""
    if not isinstance(raw, (list, tuple)):
        return ()
    out = []
    for item in raw:
        if isinstance(item, bytes):
            item = item.decode("utf-8", "replace")
        text = str(item)
        if text:
            out.append(text)
    return tuple(out)


async def decide_interview_async(
    session_id: Any,
    *,
    profile: Optional[Mapping[str, Any]] = None,
    entities: Optional[Mapping[str, Any]] = None,
    chief_complaint: Optional[str] = None,
    safety_result: Optional[Mapping[str, Any]] = None,
    flow_slots: Sequence[Any] = (),
    asked_topics: Sequence[Any] = (),
    safety_topics: Optional[Sequence[Any]] = None,
) -> InterviewDecision:
    """Build this turn's facts and choose the next topic, off the event loop.

    Returns an unavailable decision rather than raising, for every failure
    including a malformed call — the caller falls back to the existing planner
    and the consultation continues.
    """
    try:
        fact_set = fact_builder.build_facts(
            session_id,
            profile=profile,
            entities=entities,
            chief_complaint=chief_complaint,
            safety_result=safety_result,
            flow_slots=flow_slots,
            asked_topics=asked_topics,
            safety_topics=safety_topics,
        )
        session_key = vocabulary.slug_session_key(session_id)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Symbolic fact building failed (%s: %s)", type(exc).__name__, exc)
        return InterviewDecision.unavailable(f"{type(exc).__name__}: {exc}")

    return await asyncio.to_thread(decide_interview, fact_set, session_key)


async def observe_turn(
    session_id: Any,
    *,
    profile: Optional[Mapping[str, Any]] = None,
    entities: Optional[Mapping[str, Any]] = None,
    chief_complaint: Optional[str] = None,
    safety_result: Optional[Mapping[str, Any]] = None,
) -> Optional[ReasoningResult]:
    """Shadow-mode entry point. Returns None when the flag is off.

    Runs on the request path, so the Prolog work goes to a worker thread —
    pyswip is a blocking C extension and must never sit on the event loop, even
    for the ~0.5ms a turn actually costs. Swallows everything: a fault in an
    observation-only layer must not affect the consultation.
    """
    if not enabled():
        return None

    try:
        build_started = time.perf_counter()
        fact_set = fact_builder.build_facts(
            session_id,
            profile=profile,
            entities=entities,
            chief_complaint=chief_complaint,
            safety_result=safety_result,
        )
        build_ms = (time.perf_counter() - build_started) * 1000
        session_key = vocabulary.slug_session_key(session_id)

        result = await asyncio.to_thread(reason, fact_set, session_key)
        result = ReasoningResult(
            available=result.available,
            urgency=result.urgency,
            knowledge=result.knowledge,
            fact_count=result.fact_count,
            rejected=result.rejected,
            build_ms=build_ms,
            query_ms=result.query_ms,
            degraded_reason=result.degraded_reason,
        )
    except Exception as exc:  # noqa: BLE001 - shadow mode is never load-bearing
        logger.warning("Symbolic shadow observation failed (%s: %s)", type(exc).__name__, exc)
        return None

    fields = result.as_log_fields()
    logger.info(
        "symbolic(shadow) available=%s urgency=%s rules=%s facts=%d rejected=%d "
        "symptoms=%s answered=%s unanswered=%s build=%.2fms query=%.2fms%s",
        fields["available"], fields["urgency"], fields["urgency_rules"] or "-",
        fields["facts"], fields["rejected"],
        fields["symptoms"] or "-", fields["answered"] or "-",
        fields["unanswered"] or "-", fields["build_ms"], fields["query_ms"],
        f" degraded={fields['degraded_reason']}" if fields["degraded_reason"] else "",
    )
    if result.rejected:
        logger.info(
            "symbolic(shadow) rejected: %s",
            "; ".join(f"{r.field}={r.raw!r} ({r.reason})" for r in result.rejected[:10]),
        )
    return result
