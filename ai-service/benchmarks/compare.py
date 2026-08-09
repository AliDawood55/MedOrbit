"""
Phase 6.5 — read benchmark artifacts and print comparison tables.

    python benchmarks/compare.py benchmarks/results/*.json

Pure reporting. It reads the JSON artifacts the runner wrote and computes
nothing the runner did not already record, so a table can always be traced back
to per-case rows.
"""

from __future__ import annotations

import glob
import json
import sys
from typing import Any, Dict, List


def load(paths: List[str]) -> List[Dict[str, Any]]:
    out = []
    for pattern in paths:
        for path in sorted(glob.glob(pattern)):
            with open(path, encoding="utf-8") as handle:
                out.append(json.load(handle))
    return out


def _row(artifact):
    m = artifact["metrics"]
    return {
        "run": f'{artifact["model"]}/{artifact["prompt_version"]}/{artifact["split"]}',
        "n": m["n_cases"],
        "P": m["symptom_micro"]["precision"],
        "R": m["symptom_micro"]["recall"],
        "F1": m["symptom_micro"]["f1"],
        "exact": m["exact_match_rate"],
        "multi_R": m["multi_symptom_recall"],
        "safety_R": m["safety_atom_recall"],
        "halluc": m["hallucinated_total"],
        "malformed": m["malformed_rate"],
        "fail": m["failure_rate"],
        "mean_ms": m["latency_ms"]["mean"],
        "p95_ms": m["latency_ms"]["p95"],
    }


def main() -> int:
    artifacts = load(sys.argv[1:] or ["benchmarks/results/*.json"])
    if not artifacts:
        print("no artifacts")
        return 1

    print(f"{'RUN':34} {'n':>3} {'P':>6} {'R':>6} {'F1':>6} {'exact%':>7} "
          f"{'multiR':>7} {'safeR':>6} {'hall':>5} {'malf%':>6} {'fail%':>6} "
          f"{'mean_ms':>8} {'p95_ms':>8}")
    print("-" * 130)
    for a in artifacts:
        r = _row(a)
        def f(v, w=6, p=3):
            return f"{v:>{w}.{p}f}" if isinstance(v, float) else f"{str(v):>{w}}"
        print(f"{r['run']:34} {r['n']:>3} {f(r['P'])} {f(r['R'])} {f(r['F1'])} "
              f"{f(r['exact'],7,1)} {f(r['multi_R'],7)} {f(r['safety_R'])} "
              f"{r['halluc']:>5} {f(r['malformed'],6,1)} {f(r['fail'],6,1)} "
              f"{f(r['mean_ms'],8,0)} {f(r['p95_ms'],8,0)}")

    print("\n\nPOLARITY (precision / recall / F1)")
    print(f"{'RUN':34} {'present':>22} {'absent':>22} {'uncertain':>22}")
    print("-" * 130)
    for a in artifacts:
        m = a["metrics"]["polarity"]
        cells = []
        for pol in ("present", "absent", "uncertain"):
            d = m[pol]
            cells.append(f"{d['precision']:.2f}/{d['recall']:.2f}/{d['f1']:.2f} ({d['tp']}/{d['tp']+d['fn']})")
        run = f'{a["model"]}/{a["prompt_version"]}/{a["split"]}'
        print(f"{run:34} {cells[0]:>22} {cells[1]:>22} {cells[2]:>22}")

    print("\n\nBY LANGUAGE (precision / recall / F1)")
    print(f"{'RUN':34} {'arabic':>26} {'english':>26}")
    print("-" * 100)
    for a in artifacts:
        m = a["metrics"]["by_language"]
        cells = []
        for lang in ("ar", "en"):
            d = m.get(lang)
            cells.append(f"{d['precision']:.2f}/{d['recall']:.2f}/{d['f1']:.2f} (tp{d['tp']} fp{d['fp']} fn{d['fn']})"
                         if d else "-")
        run = f'{a["model"]}/{a["prompt_version"]}/{a["split"]}'
        print(f"{run:34} {cells[0]:>26} {cells[1]:>26}")

    print("\n\nSAFETY ATOMS (raw counts, no weighting)")
    for a in artifacts:
        m = a["metrics"]
        run = f'{a["model"]}/{a["prompt_version"]}/{a["split"]}'
        print(f"{run:34} recall {m['safety_atom_found']}/{m['safety_atom_expected']}"
              f"   FALSE POSITIVES: {m.get('safety_false_positive_count', '?')}")
        print(f"{'':34}   misses={m['safety_atom_misses'] or '-'}")
        print(f"{'':34}   false_pos={m.get('safety_false_positives') or '-'}")

    print("\n\nHALLUCINATED CANONICAL ATOMS")
    for a in artifacts:
        run = f'{a["model"]}/{a["prompt_version"]}/{a["split"]}'
        print(f"{run:34} {a['metrics']['hallucinated_atoms'] or '-'}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
