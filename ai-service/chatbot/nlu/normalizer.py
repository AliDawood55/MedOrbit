import json
import os
import re
from typing import Dict, Optional, Tuple

from chatbot.utils.text_normalizer import detect_language, normalize_arabic, normalize_english


class TextNormalizer:
    """
    Advanced text normalizer with spell correction, dialect support,
    and fuzzy matching for Arabic and English medical queries.
    """

    def __init__(self):
        self.dialect_data = self._load_dialect_data()
        self._build_spell_map()

    def _load_dialect_data(self) -> Dict:
        base_path = os.path.join(os.path.dirname(__file__), "data")
        path = os.path.join(base_path, "palestinian_dialect.json")
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _build_spell_map(self):
        """Build common Arabic misspelling corrections."""
        self.spell_corrections = {
            "مستشفا": "مستشفى",
            "مستشفي": "مستشفى",
            "صيدليه": "صيدلية",
            "دكتورر": "دكتور",
            "دكتر": "دكتور",
            "طبيب": "دكتور",
            "بارستمول": "باراسيتامول",
            "بنادول": "بانادول",
            "تحاليلل": "تحاليل",
            "تحليلل": "تحليل",
            "معمل": "مختبر",
            "اشعه": "أشعة",
            "الالم": "الألم",
            "الوجع": "الوجع",
            "الموعد": "موعد",
            "المعده": "المعدة",
            "الظهر": "الظهر",
            "الصدر": "الصدر",
            "الراس": "الرأس",
            "البطن": "البطن",
            "medecine": "medicine",
            "medicin": "medicine",
            "medacine": "medicine",
            "hospetal": "hospital",
            "hospitle": "hospital",
            "hosptal": "hospital",
            "clinnic": "clinic",
            "clinik": "clinic",
            "farmasy": "pharmacy",
            "farmacey": "pharmacy",
            "pharmcy": "pharmacy",
            "apointment": "appointment",
            "apointmint": "appointment",
            "doktor": "doctor",
            "docotr": "doctor",
            "dokter": "doctor",
            "sergery": "surgery",
            "sergary": "surgery",
            "surgary": "surgery",
            "headake": "headache",
            "headak": "headache",
            "stomack": "stomach",
            "stomac": "stomach",
            "diabetis": "diabetes",
            "diabeties": "diabetes",
            "allergy": "allergy",
            "alergy": "allergy",
            "allergy": "allergy",
            "pneumonia": "pneumonia",
            "numonia": "pneumonia",
            "pnumonia": "pneumonia",
        }

    def normalize(self, text: str) -> str:
        """
        Full normalization pipeline:
        1. Spell correction
        2. Palestinian dialect normalization
        3. Standard Arabic/English normalization
        4. Whitespace cleanup
        """
        if not text:
            return ""

        original = text.strip()

        corrected = self._apply_spell_correction(original)

        normalized_dialect = self._normalize_dialect(corrected)

        lang = detect_language(normalized_dialect)
        if lang == "ar":
            result = normalize_arabic(normalized_dialect)
        else:
            result = normalize_english(normalized_dialect)

        return result

    def normalize_with_metadata(self, text: str) -> Dict:
        """
        Normalize and return metadata about what was changed.
        """
        original = text.strip()
        corrected = self._apply_spell_correction(original)
        dialect_normalized = self._normalize_dialect(corrected)
        lang = detect_language(dialect_normalized)

        return {
            "original": original,
            "corrected": corrected if corrected != original else None,
            "dialect_normalized": dialect_normalized if dialect_normalized != corrected else None,
            "normalized": normalize_arabic(dialect_normalized) if lang == "ar" else normalize_english(dialect_normalized),
            "language": "arabic" if lang == "ar" else "english",
            "was_corrected": corrected != original,
            "was_dialect": dialect_normalized != corrected
        }

    def _apply_spell_correction(self, text: str) -> str:
        """Apply known spell corrections."""
        result = text
        for wrong, correct in self.spell_corrections.items():
            if wrong in result:
                result = result.replace(wrong, correct)
        return result

    def _normalize_dialect(self, text: str) -> str:
        """Normalize Palestinian dialect expressions to standard Arabic.

        Boundary-safe: uses \\b, which Python's `re` module already treats as
        Unicode-aware (Arabic letters count as word characters, same as
        English letters and digits), so a short expression like "لا" or
        "مين" only fires as its own standalone word/phrase and never fires
        merely because its characters happen to appear inside an unrelated
        longer word — e.g. "لا" no longer matches inside "السلامة", nor
        "مين" inside "التأمين". Multi-word expressions ("كم يستغرق") are
        matched the same way, with the boundary check only applied at the
        outer edges of the whole phrase.
        """
        if not self.dialect_data:
            return text

        result = text

        for expressions in self.dialect_data.values():
            if not isinstance(expressions, dict):
                continue
            for dialect_expr, standard in expressions.items():
                pattern = r'\b' + re.escape(dialect_expr) + r'\b'
                result = re.sub(pattern, standard, result)

        return result

    def fuzzy_match(self, word: str, candidates: list, threshold: float = 0.8) -> Optional[Tuple[str, float]]:
        """
        Fuzzy match a word against a list of candidates using Damerau-Levenshtein
        distance (insertions, deletions, substitutions, and adjacent-letter
        transpositions each count as a single edit — e.g. "docotr" vs "doctor").
        Returns (best_match, score) if above threshold, else None.
        """
        if not word or not candidates:
            return None

        word = word.lower()
        best_match = None
        best_score = 0.0

        for candidate in candidates:
            score = self._levenshtein_similarity(word, candidate.lower())
            if score > best_score:
                best_score = score
                best_match = candidate

        if best_score >= threshold:
            return (best_match, best_score)
        return None

    def _levenshtein_similarity(self, a: str, b: str) -> float:
        """Calculate Levenshtein-based similarity score (0.0 to 1.0)."""
        if not a and not b:
            return 1.0
        if not a or not b:
            return 0.0

        if len(a) > len(b):
            a, b = b, a

        distance = self._levenshtein_distance(a, b)
        max_len = max(len(a), len(b))
        if max_len == 0:
            return 1.0
        return 1.0 - (distance / max_len)

    def _levenshtein_distance(self, a: str, b: str) -> int:
        """Compute Damerau-Levenshtein distance between two strings.

        Insertions, deletions, and substitutions each cost one edit, as in
        plain Levenshtein distance. An adjacent-letter transposition (e.g.
        "docotr" -> "doctor") also costs a single edit rather than two, since
        that is the single most common typo shape and scoring it as two edits
        was pushing common misspellings below the fuzzy-match threshold.
        """
        len_a, len_b = len(a), len(b)
        d = [[0] * (len_b + 1) for _ in range(len_a + 1)]

        for i in range(len_a + 1):
            d[i][0] = i
        for j in range(len_b + 1):
            d[0][j] = j

        for i in range(1, len_a + 1):
            for j in range(1, len_b + 1):
                cost = 0 if a[i - 1] == b[j - 1] else 1
                d[i][j] = min(
                    d[i - 1][j] + 1,
                    d[i][j - 1] + 1,
                    d[i - 1][j - 1] + cost,
                )
                if (
                    i > 1 and j > 1
                    and a[i - 1] == b[j - 2]
                    and a[i - 2] == b[j - 1]
                ):
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)

        return d[len_a][len_b]
