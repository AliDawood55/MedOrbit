import json
import os
import time
from typing import Dict, Optional

from chatbot.utils.text_normalizer import normalize_text
from chatbot.nlu.normalizer import TextNormalizer
from chatbot.nlu.synonyms import SPECIALTY_CANONICAL_KEYS, SynonymEngine
from chatbot.nlu.tokens import Tokenizer
from chatbot.nlu.context_resolver import ContextResolver


class EntityExtractor:
    """
    Entity extractor using the hybrid NLU engine.
    
    Preserves the existing public interface:
        extract(text, context) -> Dict
    
    Internally uses full NLU pipeline:
        normalization → dialect → tokens → synonyms → 
        context resolution → entity linking
    """

    def __init__(self):
        self.entities = self._load_entities()
        
        self.normalizer = TextNormalizer()
        self.synonyms = SynonymEngine()
        self.tokenizer = Tokenizer()
        self.context_resolver = ContextResolver()

    def _load_entities(self):
        base_path = os.path.dirname(__file__)
        file_path = os.path.join(base_path, "medical_entities.json")
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def extract(self, text: str, context: Optional[Dict] = None) -> Dict:
        """
        Extract entities from user text using the hybrid NLU pipeline.
        
        Supports:
        - 22 medical specialties
        - 9 facility types
        - 14 symptoms
        - 9 Nablus locations
        - Medications
        - Services
        - Numeric values
        - Contextual resolution
        - Palestinian dialect expressions
        """
        start_time = time.time()
        
        if not text:
            return self._empty_result(text)

        normalized_info = self.normalizer.normalize_with_metadata(text)
        normalized = normalized_info["normalized"]
        lang = normalized_info["language"]

        tokens = self.tokenizer.tokenize(normalized)
        ngrams = self.tokenizer.extract_ngrams(tokens, min_n=1, max_n=3)
        ngram_set = set(ngrams)

        resolved_text = self.synonyms.resolve_text(normalized)
        # For the specialty match below: exact-equality lookup against the
        # resolved text's own tokens, not `canonical in resolved_text`
        # substring search — a short specialty abbreviation like "ent" is a
        # literal substring of unrelated English words ("appointment"),
        # which was matching as a false specialty. resolve_text() already
        # performs its word replacements with `\b`-bounded regexes, so
        # tokenizing its output the same way the message itself is tokenized
        # keeps every remaining word-boundary-safe.
        resolved_tokens = set(self.tokenizer.tokenize(resolved_text, keep_stop_words=True))

        extracted = self._empty_result(text)
        extracted["language"] = "arabic" if lang == "ar" else "english"
        extracted["was_corrected"] = normalized_info["was_corrected"]
        extracted["was_dialect"] = normalized_info["was_dialect"]

        if "specialties" in self.entities:
            for key, langs in self.entities["specialties"].items():
                for words in langs.values():
                    for word in words:
                        word_norm = normalize_text(word)
                        # Exact match against a whole token or contiguous
                        # n-gram, not `word_norm in normalized` substring
                        # search — a short Arabic trigger word like "انف"
                        # (nose) is a literal substring of unrelated words
                        # such as "انفلونزا" (flu), and "بول" (urine) is a
                        # literal substring of "بوليصة" (insurance policy).
                        if word_norm in ngram_set:
                            if key not in extracted["specialties"]:
                                extracted["specialties"].append(key)
                            if not extracted["specialty"]:
                                extracted["specialty"] = key

        for canonical in self.synonyms.get_all_canonical_forms():
            if canonical not in SPECIALTY_CANONICAL_KEYS:
                continue
            if canonical in resolved_tokens:
                if canonical not in extracted["specialties"]:
                    extracted["specialties"].append(canonical)
                if not extracted["specialty"]:
                    extracted["specialty"] = canonical

        type_candidates = {"clinic", "hospital", "pharmacy", "laboratory", 
                          "radiology", "dental", "emergency", "optical", "vaccination"}
        
        for ngram in ngrams:
            canonical = self.synonyms.resolve(ngram)
            if canonical in type_candidates:
                if canonical not in extracted["types"]:
                    extracted["types"].append(canonical)
                if not extracted["type"]:
                    extracted["type"] = canonical

        if "types" in self.entities:
            for key, langs in self.entities["types"].items():
                for words in langs.values():
                    for word in words:
                        word_norm = normalize_text(word)
                        if word_norm in normalized:
                            if key not in extracted["types"]:
                                extracted["types"].append(key)
                            if not extracted["type"]:
                                extracted["type"] = key

        if "symptoms" in self.entities:
            for key, langs in self.entities["symptoms"].items():
                for words in langs.values():
                    for word in words:
                        word_norm = normalize_text(word)
                        if word_norm in normalized:
                            if key not in extracted["symptoms"]:
                                extracted["symptoms"].append(key)

        for ngram in ngrams:
            canonical = self.synonyms.resolve(ngram)
            symptom_keys = {"headache", "fever", "cough", "fatigue", "dizziness", "nausea",
                          "chest_pain", "stomach_ache", "back_pain", "insomnia", "anxiety", "skin_rash"}
            if canonical in symptom_keys:
                if canonical not in extracted["symptoms"]:
                    extracted["symptoms"].append(canonical)

        if "locations" in self.entities:
            for key, langs in self.entities["locations"].items():
                for words in langs.values():
                    for word in words:
                        word_norm = normalize_text(word)
                        if word_norm in normalized:
                            extracted["location"] = key

        for ngram in ngrams:
            if ngram.lower() in ("nabulus", "nablus", "نابلس"):
                extracted["location"] = "nablus"
            elif ngram.lower() in ("rafidia", "رفيديا"):
                extracted["location"] = "rafidia"

        if "medications" in self.entities:
            for key, langs in self.entities["medications"].items():
                for words in langs.values():
                    for word in words:
                        word_norm = normalize_text(word)
                        if word_norm in normalized:
                            if key not in extracted["medications"]:
                                extracted["medications"].append(key)

        for ngram in ngrams:
            canonical = self.synonyms.resolve(ngram)
            med_keys = {"paracetamol", "ibuprofen", "aspirin", "amoxicillin", "omeprazole", "metformin", "insulin"}
            if canonical in med_keys:
                if canonical not in extracted["medications"]:
                    extracted["medications"].append(canonical)

        if "services" in self.entities:
            service_words = self.entities["services"].get("ar", []) + self.entities["services"].get("en", [])
            for word in service_words:
                word_norm = normalize_text(word)
                if word_norm in normalized:
                    if word not in extracted["services"]:
                        extracted["services"].append(word)

        numbers = self.tokenizer.extract_numbers(text)
        if numbers:
            extracted["numbers"] = numbers
            for num in numbers:
                if num["type"] == "ordinal":
                    extracted["ordinal_index"] = num["value"]

        if context:
            context_resolved = self.context_resolver.resolve(text, context)
            
            for key, value in context_resolved.items():
                if key.startswith("_"):
                    continue
                if key == "intent_override":
                    if value:
                        extracted["_intent_override"] = value
                    continue
                if extracted.get(key) is None or (isinstance(extracted.get(key), list) and len(extracted[key]) == 0):
                    extracted[key] = value
                    extracted["_inherited"] = True
                elif isinstance(extracted.get(key), list) and isinstance(value, list):
                    for item in value:
                        if item not in extracted[key]:
                            extracted[key].append(item)
                            extracted["_inherited"] = True

            if context_resolved.get("is_follow_up"):
                extracted["is_follow_up"] = True
                extracted["_inherited"] = True

            if context_resolved.get("intent_override") == "show_route":
                extracted["_intent_override"] = "show_route"

        extracted["_processing_ms"] = round((time.time() - start_time) * 1000, 2)

        return extracted

    def _empty_result(self, text: str) -> Dict:
        """Return empty extraction result with standard shape."""
        return {
            "specialty": None,
            "specialties": [],
            "type": None,
            "types": [],
            "symptoms": [],
            "location": None,
            "medications": [],
            "services": [],
            "language": "arabic",
            "raw": text,
            "is_follow_up": False,
            "was_corrected": False,
            "was_dialect": False,
            "numbers": None,
            "ordinal_index": None,
            "_inherited": False
        }
