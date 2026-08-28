"""
Phase 8.1 — subject-attribution capability report.

    python benchmarks/attribution_report.py benchmarks/results/*__attribution.json

Answers one question with raw counts, not a composite score:

    Can this model tell WHO a symptom belongs to, and whether an utterance is a
    report at all — while still extracting the patient's own symptoms?

Both halves matter. A model that never extracts anything scores zero false
positives and is useless, so positive-control recall is reported beside every
false-positive count and neither is allowed to stand alone.

WHY THE COUNTS ARE NOT COMBINED
-------------------------------
A third-party safety false positive and a missed hedge are not commensurable.
The first escalates a consultation on somebody else's medical history; the
second loses a nuance. Averaging them into one number would let a model buy
its way out of the dangerous failure with wins on the harmless one, which is
exactly what the Phase 8 aggregate F1 did before the negative controls existed.
"""

from __future__ import annotations

import glob
import json
import sys
from typing import Any, Dict, List

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])

from understanding_corpus import SAFETY_ATOMS  # noqa: E402


def _emitted(row: Dict[str, Any]) -> set:
    return set(sum(row["actual"].values(), []))


def analyse(artifact: Dict[str, Any]) -> Dict[str, Any]:
    rows = artifact["cases"]

    def pick(category):
        return [r for r in rows if category in r["categories"]]

    third = pick("third_party")
    question = pick("question_not_report")
    positive = pick("positive_control")
    controls = [r for r in rows if "negative_control" in r["categories"]]

    def false_positives(group):
        """Atoms emitted for cases whose ground truth expects none of them."""
        out, safety = [], []
        for row in group:
            expected = set(sum(row["expected"].values(), []))
            for atom in sorted(_emitted(row) - expected):
                out.append(f"{row['case_id']}:{atom}")
                if atom in SAFETY_ATOMS:
                    safety.append(f"{row['case_id']}:{atom}")
        return out, safety

    third_fp, third_safety_fp = false_positives(third)
    q_fp, q_safety_fp = false_positives(question)
    control_fp, control_safety_fp = false_positives(controls)

    pos_hits, pos_misses = [], []
    pos_safety_expected = pos_safety_found = 0
    for row in positive:
        for atom in row["expected"]["present"]:
            if atom in SAFETY_ATOMS:
                pos_safety_expected += 1
            if atom in row["actual"]["present"]:
                pos_hits.append(f"{row['case_id']}:{atom}")
                if atom in SAFETY_ATOMS:
                    pos_safety_found += 1
            else:
                pos_misses.append(f"{row['case_id']}:{atom}")

    tp = fp = fn = 0
    for row in rows:
        for pol in ("present", "absent", "uncertain"):
            exp, act = set(row["expected"][pol]), set(row["actual"][pol])
            tp += len(exp & act)
            fp += len(act - exp)
            fn += len(exp - act)
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0

    latencies = sorted(r["latency_ms"] for r in rows)
    return {
        "model": artifact["model"],
        "prompt": artifact["prompt_version"],
        "n_cases": len(rows),
        "third_party": {
            "n": len(third), "false_positives": third_fp,
            "fp_count": len(third_fp),
            "safety_false_positives": third_safety_fp,
            "safety_fp_count": len(third_safety_fp),
            "clean_cases": sum(1 for r in third
                               if not (_emitted(r) - set(sum(r["expected"].values(), [])))),
        },
        "question_not_report": {
            "n": len(question), "false_positives": q_fp,
            "fp_count": len(q_fp),
            "safety_false_positives": q_safety_fp,
            "safety_fp_count": len(q_safety_fp),
            "clean_cases": sum(1 for r in question
                               if not (_emitted(r) - set(sum(r["expected"].values(), [])))),
        },
        "negative_controls": {
            "n": len(controls), "fp_count": len(control_fp),
            "safety_fp_count": len(control_safety_fp),
            "safety_false_positives": control_safety_fp,
            "clean_cases": sum(1 for r in controls
                               if not (_emitted(r) - set(sum(r["expected"].values(), [])))),
        },
        "positive_controls": {
            "n": len(positive),
            "hits": len(pos_hits), "misses": len(pos_misses),
            "missed": pos_misses,
            "safety_recall": (round(pos_safety_found / pos_safety_expected, 3)
                              if pos_safety_expected else None),
            "safety_found": pos_safety_found,
            "safety_expected": pos_safety_expected,
        },
        "subset": {
            "precision": round(precision, 4), "recall": round(recall, 4),
            "f1": round(f1, 4), "tp": tp, "fp": fp, "fn": fn,
            "exact_match_rate": round(
                100.0 * sum(1 for r in rows if r["exact_match"]) / len(rows), 1),
            "malformed_rate": round(
                100.0 * sum(1 for r in rows if r["malformed"]) / len(rows), 1),
            "failure_rate": round(
                100.0 * sum(1 for r in rows if not r["available"]) / len(rows), 1),
        },
        "latency_ms": {
            "mean": round(sum(latencies) / len(latencies), 1),
            "median": latencies[len(latencies) // 2],
            "p95": latencies[min(len(latencies) - 1, int(0.95 * len(latencies)))],
            "max": latencies[-1],
            "cold": artifact["metrics"].get("cold_latency_ms"),
        },
    }


def main() -> int:
    paths: List[str] = []
    for pattern in (sys.argv[1:] or ["benchmarks/results/*__attribution.json"]):
        paths.extend(sorted(glob.glob(pattern)))
    if not paths:
        print("no artifacts")
        return 1

    reports = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            reports.append(analyse(json.load(handle)))

    print(f"{'MODEL / PROMPT':28} {'3rd-party':>18} {'question':>18} "
          f"{'all controls':>18} {'positive ctrl':>16}")
    print(f"{'':28} {'FP  safetyFP  ok':>18} {'FP  safetyFP  ok':>18} "
          f"{'FP  safetyFP  ok':>18} {'hit/miss  safetyR':>16}")
    print("-" * 106)
    for r in reports:
        t, q, c, p = (r["third_party"], r["question_not_report"],
                      r["negative_controls"], r["positive_controls"])
        print(f"{r['model'] + '/' + r['prompt']:28} "
              f"{t['fp_count']:>3} {t['safety_fp_count']:>9} {str(t['clean_cases']) + '/' + str(t['n']):>6} "
              f"{q['fp_count']:>3} {q['safety_fp_count']:>9} {str(q['clean_cases']) + '/' + str(q['n']):>6} "
              f"{c['fp_count']:>3} {c['safety_fp_count']:>9} {str(c['clean_cases']) + '/' + str(c['n']):>6} "
              f"{str(p['hits']) + '/' + str(p['misses']):>9} {str(p['safety_recall']):>7}")

    print(f"\n{'MODEL / PROMPT':28} {'P':>7} {'R':>7} {'F1':>7} {'exact%':>8} "
          f"{'malf%':>7} {'mean_ms':>9} {'p95_ms':>8} {'cold_ms':>9}")
    print("-" * 106)
    for r in reports:
        s, L = r["subset"], r["latency_ms"]
        print(f"{r['model'] + '/' + r['prompt']:28} {s['precision']:>7.3f} {s['recall']:>7.3f} "
              f"{s['f1']:>7.3f} {s['exact_match_rate']:>8.1f} {s['malformed_rate']:>7.1f} "
              f"{L['mean']:>9.0f} {L['p95']:>8.0f} {str(L['cold']):>9}")

    print("\n\nSAFETY FALSE POSITIVES (raw)")
    for r in reports:
        print(f"  {r['model']}/{r['prompt']}")
        print(f"    third-party : {r['third_party']['safety_false_positives'] or 'none'}")
        print(f"    question    : {r['question_not_report']['safety_false_positives'] or 'none'}")
        print(f"    all controls: {r['negative_controls']['safety_false_positives'] or 'none'}")
        print(f"    positive-control misses: {r['positive_controls']['missed'] or 'none'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
