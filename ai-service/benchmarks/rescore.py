"""
Recompute an artifact's metrics from its own per-case rows.

    python benchmarks/rescore.py benchmarks/results/*.json

Exists so a metric can be ADDED without re-running the models. The per-case
rows are the primary record; `metrics` is derived from them, so re-deriving it
is always safe and never changes what was observed.
"""

from __future__ import annotations

import glob
import json
import sys

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])

from run_understanding_benchmark import score  # noqa: E402


def main() -> int:
    paths = sys.argv[1:] or ["benchmarks/results/*.json"]
    for pattern in paths:
        for path in sorted(glob.glob(pattern)):
            with open(path, encoding="utf-8") as handle:
                artifact = json.load(handle)
            if "cases" not in artifact:
                continue
            cold = artifact["metrics"].get("cold_latency_ms")
            artifact["metrics"] = score(artifact["cases"])
            if cold is not None:
                artifact["metrics"]["cold_latency_ms"] = cold
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(artifact, handle, ensure_ascii=False, indent=2)
            print(f"rescored {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
