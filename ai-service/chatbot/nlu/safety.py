import re
from typing import Dict, List, Optional, Tuple


class MedicalSafetyLayer:
    """
    Deterministic medical safety detection layer.
    Identifies emergency situations that must bypass normal intent routing.
    Always takes priority over other NLU processing.
    """

    # Critical emergency patterns — ALWAYS bypass normal routing
    EMERGENCY_PATTERNS_AR = [
        r"(الم\s+(صدر|قلب|راس\s+شديد))",
        r"(صعوبة\s+(تنفس|في\s+التنفس))",
        r"(ضيق\s+(تنفس|نفس))",
        r"(فقدان\s+(وعي|الوعي))",
        r"(جلطة|نوبة\s+قلبية|سكتة)",
        r"(نزيف\s+شديد|دم\s+كثير)",
        r"(انتحار|قتل\s+نفس|إيذاء\s+نفس)",
        r"(تسمم|سم\s+|جرعة\s+زائدة)",
        r"(حروق\s+شديدة|حرق\s+درجة\s+(ثانية|ثالثة))",
        r"(كسور\s+مفتوحة|عظم\s+بارز)",
        r"(غيبوبة|لا\s+يستجيب|غير\s+مستجيب)",
        r"(طوارئ|حالة\s+طارئة|إسعاف|اسعاف)",
        r"( Cardi|heart\s+attack|stroke|severe\s+bleeding)",
        r"(can('t|not)\s+breathe|difficulty\s+breathe|shortness\s+of\s+breath)",
        r"(unconscious|passed\s+out|fainted|not\s+responding)",
        r"(suicide|kill\s+myself|self.harm|overdose)",
        r"(poisoning|poison|toxic)",
        r"(severe\s+(pain|burn|bleeding|injury))",
        r"(emergency|urgent|immediate\s+help|call\s+ambulance)",
    ]

    # Urgent but not immediately life-threatening
    URGENT_PATTERNS_AR = [
        r"(كسر|خلع|التواء\s+شديد)",
        r"(حرارة\s+مرتفعة|حرارة\s+عالية|حمى\s+شديدة)",
        r"(الم\s+شديد|وجع\s+مستمر|ألم\s+لا\s+يحتمل)",
        r"(تقيؤ\s+دم|دم\s+في\s+البراز|نزيف\s+داخلي)",
        r"(ضغط\s+مرتفع\s+جداً|ارتفاع\s+ضغط\s+خطر)",
        r"(سكر\s+مرتفع|ارتفاع\s+سكر|هبوط\s+سكر)",
        r"(تشنج|نوبة\s+صرع|صرع)",
        r"(حساسية\s+شديدة|صدمة\s+حساسية)",
        r"(high\s+fever|very\s+high\s+temperature)",
        r"(severe\s+(pain|headache|bleeding|cough))",
        r"(blood\s+in\s+(vomit|stool|urine))",
        r"(very\s+high\s+(blood\s+pressure|sugar|BP))",
        r"(seizure|convulsion|fitting)",
        r"(severe\s+allergic\s+reaction|anaphylaxis)",
        r"(broken\s+bone|fracture|dislocation)",
        r"(uncontrollable\s+bleeding)",
    ]

    def __init__(self):
        self._compile_patterns()

    def _compile_patterns(self):
        """Compile regex patterns for performance."""
        self.emergency_re = [re.compile(p, re.IGNORECASE) for p in self.EMERGENCY_PATTERNS_AR]
        self.urgent_re = [re.compile(p, re.IGNORECASE) for p in self.URGENT_PATTERNS_AR]

    def check(self, text: str, entities: Optional[Dict] = None) -> Dict:
        """
        Check if input contains medical emergency or urgent situation.
        Returns safety assessment dict.

        Returns:
            {
                "is_emergency": bool,
                "is_urgent": bool,
                "severity": "emergency" | "urgent" | "normal",
                "matched_patterns": [],
                "response": str (safety instruction),
                "bypass_intent_routing": bool
            }
        """
        if not text:
            return {
                "is_emergency": False,
                "is_urgent": False,
                "severity": "normal",
                "matched_patterns": [],
                "response": None,
                "bypass_intent_routing": False
            }

        matched_patterns = []

        # Check emergency patterns first (highest priority)
        for pattern in self.emergency_re:
            match = pattern.search(text)
            if match:
                matched_patterns.append({
                    "type": "emergency",
                    "matched": match.group(),
                    "pattern": pattern.pattern
                })

        # If emergency detected, return immediately
        if matched_patterns:
            return {
                "is_emergency": True,
                "is_urgent": True,
                "severity": "emergency",
                "matched_patterns": matched_patterns,
                "response": self._get_emergency_response(text),
                "bypass_intent_routing": True
            }

        # Check urgent patterns
        for pattern in self.urgent_re:
            match = pattern.search(text)
            if match:
                matched_patterns.append({
                    "type": "urgent",
                    "matched": match.group(),
                    "pattern": pattern.pattern
                })

        if matched_patterns:
            return {
                "is_emergency": False,
                "is_urgent": True,
                "severity": "urgent",
                "matched_patterns": matched_patterns,
                "response": self._get_urgent_response(text),
                "bypass_intent_routing": False
            }

        # Check entities for emergency signals
        if entities:
            symptoms = entities.get("symptoms", [])
            emergency_symptoms = {"chest_pain", "breathing", "severe_bleeding", "unconscious"}
            if emergency_symptoms.intersection(symptoms):
                return {
                    "is_emergency": True,
                    "is_urgent": True,
                    "severity": "emergency",
                    "matched_patterns": [{"type": "entity_based", "symptoms": list(emergency_symptoms.intersection(symptoms))}],
                    "response": self._get_emergency_response(text),
                    "bypass_intent_routing": True
                }

        # Normal case
        return {
            "is_emergency": False,
            "is_urgent": False,
            "severity": "normal",
            "matched_patterns": [],
            "response": None,
            "bypass_intent_routing": False
        }

    def _get_emergency_response(self, text: str) -> str:
        """Get Arabic emergency response."""
        lang = "ar" if re.search(r'[\u0600-\u06FF]', text) else "en"

        if lang == "ar":
            return ("🚨 **تنبيه طبي عاجل!**\n\n"
                    "قد تكون هذه أعراض حالة طارئة. يرجى التوجه فوراً إلى أقرب طوارئ "
                    "أو الاتصال بالإسعاف على الرقم **101**.\n\n"
                    "⚠️ لا يمكنني تقديم تشخيص عبر المحادثة. هذا تنبيه سلامة تلقائي.")
        else:
            return ("🚨 **Medical Emergency Alert!**\n\n"
                    "You may be experiencing a medical emergency. "
                    "Please go to the nearest emergency room immediately "
                    "or call emergency services **(911)**.\n\n"
                    "⚠️ I cannot provide a diagnosis via chat. This is an automated safety alert.")

    def _get_urgent_response(self, text: str) -> str:
        """Get Arabic urgent care response."""
        lang = "ar" if re.search(r'[\u0600-\u06FF]', text) else "en"

        if lang == "ar":
            return ("⚠️ **بحاجة لرعاية عاجلة**\n\n"
                    "هذه الحالة تحتاج إلى متابعة طبية في أقرب وقت. "
                    "يرجى زيارة أقرب عيادة أو مركز طبي.\n\n"
                    "💡 يمكنني مساعدتك في العثور على أقرب منشأة طبية.")
        else:
            return ("⚠️ **Urgent Medical Attention Recommended**\n\n"
                    "This condition requires prompt medical attention. "
                    "Please visit the nearest clinic or medical center.\n\n"
                    "💡 I can help you find the nearest healthcare facility.")

    def get_emergency_keywords(self) -> List[str]:
        """Get all emergency keywords for quick pre-checking."""
        keywords = [
            # Arabic
            "طوارئ", "اسعاف", "إسعاف", "حالة طارئة", "خطر", "انقاذ",
            "نوبة قلبية", "جلطة", "سكتة", "نزيف", "غيبوبة",
            "صعوبة تنفس", "ضيق تنفس", "فقدان وعي",
            "انتحار", "تسمم", "جرعة زائدة",
            # English
            "emergency", "ambulance", "urgent", "heart attack", "stroke",
            "can't breathe", "unconscious", "bleeding", "suicide",
            "overdose", "poisoning", "severe pain"
        ]
        return keywords