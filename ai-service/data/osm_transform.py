"""Deterministic normalization shared by facility-data workflows."""

from __future__ import annotations

import re
import unicodedata
from urllib.parse import urlsplit, urlunsplit


ARABIC_RE = re.compile(r"[\u0600-\u06ff]")
ARABIC_DIACRITICS_RE = re.compile(r"[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed]")
WHITESPACE_RE = re.compile(r"\s+")
NON_WORD_RE = re.compile(r"[^\w\s]", re.UNICODE)

ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
ARABIC_LETTERS = str.maketrans({
    "أ": "ا",
    "إ": "ا",
    "آ": "ا",
    "ٱ": "ا",
    "ى": "ي",
    "ؤ": "و",
    "ئ": "ي",
    "ـ": "",
})

ENGLISH_ABBREVIATIONS = {
    "hosp": "hospital",
    "ctr": "center",
    "centre": "center",
    "dr": "doctor",
    "med": "medical",
    "rehab": "rehabilitation",
    "lab": "laboratory",
    "diagnostic": "diagnostics",
}

SPECIALTY_MAP = {
    "general": "general_practice",
    "general_practice": "general_practice",
    "internal": "internal_medicine",
    "internal_medicine": "internal_medicine",
    "cardiology": "cardiology",
    "neurology": "neurology",
    "orthopaedics": "orthopedics",
    "orthopedics": "orthopedics",
    "paediatrics": "pediatrics",
    "pediatrician": "pediatrics",
    "pediatrics": "pediatrics",
    "obstetrics": "obstetrics_gynecology",
    "gynaecology": "obstetrics_gynecology",
    "gynecology": "obstetrics_gynecology",
    "dermatology": "dermatology",
    "ophthalmology": "ophthalmology",
    "otolaryngology": "ent",
    "ent": "ent",
    "dentist": "dentistry",
    "dentistry": "dentistry",
    "psychiatry": "psychiatry",
    "radiology": "radiology",
    "physiotherapy": "physiotherapy",
    "laboratory": "laboratory",
    "dialysis": "dialysis",
    "nephrology": "nephrology",
    "oncology": "oncology",
    "surgery": "general_surgery",
}


def normalize_digits(value: str | None) -> str:
    return (value or "").translate(ARABIC_DIGITS)


def clean_display_text(value: str | None) -> str | None:
    if value is None:
        return None
    value = unicodedata.normalize("NFKC", str(value)).translate(ARABIC_DIGITS)
    value = WHITESPACE_RE.sub(" ", value).strip(" \t\r\n,;،؛")
    return value or None


def normalize_arabic_key(value: str | None) -> str:
    value = clean_display_text(value) or ""
    value = ARABIC_DIACRITICS_RE.sub("", value).translate(ARABIC_LETTERS)
    value = NON_WORD_RE.sub(" ", value)
    return WHITESPACE_RE.sub(" ", value).strip().casefold()


def normalize_english_key(value: str | None) -> str:
    value = clean_display_text(value) or ""
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    tokens = NON_WORD_RE.sub(" ", value.casefold()).split()
    return " ".join(ENGLISH_ABBREVIATIONS.get(token, token) for token in tokens)


def normalize_name_key(value: str | None) -> str:
    value = clean_display_text(value)
    if not value:
        return ""
    return normalize_arabic_key(value) if ARABIC_RE.search(value) else normalize_english_key(value)


def normalize_phone(value: str | None) -> str | None:
    if not value:
        return None
    value = normalize_digits(value)
    value = re.sub(r"(?i)(ext\.?|x)\s*\d+$", "", value)
    digits = re.sub(r"\D", "", value)
    if digits.startswith("00970"):
        digits = digits[2:]
    elif digits.startswith("970"):
        pass
    elif digits.startswith("0"):
        digits = "970" + digits[1:]
    return f"+{digits}" if digits else None


def split_phone_numbers(value: str | None) -> list[str]:
    if not value:
        return []
    numbers = []
    for part in re.split(r"\s*(?:/|;|,|،|\bor\b)\s*", normalize_digits(value), flags=re.IGNORECASE):
        normalized = normalize_phone(part)
        if normalized and normalized not in numbers:
            numbers.append(normalized)
    return numbers


def normalize_url(value: str | None) -> str | None:
    value = clean_display_text(value)
    if not value:
        return None
    if not re.match(r"^https?://", value, re.IGNORECASE):
        value = "https://" + value
    try:
        parts = urlsplit(value)
    except ValueError:
        return None
    if parts.scheme not in {"http", "https"} or not parts.netloc or " " in parts.netloc:
        return None
    host = parts.hostname.casefold() if parts.hostname else ""
    if not host or "." not in host:
        return None
    netloc = host + (f":{parts.port}" if parts.port else "")
    path = parts.path.rstrip("/")
    return urlunsplit((parts.scheme.casefold(), netloc, path, parts.query, ""))


def website_domain(value: str | None) -> str | None:
    normalized = normalize_url(value)
    if not normalized:
        return None
    host = urlsplit(normalized).hostname or ""
    return host[4:] if host.startswith("www.") else host


def normalize_specialties(raw: str | list[str] | None) -> tuple[list[str], list[str]]:
    if not raw:
        return [], []
    values = raw if isinstance(raw, list) else re.split(r"[;,|]", raw)
    valid: list[str] = []
    unknown: list[str] = []
    for value in values:
        key = normalize_english_key(str(value)).replace(" ", "_")
        mapped = SPECIALTY_MAP.get(key)
        target = valid if mapped else unknown
        item = mapped or key
        if item and item not in target:
            target.append(item)
    return valid, unknown


def resolve_names(name_ar: str | None, name_en: str | None, name_raw: str | None) -> tuple[str | None, str | None]:
    """Fill missing display names without altering supplied human-readable names."""
    name_ar = clean_display_text(name_ar)
    name_en = clean_display_text(name_en)
    name_raw = clean_display_text(name_raw)
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


def process_place(place: dict) -> dict | None:
    """Backward-compatible OSM-to-DB projection used by legacy builders."""
    name_ar, name_en = resolve_names(place.get("name_ar"), place.get("name_en"), place.get("name_raw"))
    if name_ar is None:
        return None
    return {
        "osm_type": place.get("osm_type"),
        "osm_id": place.get("osm_id"),
        "osm_url": place.get("osm_url"),
        "name_ar": name_ar,
        "name_en": name_en,
        "address": clean_display_text(place.get("address")),
        "lat": place.get("latitude"),
        "lng": place.get("longitude"),
        "phone": normalize_phone(place.get("phone")),
        "type": place.get("type_normalized"),
    }
