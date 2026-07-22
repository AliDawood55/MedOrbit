"""
Shared post-processing for OSMCollector.format_place() output. Used by
save_to_db.py, build_nablus_seed.py, and build_nablus_cleanup.py so the
name-resolution rule lives in exactly one place and can't drift between them.
"""
import re

ARABIC_RE = re.compile(r"[؀-ۿ]")


def resolve_names(name_ar, name_en, name_raw):
    """
    Approved rule: classify the generic `name` tag by script and use it to
    fill whichever of name_ar/name_en is missing — checked independently for
    each side, not just when both are empty (a record can have a real
    name:en tag and a separately-available Arabic name_raw at the same time;
    the Arabic side must still get name_raw, not be discarded and backfilled
    from the English tag). Only after that, cross-backfill whichever side is
    STILL empty from the other side, so nothing renders blank. Returns
    (None, None) if there's no name at all — the caller should drop that
    record.
    """
    if not name_ar and not name_en and not name_raw:
        return None, None

    if name_raw:
        raw_is_arabic = bool(ARABIC_RE.search(name_raw))
        if not name_ar and raw_is_arabic:
            name_ar = name_raw
        if not name_en and not raw_is_arabic:
            name_en = name_raw

    if not name_ar and name_en:
        name_ar = name_en
    if not name_en and name_ar:
        name_en = name_ar

    return name_ar, name_en


def process_place(p):
    """
    Takes one dict from OSMCollector.format_place() and returns the fully
    resolved record ready to write (name_ar/name_en resolved, address/type/
    phone/coords passed through as-is since format_place() already produced
    clean values for those), or None if the record should be dropped
    (no name at all).
    """
    name_ar, name_en = resolve_names(p["name_ar"], p["name_en"], p["name_raw"])
    if name_ar is None:
        return None

    return {
        "osm_type": p["osm_type"],
        "osm_id": p["osm_id"],
        "osm_url": p["osm_url"],
        "name_ar": name_ar,
        "name_en": name_en,
        "address": p["address"],
        "lat": p["latitude"],
        "lng": p["longitude"],
        "phone": p["phone"],
        "type": p["type_normalized"],
    }
