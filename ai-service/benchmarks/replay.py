"""
Phase 8 — offline legacy-vs-structured divergence analysis.

    python benchmarks/replay.py --model qwen2.5:3b --prompt v1 --split held_out

WHY REPLAY RATHER THAN LIVE SHADOW
----------------------------------
Live shadow costs ~2.6-3.4 s of real patient waiting per turn and produces
UNLABELLED divergence — it can tell you the two extractors disagreed, never
which one was right. Replay against a labelled corpus costs a patient nothing
and answers the question that actually matters. Adding latency to a live
consultation to collect data that replay yields for free is not a trade worth
making, so this is the Phase 8 evaluation path.

WHAT IT WILL NOT DO
-------------------
No database. No `interview_engine.handle_message`. No session creation. No TTS.
No HTTP endpoint. It reads an approved benchmark corpus, runs both extractors
over the text, and writes counts. Raw case text is never written to the output
artifact — only case IDs, which are already de-identified by construction.

DIVERGENCE CLASSES
------------------
Per (case, symptom) pair, judged against ground truth, so "they disagreed" is
resolved into who was right:

    BOTH_CORRECT              both found it, and it is real
    LEGACY_ONLY_CORRECT       the keyword matcher won
    STRUCTURED_ONLY_CORRECT   the model found what the extractor cannot see
    BOTH_WRONG                neither found a real observation
    STRUCTURED_FALSE_POSITIVE the model invented an atom
    STRUCTURED_FALSE_NEGATIVE the model missed a real one
    POLARITY_ERROR            right symptom, wrong present/absent/uncertain
    SAFETY_FALSE_POSITIVE     an invented atom that reaches rules/safety.pl
    SAFETY_FALSE_NEGATIVE     a missed atom that would have escalated

The legacy extractor has no polarity at all, so it is only ever compared on
PRESENT symptoms. Scoring it against denials it structurally cannot express
would be a rigged comparison.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))

from understanding_corpus import SAFETY_ATOMS, by_split  # noqa: E402

from run_understanding_benchmark import PROMPTS, RESULTS_DIR, run_case  # noqa: E402

from chatbot.entities.extractor import EntityExtractor  # noqa: E402
from virtual_doctor.reasoning_engine import vocabulary  # noqa: E402

CLASSES = (
    "BOTH_CORRECT", "LEGACY_ONLY_CORRECT", "STRUCTURED_ONLY_CORRECT",
    "BOTH_WRONG", "STRUCTURED_FALSE_POSITIVE", "STRUCTURED_FALSE_NEGATIVE",
    "POLARITY_ERROR", "SAFETY_FALSE_POSITIVE", "SAFETY_FALSE_NEGATIVE",
)

_extractor = EntityExtractor()


def legacy_present(text: str) -> set:
    """What the legacy extractor contributes, canonicalised. PRESENT only —
    it has no way to express a denial or a hedge."""
    found = set()
    for raw in (_extractor.extract(text).get("symptoms") or []):
        canonical = vocabulary.canonical_symptom(raw)
        if canonical is not None:
            found.add(canonical)
    return found


def classify(case: Dict[str, Any], row: Dict[str, Any]) -> List[str]:
    """Divergence labels for one case. Multiple labels per case are normal."""
    labels: List[str] = []
    exp = case["expected"]
    exp_present = set(exp["present"])
    exp_any = exp_present | set(exp["absent"]) | set(exp["uncertain"])

    legacy = legacy_present(case["text"])
    s_present = set(row["actual"]["present"])
    s_any = s_present | set(row["actual"]["absent"]) | set(row["actual"]["uncertain"])

    # Present-symptom agreement, the only axis both extractors can be scored on.
    for atom in exp_present:
        in_legacy, in_structured = atom in legacy, atom in s_present
        if in_legacy and in_structured:
            labels.append("BOTH_CORRECT")
        elif in_legacy:
            labels.append("LEGACY_ONLY_CORRECT")
        elif in_structured:
            labels.append("STRUCTURED_ONLY_CORRECT")
        else:
            labels.append("BOTH_WRONG")
            if atom in SAFETY_ATOMS:
                labels.append("SAFETY_FALSE_NEGATIVE")

    # Structured-only judgements.
    for atom in s_any - exp_any:
        labels.append("STRUCTURED_FALSE_POSITIVE")
        if atom in SAFETY_ATOMS:
            labels.append("SAFETY_FALSE_POSITIVE")
    for atom in exp_any - s_any:
        labels.append("STRUCTURED_FALSE_NEGATIVE")
        if atom in SAFETY_ATOMS and atom in exp_present:
            labels.append("SAFETY_FALSE_NEGATIVE")

    # Right symptom, wrong polarity — distinct from a miss, because the fact
    # still reaches Prolog, just under the wrong predicate.
    for pol in ("present", "absent", "uncertain"):
        for atom in set(exp[pol]):
            if atom not in s_any:
                continue
            if atom not in set(row["actual"][pol]):
                labels.append("POLARITY_ERROR")

    return labels


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="qwen2.5:3b")
    parser.add_argument("--prompt", default="v1", choices=sorted(PROMPTS))
    parser.add_argument("--split", default="held_out",
                        choices=("dev", "held_out", "all"))
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    cases = by_split(args.split)
    os.makedirs(RESULTS_DIR, exist_ok=True)
    out_path = args.out or os.path.join(
        RESULTS_DIR,
        f"replay__{args.model.replace(':', '_')}__{args.prompt}__{args.split}.json")

    counts: Counter = Counter()
    examples: Dict[str, List[str]] = defaultdict(list)
    per_case = []

    for index, case in enumerate(cases, 1):
        row = await run_case(case, args.model, args.prompt, args.timeout)
        labels = classify(case, row)
        for label in set(labels):
            counts[label] += labels.count(label)
            if len(examples[label]) < 8:
                examples[label].append(case["id"])
        legacy = sorted(legacy_present(case["text"]))
        per_case.append({
            "case_id": case["id"], "lang": case["lang"],
            "categories": case["categories"],
            "expected": case["expected"],
            "legacy_present": legacy,
            "structured": row["actual"],
            "labels": sorted(set(labels)),
            "latency_ms": row["latency_ms"],
        })
        print(f"[{index:>3}/{len(cases)}] {case['id']:24} {sorted(set(labels))}",
              file=sys.stderr)

    artifact = {
        "schema": "medorbit.understanding_replay.v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": args.model,
        "prompt_version": args.prompt,
        "split": args.split,
        "n_cases": len(cases),
        "divergence_counts": {k: counts.get(k, 0) for k in CLASSES},
        "examples": {k: examples.get(k, []) for k in CLASSES},
        "cases": per_case,
    }
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(artifact, handle, ensure_ascii=False, indent=2)

    print(f"\nwrote {out_path}", file=sys.stderr)
    print(json.dumps({"divergence_counts": artifact["divergence_counts"],
                      "examples": artifact["examples"]},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
