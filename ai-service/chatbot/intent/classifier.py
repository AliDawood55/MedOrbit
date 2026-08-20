import json
import os
import re
import time
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

from chatbot.utils.text_normalizer import normalize_text, detect_language
from chatbot.nlu.pipeline import NLUPipeline
from chatbot.nlu.normalizer import TextNormalizer
from chatbot.nlu.synonyms import SynonymEngine
from chatbot.nlu.tokens import Tokenizer
from chatbot.nlu.ranker import IntentRanker
from chatbot.nlu.safety import MedicalSafetyLayer


class IntentClassifier:
    """
    Intent classifier using the hybrid NLU pipeline.
    
    Preserves the existing public interface:
        classify(text, context) -> Dict
    
    Internally uses the full NLU pipeline:
        normalization → spelling → dialect → tokens → synonyms → 
        regex + fuzzy → ranking → safety check
    """

    def __init__(self):
        self.intents = self._load_intents()
        self.confidence_threshold = 0.3
        self.pattern_boost = 0.2
        
        # NLU modules
        self.nlu = NLUPipeline()
        self.normalizer = TextNormalizer()
        self.synonyms = SynonymEngine()
        self.tokenizer = Tokenizer()
        self.ranker = IntentRanker()
        self.safety = MedicalSafetyLayer()

    def _load_intents(self):
        base_path = os.path.dirname(__file__)
        file_path = os.path.join(base_path, "intents.json")
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)

    # Characters that count as "inside a word" for boundary purposes: Latin
    # letters, digits, and Arabic letters. A keyword must not be preceded or
    # followed by one of these to count as a standalone-word/phrase match —
    # otherwise a short keyword like "er" fires inside "there", or an Arabic
    # keyword fires inside an unrelated longer word via an attached prefix
    # (ال) or suffix.
    _WORD_BOUNDARY_CHARS = r"A-Za-z0-9؀-ۿ"

    # intents.json stores Arabic keywords in their bare form ("دكتور",
    # "عيادة", "تأمين"), but Arabic almost always attaches a proclitic
    # directly onto the noun with no space: the definite article "ال"
    # ("الدكتور", "العيادة", "التأمين" — "the doctor/clinic/insurance"), or
    # the preposition "ل" ("for/to") contracted with that same article into
    # "لل" ("للحامل" — "for the pregnant [woman]"). Without allowing these,
    # the strict boundary rule above would block those extremely common
    # real-world forms, which is not the intended effect of closing the
    # embedded-substring bug — these are grammatical particles, not a
    # different, unrelated word the way "أ" is in "أطباء". So a keyword also
    # counts as matched when immediately preceded by one of these.
    _ARABIC_PROCLITICS = ("ال", "لل")

    # Compiled boundary-safe patterns, keyed by keyword_norm. classify() runs
    # this check for every keyword of every intent on every call, so
    # rebuilding and recompiling the pattern string from scratch each time
    # was measurably slower than the plain substring check it replaced.
    # Shared at the class level (the keyword set is fixed, defined by
    # intents.json) so the cache is warm after the first classify() call
    # across every IntentClassifier instance.
    _keyword_pattern_cache: Dict[str, Tuple["re.Pattern", ...]] = {}

    @classmethod
    def _keyword_in_text(cls, keyword_norm: str, text: str) -> bool:
        """Boundary-safe containment check: True if `keyword_norm` appears in
        `text` as a standalone word or standalone multi-word phrase (or that
        same word with a recognized Arabic proclitic directly attached), not
        merely as a substring embedded inside a longer, unrelated token."""
        if not keyword_norm:
            return False
        patterns = cls._keyword_pattern_cache.get(keyword_norm)
        if patterns is None:
            escaped = re.escape(keyword_norm)
            prefixes = ("",) + cls._ARABIC_PROCLITICS
            patterns = tuple(
                re.compile(
                    r"(?<![" + cls._WORD_BOUNDARY_CHARS + r"])"
                    + prefix + escaped
                    + r"(?![" + cls._WORD_BOUNDARY_CHARS + r"])"
                )
                for prefix in prefixes
            )
            cls._keyword_pattern_cache[keyword_norm] = patterns
        return any(p.search(text) is not None for p in patterns)

    # Mirrors chatbot/nlu/safety.py's own informational-ER-place exemption
    # (same policy, same narrow phrasing) — distinguishes "the emergency
    # department" as a place/service from a personal emergency being
    # reported. Matches ONLY the department-as-place phrasing "قسم
    # الطوارئ"/"غرفة الطوارئ" — never bare "طوارئ" alone, which must
    # always still win Step 9 on its own.
    _ER_PLACE_PATTERN = re.compile(r"قسم\s+الطوارئ|غرفة\s+الطوارئ", re.IGNORECASE)

    def _is_informational_er_place_query(
        self, text: str, matched_kw: List[str], matched_pat: List[str]
    ) -> bool:
        """True only when the sole reason the "emergency" intent scored is
        the bare "طوارئ" keyword AND the text specifically names the
        emergency department as a place, rather than reporting a personal
        emergency. Any other matched emergency keyword or regex pattern
        (a real symptom, a self-report, "اسعاف", "حالة طارئة", etc.) means
        this returns False and Step 9 still forces "emergency" outright.
        """
        if matched_pat:
            return False
        if matched_kw != ["طوارئ"]:
            return False
        return bool(self._ER_PLACE_PATTERN.search(text))

    def classify(self, text: str, context: Optional[Dict] = None) -> Dict:
        """
        Full hybrid NLU classification.
        
        Pipeline:
        1. Language detection
        2. Normalization (spell correction, dialect, Arabic)
        3. Tokenization + stemming
        4. Synonym expansion
        5. Keyword matching (weighted by language)
        6. Regex pattern matching
        7. Context-aware boosting
        8. Multi-intent ranking with calibration
        9. Medical safety check (highest priority)
        10. Emergency override
        11. Fallback with context reuse
        """
        start_time = time.time()
        pipeline_log = []

        if not text:
            return self._fallback_response(text)

        # Step 1: Language detection
        lang = detect_language(text)
        pipeline_log.append({"step": "language_detection", "language": lang})

        # Step 2: Full normalization
        normalized_info = self.normalizer.normalize_with_metadata(text)
        normalized_text = normalized_info["normalized"]
        pipeline_log.append({
            "step": "normalization",
            "was_corrected": normalized_info["was_corrected"],
            "was_dialect": normalized_info["was_dialect"],
            "language": normalized_info["language"]
        })

        # Step 3: Medical safety check — always runs first
        safety_result = self.safety.check(text)
        pipeline_log.append({"step": "safety_check", "severity": safety_result["severity"]})
        
        if safety_result["bypass_intent_routing"]:
            return {
                "intent": "emergency",
                "confidence": 1.0,
                "matched_keywords": safety_result["matched_patterns"],
                "matched_patterns": [],
                "is_emergency": True,
                "_pipeline": pipeline_log,
                "_processing_ms": round((time.time() - start_time) * 1000, 2)
            }

        # Step 4: Tokenization + stemming
        tokens = self.tokenizer.tokenize(normalized_text)
        ngrams = self.tokenizer.extract_ngrams(tokens, min_n=1, max_n=3)
        pipeline_log.append({"step": "tokenization", "token_count": len(tokens), "ngram_count": len(ngrams)})

        # Step 5: Synonym resolution
        resolved_text = self.synonyms.resolve_text(normalized_text)
        resolved_tokens = self.synonyms.resolve_tokens(tokens)
        pipeline_log.append({"step": "synonym_resolution", "changed": resolved_text != normalized_text})

        # Step 6: Keyword matching (weighted by language)
        scores = defaultdict(float)
        matched_keywords = defaultdict(list)
        matched_patterns = defaultdict(list)

        # Use resolved text for matching (handles synonyms)
        match_text = resolved_text if resolved_text != normalized_text else normalized_text
        
        for intent, intent_data in self.intents.items():
            if intent == "metadata":
                continue
            
            # Get keywords
            keywords_ar = intent_data.get("keywords_ar", [])
            keywords_en = intent_data.get("keywords_en", [])
            
            # Primary language keywords
            primary_keywords = keywords_ar if lang == "ar" else keywords_en
            secondary_keywords = keywords_en if lang == "ar" else keywords_ar
            all_keywords = primary_keywords + secondary_keywords

            ngram_text = ' '.join(ngrams)
            for keyword in all_keywords:
                keyword_norm = normalize_text(keyword)
                if self._keyword_in_text(keyword_norm, match_text) or self._keyword_in_text(keyword_norm, ngram_text):
                    weight = 1.0 if keyword in primary_keywords else 0.6
                    scores[intent] += weight
                    matched_keywords[intent].append(keyword)

            # Also check original normalized for dialect-expanded terms
            for keyword in all_keywords:
                keyword_norm = normalize_text(keyword)
                if keyword_norm != keyword and self._keyword_in_text(keyword_norm, normalized_text):
                    if keyword_norm not in [normalize_text(k) for k in matched_keywords[intent]]:
                        weight = 0.8 if keyword in primary_keywords else 0.5
                        scores[intent] += weight
                        matched_keywords[intent].append(keyword + "(expanded)")

        # Step 7: Regex pattern matching
        for intent, intent_data in self.intents.items():
            if intent == "metadata":
                continue
            patterns = intent_data.get("patterns", [])
            for pattern in patterns:
                try:
                    if re.search(pattern, text, re.IGNORECASE):
                        scores[intent] += self.pattern_boost
                        matched_patterns[intent].append(pattern)
                except re.error:
                    continue

        pipeline_log.append({
            "step": "keyword_matching",
            "matched_intents": list(scores.keys()),
            "total_keywords_matched": sum(len(v) for v in matched_keywords.values())
        })

        # Step 8: Context-aware boosting
        if context:
            last_intent = context.get("lastIntent")
            current_topic = context.get("currentTopic")

            if last_intent and last_intent in scores:
                scores[last_intent] *= 1.2
                pipeline_log.append({"step": "context_boost", "boosted_intent": last_intent, "factor": 1.2})

            if current_topic and current_topic in scores:
                scores[current_topic] *= 1.15
                pipeline_log.append({"step": "context_boost", "boosted_topic": current_topic, "factor": 1.15})

            if len(text.split()) <= 5 and last_intent:
                scores[last_intent] *= 1.3
                pipeline_log.append({"step": "follow_up_boost", "boosted_intent": last_intent, "factor": 1.3})

        # Step 9: Emergency override (double-check through entity detection)
        if "emergency" in scores and scores["emergency"] >= 1.0:
            if self._is_informational_er_place_query(
                text, matched_keywords.get("emergency", []), matched_patterns.get("emergency", [])
            ):
                # Informational/place query naming the ER (see
                # _is_informational_er_place_query) — let it continue to
                # normal ranking instead of forcing "emergency". The
                # emergency intent is removed from contention entirely so
                # it can't also win Step 10 purely on this same,
                # now-exempted "طوارئ" match.
                del scores["emergency"]
                matched_keywords.pop("emergency", None)
                matched_patterns.pop("emergency", None)
                pipeline_log.append({
                    "step": "emergency_override_exempted",
                    "reason": "informational_er_place_query"
                })
            else:
                return {
                    "intent": "emergency",
                    "confidence": 1.0,
                    "matched_keywords": matched_keywords.get("emergency", []),
                    "matched_patterns": matched_patterns.get("emergency", []),
                    "is_emergency": True,
                    "_pipeline": pipeline_log,
                    "_processing_ms": round((time.time() - start_time) * 1000, 2)
                }

        # Step 10: Multi-intent ranking with calibration
        if not scores:
            result = self._fallback_response(text, context)
            result["_pipeline"] = pipeline_log
            result["_processing_ms"] = round((time.time() - start_time) * 1000, 2)
            return result

        ranked = self.ranker.rank(scores, matched_keywords, text, context)
        best = self.ranker.get_best_intent(ranked)
        alternatives = self.ranker.get_alternatives(ranked)

        pipeline_log.append({
            "step": "ranking",
            "best_intent": best["intent"],
            "confidence": best["confidence"],
            "alternatives": [a["intent"] for a in alternatives]
        })

        result = {
            "intent": best["intent"],
            "confidence": best["confidence"],
            "matched_keywords": best.get("matched_terms", []),
            "matched_patterns": matched_patterns.get(best["intent"], []),
            "is_fallback": best.get("is_fallback", False),
            "alternative_intents": alternatives,
            "is_emergency": False,
            "_pipeline": pipeline_log,
            "_processing_ms": round((time.time() - start_time) * 1000, 2)
        }

        # Apply intent-specific confidence threshold
        intent_meta = self.intents.get(best["intent"], {})
        threshold = intent_meta.get("confidence_threshold", self.confidence_threshold)
        if best["confidence"] < threshold:
            result = self._fallback_response(text, context)
            result["_pipeline"] = pipeline_log
            result["_processing_ms"] = round((time.time() - start_time) * 1000, 2)

        return result

    def _fallback_response(self, text: str, context: Optional[Dict] = None) -> Dict:
        """Intelligent fallback with context reuse."""
        if context:
            last_intent = context.get("lastIntent")
            if last_intent and last_intent != "unknown":
                return {
                    "intent": last_intent,
                    "confidence": 0.25,
                    "matched_keywords": [],
                    "matched_patterns": [],
                    "is_fallback": True,
                    "alternative_intents": [],
                    "is_emergency": False
                }

        return {
            "intent": "unknown",
            "confidence": 0.0,
            "matched_keywords": [],
            "matched_patterns": [],
            "is_fallback": True,
            "alternative_intents": [],
            "is_emergency": False
        }