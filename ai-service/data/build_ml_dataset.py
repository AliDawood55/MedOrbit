"""Build leakage-safe facility-type text-classification splits."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from facility_pipeline import utc_now
from osm_transform import clean_display_text


HERE = Path(__file__).resolve().parent
DEFAULT_INPUT = HERE / "reports" / "nablus" / "nablus_canonical_facilities.jsonl"
DEFAULT_OUTPUT = HERE / "ml" / "nablus_facility_type"
DEFAULT_SEED = 20260809


def load_records(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def _stable_rank(group_id: str, seed: int) -> str:
    return hashlib.sha256(f"{seed}:{group_id}".encode("utf-8")).hexdigest()


def assign_group_splits(records: list[dict[str, Any]], seed: int = DEFAULT_SEED) -> dict[str, str]:
    groups_by_label: dict[str, list[str]] = defaultdict(list)
    for record in records:
        label, group_id = record.get("facility_type"), record.get("canonical_id")
        if label and group_id:
            groups_by_label[label].append(group_id)
    result: dict[str, str] = {}
    for label, group_ids in sorted(groups_by_label.items()):
        ordered = sorted(set(group_ids), key=lambda group_id: _stable_rank(group_id, seed))
        count = len(ordered)
        if count < 3:
            for group_id in ordered:
                result[group_id] = "train"
            continue
        test_count = max(1, round(count * 0.15))
        validation_count = max(1, round(count * 0.15))
        if test_count + validation_count >= count:
            validation_count = 1
            test_count = 1
        for group_id in ordered[:test_count]:
            result[group_id] = "test"
        for group_id in ordered[test_count:test_count + validation_count]:
            result[group_id] = "validation"
        for group_id in ordered[test_count + validation_count:]:
            result[group_id] = "train"
    return result


def build_samples(records: list[dict[str, Any]], seed: int = DEFAULT_SEED) -> list[dict[str, str]]:
    eligible = [
        record for record in records
        if record.get("canonical_id")
        and record.get("facility_type")
        and record.get("verification_status") in {"verified", "probable"}
        and record.get("city_scope") in {"nablus_city", "greater_nablus"}
    ]
    splits = assign_group_splits(eligible, seed)
    samples = []
    for record in eligible:
        names = []
        for value in [record.get("canonical_name_ar"), record.get("canonical_name_en"), *record.get("aliases", [])]:
            value = clean_display_text(value)
            if value and value not in names:
                names.append(value)
        for index, text in enumerate(names):
            sample_id = hashlib.sha256(f"{record['canonical_id']}:{index}:{text}".encode("utf-8")).hexdigest()[:20]
            samples.append({
                "sample_id": sample_id,
                "group_id": record["canonical_id"],
                "text": text,
                "label": record["facility_type"],
                "split": splits[record["canonical_id"]],
                "verification_status": record["verification_status"],
            })
    return samples


def assert_no_group_leakage(samples: list[dict[str, str]]) -> None:
    split_by_group: dict[str, set[str]] = defaultdict(set)
    for sample in samples:
        split_by_group[sample["group_id"]].add(sample["split"])
    leaking = {group: sorted(splits) for group, splits in split_by_group.items() if len(splits) > 1}
    if leaking:
        raise ValueError(f"Group leakage detected: {leaking}")


def write_dataset(samples: list[dict[str, str]], output_dir: Path, input_path: Path, seed: int) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    fields = ["sample_id", "group_id", "text", "label", "split", "verification_status"]
    for split in ("train", "validation", "test"):
        rows = [sample for sample in samples if sample["split"] == split]
        with (output_dir / f"{split}.csv").open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    group_counts = Counter((sample["split"], sample["group_id"]) for sample in samples)
    class_groups: dict[str, set[str]] = defaultdict(set)
    for sample in samples:
        class_groups[sample["label"]].add(sample["group_id"])
    dataset_version = hashlib.sha256(input_path.read_bytes() + str(seed).encode("ascii")).hexdigest()[:16]
    manifest = {
        "dataset_version": dataset_version,
        "created_at": utc_now(),
        "source_file": str(input_path),
        "random_seed": seed,
        "sample_count": len(samples),
        "group_count": len({sample["group_id"] for sample in samples}),
        "split_sample_counts": dict(sorted(Counter(sample["split"] for sample in samples).items())),
        "split_group_counts": dict(sorted(Counter(split for split, _ in group_counts).items())),
        "class_group_counts": dict(sorted((label, len(groups)) for label, groups in class_groups.items())),
        "group_assignments": dict(sorted({sample["group_id"]: sample["split"] for sample in samples}.items())),
        "label_provenance_warning": "Most type labels originate from OSM tags; they are metadata labels, not clinical labels.",
    }
    (output_dir / "dataset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    samples = build_samples(load_records(args.input), args.seed)
    assert_no_group_leakage(samples)
    manifest = write_dataset(samples, args.output_dir, args.input, args.seed)
    print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
