"""Plan or apply idempotent Nablus facility ingestion into MedOrbit PostgreSQL."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

import psycopg2
from dotenv import load_dotenv

from facility_pipeline import DB_TYPE_MAP, duplicate_features, haversine_meters, utc_now
from osm_transform import ARABIC_RE, normalize_name_key


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_INPUT = HERE / "reports" / "nablus" / "nablus_canonical_facilities.jsonl"
DEFAULT_REPORT_DIR = HERE / "reports" / "nablus"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--report-dir", type=Path, default=DEFAULT_REPORT_DIR)
    return parser.parse_args()


def load_canonical(path: Path) -> list[dict[str, Any]]:
    records = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if line.strip():
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    raise ValueError(f"Invalid JSONL at {path}:{line_number}: {exc}") from exc
    return records


def connect():
    load_dotenv(ROOT / ".env")
    return psycopg2.connect(
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        connect_timeout=10,
        application_name="medorbit_facility_ingestion",
    )


def fetch_existing(connection) -> list[dict[str, Any]]:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT id, name_ar, name_en, address_ar, address_en, city, region,
                   latitude, longitude, phone, email, website, type, services,
                   is_active, verification_status
            FROM medorbit.clinics
            ORDER BY id
            """
        )
        columns = [description.name for description in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


def _candidate_names(record: dict[str, Any]) -> set[str]:
    names = [record.get("canonical_name_ar"), record.get("canonical_name_en"), *record.get("aliases", [])]
    return {normalize_name_key(name) for name in names if normalize_name_key(name)}


def _db_names(record: dict[str, Any]) -> set[str]:
    return {normalize_name_key(record.get("name_ar")), normalize_name_key(record.get("name_en"))} - {""}


def _record_similarity(candidate: dict[str, Any], existing: dict[str, Any]) -> float:
    left = {
        "canonical_name_ar": candidate.get("canonical_name_ar"),
        "canonical_name_en": candidate.get("canonical_name_en"),
        "aliases": candidate.get("aliases", []),
        "facility_type": candidate.get("facility_type"),
        "latitude": candidate.get("latitude"),
        "longitude": candidate.get("longitude"),
        "phone_numbers": candidate.get("phone_numbers", []),
        "website": candidate.get("website"),
    }
    right = {
        "canonical_name_ar": existing.get("name_ar"),
        "canonical_name_en": existing.get("name_en"),
        "aliases": [],
        "facility_type": existing.get("type"),
        "latitude": float(existing["latitude"]),
        "longitude": float(existing["longitude"]),
        "phone_numbers": [existing["phone"]] if existing.get("phone") else [],
        "website": existing.get("website"),
    }
    return duplicate_features(left, right)["name_similarity"]


def find_match(candidate: dict[str, Any], existing_rows: list[dict[str, Any]]) -> tuple[dict[str, Any] | None, str | None]:
    latitude, longitude = candidate.get("latitude"), candidate.get("longitude")
    if latitude is None or longitude is None:
        return None, None
    nearby = []
    for existing in existing_rows:
        distance = haversine_meters(latitude, longitude, float(existing["latitude"]), float(existing["longitude"]))
        similarity = _record_similarity(candidate, existing)
        if distance <= 2 and similarity >= 0.60:
            nearby.append((similarity, -distance, existing, "coordinate_and_name"))
        elif distance <= 100 and similarity >= 0.92:
            nearby.append((similarity, -distance, existing, "nearby_normalized_name"))
    if not nearby:
        candidate_keys = _candidate_names(candidate)
        global_name_matches = [row for row in existing_rows if candidate_keys & _db_names(row)]
        if len(global_name_matches) == 1:
            row = global_name_matches[0]
            distance = haversine_meters(latitude, longitude, float(row["latitude"]), float(row["longitude"]))
            if distance <= 500:
                return row, "unique_name_within_500m"
        return None, None
    nearby.sort(key=lambda item: (item[0], item[1]), reverse=True)
    if len(nearby) > 1 and nearby[0][0] - nearby[1][0] < 0.02:
        return None, "ambiguous_db_match"
    return nearby[0][2], nearby[0][3]


def _meaningful_address(value: Any) -> bool:
    return bool(value and str(value).strip() not in {"N/A"})


def build_updates(candidate: dict[str, Any], existing: dict[str, Any]) -> dict[str, Any]:
    updates: dict[str, Any] = {}
    bilingual_candidate = (
        candidate.get("canonical_name_ar")
        and candidate.get("canonical_name_en")
        and ARABIC_RE.search(candidate["canonical_name_ar"])
        and not ARABIC_RE.search(candidate["canonical_name_en"])
    )
    if bilingual_candidate and existing.get("name_ar") == existing.get("name_en") and candidate.get("verification_status") == "verified":
        updates["name_ar"] = candidate["canonical_name_ar"]
        updates["name_en"] = candidate["canonical_name_en"]
    if not _meaningful_address(existing.get("address_ar")) and candidate.get("address_ar"):
        updates["address_ar"] = candidate["address_ar"]
    if not _meaningful_address(existing.get("address_en")) and candidate.get("address_en"):
        updates["address_en"] = candidate["address_en"]
    if not existing.get("phone") and candidate.get("phone_numbers"):
        updates["phone"] = candidate["phone_numbers"][0]
    for field in ("email", "website"):
        if not existing.get(field) and candidate.get(field):
            updates[field] = candidate[field]
    if not existing.get("type") and candidate.get("facility_type"):
        updates["type"] = DB_TYPE_MAP[candidate["facility_type"]]
    existing_services = list(existing.get("services") or [])
    merged_services = existing_services.copy()
    for service in candidate.get("services", []):
        if service and service not in merged_services:
            merged_services.append(service)
    if merged_services != existing_services:
        updates["services"] = merged_services
    if existing.get("verification_status") == "pending" and candidate.get("verification_status") == "verified":
        updates["verification_status"] = "verified"
    return updates


def plan_ingestion(canonical: list[dict[str, Any]], existing_rows: list[dict[str, Any]]) -> dict[str, Any]:
    actions: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    for record in canonical:
        if record.get("city_scope") not in {"nablus_city", "greater_nablus"}:
            rejected.append({"canonical_id": record.get("canonical_id"), "reason": "outside_or_missing_geographic_scope"})
            continue
        if record.get("verification_status") == "needs_review":
            rejected.append({"canonical_id": record.get("canonical_id"), "reason": "quality_error_requires_review"})
            continue
        if record.get("latitude") is None or record.get("longitude") is None or not record.get("facility_type"):
            rejected.append({"canonical_id": record.get("canonical_id"), "reason": "missing_required_db_fields"})
            continue
        matched, match_reason = find_match(record, existing_rows)
        if match_reason == "ambiguous_db_match":
            rejected.append({"canonical_id": record.get("canonical_id"), "reason": match_reason})
            continue
        if matched:
            updates = build_updates(record, matched)
            actions.append({
                "action": "update" if updates else "unchanged",
                "canonical_id": record["canonical_id"],
                "db_id": str(matched["id"]),
                "match_reason": match_reason,
                "updates": updates,
                "record": record,
            })
        else:
            actions.append({
                "action": "insert",
                "canonical_id": record["canonical_id"],
                "db_id": None,
                "match_reason": None,
                "updates": {},
                "record": record,
            })
    counts = {kind: sum(action["action"] == kind for action in actions) for kind in ("insert", "update", "unchanged")}
    counts["rejected"] = len(rejected)
    return {
        "generated_at": utc_now(),
        "canonical_input": len(canonical),
        "existing_db_records": len(existing_rows),
        "counts": counts,
        "actions": actions,
        "rejected": rejected,
    }


def _sql_literal(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "ARRAY[" + ",".join(_sql_literal(item) for item in value) + "]::text[]"
    return "'" + str(value).replace("'", "''") + "'"


def render_dry_run_sql(plan: dict[str, Any]) -> str:
    lines = [
        "-- MedOrbit Nablus facility ingestion dry run",
        f"-- generated_at: {plan['generated_at']}",
        "-- This script always rolls back; save_to_db.py --apply performs parameterized writes.",
        "BEGIN;",
    ]
    for action in plan["actions"]:
        record = action["record"]
        lines.append(f"-- {action['action']} {record['canonical_id']} {record.get('canonical_name_en') or record.get('canonical_name_ar')}")
        if action["action"] == "update":
            assignments = [f"{field} = {_sql_literal(value)}" for field, value in action["updates"].items()]
            assignments.append("updated_at = NOW()")
            lines.append(f"UPDATE medorbit.clinics SET {', '.join(assignments)} WHERE id = {_sql_literal(action['db_id'])}::uuid;")
        elif action["action"] == "insert":
            address_ar = record.get("address_ar") or record.get("address_en") or ""
            address_en = record.get("address_en") or record.get("address_ar") or ""
            columns = "name_ar,name_en,address_ar,address_en,city,latitude,longitude,phone,email,website,type,services,is_active,verification_status"
            values = [
                record.get("canonical_name_ar") or record.get("canonical_name_en"),
                record.get("canonical_name_en") or record.get("canonical_name_ar"),
                address_ar, address_en, "Nablus", record["latitude"], record["longitude"],
                (record.get("phone_numbers") or [None])[0], record.get("email"), record.get("website"),
                DB_TYPE_MAP[record["facility_type"]], record.get("services", []), True,
                "verified" if record.get("verification_status") == "verified" else "pending",
            ]
            lines.append(f"INSERT INTO medorbit.clinics ({columns}) SELECT {','.join(_sql_literal(value) for value in values)} WHERE NOT EXISTS (SELECT 1 FROM medorbit.clinics WHERE latitude = {_sql_literal(record['latitude'])} AND longitude = {_sql_literal(record['longitude'])} AND (lower(name_ar) = lower({_sql_literal(values[0])}) OR lower(name_en) = lower({_sql_literal(values[1])})));" )
    lines.extend(["ROLLBACK;", ""])
    return "\n".join(lines)


def write_plan(plan: dict[str, Any], report_dir: Path) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    serializable = {
        **plan,
        "actions": [
            {key: value for key, value in action.items() if key != "record"}
            | {"facility_name": action["record"].get("canonical_name_en") or action["record"].get("canonical_name_ar")}
            for action in plan["actions"]
        ],
    }
    (report_dir / "nablus_ingestion_dry_run.json").write_text(
        json.dumps(serializable, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8"
    )
    (report_dir / "nablus_ingestion_dry_run.sql").write_text(render_dry_run_sql(plan), encoding="utf-8")


def apply_plan(connection, plan: dict[str, Any]) -> dict[str, int]:
    counts = {"inserted": 0, "updated": 0, "unchanged": 0, "rejected": len(plan["rejected"])}
    with connection:
        with connection.cursor() as cursor:
            for action in plan["actions"]:
                if action["action"] == "unchanged":
                    counts["unchanged"] += 1
                    continue
                record = action["record"]
                if action["action"] == "update":
                    fields = list(action["updates"])
                    assignments = ", ".join(f"{field} = %s" for field in fields)
                    cursor.execute(
                        f"UPDATE medorbit.clinics SET {assignments}, updated_at = NOW() WHERE id = %s",
                        [action["updates"][field] for field in fields] + [action["db_id"]],
                    )
                    counts["updated"] += cursor.rowcount
                    continue
                address_ar = record.get("address_ar") or record.get("address_en") or ""
                address_en = record.get("address_en") or record.get("address_ar") or ""
                values = (
                    record.get("canonical_name_ar") or record.get("canonical_name_en"),
                    record.get("canonical_name_en") or record.get("canonical_name_ar"),
                    address_ar,
                    address_en,
                    "Nablus",
                    record["latitude"],
                    record["longitude"],
                    (record.get("phone_numbers") or [None])[0],
                    record.get("email"),
                    record.get("website"),
                    DB_TYPE_MAP[record["facility_type"]],
                    record.get("services", []),
                    True,
                    "verified" if record.get("verification_status") == "verified" else "pending",
                )
                cursor.execute(
                    """
                    INSERT INTO medorbit.clinics
                      (name_ar,name_en,address_ar,address_en,city,latitude,longitude,phone,email,website,type,services,is_active,verification_status)
                    SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    WHERE NOT EXISTS (
                      SELECT 1 FROM medorbit.clinics
                      WHERE latitude = %s AND longitude = %s
                        AND (lower(name_ar) = lower(%s) OR lower(name_en) = lower(%s))
                    )
                    """,
                    values + (record["latitude"], record["longitude"], values[0], values[1]),
                )
                counts["inserted"] += cursor.rowcount
                if cursor.rowcount == 0:
                    counts["unchanged"] += 1
    return counts


def main() -> None:
    args = parse_args()
    canonical = load_canonical(args.input)
    connection = connect()
    try:
        existing = fetch_existing(connection)
        plan = plan_ingestion(canonical, existing)
        write_plan(plan, args.report_dir)
        print(json.dumps({"mode": "dry_run", **{key: value for key, value in plan.items() if key not in {"actions", "rejected"}}}, ensure_ascii=False, indent=2))
        print(json.dumps({"counts": plan["counts"], "rejected": plan["rejected"]}, ensure_ascii=False, indent=2))
        if args.apply:
            applied = apply_plan(connection, plan)
            post_existing = fetch_existing(connection)
            post_plan = plan_ingestion(canonical, post_existing)
            result = {
                "mode": "apply",
                "applied": applied,
                "post_apply_counts": post_plan["counts"],
                "idempotent": post_plan["counts"]["insert"] == 0 and post_plan["counts"]["update"] == 0,
                "completed_at": utc_now(),
            }
            (args.report_dir / "nablus_ingestion_apply.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8"
            )
            print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    finally:
        connection.close()


if __name__ == "__main__":
    main()
