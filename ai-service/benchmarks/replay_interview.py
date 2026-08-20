"""
Phase 9 — legacy vs symbolic next-topic replay.

    python benchmarks/replay_interview.py

FULLY DETERMINISTIC. No model calls, no network, no database. Topic selection
is Prolog plus the flow files on one side and a pure Python helper on the
other, so this runs in milliseconds and the same input always gives the same
answer — which is why the assertions built on it live in the unit suite rather
than in a nightly job.

WHAT IS COMPARED
----------------
    LEGACY   interview_engine._next_unfilled_slot(flow, profile)
             the static flow's own rule: first slot the profile has not filled,
             in the order flows/*.json declares them.
    SYMBOLIC reasoning_engine.decide_interview(...)
             rules/interview.pl next_question/2.

Both decide a canonical TOPIC. Neither decides wording — that split is verified
separately, through the clamp.

CLASSIFICATION RULE, STATED BEFORE THE COUNTS
---------------------------------------------
Each turn carries an `expected_topic` derived from the flow's declared slot
order (and, on safety-flagged turns, the Phase 3 red-flag-follow-up rule).
Divergence is judged against that expectation, never against "they differ":

    SAME              both chose the same topic
    SYMBOLIC_BETTER   symbolic matched the expectation, legacy did not
    LEGACY_BETTER     legacy matched the expectation, symbolic did not
    BOTH_ACCEPTABLE   they differ, both are valid unanswered flow slots, and
                      the expectation does not discriminate between them
    SYMBOLIC_INVALID  symbolic chose a topic the flow does not declare, or one
                      already answered
    LEGACY_INVALID    the same, for legacy

"Different" is never by itself evidence of "better". A difference with no
expectation behind it is BOTH_ACCEPTABLE, not a win.
"""

from __future__ import annotations

import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))

from interview_trajectories import PAIRS, TRAJECTORIES  # noqa: E402

from virtual_doctor import interview_engine, reasoning_engine  # noqa: E402
from virtual_doctor.reasoning_engine import fact_builder, vocabulary  # noqa: E402

CLASSES = ("SAME", "SYMBOLIC_BETTER", "LEGACY_BETTER", "BOTH_ACCEPTABLE",
           "SYMBOLIC_INVALID", "LEGACY_INVALID")


def flow_for(complaint: str) -> dict:
    return interview_engine.FLOWS.get(complaint, interview_engine.FLOWS["generic"])


def legacy_topic(complaint: str, profile: Dict[str, Any]) -> Optional[str]:
    slot = interview_engine._next_unfilled_slot(flow_for(complaint), profile)
    return slot.get("key") if slot else None


def symbolic_decision(session: str, complaint: str, turn: Dict[str, Any]):
    safety_result = None
    if turn["safety_flagged"]:
        safety_result = {"severity": turn["safety_flagged"],
                         "matched_patterns": [{"type": turn["safety_flagged"],
                                               "matched": "x", "pattern": "p"}]}
    fact_set = fact_builder.build_facts(
        session,
        profile=turn["profile"],
        entities=turn["entities"],
        chief_complaint=complaint,
        safety_result=safety_result,
        flow_slots=flow_for(complaint).get("slots", []),
        asked_topics=turn["asked_topics"],
    )
    return reasoning_engine.decide_interview(
        fact_set, vocabulary.slug_session_key(session))


def classify(turn, complaint, legacy, symbolic_topic) -> str:
    expected = turn["expected_topic"]
    declared = [s.get("key") for s in flow_for(complaint).get("slots", [])]
    answered = {k for k, v in turn["profile"].items()
                if k in declared and isinstance(v, str) and v.strip()}

    def invalid(topic):
        """A topic is invalid if the active flow does not declare it, or if the
        profile already answered it. `None` is never invalid — it means the
        planner is proposing to stop, which the expectation judges."""
        return topic is not None and (topic not in declared or topic in answered)

    if invalid(symbolic_topic):
        return "SYMBOLIC_INVALID"
    if invalid(legacy):
        return "LEGACY_INVALID"
    if legacy == symbolic_topic:
        return "SAME"

    if expected is None:
        # expected-None covers two situations: the interview is complete, and
        # no clinical topic is relevant yet (intake unfinished).
        #
        # When symbolic declines and legacy does not, that is NOT scored as a
        # symbolic win, even though symbolic matches the expectation. The
        # comparison here is between _next_unfilled_slot and interview.pl, but
        # the legacy SYSTEM gates intake upstream of the planner entirely
        # (interview_engine._next_intake_reply), so it never reaches a clinical
        # question in that state either. Claiming a win would be scoring a
        # helper out of the context that protects it.
        if symbolic_topic is None:
            return "BOTH_ACCEPTABLE"
        # Symbolic proposing a topic where none was expected is a real
        # mismatch, and `expected_mismatch` records it separately.
        return "BOTH_ACCEPTABLE"

    if symbolic_topic == expected:
        return "SYMBOLIC_BETTER"
    if legacy == expected:
        return "LEGACY_BETTER"
    return "BOTH_ACCEPTABLE"


def run() -> Dict[str, Any]:
    counts: Counter = Counter()
    rows: List[Dict[str, Any]] = []
    violations = {"repeated_answered": [], "invalid_topic": [],
                  "missing_required": [], "expected_mismatch": []}

    for trajectory in TRAJECTORIES:
        complaint = trajectory["complaint"]
        for index, turn in enumerate(trajectory["turns"]):
            session = f"{trajectory['id']}-{index}"
            decision = symbolic_decision(session, complaint, turn)
            legacy = legacy_topic(complaint, turn["profile"])
            symbolic = decision.topic if decision.available else None
            label = classify(turn, complaint, legacy, symbolic)
            counts[label] += 1

            declared = [s.get("key") for s in flow_for(complaint).get("slots", [])]
            answered = {k for k, v in turn["profile"].items()
                        if k in declared and isinstance(v, str) and v.strip()}
            case = f"{trajectory['id']}#{index}"

            if symbolic is not None and symbolic in answered:
                violations["repeated_answered"].append(f"{case}:{symbolic}")
            if symbolic is not None and symbolic not in declared:
                violations["invalid_topic"].append(f"{case}:{symbolic}")
            if symbolic != turn["expected_topic"]:
                violations["expected_mismatch"].append(
                    f"{case}: expected={turn['expected_topic']} symbolic={symbolic}")
            # A required slot must never be skipped: if the planner says the
            # interview is complete while a declared slot is unfilled, that is a
            # missing mandatory question.
            if decision.available and decision.complete and (set(declared) - answered):
                violations["missing_required"].append(
                    f"{case}: complete with unfilled {sorted(set(declared) - answered)}")

            rows.append({
                "trajectory": trajectory["id"], "turn": index,
                "complaint": complaint,
                "categories": trajectory["categories"],
                "safety_flagged": turn["safety_flagged"],
                "answered_slots": sorted(answered),
                "expected_topic": turn["expected_topic"],
                "legacy_topic": legacy,
                "symbolic_topic": symbolic,
                "symbolic_ranked": list(decision.ranked),
                "symbolic_complete": decision.complete,
                "symbolic_available": decision.available,
                "priority": decision.priority,
                "classification": label,
                "note": turn["note"],
                "query_ms": round(decision.query_ms, 3),
            })

    # Paired adaptivity: same complaint, different known facts, different question.
    pairs = []
    index_by_id = {t["id"]: t for t in TRAJECTORIES}
    for left, right, turn_index in PAIRS:
        lrow = next(r for r in rows if r["trajectory"] == left and r["turn"] == turn_index)
        rrow = next(r for r in rows if r["trajectory"] == right and r["turn"] == turn_index)
        pairs.append({
            "left": left, "right": right, "turn": turn_index,
            "complaint": index_by_id[left]["complaint"],
            "left_answered": lrow["answered_slots"],
            "right_answered": rrow["answered_slots"],
            "left_topic": lrow["symbolic_topic"],
            "right_topic": rrow["symbolic_topic"],
            "differs": lrow["symbolic_topic"] != rrow["symbolic_topic"],
        })

    return {
        "schema": "medorbit.interview_replay.v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "n_trajectories": len(TRAJECTORIES),
        "n_turns": len(rows),
        "classification_counts": {k: counts.get(k, 0) for k in CLASSES},
        "violations": violations,
        "pairs": pairs,
        "turns": rows,
    }


def main() -> int:
    if not reasoning_engine.available():
        print("SWI-Prolog/pyswip not available", file=sys.stderr)
        return 1
    artifact = run()
    out_dir = os.path.join(os.path.dirname(__file__), "results")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "interview_replay.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(artifact, handle, ensure_ascii=False, indent=2)

    print(f"trajectories={artifact['n_trajectories']} turns={artifact['n_turns']}")
    print(json.dumps(artifact["classification_counts"], indent=2))
    print("\nVIOLATIONS")
    for key, items in artifact["violations"].items():
        print(f"  {key:20} {len(items):3}  {items[:6] if items else ''}")
    print("\nPAIRED ADAPTIVITY (same complaint, different known facts)")
    for pair in artifact["pairs"]:
        mark = "DIFFERS" if pair["differs"] else "same"
        print(f"  {pair['complaint']:16} {pair['left']:9} {str(pair['left_topic']):22}"
              f" | {pair['right']:9} {str(pair['right_topic']):22} -> {mark}")
    print(f"\nwrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
