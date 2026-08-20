import time
from collections import OrderedDict
from typing import Dict, List, Optional, Any


class SlotFiller:
    """
    Slot Filling System for collecting missing information.
    
    Tracks required and optional slots across multiple messages.
    Generates follow-up questions for missing slots.
    Supports conversation state management.
    """

    # Required slots for each intent type
    INTENT_SLOTS = {
        "find_doctor": {
            "required": ["specialty"],
            "optional": ["location", "region", "language", "gender", "insurance", "max_fee", "min_rating"],
            "follow_up_order": ["specialty", "location", "region", "gender", "insurance"]
        },
        "find_nearest": {
            "required": ["type", "location"],
            "optional": ["radius", "insurance", "open_now", "rating"],
            "follow_up_order": ["type", "location", "radius"]
        },
        "book_appointment": {
            "required": ["doctor", "date", "time"],
            "optional": ["clinic", "patient_name", "reason", "insurance"],
            "follow_up_order": ["doctor", "date", "time", "clinic", "reason"]
        },
        "medication_info": {
            "required": ["medication"],
            "optional": ["dosage", "frequency", "duration"],
            "follow_up_order": ["medication", "dosage"]
        },
        "symptom_analysis": {
            "required": ["symptoms"],
            "optional": ["duration", "severity", "age", "gender", "chronic_conditions", "medications"],
            "follow_up_order": ["duration", "severity", "age", "gender"]
        },
        "clinic_info": {
            "required": ["clinic"],
            "optional": ["location", "service", "doctor"],
            "follow_up_order": ["clinic", "location"]
        },
        "hospital_info": {
            "required": ["hospital"],
            "optional": ["department", "location"],
            "follow_up_order": ["hospital", "department"]
        },
        "show_route": {
            "required": ["destination"],
            "optional": ["origin", "mode", "departure_time"],
            "follow_up_order": ["destination", "origin", "mode"]
        },
        "lab_result_query": {
            "required": ["test_type"],
            "optional": ["date", "patient_name"],
            "follow_up_order": ["test_type", "date"]
        }
    }

    # Slot descriptions for generating follow-up questions
    SLOT_DESCRIPTIONS = {
        "specialty": {
            "ar": "ما هو التخصص الطبي الذي تبحث عنه؟",
            "en": "What medical specialty are you looking for?"
        },
        "location": {
            "ar": "في أي منطقة أو مدينة؟",
            "en": "In which area or city?"
        },
        "region": {
            "ar": "أي منطقة بالضبط؟",
            "en": "Which specific area?"
        },
        "type": {
            "ar": "هل تبحث عن عيادة، مستشفى، أم صيدلية؟",
            "en": "Are you looking for a clinic, hospital, or pharmacy?"
        },
        "doctor": {
            "ar": "من هو الطبيب الذي تريد؟",
            "en": "Which doctor are you looking for?"
        },
        "date": {
            "ar": "في أي تاريخ تريد الموعد؟",
            "en": "What date would you like the appointment?"
        },
        "time": {
            "ar": "في أي وقت تفضل الموعد؟",
            "en": "What time would you prefer?"
        },
        "clinic": {
            "ar": "ما اسم العيادة؟",
            "en": "What is the clinic name?"
        },
        "hospital": {
            "ar": "ما اسم المستشفى؟",
            "en": "What is the hospital name?"
        },
        "medication": {
            "ar": "ما اسم الدواء؟",
            "en": "What is the medication name?"
        },
        "dosage": {
            "ar": "ما هي الجرعة التي تريد معرفتها؟",
            "en": "What dosage information do you need?"
        },
        "symptoms": {
            "ar": "ما هي الأعراض التي تشعر بها؟",
            "en": "What symptoms are you experiencing?"
        },
        "duration": {
            "ar": "منذ متى وأنت تشعر بهذه الأعراض؟",
            "en": "How long have you had these symptoms?"
        },
        "severity": {
            "ar": "ما شدة الأعراض: خفيفة، متوسطة، أم شديدة؟",
            "en": "How severe are the symptoms: mild, moderate, or severe?"
        },
        "age": {
            "ar": "كم عمرك؟",
            "en": "How old are you?"
        },
        "gender": {
            "ar": "الجنس: ذكر أم أنثى؟",
            "en": "Gender: male or female?"
        },
        "insurance": {
            "ar": "ما هي شركة التأمين الصحي لديك؟",
            "en": "What is your health insurance provider?"
        },
        "radius": {
            "ar": "ما المسافة القصوى التي تناسبك؟",
            "en": "What is the maximum distance you prefer?"
        },
        "destination": {
            "ar": "أين تريد الذهاب؟",
            "en": "Where do you want to go?"
        },
        "origin": {
            "ar": "من أين ستبدأ؟",
            "en": "Where will you start from?"
        },
        "mode": {
            "ar": "هل تفضل المشي أم السيارة؟",
            "en": "Do you prefer walking or driving?"
        },
        "test_type": {
            "ar": "ما نوع التحليل أو الفحص الذي تسأل عنه؟",
            "en": "What type of test or analysis are you asking about?"
        },
        "reason": {
            "ar": "ما سبب الزيارة؟",
            "en": "What is the reason for the visit?"
        },
        "language": {
            "ar": "هل تريد طبيب يتحدث لغة معينة؟",
            "en": "Do you need a doctor who speaks a specific language?"
        },
        "min_rating": {
            "ar": "ما هو أقل تقييم مقبول للطبيب؟",
            "en": "What is the minimum rating you'd accept?"
        },
        "max_fee": {
            "ar": "ما هو أقصى سعر كشف تقبله؟",
            "en": "What is the maximum consultation fee you'd accept?"
        },
        "open_now": {
            "ar": "هل تريد مكاناً مفتوحاً الآن؟",
            "en": "Do you need a place that is open now?"
        }
    }

    # Bounded-storage settings for conversation_states (prevents unbounded
    # process-lifetime memory growth). See ai-service audit, Phase 0.
    MAX_CONVERSATION_STATES = 1000
    CONVERSATION_STATE_TTL_SECONDS = 3600

    def __init__(self):
        self.conversation_states = OrderedDict()  # conversation_id -> state dict, LRU-ordered
        self._state_last_access: Dict[str, float] = {}  # conversation_id -> last access timestamp

    def _touch(self, conversation_id: str) -> None:
        """Record recent access and refresh LRU position for a conversation_id."""
        self._state_last_access[conversation_id] = time.time()
        if conversation_id in self.conversation_states:
            self.conversation_states.move_to_end(conversation_id)

    def _evict_expired(self) -> None:
        """Remove conversation states that haven't been touched within the TTL."""
        now = time.time()
        expired_ids = [
            cid for cid, last_access in self._state_last_access.items()
            if now - last_access > self.CONVERSATION_STATE_TTL_SECONDS
        ]
        for cid in expired_ids:
            self.conversation_states.pop(cid, None)
            self._state_last_access.pop(cid, None)

    def _evict_lru_if_needed(self) -> None:
        """Evict least-recently-used conversation states beyond MAX_CONVERSATION_STATES."""
        while len(self.conversation_states) > self.MAX_CONVERSATION_STATES:
            oldest_id, _ = self.conversation_states.popitem(last=False)
            self._state_last_access.pop(oldest_id, None)

    def initialize_state(self, conversation_id: str, intent: str, entities: Dict) -> Dict:
        """Initialize or reset slot filling state for a conversation."""
        self._evict_expired()

        state = {
            "intent": intent,
            "filled_slots": dict(entities),
            "missing_slots": [],
            "asked_slots": set(),
            "completed": False
        }

        slot_def = self.INTENT_SLOTS.get(intent)
        if slot_def:
            # Check which required slots are missing
            for slot in slot_def["required"]:
                if slot not in entities or not entities.get(slot):
                    state["missing_slots"].append(slot)

        self.conversation_states[conversation_id] = state
        self._touch(conversation_id)
        self._evict_lru_if_needed()
        return state

    def update_state(self, conversation_id: str, intent: str, entities: Dict) -> Dict:
        """
        Update slot filling state with new entities from a follow-up message.
        Returns updated state with any remaining missing slots.
        """
        self._evict_expired()

        # Get or create state
        if conversation_id not in self.conversation_states:
            return self.initialize_state(conversation_id, intent, entities)

        state = self.conversation_states[conversation_id]

        # Update intent if changed
        if intent != "unknown" and intent != state.get("intent"):
            state["intent"] = intent

        # Merge new entities into filled slots
        for key, value in entities.items():
            if value and key not in state["filled_slots"]:
                state["filled_slots"][key] = value
            elif value and isinstance(value, list):
                existing = state["filled_slots"].get(key, [])
                if isinstance(existing, list):
                    state["filled_slots"][key] = list(set(existing + value))

        # Recalculate missing slots
        state["missing_slots"] = []
        slot_def = self.INTENT_SLOTS.get(state["intent"])
        if slot_def:
            for slot in slot_def["required"]:
                slot_value = state["filled_slots"].get(slot)
                if not slot_value or (isinstance(slot_value, list) and len(slot_value) == 0):
                    state["missing_slots"].append(slot)

        state["completed"] = len(state["missing_slots"]) == 0
        self.conversation_states[conversation_id] = state
        self._touch(conversation_id)
        self._evict_lru_if_needed()
        return state

    def get_next_question(self, conversation_id: str, language: str = "ar") -> Optional[Dict]:
        """
        Get the next follow-up question for missing slots.
        Returns None if all required slots are filled.
        """
        self._evict_expired()

        state = self.conversation_states.get(conversation_id)
        if not state or state["completed"]:
            return None

        slot_def = self.INTENT_SLOTS.get(state["intent"])
        if not slot_def:
            return None

        # Find the first unfilled slot following the preferred order
        for slot in slot_def.get("follow_up_order", slot_def["required"]):
            if slot in state["missing_slots"] and slot not in state["asked_slots"]:
                # Mark as asked
                state["asked_slots"].add(slot)
                self.conversation_states[conversation_id] = state
                self._touch(conversation_id)

                # Get question text
                descriptions = self.SLOT_DESCRIPTIONS.get(slot, {})
                question = descriptions.get("ar") if language == "ar" else descriptions.get("en")

                if question:
                    return {
                        "slot": slot,
                        "question": question,
                        "language": language,
                        "required": slot in slot_def["required"]
                    }

        return None

    def get_state_summary(self, conversation_id: str) -> Dict:
        """Get a summary of the current slot filling state."""
        self._evict_expired()

        state = self.conversation_states.get(conversation_id)
        if not state:
            return {
                "active": False,
                "intent": None,
                "filled_slots": {},
                "missing_slots": [],
                "completed": False
            }

        self._touch(conversation_id)

        return {
            "active": True,
            "intent": state["intent"],
            "filled_slots": state["filled_slots"],
            "missing_slots": state["missing_slots"],
            "completed": state["completed"],
            "asked_slots": list(state["asked_slots"])
        }

    def clear_state(self, conversation_id: str):
        """Clear slot filling state for a conversation."""
        if conversation_id in self.conversation_states:
            del self.conversation_states[conversation_id]
        self._state_last_access.pop(conversation_id, None)

    def extract_slot_values(self, text: str, language: str = "ar") -> Dict:
        """
        Extract potential slot values from user text.
        This is a lightweight extraction used during slot filling.
        """
        extracted = {}

        # Extract numbers (age, fee, distance)
        import re
        numbers = re.findall(r'\d+', text)
        if numbers:
            extracted["numbers"] = [int(n) for n in numbers]

        # Extract common patterns
        if language == "ar":
            # Age patterns
            age_match = re.search(r'(\d+)\s*(سنة|سنه|عام)', text)
            if age_match:
                extracted["age"] = int(age_match.group(1))

            # Time patterns
            time_match = re.search(r'(\d+):(\d+)', text)
            if time_match:
                extracted["time"] = f"{time_match.group(1)}:{time_match.group(2)}"

            # Duration patterns
            duration_units = {
                "يوم": "days", "ايام": "days", "أيام": "days",
                "شهر": "months", "اشهر": "months", "أشهر": "months",
                "سنة": "years", "سنوات": "years",
                "ساعة": "hours", "ساعات": "hours"
            }
            for unit_word, unit in duration_units.items():
                dur_match = re.search(r'(\d+)\s*' + unit_word, text)
                if dur_match:
                    extracted["duration"] = {
                        "value": int(dur_match.group(1)),
                        "unit": unit
                    }
                    break
        else:
            # English age
            age_match = re.search(r'(\d+)\s*(years?|yrs?)', text)
            if age_match:
                extracted["age"] = int(age_match.group(1))

            # Duration
            dur_match = re.search(r'(\d+)\s*(day|days|week|weeks|month|months|year|years)', text)
            if dur_match:
                val = int(dur_match.group(1))
                unit = dur_match.group(2)
                extracted["duration"] = {"value": val, "unit": unit}

            # Money
            fee_match = re.search(r'(\d+)\s*(shekel|nis|₪|usd|\$)', text)
            if fee_match:
                extracted["max_fee"] = int(fee_match.group(1))

        return extracted