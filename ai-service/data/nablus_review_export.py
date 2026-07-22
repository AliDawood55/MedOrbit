"""
Phase A — Nablus clinic data collection for manual review.
Fetches real OSM records (amenity=hospital|clinic|doctors|pharmacy and
healthcare=*) for the Nablus bbox and writes a CSV for human review.
Does NOT touch the database — that only happens after manual approval,
via a separately-written SQL file.
"""
import csv
from osm_collector import OSMCollector

BBOX = (32.18, 35.21, 32.26, 35.31)  # south, west, north, east
OUT_CSV = "nablus_osm_review.csv"

FIELDS = [
    "osm_type", "osm_id", "osm_url",
    "name_ar", "name_en", "name_raw",
    "type_raw_amenity", "type_raw_healthcare", "type_normalized",
    "lat", "lng", "phone", "address",
    "name_ar_provided", "name_en_provided", "phone_provided", "address_provided", "type_provided",
]


def main():
    collector = OSMCollector()
    places = collector.fetch_healthcare(bbox=BBOX)

    print(f"Collected {len(places)} unique OSM records")

    rows = []
    for p in places:
        rows.append({
            "osm_type": p["osm_type"],
            "osm_id": p["osm_id"],
            "osm_url": p["osm_url"],
            "name_ar": p["name_ar"],
            "name_en": p["name_en"],
            "name_raw": p["name_raw"],
            "type_raw_amenity": p["type_raw_amenity"],
            "type_raw_healthcare": p["type_raw_healthcare"],
            "type_normalized": p["type_normalized"],
            "lat": p["latitude"],
            "lng": p["longitude"],
            "phone": p["phone"],
            "address": p["address"],
            "name_ar_provided": bool(p["name_ar"]),
            "name_en_provided": bool(p["name_en"]),
            "phone_provided": bool(p["phone"]),
            "address_provided": bool(p["address"]),
            "type_provided": bool(p["type_normalized"]),
        })

    with open(OUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {OUT_CSV}")

    # ---- Summary report ----
    by_type = {}
    for r in rows:
        t = r["type_normalized"] or "(unmapped)"
        by_type[t] = by_type.get(t, 0) + 1

    print("\nCounts per normalized type:")
    for t, c in sorted(by_type.items(), key=lambda x: -x[1]):
        print(f"  {t}: {c}")

    total = len(rows)
    has_name_ar = sum(1 for r in rows if r["name_ar_provided"])
    has_name_en = sum(1 for r in rows if r["name_en_provided"])
    has_name_raw = sum(1 for r in rows if r["name_raw"])
    has_phone = sum(1 for r in rows if r["phone_provided"])
    has_address = sum(1 for r in rows if r["address_provided"])
    has_neither_name = sum(1 for r in rows if not r["name_ar"] and not r["name_en"] and not r["name_raw"])

    print(f"\nTotal records: {total}")
    print(f"  name:ar tag present: {has_name_ar}")
    print(f"  name:en tag present: {has_name_en}")
    print(f"  generic name tag present: {has_name_raw}")
    print(f"  no name at all (name/name:ar/name:en all missing): {has_neither_name}")
    print(f"  phone present: {has_phone}")
    print(f"  address (any addr:* part) present: {has_address}")
    print(f"  unmapped type (neither amenity nor healthcare recognized): {by_type.get('(unmapped)', 0)}")


if __name__ == "__main__":
    main()
