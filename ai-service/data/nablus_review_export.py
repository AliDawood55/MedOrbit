"""Collect and build the auditable Nablus facility review dataset."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from facility_pipeline import (
    CITY_BBOX,
    GREATER_NABLUS_BBOX,
    load_legacy_osm_csv,
    load_official_sources,
    load_scope_overrides,
    run_pipeline,
)
from osm_collector import OSMCollector


HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE / "reports" / "nablus"
DEFAULT_OFFICIAL = HERE / "official_nablus_sources.json"
LEGACY_SNAPSHOT = HERE / "nablus_wide_review2.csv"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", choices=("city", "greater"), default="greater")
    parser.add_argument("--refresh", action="store_true", help="Ignore a valid Overpass cache and fetch once")
    parser.add_argument("--offline", action="store_true", help="Use the immutable legacy CSV snapshot; make no network call")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--official-sources", type=Path, default=DEFAULT_OFFICIAL)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.offline and args.refresh:
        raise SystemExit("--offline and --refresh are mutually exclusive")
    bbox = CITY_BBOX if args.scope == "city" else GREATER_NABLUS_BBOX
    if args.offline:
        osm_records = load_legacy_osm_csv(LEGACY_SNAPSHOT)
        collection_mode = "legacy_snapshot"
    else:
        collector = OSMCollector(cache_dir=HERE / "cache", cache_max_age_hours=168)
        osm_records = collector.fetch_healthcare(bbox=bbox, force_refresh=args.refresh)
        collection_mode = "overpass_cache_or_refresh"
    official_records = load_official_sources(args.official_sources)
    scope_overrides = load_scope_overrides(args.official_sources)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    raw_path = args.output_dir / "nablus_osm_raw.json"
    raw_path.write_text(
        json.dumps(
            {
                "collection_mode": collection_mode,
                "bbox": list(bbox),
                "records": osm_records,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    summary = run_pipeline(osm_records, official_records, args.output_dir, scope_overrides)
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
