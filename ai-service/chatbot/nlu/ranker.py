import re
from typing import Dict, List, Optional

_WORD_BOUNDARY_CHARS = r"A-Za-z0-9؀-ۿ"


_negation_pattern_cache: Dict[str, "re.Pattern"] = {}


def _contains_word(text: str, word: str) -> bool:
    if not word:
        return False
    pattern = _negation_pattern_cache.get(word)
    if pattern is None:
        pattern = re.compile(
            r"(?<![" + _WORD_BOUNDARY_CHARS + r"])"
            + re.escape(word)
            + r"(?![" + _WORD_BOUNDARY_CHARS + r"])"
        )
        _negation_pattern_cache[word] = pattern
    return pattern.search(text) is not None


class IntentRanker:
    """
    Multi-intent ranking system with confidence calibration.
    Returns ranked list of possible intents with normalized confidence scores.
    """

    MATCH_WEIGHTS = {
        "exact_keyword": 1.0,
        "fuzzy_keyword": 0.7,
        "regex_pattern": 0.8,
        "synonym_resolved": 0.6,
        "context_boost": 0.3,
        "follow_up_boost": 0.25,
        "negation_penalty": -0.5
    }

    INTENT_CATEGORIES = {
        "greeting": ["small_talk", "thanks", "bye"],
        "search": ["find_doctor", "find_nearest", "find_hospital", "find_pharmacy", "find_clinic"],
        "medical": ["symptom_analysis", "medication_info", "drug_interaction", "side_effects"],
        "appointment": ["book_appointment", "cancel_appointment", "reschedule_appointment", "appointment_status"],
        "navigation": ["show_route", "travel_time", "distance"],
        "information": ["clinic_info", "hospital_info", "doctor_profile", "working_hours", "insurance_query"],
        "records": ["medical_history", "lab_result_query", "medical_report"],
        "platform": ["platform_support", "settings", "feedback", "complaint"],
        "emergency": ["emergency"]
    }

    INTENT_TO_CATEGORY = {}
    for category, intents in INTENT_CATEGORIES.items():
        for intent in intents:
            INTENT_TO_CATEGORY[intent] = category

    NEGATION_WORDS_AR = ["لا", "ليس", "لست", "مش", "غير", "بدون", "بلا", "ما", "لم"]
    NEGATION_WORDS_EN = ["not", "no", "don't", "dont", "doesn't", "isn't", "aren't", "without", "never"]

    def __init__(self):
        self.confidence_threshold = 0.15

    def rank(
        self,
        scores: Dict[str, float],
        matched_keywords: Dict[str, List],
        text: str,
        context: Optional[Dict] = None
    ) -> List[Dict]:
        """
        Rank intents by confidence with calibration.
        Returns sorted list of intent results.
        """
        if not scores:
            return [{
                "intent": "unknown",
                "confidence": 0.0,
                "matched_terms": [],
                "is_fallback": True
            }]

        text_lower = text.lower()
        calibrated_scores = {}

        for intent, raw_score in scores.items():
            calibrated = raw_score

            has_negation = any(
                _contains_word(text_lower, n) for n in self.NEGATION_WORDS_AR + self.NEGATION_WORDS_EN
            )
            if has_negation:
                calibrated *= 0.5

            intent_category = self.INTENT_TO_CATEGORY.get(intent)
            if intent_category:
                same_category_count = sum(
                    1 for i in scores if self.INTENT_TO_CATEGORY.get(i) == intent_category
                )
                if same_category_count > 1:
                    calibrated *= (1.0 / same_category_count)

            keywords = matched_keywords.get(intent, [])
            if len(keywords) >= 2:
                calibrated *= 1.2
            if len(keywords) >= 4:
                calibrated *= 1.3

            calibrated_scores[intent] = calibrated

        total = sum(calibrated_scores.values())
        if total > 0:
            for intent in calibrated_scores:
                calibrated_scores[intent] = calibrated_scores[intent] / total

        ranked = []
        for intent, confidence in sorted(calibrated_scores.items(), key=lambda x: x[1], reverse=True):
            if confidence >= self.confidence_threshold:
                ranked.append({
                    "intent": intent,
                    "confidence": round(confidence, 4),
                    "matched_terms": matched_keywords.get(intent, []),
                    "is_fallback": False
                })

        if not ranked:
            ranked.append({
                "intent": "unknown",
                "confidence": 0.0,
                "matched_terms": [],
                "is_fallback": True
            })

        return ranked

    def get_best_intent(self, ranked: List[Dict]) -> Dict:
        """Get the highest-ranked intent."""
        return ranked[0] if ranked else {
            "intent": "unknown",
            "confidence": 0.0,
            "matched_terms": [],
            "is_fallback": True
        }

    def get_alternatives(self, ranked: List[Dict], top_n: int = 3) -> List[Dict]:
        """Get top N alternative intents (excludes best)."""
        return ranked[1:top_n + 1] if len(ranked) > 1 else []

    def is_confident(self, ranked: List[Dict], threshold: float = 0.5) -> bool:
        """Check if the top intent is confidently identified."""
        if not ranked:
            return False
        return ranked[0]["confidence"] >= threshold and not ranked[0].get("is_fallback", False)
