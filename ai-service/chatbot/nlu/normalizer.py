import json
import os
import re
from typing import Dict, Optional, Tuple

from chatbot.utils.text_normalizer import normalize_text, detect_language, normalize_arabic, normalize_english


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
            # Common misspellings
            "مستشفا": "مستشفى",
            "مستشفي": "مستشفى",
            "صيدليه": "صيدلية",
            "صيدلي": "صيدلية",
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
            # Common English misspellings
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

        # Step 1: Spell correction
        corrected = self._apply_spell_correction(original)

        # Step 2: Dialect normalization
        normalized_dialect = self._normalize_dialect(corrected)

        # Step 3: Standard normalization
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
        """Normalize Palestinian dialect expressions to standard Arabic."""
        if not self.dialect_data:
            return text

        result = text

        # Process all dialect categories
        for category, expressions in self.dialect_data.items():
            if not isinstance(expressions, dict):
                continue
            for dialect_expr, standard in expressions.items():
                if dialect_expr in result:
                    # Replace dialect expression with standard form
                    result = result.replace(dialect_expr, standard)

        return result

    def fuzzy_match(self, word: str, candidates: list, threshold: float = 0.8) -> Optional[Tuple[str, float]]:
        """
        Fuzzy match a word against a list of candidates using Levenshtein distance.
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

        # Optimize by using shorter string as reference
        if len(a) > len(b):
            a, b = b, a

        distance = self._levenshtein_distance(a, b)
        max_len = max(len(a), len(b))
        if max_len == 0:
            return 1.0
        return 1.0 - (distance / max_len)

    def _levenshtein_distance(self, a: str, b: str) -> int:
        """Compute Levenshtein distance between two strings."""
        if len(a) < len(b):
            a, b = b, a

        previous_row = list(range(len(b) + 1))
        for i, char_a in enumerate(a):
            current_row = [i + 1]
            for j, char_b in enumerate(b):
                insertions = previous_row[j + 1] + 1
                deletions = current_row[j] + 1
                substitutions = previous_row[j] + (char_a != char_b)
                current_row.append(min(insertions, deletions, substitutions))
            previous_row = current_row

        return previous_row[-1]