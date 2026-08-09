"""
Phase 6.5 — structured understanding benchmark runner.

    python benchmarks/run_understanding_benchmark.py --model qwen2.5:3b --split held_out

Deliberately NOT a unit test. It makes real model calls, takes minutes, and its
results depend on which weights happen to be installed — none of which belongs
in a suite that has to be fast and deterministic. The Phase 6 unit tests already
prove the parser and the trust boundary; this measures the model.

FAILED GENERATIONS STAY IN THE DENOMINATOR
------------------------------------------
A timeout, a malformed payload and a confidently wrong answer are all counted as
what they are. A benchmark that drops the runs it could not parse reports the
accuracy of a model that never fails, which is not the model anyone runs.

WHAT IS SCORED
--------------
Canonical facts only: symptom sets by polarity, slot keys answered, correction
fields. No condition, no urgency, no diagnosis — scoring those would reintroduce
the Phase 5 question this benchmark has no business answering.

Precision/recall/F1 are micro-averaged over (case, symptom) pairs, so a case
with three symptoms counts three times and a model cannot win by being right
about the easy singletons.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))

from understanding_corpus import CORPUS, SAFETY_ATOMS, by_split  # noqa: E402

from virtual_doctor import understanding  # noqa: E402
from virtual_doctor.reasoning_engine import vocabulary  # noqa: E402

RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")


# ---------------------------------------------------------------------------
# Prompt variants
# ---------------------------------------------------------------------------
# v1 is the shipped Phase 6 prompt, used unmodified so the baseline is the real
# baseline. Variants are registered here rather than edited in place so a run
# can name exactly which prompt produced it.

def prompt_v1(message: str, lang: str) -> str:
    """The shipped Phase 6 prompt (understanding.build_prompt)."""
    return understanding.build_prompt(message, lang)


from prompt_variants import build_v2, build_v3, build_v4  # noqa: E402
from subject_prototype import build_v5, filter_by_subject  # noqa: E402

PROMPTS = {"v1": prompt_v1, "v2": build_v2, "v3": build_v3,
           "v4": build_v4, "v5": build_v5}

# Phase 8.1: a variant may NARROW the payload before the production validator
# sees it. v5 uses this to drop observations the model did not claim for the
# patient. The production validator still runs afterwards and still does all the
# actual validation — a prefilter can only remove entries, never admit one.
PREFILTERS = {"v5": filter_by_subject}


def register_prompt(name, fn):
    PROMPTS[name] = fn


# ---------------------------------------------------------------------------
# Running one case
# ---------------------------------------------------------------------------

async def run_case(case: Dict[str, Any], model: str, prompt_name: str,
                   timeout: float) -> Dict[str, Any]:
    """One model call, parsed through the real production validator.

    The call is made here rather than through understanding.understand() so the
    model and prompt can vary per run, but the response takes exactly the
    production path afterwards — _extract_json then parse_understanding — so
    what is measured is what production would have got.
    """
    import requests

    build = PROMPTS[prompt_name]
    subject_stats: Dict[str, int] = {}
    started = time.perf_counter()
    error: Optional[str] = None
    content = ""
    try:
        response = await asyncio.to_thread(
            requests.post,
            understanding.CHAT_URL,
            json={
                "model": model,
                "messages": [
                    {"role": "system",
                     "content": understanding._SYSTEM.get(case["lang"], understanding._SYSTEM["en"])},
                    {"role": "user", "content": build(case["text"], case["lang"])},
                ],
                "stream": False,
                "format": "json",
                "keep_alive": understanding.KEEP_ALIVE,
                "options": {"temperature": 0.1},
            },
            timeout=timeout,
        )
        response.raise_for_status()
        content = response.json().get("message", {}).get("content", "")
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"

    elapsed = (time.perf_counter() - started) * 1000

    if error is not None:
        result = understanding.ClinicalUnderstanding.unavailable(error, elapsed_ms=elapsed)
        raw_keys: List[str] = []
    else:
        payload = understanding._extract_json(content)
        if payload is None:
            result = understanding.ClinicalUnderstanding.unavailable(
                "unparseable output", malformed=True, elapsed_ms=elapsed)
            raw_keys = []
        else:
            raw_keys = sorted(str(k) for k in payload)
            prefilter = PREFILTERS.get(prompt_name)
            if prefilter is not None:
                payload, subject_stats = prefilter(payload)
            result = understanding.parse_understanding(payload, elapsed_ms=elapsed)

    actual = {
        "present": list(result.present_symptoms),
        "absent": list(result.denied_symptoms),
        "uncertain": list(result.uncertain_symptoms),
    }
    return {
        "case_id": case["id"],
        "lang": case["lang"],
        "split": case["split"],
        "categories": case["categories"],
        "expected": case["expected"],
        "expected_findings": case["expected_findings"],
        "expected_corrections": case["expected_corrections"],
        "safety_atoms": case["safety_atoms"],
        "actual": actual,
        "actual_findings": sorted({f.slot for f in result.findings}),
        "actual_corrections": sorted({c.field for c in result.corrections}),
        "available": result.available,
        "malformed": result.malformed,
        "failure_reason": result.reason,
        "rejected": [{"field": r.field, "reason": r.reason} for r in result.rejected],
        "rejected_raw": [r.raw for r in result.rejected],
        "forbidden_keys": list(result.forbidden_keys),
        "unknown_keys": list(result.unknown_keys),
        "raw_top_level_keys": raw_keys,
        "conflicts": list(result.conflicts),
        "subject_stats": subject_stats,
        "latency_ms": round(elapsed, 1),
        "exact_match": (actual["present"] == case["expected"]["present"]
                        and actual["absent"] == case["expected"]["absent"]
                        and actual["uncertain"] == case["expected"]["uncertain"]),
    }


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

def _prf(tp: int, fp: int, fn: int) -> Dict[str, float]:
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    return {"precision": round(precision, 4), "recall": round(recall, 4),
            "f1": round(f1, 4), "tp": tp, "fp": fp, "fn": fn}


def score(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Aggregate metrics. Every row counts, including failed generations."""
    tp = fp = fn = 0
    polarity = {p: {"tp": 0, "fp": 0, "fn": 0} for p in ("present", "absent", "uncertain")}
    lang_counts: Dict[str, Dict[str, int]] = defaultdict(lambda: {"tp": 0, "fp": 0, "fn": 0})
    safety_expected = safety_found = 0
    safety_misses: List[str] = []
    safety_polarity_errors: List[str] = []
    # A safety atom the model asserted that the patient never mentioned. Scored
    # separately from ordinary hallucination because the consequence is
    # different in kind: an invented `seizure` reaches rules/safety.pl and
    # escalates the consultation to urgent. A miss loses an escalation; a false
    # positive manufactures one.
    safety_false_positives: List[str] = []
    multi_expected = multi_found = 0
    hallucinated: Counter = Counter()
    exact = malformed = unavailable = forbidden = 0
    latencies: List[float] = []
    category_exact: Dict[str, List[int]] = defaultdict(list)

    for row in rows:
        latencies.append(row["latency_ms"])
        if row["malformed"]:
            malformed += 1
        if not row["available"]:
            unavailable += 1
        if row["forbidden_keys"]:
            forbidden += 1
        if row["exact_match"]:
            exact += 1
        for cat in row["categories"]:
            category_exact[cat].append(1 if row["exact_match"] else 0)

        # Any canonical atom the model produced that the ground truth does not
        # place in ANY polarity is a hallucinated canonical atom: the validator
        # let it through because it is real vocabulary, but the patient did not
        # say it.
        expected_all = set(sum(row["expected"].values(), []))
        actual_all = set(sum(row["actual"].values(), []))
        for atom in actual_all - expected_all:
            hallucinated[atom] += 1
            if atom in SAFETY_ATOMS:
                polarity_seen = ("present" if atom in row["actual"]["present"]
                                 else "absent" if atom in row["actual"]["absent"]
                                 else "uncertain")
                safety_false_positives.append(f"{row['case_id']}:{atom}({polarity_seen})")

        for pol in ("present", "absent", "uncertain"):
            exp, act = set(row["expected"][pol]), set(row["actual"][pol])
            hit, extra, miss = len(exp & act), len(act - exp), len(exp - act)
            polarity[pol]["tp"] += hit
            polarity[pol]["fp"] += extra
            polarity[pol]["fn"] += miss
            tp += hit
            fp += extra
            fn += miss
            lang_counts[row["lang"]]["tp"] += hit
            lang_counts[row["lang"]]["fp"] += extra
            lang_counts[row["lang"]]["fn"] += miss

        # Safety atoms: raw counts, no weighting formula.
        for atom in row["safety_atoms"]:
            safety_expected += 1
            if atom in row["actual"]["present"]:
                safety_found += 1
            else:
                safety_misses.append(f"{row['case_id']}:{atom}")
                if atom in row["actual"]["absent"] or atom in row["actual"]["uncertain"]:
                    safety_polarity_errors.append(f"{row['case_id']}:{atom}")

        if len(row["expected"]["present"]) > 1:
            multi_expected += len(row["expected"]["present"])
            multi_found += len(set(row["expected"]["present"]) & set(row["actual"]["present"]))

    # --- Phase 8: per-category slices -------------------------------------
    # A model that handles textbook MSA but not how people actually speak to a
    # voice assistant scores fine in aggregate and fails in production. These
    # slices make colloquial / code-switched / ASR-like performance visible
    # instead of averaged away.
    def _subset(predicate):
        picked = [r for r in rows if predicate(r)]
        if not picked:
            return None
        stp = sfp = sfn = 0
        for row in picked:
            for pol in ("present", "absent", "uncertain"):
                exp, act = set(row["expected"][pol]), set(row["actual"][pol])
                stp += len(exp & act)
                sfp += len(act - exp)
                sfn += len(exp - act)
        stats = _prf(stp, sfp, sfn)
        stats["n_cases"] = len(picked)
        stats["exact_match_rate"] = round(
            100.0 * sum(1 for r in picked if r["exact_match"]) / len(picked), 1)
        return stats

    by_category = {
        cat: _subset(lambda r, c=cat: c in r["categories"])
        for cat in ("colloquial", "code_switch", "asr_like", "negative_control",
                    "uncertainty", "multi_symptom", "negation", "third_party",
                    "question_not_report")
    }

    # --- Phase 8: the negative-control gate --------------------------------
    # Cases where the patient reported NOTHING. Any canonical atom produced
    # here is invented outright, and an invented SAFETY atom reaches
    # rules/safety.pl and manufactures an escalation. Reported on its own, never
    # folded into aggregate precision.
    controls = [r for r in rows if "negative_control" in r["categories"]]
    control_invented = []
    control_safety_invented = []
    for row in controls:
        expected_all = set(sum(row["expected"].values(), []))
        for atom in set(sum(row["actual"].values(), [])) - expected_all:
            control_invented.append(f"{row['case_id']}:{atom}")
            if atom in SAFETY_ATOMS:
                control_safety_invented.append(f"{row['case_id']}:{atom}")

    latencies.sort()
    n = len(rows)

    def pct(x):
        return round(100.0 * x / n, 1) if n else 0.0

    return {
        "n_cases": n,
        "symptom_micro": _prf(tp, fp, fn),
        "polarity": {p: _prf(v["tp"], v["fp"], v["fn"]) for p, v in polarity.items()},
        "by_language": {lang: _prf(v["tp"], v["fp"], v["fn"])
                        for lang, v in sorted(lang_counts.items())},
        "exact_match_rate": pct(exact),
        "exact_match_count": exact,
        "multi_symptom_recall": round(multi_found / multi_expected, 4) if multi_expected else None,
        "multi_symptom_found": multi_found,
        "multi_symptom_expected": multi_expected,
        "safety_atom_recall": round(safety_found / safety_expected, 4) if safety_expected else None,
        "safety_atom_found": safety_found,
        "safety_atom_expected": safety_expected,
        "safety_atom_misses": safety_misses,
        "safety_polarity_errors": safety_polarity_errors,
        "safety_false_positives": safety_false_positives,
        "safety_false_positive_count": len(safety_false_positives),
        "by_category": by_category,
        "negative_controls": {
            "n_cases": len(controls),
            "invented_atoms": control_invented,
            "invented_count": len(control_invented),
            "clean_rate": round(
                100.0 * (len(controls) - len({c.split(":")[0] for c in control_invented}))
                / len(controls), 1) if controls else None,
            "safety_invented": control_safety_invented,
            "safety_invented_count": len(control_safety_invented),
        },
        "hallucinated_atoms": dict(hallucinated),
        "hallucinated_total": sum(hallucinated.values()),
        "malformed_rate": pct(malformed),
        "malformed_count": malformed,
        "failure_rate": pct(unavailable),
        "failure_count": unavailable,
        "forbidden_key_rate": pct(forbidden),
        "forbidden_key_count": forbidden,
        "latency_ms": {
            "mean": round(statistics.mean(latencies), 1) if latencies else None,
            "median": round(statistics.median(latencies), 1) if latencies else None,
            "p95": round(latencies[min(len(latencies) - 1, int(0.95 * len(latencies)))], 1)
                   if latencies else None,
            "min": round(latencies[0], 1) if latencies else None,
            "max": round(latencies[-1], 1) if latencies else None,
        },
        "exact_match_by_category": {
            cat: {"rate": round(100.0 * sum(v) / len(v), 1), "n": len(v)}
            for cat, v in sorted(category_exact.items())
        },
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=understanding.MODEL)
    parser.add_argument("--prompt", default="v1", choices=sorted(PROMPTS))
    parser.add_argument("--split", default="held_out", choices=("dev", "held_out", "all"))
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--out", default=None)
    # Phase 8.1: run a focused capability subset rather than the whole corpus.
    # A capability question ("can this model attribute a subject?") is answered
    # by the cases that probe it, and a 7B model costs ~7s per case, so running
    # 142 of them to answer a question 45 of them settle is wasted time.
    parser.add_argument("--categories", default=None,
                        help="comma-separated; keep cases carrying ANY of them")
    parser.add_argument("--label", default=None,
                        help="artifact filename tag, for focused subsets")
    args = parser.parse_args()

    cases = by_split(args.split)
    if args.categories:
        wanted = {c.strip() for c in args.categories.split(",") if c.strip()}
        cases = [c for c in cases if wanted & set(c["categories"])]
        if not cases:
            print(f"no cases match {sorted(wanted)}", file=sys.stderr)
            return 1
    os.makedirs(RESULTS_DIR, exist_ok=True)
    tag = f"__{args.label}" if args.label else ""
    out_path = args.out or os.path.join(
        RESULTS_DIR,
        f"{args.model.replace(':', '_').replace('/', '_')}__{args.prompt}__{args.split}{tag}.json")

    # Cold latency is measured separately and excluded from the warm stats: it
    # includes weight loading, which happens once per model, not once per turn.
    cold_started = time.perf_counter()
    await run_case(cases[0], args.model, args.prompt, args.timeout)
    cold_ms = round((time.perf_counter() - cold_started) * 1000, 1)

    rows = []
    for index, case in enumerate(cases, 1):
        row = await run_case(case, args.model, args.prompt, args.timeout)
        rows.append(row)
        flag = "ok " if row["exact_match"] else "MISS"
        print(f"[{index:>3}/{len(cases)}] {flag} {case['id']:22} {row['latency_ms']:>7.0f}ms",
              file=sys.stderr)

    metrics = score(rows)
    metrics["cold_latency_ms"] = cold_ms

    artifact = {
        "schema": "medorbit.understanding_benchmark.v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": args.model,
        "prompt_version": args.prompt,
        "split": args.split,
        "categories_filter": sorted(
            {c.strip() for c in args.categories.split(",")}) if args.categories else None,
        "temperature": 0.1,
        "timeout_s": args.timeout,
        "vocabulary_size": len(vocabulary.SYMPTOMS),
        "safety_atoms": list(SAFETY_ATOMS),
        "metrics": metrics,
        "cases": rows,
    }
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(artifact, handle, ensure_ascii=False, indent=2)

    print(f"\nwrote {out_path}", file=sys.stderr)
    print(json.dumps({k: v for k, v in metrics.items()
                      if k not in ("exact_match_by_category",)},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
