"""Canonical Nablus healthcare-facility data engineering pipeline.

This module handles facility metadata only.  It has no dependency on, and no
interaction with, Virtual Doctor clinical reasoning.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from difflib import SequenceMatcher
from itertools import combinations
from pathlib import Path
from typing import Any, Iterable

from osm_transform import (
    ARABIC_RE,
    clean_display_text,
    normalize_name_key,
    normalize_specialties,
    normalize_url,
    resolve_names,
    split_phone_numbers,
    website_domain,
)


CITY_BBOX = (32.18, 35.21, 32.26, 35.31)
GREATER_NABLUS_BBOX = (32.15, 35.15, 32.293, 35.35)

CANONICAL_TYPES = {
    "hospital",
    "medical_center",
    "health_center",
    "clinic",
    "specialty_clinic",
    "dental",
    "laboratory",
    "imaging",
    "rehabilitation",
    "mental_health",
    "pharmacy",
    "other_healthcare",
}

DB_TYPE_MAP = {
    "hospital": "hospital",
    "medical_center": "medical_center",
    "health_center": "medical_center",
    "clinic": "clinic",
    "specialty_clinic": "clinic",
    "dental": "dental",
    "laboratory": "laboratory",
    "imaging": "radiology",
    "rehabilitation": "clinic",
    "mental_health": "clinic",
    "pharmacy": "pharmacy",
    "other_healthcare": "clinic",
}

TYPE_ALIASES = {
    "hospital": "hospital",
    "clinic": "clinic",
    "doctors": "clinic",
    "doctor": "clinic",
    "pharmacy": "pharmacy",
    "dentist": "dental",
    "dental": "dental",
    "laboratory": "laboratory",
    "medical_laboratory": "laboratory",
    "radiology": "imaging",
    "imaging": "imaging",
    "centre": "medical_center",
    "center": "medical_center",
    "medical_center": "medical_center",
    "health_centre": "health_center",
    "health_center": "health_center",
    "physiotherapist": "rehabilitation",
    "rehabilitation": "rehabilitation",
    "psychotherapist": "mental_health",
    "psychiatry": "mental_health",
    "mental_health": "mental_health",
    "midwife": "specialty_clinic",
    "optometrist": "specialty_clinic",
    "other_healthcare": "other_healthcare",
}

MISSING_REVIEW_FIELDS = (
    "canonical_name_ar",
    "canonical_name_en",
    "facility_type",
    "address_ar",
    "address_en",
    "phone_numbers",
    "website",
    "latitude",
    "longitude",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def in_bbox(latitude: float, longitude: float, bbox: tuple[float, float, float, float]) -> bool:
    south, west, north, east = bbox
    return south <= latitude <= north and west <= longitude <= east


def classify_city_scope(latitude: float | None, longitude: float | None) -> str:
    if latitude is None or longitude is None:
        return "needs_geolocation"
    if in_bbox(latitude, longitude, CITY_BBOX):
        return "nablus_city"
    if in_bbox(latitude, longitude, GREATER_NABLUS_BBOX):
        return "greater_nablus"
    return "outside_primary_scope"


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6_371_008.8
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    value = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(value))


def _float_or_none(value: Any) -> float | None:
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _bool_from_source(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if value is None:
        return None
    normalized = str(value).strip().casefold()
    if normalized in {"yes", "true", "1", "24_7", "designated"}:
        return True
    if normalized in {"no", "false", "0"}:
        return False
    return None


def canonical_type(amenity: str | None, healthcare: str | None, normalized: str | None = None) -> str | None:
    for value in (healthcare, amenity, normalized):
        if value:
            mapped = TYPE_ALIASES.get(str(value).strip().casefold())
            if mapped:
                return mapped
    return None


def _stable_source_key(record: dict[str, Any]) -> str:
    return f"{record.get('source_type') or 'unknown'}:{record.get('source_record_id') or record.get('source_url') or record.get('canonical_name_en') or record.get('canonical_name_ar')}"


def _stable_id(records: Iterable[dict[str, Any]]) -> str:
    keys = sorted({_stable_source_key(record) for record in records})
    return "fac_" + hashlib.sha256("|".join(keys).encode("utf-8")).hexdigest()[:20]


def _alias_list(*values: Any) -> list[str]:
    aliases: list[str] = []
    for value in values:
        candidates = value if isinstance(value, list) else [value]
        for candidate in candidates:
            candidate = clean_display_text(candidate)
            if candidate and candidate not in aliases:
                aliases.append(candidate)
    return aliases


def _evidence(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "source_url": record.get("source_url"),
        "source_type": record.get("source_type"),
        "source_name": record.get("source_name"),
        "source_record_id": record.get("source_record_id"),
        "collected_at": record.get("collected_at"),
        "last_verified_at": record.get("last_verified_at"),
        "raw_source_payload": record.get("raw_source_payload"),
    }


def canonical_from_osm(place: dict[str, Any]) -> dict[str, Any] | None:
    name_ar, name_en = resolve_names(place.get("name_ar"), place.get("name_en"), place.get("name_raw"))
    if not name_ar and not name_en:
        return None
    latitude = _float_or_none(place.get("latitude", place.get("lat")))
    longitude = _float_or_none(place.get("longitude", place.get("lng")))
    raw_specialty = place.get("healthcare_speciality")
    specialties, unknown_specialties = normalize_specialties(raw_specialty)
    facility_type = canonical_type(
        place.get("type_raw_amenity"),
        place.get("type_raw_healthcare"),
        place.get("type_normalized"),
    )
    source_record_id = place.get("source_record_id") or (
        f"{place.get('osm_type')}:{place.get('osm_id')}" if place.get("osm_type") and place.get("osm_id") is not None else None
    )
    source_url = place.get("source_url") or place.get("osm_url")
    phone_numbers = split_phone_numbers(place.get("phone"))
    address = clean_display_text(place.get("address"))
    record = {
        "canonical_name_ar": name_ar,
        "canonical_name_en": name_en,
        "aliases": _alias_list(place.get("name_raw"), place.get("name_ar"), place.get("name_en")),
        "facility_type": facility_type,
        "facility_subtype": clean_display_text(place.get("type_raw_healthcare")),
        "ownership": clean_display_text(place.get("operator_type")),
        "specialties": specialties,
        "unknown_specialties": unknown_specialties,
        "services": specialties.copy(),
        "address_ar": clean_display_text(place.get("address_ar")) or (address if address and ARABIC_RE.search(address) else None),
        "address_en": clean_display_text(place.get("address_en")) or (address if address and not ARABIC_RE.search(address) else None),
        "street": None,
        "neighborhood": None,
        "city": "Nablus",
        "governorate": "Nablus",
        "latitude": latitude,
        "longitude": longitude,
        "phone_numbers": phone_numbers,
        "email": clean_display_text(place.get("email")),
        "website": normalize_url(place.get("website")),
        "opening_hours": clean_display_text(place.get("opening_hours")),
        "emergency_available": _bool_from_source(place.get("emergency")),
        "ambulance_available": None,
        "wheelchair_access": clean_display_text(place.get("wheelchair")),
        "osm_id": str(place.get("osm_id")) if place.get("osm_id") is not None else None,
        "osm_type": place.get("osm_type"),
        "source_url": source_url,
        "source_type": "openstreetmap",
        "source_name": place.get("source_name") or "OpenStreetMap contributors",
        "source_record_id": source_record_id,
        "verification_status": "probable",
        "confidence_score": 0.68 if facility_type else 0.52,
        "collected_at": place.get("collected_at") or utc_now(),
        "last_verified_at": place.get("last_verified_at") or place.get("collected_at") or utc_now(),
        "raw_source_payload": place.get("raw_source_payload") or place,
        "match_osm_ids": [],
        "city_scope_override": None,
    }
    record["city_scope"] = classify_city_scope(latitude, longitude)
    record["source_evidence"] = [_evidence(record)]
    record["field_provenance"] = {
        field: [_stable_source_key(record)]
        for field, value in record.items()
        if value not in (None, "", [], {}) and field not in {"source_evidence", "field_provenance", "raw_source_payload"}
    }
    return record


def canonical_from_official(source: dict[str, Any]) -> dict[str, Any] | None:
    name_ar, name_en = resolve_names(source.get("canonical_name_ar"), source.get("canonical_name_en"), source.get("name"))
    if not name_ar and not name_en:
        return None
    facility_type = canonical_type(None, source.get("facility_type"), source.get("facility_type"))
    specialties, unknown_specialties = normalize_specialties(source.get("specialties"))
    services = [clean_display_text(value) for value in source.get("services", [])]
    services = [value for value in services if value]
    latitude = _float_or_none(source.get("latitude"))
    longitude = _float_or_none(source.get("longitude"))
    record = {
        "canonical_name_ar": name_ar,
        "canonical_name_en": name_en,
        "aliases": _alias_list(source.get("aliases"), source.get("name")),
        "facility_type": facility_type,
        "facility_subtype": clean_display_text(source.get("facility_subtype")),
        "ownership": clean_display_text(source.get("ownership")),
        "specialties": specialties,
        "unknown_specialties": unknown_specialties,
        "services": services,
        "address_ar": clean_display_text(source.get("address_ar")),
        "address_en": clean_display_text(source.get("address_en")),
        "street": clean_display_text(source.get("street")),
        "neighborhood": clean_display_text(source.get("neighborhood")),
        "city": clean_display_text(source.get("city")) or "Nablus",
        "governorate": clean_display_text(source.get("governorate")) or "Nablus",
        "latitude": latitude,
        "longitude": longitude,
        "phone_numbers": [number for value in source.get("phone_numbers", []) for number in split_phone_numbers(value)],
        "email": clean_display_text(source.get("email")),
        "website": normalize_url(source.get("website")),
        "opening_hours": clean_display_text(source.get("opening_hours")),
        "emergency_available": _bool_from_source(source.get("emergency_available")),
        "ambulance_available": _bool_from_source(source.get("ambulance_available")),
        "wheelchair_access": clean_display_text(source.get("wheelchair_access")),
        "osm_id": None,
        "osm_type": None,
        "source_url": source.get("source_url"),
        "source_type": source.get("source_type") or "official_organization",
        "source_name": source.get("source_name"),
        "source_record_id": source.get("source_record_id"),
        "verification_status": source.get("verification_status") or "probable",
        "confidence_score": float(source.get("confidence_score", 0.82)),
        "collected_at": source.get("collected_at") or utc_now(),
        "last_verified_at": source.get("last_verified_at") or utc_now(),
        "raw_source_payload": source,
        "match_osm_ids": [str(value) for value in source.get("match_osm_ids", [])],
        "city_scope_override": source.get("city_scope_override"),
    }
    record["phone_numbers"] = list(dict.fromkeys(record["phone_numbers"]))
    record["city_scope"] = source.get("city_scope") or classify_city_scope(latitude, longitude)
    record["source_evidence"] = [_evidence(record)]
    record["field_provenance"] = {
        field: [_stable_source_key(record)]
        for field, value in record.items()
        if value not in (None, "", [], {}) and field not in {"source_evidence", "field_provenance", "raw_source_payload"}
    }
    return record


def _name_keys(record: dict[str, Any]) -> set[str]:
    keys = set()
    for value in [record.get("canonical_name_ar"), record.get("canonical_name_en"), *record.get("aliases", [])]:
        key = normalize_name_key(value)
        if key:
            keys.add(key)
    return keys


def name_similarity(left: dict[str, Any], right: dict[str, Any]) -> float:
    left_keys, right_keys = _name_keys(left), _name_keys(right)
    if not left_keys or not right_keys:
        return 0.0
    return max(SequenceMatcher(None, a, b).ratio() for a in left_keys for b in right_keys)


def _types_compatible(left: str | None, right: str | None) -> bool:
    if not left or not right or left == right:
        return True
    clinic_family = {"clinic", "specialty_clinic", "medical_center", "health_center", "rehabilitation", "mental_health"}
    return left in clinic_family and right in clinic_family


def duplicate_features(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    distance = None
    if None not in (left.get("latitude"), left.get("longitude"), right.get("latitude"), right.get("longitude")):
        distance = haversine_meters(left["latitude"], left["longitude"], right["latitude"], right["longitude"])
    left_phones, right_phones = set(left.get("phone_numbers", [])), set(right.get("phone_numbers", []))
    left_domain, right_domain = website_domain(left.get("website")), website_domain(right.get("website"))
    return {
        "name_similarity": round(name_similarity(left, right), 4),
        "distance_meters": round(distance, 2) if distance is not None else None,
        "phone_equal": bool(left_phones & right_phones),
        "domain_equal": bool(left_domain and right_domain and left_domain == right_domain),
        "type_compatible": _types_compatible(left.get("facility_type"), right.get("facility_type")),
        "same_osm_id": bool(
            left.get("osm_id") and right.get("osm_id") and left.get("osm_id") == right.get("osm_id") and left.get("osm_type") == right.get("osm_type")
        ),
        "same_source_id": bool(
            left.get("source_type") == right.get("source_type")
            and left.get("source_record_id")
            and left.get("source_record_id") == right.get("source_record_id")
        ),
        "explicit_official_osm_match": bool(
            (right.get("source_record_id") in left.get("match_osm_ids", []))
            or (left.get("source_record_id") in right.get("match_osm_ids", []))
        ),
    }


def classify_duplicate(features: dict[str, Any]) -> tuple[str, str]:
    similarity = features["name_similarity"]
    distance = features["distance_meters"]
    compatible = features["type_compatible"]
    if features["same_osm_id"] or features["same_source_id"] or features["explicit_official_osm_match"]:
        return "exact", "stable source identity or curated official-to-OSM match"
    if compatible and distance is not None and distance <= 25 and similarity >= 0.92:
        return "exact", "very similar name within 25 m"
    if compatible and features["phone_equal"] and distance is not None and distance <= 50 and similarity >= 0.80:
        return "exact", "same normalized phone and compatible name within 50 m"
    if compatible and distance is not None and distance <= 150 and similarity >= 0.92:
        return "probable", "very similar name within 150 m"
    if compatible and features["domain_equal"] and similarity >= 0.70:
        return "probable", "same website domain and compatible name"
    if compatible and features["phone_equal"] and distance is not None and distance <= 250 and similarity >= 0.85:
        return "probable", "same normalized phone and compatible name within 250 m"
    if compatible and distance is not None and distance <= 500 and similarity >= 0.72:
        return "possible", "similar name within 500 m"
    if compatible and distance is None and similarity >= 0.95:
        return "possible", "near-exact name without coordinates"
    if compatible and features["phone_equal"] and similarity >= 0.75:
        return "possible", "same normalized phone but location is not close enough to merge"
    return "distinct", "insufficient duplicate evidence"


class _UnionFind:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))

    def find(self, value: int) -> int:
        while self.parent[value] != value:
            self.parent[value] = self.parent[self.parent[value]]
            value = self.parent[value]
        return value

    def union(self, left: int, right: int) -> None:
        a, b = self.find(left), self.find(right)
        if a != b:
            self.parent[b] = a


def _source_priority(record: dict[str, Any], field: str) -> int:
    source_type = record.get("source_type")
    if field in {"latitude", "longitude", "osm_id", "osm_type"}:
        return 100 if source_type == "openstreetmap" else 70
    priorities = {
        "government_directory": 100,
        "official_hospital": 95,
        "official_organization": 90,
        "municipal_directory": 85,
        "openstreetmap": 70,
        "public_directory": 40,
    }
    return priorities.get(source_type, 30)


def merge_records(records: list[dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    ordered = sorted(records, key=lambda record: _source_priority(record, "canonical_name_en"), reverse=True)
    merged = json.loads(json.dumps(ordered[0], ensure_ascii=False))
    conflicts: list[dict[str, Any]] = []
    list_fields = {"aliases", "specialties", "unknown_specialties", "services", "phone_numbers", "source_evidence"}
    scalar_fields = {
        "canonical_name_ar", "canonical_name_en", "facility_type", "facility_subtype", "ownership",
        "address_ar", "address_en", "street", "neighborhood", "city", "governorate", "latitude", "longitude",
        "email", "website", "opening_hours", "emergency_available", "ambulance_available", "wheelchair_access",
        "osm_id", "osm_type", "city_scope",
        "city_scope_override",
    }
    provenance: dict[str, list[str]] = defaultdict(list)
    for record in records:
        source_key = _stable_source_key(record)
        for field in scalar_fields:
            value = record.get(field)
            if value in (None, "") or (field == "city_scope" and value == "needs_geolocation"):
                continue
            if source_key not in provenance[field]:
                provenance[field].append(source_key)
            existing = merged.get(field)
            if existing in (None, "", "needs_geolocation"):
                merged[field] = value
            elif existing != value:
                if field in {"latitude", "longitude"} and abs(float(existing) - float(value)) < 0.00001:
                    continue
                winner = max(records, key=lambda item: _source_priority(item, field))
                chosen = winner.get(field) if winner.get(field) not in (None, "") else existing
                conflicts.append({
                    "field": field,
                    "chosen_value": chosen,
                    "values": json.dumps(sorted({str(existing), str(value)}), ensure_ascii=False),
                    "reason": "authoritative-source priority; conflicting value preserved for review",
                    "source_urls": " | ".join(sorted({str(item.get("source_url")) for item in records if item.get("source_url")})),
                })
                merged[field] = chosen
        for field in list_fields:
            current = merged.setdefault(field, [])
            for value in record.get(field, []):
                if value not in current:
                    current.append(value)

    merged["canonical_id"] = _stable_id(records)
    merged["field_provenance"] = dict(provenance)
    merged["source_url"] = next((record.get("source_url") for record in ordered if record.get("source_url")), None)
    merged["source_type"] = next((record.get("source_type") for record in ordered if record.get("source_type")), None)
    merged["source_name"] = next((record.get("source_name") for record in ordered if record.get("source_name")), None)
    merged["source_record_id"] = next((record.get("source_record_id") for record in ordered if record.get("source_record_id")), None)
    merged["raw_source_payload"] = [record.get("raw_source_payload") for record in records]
    merged["collected_at"] = min(record.get("collected_at") or utc_now() for record in records)
    merged["last_verified_at"] = max(record.get("last_verified_at") or record.get("collected_at") or utc_now() for record in records)
    source_types = {record.get("source_type") for record in records}
    if "openstreetmap" in source_types and source_types - {"openstreetmap"}:
        merged["verification_status"] = "verified"
        merged["confidence_score"] = max(0.92, max(float(record.get("confidence_score", 0)) for record in records))
    else:
        merged["verification_status"] = "probable"
        merged["confidence_score"] = max(float(record.get("confidence_score", 0.5)) for record in records)
    explicit_scope = next((record.get("city_scope_override") for record in records if record.get("city_scope_override")), None)
    merged["city_scope"] = explicit_scope or classify_city_scope(merged.get("latitude"), merged.get("longitude"))
    for conflict in conflicts:
        conflict["canonical_id"] = merged["canonical_id"]
        conflict["facility_name"] = merged.get("canonical_name_en") or merged.get("canonical_name_ar")
    return merged, conflicts


def deduplicate(records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    union = _UnionFind(len(records))
    candidates: list[dict[str, Any]] = []
    for left_index, right_index in combinations(range(len(records)), 2):
        left, right = records[left_index], records[right_index]
        features = duplicate_features(left, right)
        classification, reason = classify_duplicate(features)
        if classification == "exact":
            union.union(left_index, right_index)
        if classification in {"probable", "possible"}:
            candidates.append({
                "classification": classification,
                "reason": reason,
                "left_source_id": left.get("source_record_id"),
                "right_source_id": right.get("source_record_id"),
                "left_name": left.get("canonical_name_en") or left.get("canonical_name_ar"),
                "right_name": right.get("canonical_name_en") or right.get("canonical_name_ar"),
                "left_type": left.get("facility_type"),
                "right_type": right.get("facility_type"),
                "left_source_url": left.get("source_url"),
                "right_source_url": right.get("source_url"),
                **features,
                "review_decision": "",
            })
    clusters: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for index, record in enumerate(records):
        clusters[union.find(index)].append(record)
    canonical: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    for cluster in clusters.values():
        merged, cluster_conflicts = merge_records(cluster)
        canonical.append(merged)
        conflicts.extend(cluster_conflicts)
    canonical.sort(key=lambda item: (item.get("city_scope", ""), normalize_name_key(item.get("canonical_name_en") or item.get("canonical_name_ar"))))
    candidates.sort(key=lambda item: (item["classification"], -item["name_similarity"], item["distance_meters"] or 10**9))
    return canonical, candidates, conflicts


def validate_record(record: dict[str, Any]) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []

    def add(code: str, severity: str, field: str, message: str) -> None:
        issues.append({
            "canonical_id": record.get("canonical_id"),
            "facility_name": record.get("canonical_name_en") or record.get("canonical_name_ar"),
            "code": code,
            "severity": severity,
            "field": field,
            "message": message,
            "source_urls": " | ".join(sorted({e.get("source_url") for e in record.get("source_evidence", []) if e.get("source_url")})),
        })

    if not record.get("canonical_name_ar") and not record.get("canonical_name_en"):
        add("missing_canonical_name", "error", "canonical_name", "No usable canonical name")
    if record.get("facility_type") not in CANONICAL_TYPES:
        add("unknown_category", "error", "facility_type", f"Unsupported category: {record.get('facility_type')!r}")
    latitude, longitude = record.get("latitude"), record.get("longitude")
    if latitude is None or longitude is None:
        add("missing_coordinates", "warning", "latitude,longitude", "Coordinates are missing")
    else:
        if not -90 <= latitude <= 90:
            add("invalid_latitude", "error", "latitude", f"Latitude out of range: {latitude}")
        if not -180 <= longitude <= 180:
            add("invalid_longitude", "error", "longitude", f"Longitude out of range: {longitude}")
        if abs(latitude) < 0.001 and abs(longitude) < 0.001:
            add("null_island", "error", "latitude,longitude", "Coordinate is at null island")
        if record.get("city_scope") == "outside_primary_scope":
            add("outside_geographic_scope", "warning", "city_scope", "Coordinate is outside the greater-Nablus bbox")
    for phone in record.get("phone_numbers", []):
        digit_count = len(re.sub(r"\D", "", phone))
        if digit_count < 8 or digit_count > 15:
            add("malformed_phone", "warning", "phone_numbers", f"Malformed phone: {phone}")
    raw_website = record.get("website")
    if raw_website and not normalize_url(raw_website):
        add("malformed_url", "warning", "website", f"Malformed website: {raw_website}")
    for specialty in record.get("unknown_specialties", []):
        add("invalid_specialty_label", "warning", "specialties", f"Unmapped specialty: {specialty}")
    if record.get("canonical_name_en") and ARABIC_RE.search(record["canonical_name_en"]):
        add("english_name_contains_arabic", "info", "canonical_name_en", "English display field contains Arabic text")
    if record.get("canonical_name_ar") and not ARABIC_RE.search(record["canonical_name_ar"]):
        add("arabic_name_contains_no_arabic", "info", "canonical_name_ar", "Arabic display field contains no Arabic text")
    return issues


def _cross_record_quality(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    osm_ids: dict[str, list[dict[str, Any]]] = defaultdict(list)
    source_ids: dict[str, list[dict[str, Any]]] = defaultdict(list)
    name_keys: dict[str, list[dict[str, Any]]] = defaultdict(list)
    phones: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        if record.get("osm_id"):
            osm_ids[f"{record.get('osm_type')}:{record['osm_id']}"] .append(record)
        for evidence in record.get("source_evidence", []):
            if evidence.get("source_type") and evidence.get("source_record_id"):
                source_ids[f"{evidence['source_type']}:{evidence['source_record_id']}"] .append(record)
        for key in _name_keys(record):
            name_keys[key].append(record)
        for phone in record.get("phone_numbers", []):
            phones[phone].append(record)

    def add(code: str, severity: str, key: str, matches: list[dict[str, Any]], message: str) -> None:
        issues.append({
            "canonical_id": " | ".join(record["canonical_id"] for record in matches),
            "facility_name": " | ".join(str(record.get("canonical_name_en") or record.get("canonical_name_ar")) for record in matches),
            "code": code,
            "severity": severity,
            "field": key,
            "message": message,
            "source_urls": " | ".join(sorted({e.get("source_url") for record in matches for e in record.get("source_evidence", []) if e.get("source_url")})),
        })

    for key, matches in osm_ids.items():
        if len(matches) > 1:
            add("duplicate_osm_id", "error", key, matches, "OSM identity appears in multiple canonical records")
    for key, matches in source_ids.items():
        if len(matches) > 1:
            add("duplicate_source_id", "error", key, matches, "Source identity appears in multiple canonical records")
    for key, matches in name_keys.items():
        unique = {record["canonical_id"] for record in matches}
        if key and len(unique) > 1:
            add("duplicate_normalized_name", "warning", key, list({record["canonical_id"]: record for record in matches}.values()), "Normalized name appears on multiple records")
    for phone, matches in phones.items():
        unique = list({record["canonical_id"]: record for record in matches}.values())
        if len(unique) >= 3:
            add("phone_overuse", "warning", phone, unique, "Phone is shared by at least three canonical facilities")
    return issues


def load_official_sources(path: str | Path) -> list[dict[str, Any]]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(payload.get("records"), list):
        raise ValueError("Official source file must contain a records list")
    return payload["records"]


def load_scope_overrides(path: str | Path) -> dict[str, dict[str, str]]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    overrides = payload.get("geographic_overrides", {})
    if not isinstance(overrides, dict):
        raise ValueError("geographic_overrides must be an object")
    return overrides


def load_legacy_osm_csv(path: str | Path) -> list[dict[str, Any]]:
    records = []
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            row["latitude"] = row.get("lat")
            row["longitude"] = row.get("lng")
            row["source_url"] = row.get("osm_url")
            row["source_type"] = "openstreetmap"
            row["source_name"] = "OpenStreetMap contributors"
            row["source_record_id"] = f"{row.get('osm_type')}:{row.get('osm_id')}"
            row["collected_at"] = datetime.fromtimestamp(Path(path).stat().st_mtime, timezone.utc).replace(microsecond=0).isoformat()
            row["raw_source_payload"] = row.copy()
            records.append(row)
    return records


def _write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            serialized = {}
            for field in fields:
                value = row.get(field)
                if isinstance(value, (list, dict)):
                    value = json.dumps(value, ensure_ascii=False, sort_keys=True)
                serialized[field] = value
            writer.writerow(serialized)


def _missing_rows(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for record in records:
        missing = [field for field in MISSING_REVIEW_FIELDS if record.get(field) in (None, "", [])]
        if missing:
            rows.append({
                "canonical_id": record["canonical_id"],
                "facility_name": record.get("canonical_name_en") or record.get("canonical_name_ar"),
                "facility_type": record.get("facility_type"),
                "city_scope": record.get("city_scope"),
                "verification_status": record.get("verification_status"),
                "missing_fields": " | ".join(missing),
                "source_urls": " | ".join(sorted({e.get("source_url") for e in record.get("source_evidence", []) if e.get("source_url")})),
                "review_notes": "",
            })
    return rows


def build_eda(records: list[dict[str, Any]], source_count: int, duplicate_candidates: list[dict[str, Any]], issues: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(records)
    def pct(count: int) -> float:
        return round(100 * count / total, 2) if total else 0.0
    return {
        "generated_at": utc_now(),
        "total_source_records": source_count,
        "total_canonical_facilities": total,
        "counts_by_type": dict(sorted(Counter(record.get("facility_type") or "unknown" for record in records).items())),
        "specialty_distribution": dict(sorted(Counter(s for record in records for s in record.get("specialties", [])).items())),
        "geographic_distribution": dict(sorted(Counter(record.get("city_scope") for record in records).items())),
        "source_coverage": dict(sorted(Counter(e.get("source_type") for record in records for e in record.get("source_evidence", [])).items())),
        "verification_distribution": dict(sorted(Counter(record.get("verification_status") for record in records).items())),
        "availability_percent": {
            "arabic_name": pct(sum(bool(record.get("canonical_name_ar") and ARABIC_RE.search(record["canonical_name_ar"])) for record in records)),
            "english_name": pct(sum(bool(record.get("canonical_name_en") and not ARABIC_RE.search(record["canonical_name_en"])) for record in records)),
            "coordinates": pct(sum(record.get("latitude") is not None and record.get("longitude") is not None for record in records)),
            "phone": pct(sum(bool(record.get("phone_numbers")) for record in records)),
            "website": pct(sum(bool(record.get("website")) for record in records)),
            "address_any": pct(sum(bool(record.get("address_ar") or record.get("address_en")) for record in records)),
        },
        "duplicate_candidates": dict(sorted(Counter(candidate["classification"] for candidate in duplicate_candidates).items())),
        "quality_issues_by_code": dict(sorted(Counter(issue["code"] for issue in issues).items())),
        "class_imbalance": {
            "largest_class": Counter(record.get("facility_type") or "unknown" for record in records).most_common(1)[0] if records else None,
            "smallest_nonzero_class": min(Counter(record.get("facility_type") or "unknown" for record in records).items(), key=lambda item: item[1]) if records else None,
        },
    }


def run_pipeline(
    osm_records: list[dict[str, Any]],
    official_records: list[dict[str, Any]],
    output_dir: str | Path,
    scope_overrides: dict[str, dict[str, str]] | None = None,
) -> dict[str, Any]:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    rejected: list[dict[str, Any]] = []
    source_records: list[dict[str, Any]] = []
    for raw in osm_records:
        record = canonical_from_osm(raw)
        if record:
            override = (scope_overrides or {}).get(record.get("source_record_id"), {})
            if override.get("city_scope"):
                record["city_scope_override"] = override["city_scope"]
                record["city_scope"] = override["city_scope"]
                record["geographic_override_reason"] = override.get("reason")
            source_records.append(record)
        else:
            rejected.append({"source_record_id": raw.get("source_record_id") or raw.get("osm_id"), "reason": "missing_name"})
    for raw in official_records:
        record = canonical_from_official(raw)
        if record:
            source_records.append(record)
        else:
            rejected.append({"source_record_id": raw.get("source_record_id"), "reason": "missing_name"})

    canonical, duplicates, conflicts = deduplicate(source_records)
    issues = [issue for record in canonical for issue in validate_record(record)]
    issues.extend(_cross_record_quality(canonical))
    issue_ids = {issue["canonical_id"] for issue in issues if issue["severity"] == "error"}
    for record in canonical:
        if record["canonical_id"] in issue_ids:
            record["verification_status"] = "needs_review"
            record["confidence_score"] = min(float(record.get("confidence_score", 0.5)), 0.49)
    missing = _missing_rows(canonical)
    eda = build_eda(canonical, len(source_records), duplicates, issues)
    exact_merged = len(source_records) - len(canonical)

    canonical_fields = [
        "canonical_id", "canonical_name_ar", "canonical_name_en", "aliases", "facility_type", "facility_subtype",
        "ownership", "specialties", "services", "address_ar", "address_en", "street", "neighborhood", "city",
        "governorate", "city_scope", "latitude", "longitude", "phone_numbers", "email", "website", "opening_hours",
        "emergency_available", "ambulance_available", "wheelchair_access", "osm_id", "osm_type", "source_url",
        "source_type", "source_name", "source_record_id", "verification_status", "confidence_score", "collected_at",
        "last_verified_at", "source_evidence", "field_provenance", "raw_source_payload",
    ]
    _write_csv(output_dir / "nablus_canonical_facilities.csv", canonical, canonical_fields)
    with (output_dir / "nablus_canonical_facilities.jsonl").open("w", encoding="utf-8") as handle:
        for record in canonical:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    _write_csv(
        output_dir / "nablus_facilities_review.csv",
        canonical,
        [
            "canonical_id", "canonical_name_ar", "canonical_name_en", "aliases", "facility_type", "specialties",
            "city_scope", "latitude", "longitude", "phone_numbers", "website", "verification_status", "confidence_score",
            "source_url", "source_type", "source_record_id", "source_evidence",
        ],
    )
    duplicate_fields = [
        "classification", "reason", "left_source_id", "right_source_id", "left_name", "right_name", "left_type",
        "right_type", "name_similarity", "distance_meters", "phone_equal", "domain_equal", "type_compatible",
        "left_source_url", "right_source_url", "review_decision",
    ]
    _write_csv(output_dir / "nablus_duplicates_review.csv", duplicates, duplicate_fields)
    _write_csv(
        output_dir / "nablus_conflicts_review.csv",
        conflicts,
        ["canonical_id", "facility_name", "field", "chosen_value", "values", "reason", "source_urls"],
    )
    _write_csv(
        output_dir / "nablus_missing_fields_review.csv",
        missing,
        ["canonical_id", "facility_name", "facility_type", "city_scope", "verification_status", "missing_fields", "source_urls", "review_notes"],
    )
    _write_csv(
        output_dir / "nablus_quality_issues.csv",
        issues,
        ["canonical_id", "facility_name", "code", "severity", "field", "message", "source_urls"],
    )
    (output_dir / "nablus_quality_report.json").write_text(
        json.dumps({
            "generated_at": utc_now(),
            "summary": dict(Counter(issue["severity"] for issue in issues)),
            "by_code": dict(sorted(Counter(issue["code"] for issue in issues).items())),
            "issues": issues,
            "rejected": rejected,
        }, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    (output_dir / "nablus_eda.json").write_text(json.dumps(eda, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    eda_lines = [
        "# Nablus facility EDA",
        "",
        f"Generated: {eda['generated_at']}",
        f"Source records: {eda['total_source_records']}",
        f"Canonical facilities: {eda['total_canonical_facilities']}",
        f"Exact records merged: {exact_merged}",
        "",
        "## Counts by type",
        *[f"- {key}: {value}" for key, value in eda["counts_by_type"].items()],
        "",
        "## Geographic distribution",
        *[f"- {key}: {value}" for key, value in eda["geographic_distribution"].items()],
        "",
        "## Verification distribution",
        *[f"- {key}: {value}" for key, value in eda["verification_distribution"].items()],
        "",
        "## Field availability",
        *[f"- {key}: {value:.2f}%" for key, value in eda["availability_percent"].items()],
    ]
    (output_dir / "nablus_eda.md").write_text("\n".join(eda_lines) + "\n", encoding="utf-8")
    summary = {
        "generated_at": utc_now(),
        "raw_osm_records": len(osm_records),
        "official_source_records": len(official_records),
        "source_records_retained": len(source_records),
        "records_rejected": len(rejected),
        "canonical_facilities": len(canonical),
        "exact_records_merged": exact_merged,
        "ambiguous_duplicate_candidates": len(duplicates),
        "conflicts": len(conflicts),
        "missing_field_review_records": len(missing),
        "quality_issues": len(issues),
        "counts_by_type": eda["counts_by_type"],
        "geographic_distribution": eda["geographic_distribution"],
        "verification_distribution": eda["verification_distribution"],
    }
    (output_dir / "nablus_pipeline_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    return summary
