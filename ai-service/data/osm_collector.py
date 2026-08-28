"""Respectful, cache-aware OpenStreetMap healthcare collection.

The collector intentionally returns source records, not application rows.  All
normalization, scope classification, validation, and merging live downstream.
"""

from __future__ import annotations

import hashlib
import json
import os
import random
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests


TYPE_MAP = {
    "hospital": "hospital",
    "clinic": "clinic",
    "doctors": "clinic",
    "doctor": "clinic",
    "pharmacy": "pharmacy",
    "dentist": "dental",
    "laboratory": "laboratory",
    "medical_laboratory": "laboratory",
    "centre": "medical_center",
    "center": "medical_center",
    "health_centre": "medical_center",
    "health_center": "medical_center",
    "physiotherapist": "clinic",
    "rehabilitation": "clinic",
    "psychotherapist": "clinic",
    "midwife": "clinic",
    "optometrist": "optical",
}

DEFAULT_BBOX = (32.18, 35.21, 32.26, 35.31)
DEFAULT_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


class OSMCollector:
    """Collect public OSM healthcare elements with cache and bounded retries."""

    def __init__(
        self,
        *,
        endpoints: tuple[str, ...] = DEFAULT_ENDPOINTS,
        cache_dir: str | Path | None = None,
        cache_max_age_hours: float = 168,
        session: requests.Session | None = None,
    ) -> None:
        self.places: list[dict[str, Any]] = []
        self.endpoints = endpoints
        self.url = endpoints[0]
        self.cache_dir = Path(cache_dir) if cache_dir else Path(__file__).with_name("cache")
        self.cache_max_age_hours = cache_max_age_hours
        self.session = session or requests.Session()
        self.user_agent = os.getenv(
            "MEDORBIT_OSM_USER_AGENT",
            "MedOrbit-Healthcare-Facility-Research/1.0",
        )

    @staticmethod
    def build_query(bbox: tuple[float, float, float, float]) -> str:
        south, west, north, east = bbox
        bbox_str = f"{south},{west},{north},{east}"
        selectors = []
        for element_type in ("node", "way", "relation"):
            selectors.append(
                f'{element_type}["amenity"~"^(clinic|hospital|doctors|pharmacy|dentist|laboratory)$"]({bbox_str});'
            )
            selectors.append(f'{element_type}["healthcare"]({bbox_str});')
        return "\n".join(
            [
                "[out:json][timeout:180];",
                "(",
                *selectors,
                ");",
                "out center tags;",
            ]
        )

    def _cache_path(self, query: str) -> Path:
        digest = hashlib.sha256(query.encode("utf-8")).hexdigest()[:16]
        return self.cache_dir / f"overpass_{digest}.json"

    def _read_cache(self, path: Path) -> dict[str, Any] | None:
        if not path.exists():
            return None
        age_hours = (time.time() - path.stat().st_mtime) / 3600
        if age_hours > self.cache_max_age_hours:
            return None
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        return payload if isinstance(payload, dict) and "elements" in payload else None

    def _write_cache(self, path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        temporary.replace(path)

    def _download(self, query: str) -> dict[str, Any]:
        last_error: Exception | None = None
        for attempt in range(3):
            endpoint = self.endpoints[attempt % len(self.endpoints)]
            try:
                response = self.session.post(
                    endpoint,
                    data={"data": query},
                    headers={"User-Agent": self.user_agent, "Accept": "application/json"},
                    timeout=(20, 240),
                )
                if response.status_code in {429, 502, 503, 504}:
                    retry_after = response.headers.get("Retry-After")
                    delay = min(float(retry_after), 60) if retry_after and retry_after.isdigit() else 5 * (2**attempt)
                    time.sleep(delay + random.random())
                    continue
                response.raise_for_status()
                payload = response.json()
                if not isinstance(payload, dict) or not isinstance(payload.get("elements"), list):
                    raise ValueError("Overpass response did not contain an elements list")
                return payload
            except (requests.RequestException, ValueError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(5 * (2**attempt) + random.random())
        raise RuntimeError(f"Overpass collection failed after bounded retries: {last_error}")

    def fetch_healthcare(
        self,
        bbox: tuple[float, float, float, float] = DEFAULT_BBOX,
        *,
        force_refresh: bool = False,
    ) -> list[dict[str, Any]]:
        query = self.build_query(bbox)
        cache_path = self._cache_path(query)
        data = None if force_refresh else self._read_cache(cache_path)
        cache_hit = data is not None
        if data is None:
            data = self._download(query)
            data["_medorbit"] = {
                "bbox": list(bbox),
                "collected_at": utc_now(),
                "endpoint": "overpass",
                "query_sha256": hashlib.sha256(query.encode("utf-8")).hexdigest(),
            }
            self._write_cache(cache_path, data)

        metadata = data.get("_medorbit", {})
        collected_at = metadata.get("collected_at") or utc_now()
        self.places = []
        for element in data.get("elements", []):
            place = self.format_place(element, collected_at=collected_at)
            if place:
                self.places.append(place)
        records = self.remove_duplicates()
        for record in records:
            record["cache_hit"] = cache_hit
        return records

    @staticmethod
    def format_place(element: dict[str, Any], *, collected_at: str | None = None) -> dict[str, Any] | None:
        tags = element.get("tags") or {}
        lat = element.get("lat")
        lon = element.get("lon")
        if (lat is None or lon is None) and isinstance(element.get("center"), dict):
            lat = element["center"].get("lat")
            lon = element["center"].get("lon")
        if lat is None or lon is None:
            return None

        def clean_addr(value: Any) -> str | None:
            if not isinstance(value, str) or not value.strip():
                return None
            value = value.strip()
            return None if re.match(r"^addr:", value, re.IGNORECASE) else value

        address_parts = [
            clean_addr(tags.get("addr:housenumber")),
            clean_addr(tags.get("addr:street")),
            clean_addr(tags.get("addr:place")),
            clean_addr(tags.get("addr:city")),
        ]
        address = ", ".join(part for part in address_parts if part) or clean_addr(tags.get("addr:full"))
        amenity_raw = tags.get("amenity")
        healthcare_raw = tags.get("healthcare")
        type_normalized = TYPE_MAP.get(str(amenity_raw).lower()) or TYPE_MAP.get(str(healthcare_raw).lower())
        osm_type = element.get("type")
        osm_id = element.get("id")
        osm_url = f"https://www.openstreetmap.org/{osm_type}/{osm_id}" if osm_type and osm_id is not None else None

        return {
            "osm_type": osm_type,
            "osm_id": osm_id,
            "osm_url": osm_url,
            "name_ar": tags.get("name:ar"),
            "name_en": tags.get("name:en"),
            "name_raw": tags.get("name"),
            "latitude": lat,
            "longitude": lon,
            "address": address,
            "address_ar": tags.get("addr:full:ar") or tags.get("addr:street:ar"),
            "address_en": tags.get("addr:full:en") or tags.get("addr:street:en"),
            "phone": tags.get("contact:phone") or tags.get("phone"),
            "email": tags.get("contact:email") or tags.get("email"),
            "website": tags.get("contact:website") or tags.get("website"),
            "opening_hours": tags.get("opening_hours"),
            "operator": tags.get("operator"),
            "operator_type": tags.get("operator:type"),
            "emergency": tags.get("emergency"),
            "wheelchair": tags.get("wheelchair"),
            "healthcare_speciality": tags.get("healthcare:speciality"),
            "type_raw_amenity": amenity_raw,
            "type_raw_healthcare": healthcare_raw,
            "type_normalized": type_normalized,
            "source_url": osm_url,
            "source_type": "openstreetmap",
            "source_name": "OpenStreetMap contributors",
            "source_record_id": f"{osm_type}:{osm_id}" if osm_type and osm_id is not None else None,
            "collected_at": collected_at or utc_now(),
            "raw_source_payload": {"type": osm_type, "id": osm_id, "tags": tags},
        }

    def remove_duplicates(self) -> list[dict[str, Any]]:
        unique: dict[tuple[Any, Any], dict[str, Any]] = {}
        for place in self.places:
            unique[(place.get("osm_type"), place.get("osm_id"))] = place
        return list(unique.values())
