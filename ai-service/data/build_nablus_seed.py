"""
Phase A step 2 — turn the reviewed CSV into db/08_clinics_nablus_osm.sql,
applying the approved decisions:
  1. Drop records with no name at all (no name_ar, name_en, or name_raw).
  2. Null out the known-broken addr:city value on osm_id 431927304.
  3. name_raw language fallback by Arabic-script detection, then backfill
     whichever of name_ar/name_en is still empty from the other side.
  4. Missing phone/address stay NULL. No average_rating column exists on
     medorbit.clinics, so nothing to null there — noted, not fabricated.
  5. Report any type that doesn't map cleanly instead of forcing it.
"""
import csv
import re

IN_CSV = "nablus_osm_review.csv"
OUT_SQL = "../../db/08_clinics_nablus_osm.sql"

VALID_TYPES = {"clinic", "pharmacy", "hospital", "laboratory", "dental", "radiology", "emergency"}
ARABIC_RE = re.compile(r"[؀-ۿ]")
BROKEN_ADDR_OSM_ID = "431927304"


def sql_str(v):
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def sql_num(v):
    if v is None or v == "":
        return "NULL"
    return str(v)


def main():
    with open(IN_CSV, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    print(f"Read {len(rows)} rows from review CSV")

    dropped_no_name = 0
    unmapped_types = []
    final_rows = []

    for r in rows:
        name_ar = r["name_ar"] or None
        name_en = r["name_en"] or None
        name_raw = r["name_raw"] or None

        if not name_ar and not name_en and not name_raw:
            dropped_no_name += 1
            continue

        if not name_ar and not name_en and name_raw:
            if ARABIC_RE.search(name_raw):
                name_ar = name_raw
            else:
                name_en = name_raw

        if not name_ar and name_en:
            name_ar = name_en
        if not name_en and name_ar:
            name_en = name_ar

        address = r["address"] or None
        if r["osm_id"] == BROKEN_ADDR_OSM_ID and address == "addr:city":
            address = None

        type_normalized = r["type_normalized"] or None
        if type_normalized and type_normalized not in VALID_TYPES:
            unmapped_types.append((r["osm_id"], type_normalized))
            type_normalized = None

        final_rows.append({
            "osm_type": r["osm_type"],
            "osm_id": r["osm_id"],
            "name_ar": name_ar,
            "name_en": name_en,
            "address": address,
            "lat": r["lat"],
            "lng": r["lng"],
            "phone": r["phone"] or None,
            "type": type_normalized,
        })

    print(f"Dropped (no name at all): {dropped_no_name}")
    print(f"Final rows to seed: {len(final_rows)}")
    if unmapped_types:
        print(f"Unmapped types (kept, type=NULL): {unmapped_types}")
    else:
        print("Unmapped types: none")

    by_type = {}
    for r in final_rows:
        t = r["type"] or "(null)"
        by_type[t] = by_type.get(t, 0) + 1
    print("Final counts per type:", by_type)

    lines = []
    lines.append("-- 08_clinics_nablus_osm.sql")
    lines.append("-- Real clinic/pharmacy/hospital data for Nablus, collected from OpenStreetMap")
    lines.append("-- (amenity=hospital|clinic|doctors|pharmacy and healthcare=*, bbox 32.18-32.26 lat / 35.21-35.31 lng).")
    lines.append("-- Every row traces to a real OSM node/way (see osm_id comment above each INSERT);")
    lines.append("-- verify any row at https://www.openstreetmap.org/<node|way>/<osm_id>.")
    lines.append("--")
    lines.append("-- Idempotency note: medorbit.clinics has no unique constraint on coordinates and")
    lines.append("-- no osm_id column (adding one would be a schema change, out of scope here), so")
    lines.append("-- ON CONFLICT can't target osm_id directly. Each INSERT instead guards itself with")
    lines.append("-- WHERE NOT EXISTS on the exact (latitude, longitude) pair we are writing — since")
    lines.append("-- those are literal constants in this file (not floating computed values), re-running")
    lines.append("-- this script is a safe no-op for rows already inserted.")
    lines.append("--")
    lines.append("-- address_ar/address_en are NOT NULL on this table, so rows where OSM had no addr:*")
    lines.append("-- tags at all use '' (empty string) rather than a fabricated address. This is")
    lines.append("-- deliberate — treat '' as \"no address\" everywhere it's read, same as NULL.")
    lines.append("")
    lines.append("BEGIN;")
    lines.append("")

    for r in final_rows:
        address_sql = sql_str(r['address']) if r['address'] else "''"
        lines.append(f"-- osm_{r['osm_type']}:{r['osm_id']} -- https://www.openstreetmap.org/{r['osm_type']}/{r['osm_id']}")
        lines.append(
            "INSERT INTO medorbit.clinics "
            "(name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)\n"
            f"SELECT {sql_str(r['name_ar'])}, {sql_str(r['name_en'])}, "
            f"{address_sql}, "
            f"{address_sql}, "
            f"'Nablus', {sql_num(r['lat'])}, {sql_num(r['lng'])}, {sql_str(r['phone'])}, "
            f"{sql_str(r['type'])}, {('ARRAY[' + sql_str(r['type']) + ']') if r['type'] else 'ARRAY[]::text[]'}, "
            "true, 'pending'\n"
            "WHERE NOT EXISTS (\n"
            "  SELECT 1 FROM medorbit.clinics\n"
            f"  WHERE latitude = {sql_num(r['lat'])} AND longitude = {sql_num(r['lng'])}\n"
            ");"
        )
        lines.append("")

    lines.append("COMMIT;")
    lines.append("")

    with open(OUT_SQL, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"\nWrote {OUT_SQL}")


if __name__ == "__main__":
    main()
