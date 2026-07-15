import re

ARABIC_DIACRITICS = re.compile(r"[\u0617-\u061A\u064B-\u0652]")


def normalize_arabic(text: str) -> str:
    if not text:
        return ""

    normalized = ARABIC_DIACRITICS.sub("", text)
    normalized = normalized.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    normalized = normalized.replace("ى", "ي").replace("ة", "ه")
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def normalize_english(text: str) -> str:
    if not text:
        return ""

    normalized = text.lower()
    normalized = re.sub(r"[^a-z0-9\s]", " ", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def detect_language(text: str) -> str:
    if not text:
        return "unknown"

    if re.search(r"[\u0600-\u06FF]", text):
        return "ar"
    if re.search(r"[a-zA-Z]", text):
        return "en"
    return "unknown"


def normalize_text(text: str, language: str | None = None) -> str:
    lang = language or detect_language(text)
    if lang == "ar":
        return normalize_arabic(text)
    return normalize_english(text)
