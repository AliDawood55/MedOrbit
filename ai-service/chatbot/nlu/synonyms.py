import json
import os
from typing import Dict, List, Optional


class SynonymEngine:
    """
    Medical synonym resolution engine.
    Loads external JSON dictionaries for Arabic, English, and medical terms.
    Resolves user expressions to canonical forms for intent matching.
    """

    def __init__(self):
        self.arabic_synonyms = self._load_json("arabic_synonyms.json")
        self.medical_synonyms = self._load_json("medical_synonyms.json")
        self._build_reverse_lookup()

    def _load_json(self, filename: str) -> Dict:
        """Load a JSON dictionary from the data directory."""
        base_path = os.path.join(os.path.dirname(__file__), "data")
        path = os.path.join(base_path, filename)
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _build_reverse_lookup(self):
        """Build reverse maps from any synonym to its canonical form."""
        self.synonym_to_canonical = {}

        # Arabic synonyms
        for canonical, variants in self.arabic_synonyms.items():
            for variant in variants:
                normalized = self._normalize_key(variant)
                self.synonym_to_canonical[normalized] = canonical

        # Medical synonyms
        for canonical, variants in self.medical_synonyms.items():
            for variant in variants:
                normalized = self._normalize_key(variant)
                # Medical takes priority if conflict
                self.synonym_to_canonical[normalized] = canonical

    def _normalize_key(self, text: str) -> str:
        """Normalize synonym key for lookup."""
        return text.strip().lower()

    def resolve(self, text: str) -> str:
        """
        Resolve a word or phrase to its canonical form.
        If no synonym is found, returns the original text.
        """
        if not text:
            return text

        normalized = self._normalize_key(text)
        return self.synonym_to_canonical.get(normalized, text)

    def resolve_tokens(self, tokens: List[str]) -> List[str]:
        """Resolve a list of tokens to their canonical forms."""
        return [self.resolve(t) for t in tokens]

    def resolve_text(self, text: str) -> str:
        """
        Resolve all known synonyms in a text string.
        Replaces synonym phrases with their canonical forms.
        """
        if not text:
            return text

        result = text.lower()

        # First try multi-word synonyms (sorted by length descending)
        multi_word = [(phrase, canon) for phrase, canon in self.synonym_to_canonical.items()
                      if ' ' in phrase]
        multi_word.sort(key=lambda x: len(x[0]), reverse=True)

        for phrase, canonical in multi_word:
            if phrase in result:
                result = result.replace(phrase, canonical)

        # Then single-word synonyms
        single_word = [(word, canon) for word, canon in self.synonym_to_canonical.items()
                       if ' ' not in word]
        for word, canonical in single_word:
            if word in result:
                # Word boundary check for English
                pattern = r'\b' + word + r'\b'
                import re
                result = re.sub(pattern, canonical, result)

        return result

    def get_synonyms(self, canonical: str) -> List[str]:
        """Get all synonyms for a canonical form."""
        results = []

        # Check Arabic synonyms
        if canonical in self.arabic_synonyms:
            results.extend(self.arabic_synonyms[canonical])

        # Check medical synonyms
        if canonical in self.medical_synonyms:
            results.extend(self.medical_synonyms[canonical])

        return list(set(results))

    def get_all_canonical_forms(self) -> List[str]:
        """Get all canonical forms available in the synonym engine."""
        forms = set()
        forms.update(self.arabic_synonyms.keys())
        forms.update(self.medical_synonyms.keys())
        return sorted(forms)

    def find_canonical_by_substring(self, text: str) -> List[Dict]:
        """
        Find canonical forms that match a substring of the text.
        Returns list of matches with confidence scores.
        """
        matches = []
        text_lower = text.lower()

        for phrase, canonical in self.synonym_to_canonical.items():
            if phrase in text_lower:
                confidence = len(phrase) / len(text_lower) if text_lower else 0
                confidence = min(confidence + 0.5, 1.0)  # Base boost for exact match
                matches.append({
                    "canonical": canonical,
                    "matched_phrase": phrase,
                    "confidence": round(confidence, 4)
                })

        # Sort by confidence descending
        matches.sort(key=lambda x: x["confidence"], reverse=True)
        return matches

    def expand_query(self, text: str) -> str:
        """
        Expand a query by adding synonyms in parentheses.
        Useful for building search queries that match multiple terms.
        Example: "doctor" → "doctor (physician) (طبيب)"
        """
        resolved = self.resolve(text)
        synonyms = self.get_synonyms(resolved)

        if synonyms:
            # Add top 3 synonyms
            expanded = resolved
            for syn in synonyms[:3]:
                if syn != resolved:
                    expanded += f" ({syn})"
            return expanded

        return text