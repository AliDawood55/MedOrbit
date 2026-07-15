from typing import Dict, List, Optional, Any


class ContextResolver:
    """
    Resolves follow-up references across conversation turns.
    
    Handles:
    - Pronoun resolution ("there", "that doctor", "his clinic")
    - Ordinal references ("the second one", "the first")
    - Entity inheritance from previous messages
    - Location memory across turns
    """

    def __init__(self):
        self._reference_keywords_ar = {
            "هو": "masculine",
            "هي": "feminine",
            "هم": "plural",
            "هذا": "near_masculine",
            "هذه": "near_feminine",
            "ذلك": "far_masculine",
            "تلك": "far_feminine",
            "هنالك": "there",
            "هناك": "there",
            "هون": "here",
            "هونيك": "there",
            "نفس": "same",
            "نفسه": "same_masculine",
            "نفسها": "same_feminine",
            "السابق": "previous",
            "اللي": "which",
            "اللي قبل": "previous_one",
            "المذكور": "mentioned",
        }

        self._reference_keywords_en = {
            "it": "neutral",
            "this": "near",
            "that": "far",
            "these": "near_plural",
            "those": "far_plural",
            "there": "there",
            "here": "here",
            "same": "same",
            "previous": "previous",
            "above": "above",
            "mentioned": "mentioned",
            "such": "such",
        }

        # Ordinal mapping
        self._ordinal_map = {
            "first": 0, "1st": 0, "الأول": 0, "اول": 0, "أول": 0,
            "second": 1, "2nd": 1, "الثاني": 1, "ثاني": 1,
            "third": 2, "3rd": 2, "الثالث": 2, "ثالث": 2,
            "fourth": 3, "4th": 3, "الرابع": 3, "رابع": 3,
            "fifth": 4, "5th": 4, "الخامس": 4, "خامس": 4,
        }

    def resolve(self, text: str, conversation_context: Optional[Dict] = None) -> Dict:
        """
        Resolve contextual references in user text.
        Returns resolved entities that should be merged with current extraction.
        """
        resolved = {}

        if not conversation_context:
            return resolved

        text_lower = text.lower()

        # Step 1: Check if this is a follow-up (short message without new topics)
        previous_entities = conversation_context.get("entities", {})
        previous_intent = conversation_context.get("lastIntent")
        previous_places = conversation_context.get("places", [])

        is_follow_up = self._detect_follow_up(text_lower, previous_intent)

        if is_follow_up:
            resolved["is_follow_up"] = True

            # Step 2: Resolve ordinal references ("the second one")
            ordinal = self._resolve_ordinal(text_lower)
            if ordinal is not None:
                resolved["ordinal_index"] = ordinal
                # If previous results exist, resolve to specific item
                if previous_places and ordinal < len(previous_places):
                    resolved["selected_place"] = previous_places[ordinal]
                    resolved["selected_place_index"] = ordinal

            # Step 3: Inherit previous entities
            for key in ["specialty", "type", "location", "medication"]:
                if previous_entities.get(key) and key not in resolved:
                    resolved[key] = previous_entities[key]
                    resolved[f"_{key}_inherited"] = True

            # Step 4: Inherit previous symptoms
            previous_symptoms = previous_entities.get("symptoms", [])
            if previous_symptoms:
                resolved["symptoms"] = previous_symptoms
                resolved["_symptoms_inherited"] = True

            # Step 5: Check for navigation/direction references
            if self._is_navigation_request(text_lower):
                resolved["intent_override"] = "show_route"
                resolved["_navigation"] = True

        return resolved

    def _detect_follow_up(self, text: str, previous_intent: Optional[str]) -> bool:
        """Detect if current message is a follow-up to previous conversation."""
        # Short messages are likely follow-ups
        word_count = len(text.split())
        if word_count <= 3 and previous_intent:
            return True

        # Reference keywords indicate follow-up
        for keyword in list(self._reference_keywords_ar.keys()) + list(self._reference_keywords_en.keys()):
            if keyword in text:
                return True

        # Ordinal references
        for ord_word in self._ordinal_map:
            if ord_word in text:
                return True

        return False

    def _resolve_ordinal(self, text: str) -> Optional[int]:
        """Resolve ordinal reference to an index."""
        for word, index in self._ordinal_map.items():
            if word in text:
                return index
        return None

    def _is_navigation_request(self, text: str) -> bool:
        """Check if text is a navigation/direction request."""
        nav_keywords = [
            "route", "navigation", "directions", "take me", "lead me",
            "how to get", "take there", "bring me", "go there",
            "اوصلني", "خذني", "دلني", "ارني الطريق", "المسار",
            "كيف اوصل", "كيف أصل", "اتجاه", "دليل", "وصلني"
        ]
        return any(k in text for k in nav_keywords)

    def merge_with_extraction(
        self,
        extracted: Dict,
        resolved: Dict,
        conversation_context: Optional[Dict] = None
    ) -> Dict:
        """
        Merge resolved context into entity extraction results.
        Preserves newly extracted entities over inherited ones.
        """
        merged = dict(extracted)

        # Mark as follow-up if detected
        if resolved.get("is_follow_up"):
            merged["is_follow_up"] = True

        # Merge inherited entities (don't override newly extracted)
        for key, value in resolved.items():
            if key.startswith("_"):
                continue  # Skip internal keys
            if key == "intent_override":
                continue  # Handled separately
            if key not in merged or merged[key] is None:
                merged[key] = value
            elif isinstance(merged[key], list) and isinstance(value, list):
                # Merge lists
                for item in value:
                    if item not in merged[key]:
                        merged[key].append(item)

        # Handle navigation override
        if resolved.get("intent_override") == "show_route":
            merged["_intent_override"] = "show_route"

        return merged

    def get_selection_reference(self, text: str) -> Optional[Dict]:
        """
        Extract a selection reference like "the second doctor" or "اختر الثالث".
        Returns dict with index and type if found.
        """
        text_lower = text.lower()

        ordinal = self._resolve_ordinal(text_lower)
        if ordinal is None:
            return None

        # Determine what is being selected
        entity_type = None
        type_keywords = {
            "doctor": ["doctor", "طبيب", "دكتور"],
            "clinic": ["clinic", "عيادة"],
            "hospital": ["hospital", "مستشفى"],
            "pharmacy": ["pharmacy", "صيدلية"],
            "place": ["place", "location", "مكان", "موقع"],
            "specialist": ["specialist", "اخصائي", "استشاري"],
        }

        for etype, keywords in type_keywords.items():
            if any(k in text_lower for k in keywords):
                entity_type = etype
                break

        return {
            "index": ordinal,
            "entity_type": entity_type,
            "original_text": text
        }

    def update_context(
        self,
        conversation_id: str,
        current_context: Dict,
        intent: str,
        entities: Dict,
        places: List
    ) -> Dict:
        """
        Update the conversation context with new information for future resolution.
        """
        updated = dict(current_context) if current_context else {}

        updated["lastIntent"] = intent
        updated["entities"] = entities
        if places:
            updated["places"] = places[:10]  # Keep last 10 places

        return updated