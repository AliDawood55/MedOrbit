from typing import Dict, List, Optional, Any

from chatbot.nlu.normalizer import TextNormalizer
from chatbot.nlu.synonyms import SynonymEngine
from chatbot.nlu.tokens import Tokenizer
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.nlu.slots import SlotFiller
from chatbot.nlu.ranker import IntentRanker
from chatbot.nlu.context_resolver import ContextResolver
from chatbot.nlu.entity_linker import EntityLinker
from chatbot.nlu.provider_resolver import ProviderResolver


class NLUPipeline:
    """
    Main NLU Pipeline Orchestrator.
    
    Full pipeline:
    1. Language Detection
    2. Arabic Normalization + Spell Correction
    3. Palestinian Dialect Normalization
    4. Tokenization + Stemming
    5. Synonym Expansion
    6. Regex + Keyword Matching
    7. Fuzzy Matching
    8. Entity Extraction
    9. Intent Ranking
    10. Context Resolution
    11. Slot Filling
    12. Entity Linking
    13. Medical Safety Check (deterministic override)
    14. Provider Ranking (if applicable)
    15. Final Response Building
    """

    def __init__(self):
        self.normalizer = TextNormalizer()
        self.synonyms = SynonymEngine()
        self.tokenizer = Tokenizer()
        self.safety = MedicalSafetyLayer()
        self.slots = SlotFiller()
        self.ranker = IntentRanker()
        self.context_resolver = ContextResolver()
        self.entity_linker = EntityLinker()
        self.provider_resolver = ProviderResolver()

    def process(
        self,
        text: str,
        intent_scores: Dict[str, float],
        matched_keywords: Dict[str, List],
        conversation_context: Optional[Dict] = None,
        available_data: Optional[Dict] = None,
        conversation_id: Optional[str] = None
    ) -> Dict:
        """
        Execute the full NLU pipeline on user input.
        
        Args:
            text: Raw user message
            intent_scores: Raw keyword/pattern matching scores
            matched_keywords: Keywords matched per intent
            conversation_context: Previous conversation state
            available_data: Data from backend (specialties, doctors, etc.)
            conversation_id: Current conversation ID (for slot tracking)
            
        Returns:
            Dict with processed results
        """
        # Step 1: Normalize
        normalized_info = self.normalizer.normalize_with_metadata(text)
        normalized_text = normalized_info["normalized"]
        language = normalized_info["language"]

        # Step 2: Tokenize
        tokens = self.tokenizer.tokenize(normalized_text)
        tokens_with_pos = self.tokenizer.tokenize_with_positions(text)
        ngrams = self.tokenizer.extract_ngrams(tokens, min_n=1, max_n=3)

        # Step 3: Synonym resolution
        resolved_tokens = self.synonyms.resolve_tokens(tokens)
        resolved_text = self.synonyms.resolve_text(normalized_text)

        # Step 4: Extract numbers
        numbers = self.tokenizer.extract_numbers(text)

        # Step 5: Context resolution
        context_resolved = {}
        if conversation_context:
            context_resolved = self.context_resolver.resolve(text, conversation_context)

        # Step 6: Medical safety check (highest priority)
        safety_result = self.safety.check(text)
        if safety_result["bypass_intent_routing"]:
            return {
                "intent": "emergency",
                "confidence": 1.0,
                "normalized_text": normalized_text,
                "language": language,
                "tokens": tokens,
                "ngrams": ngrams,
                "numbers": numbers,
                "safety": safety_result,
                "bypass_normal_routing": True,
                "reply": safety_result["response"],
                "matched_keywords": [],
                "resolved_text": resolved_text,
                "conversation_context": context_resolved
            }

        # Step 7: Intent ranking with calibration
        ranked_intents = self.ranker.rank(
            intent_scores,
            matched_keywords,
            resolved_text,
            conversation_context
        )
        best_intent = self.ranker.get_best_intent(ranked_intents)
        alternatives = self.ranker.get_alternatives(ranked_intents)

        # Step 8: Extract entities from resolved text
        entities = self._extract_entities(
            text, normalized_text, resolved_text, tokens, ngrams,
            numbers, context_resolved
        )

        # Step 9: Entity linking (resolve to DB IDs)
        if available_data:
            entities = self.entity_linker.link_entities(entities, available_data)

        # Handle intent override from context (e.g., follow-up navigation)
        final_intent = best_intent["intent"]
        if entities.get("_intent_override"):
            final_intent = entities["_intent_override"]

        # Step 10: Slot filling
        slot_info = None
        if conversation_id:
            if final_intent != "unknown":
                self.slots.update_state(conversation_id, final_intent, entities)

            slot_state = self.slots.get_state_summary(conversation_id)
            if slot_state.get("active") and not slot_state.get("completed"):
                next_question = self.slots.get_next_question(conversation_id, language[:2])
                slot_info = {
                    "state": slot_state,
                    "next_question": next_question
                }

        # Step 11: Build final result
        return {
            "intent": final_intent,
            "confidence": best_intent["confidence"],
            "normalized_text": normalized_text,
            "language": language,
            "tokens": tokens,
            "ngrams": ngrams,
            "numbers": numbers,
            "safety": safety_result,
            "bypass_normal_routing": False,
            "matched_keywords": best_intent.get("matched_terms", []),
            "resolved_text": resolved_text,
            "entities": entities,
            "ranked_intents": ranked_intents[:3],
            "alternative_intents": alternatives,
            "slot_filling": slot_info,
            "conversation_context": context_resolved,
            "is_confident": self.ranker.is_confident(ranked_intents)
        }

    def _extract_entities(
        self,
        original: str,
        normalized: str,
        resolved: str,
        tokens: List[str],
        ngrams: List[str],
        numbers: List[Dict],
        context_resolved: Dict
    ) -> Dict:
        """
        Extract entities from processed text.
        Combines new extraction with context-resolved entities.
        """
        entities = {
            "specialty": None,
            "specialties": [],
            "type": None,
            "types": [],
            "symptoms": [],
            "location": None,
            "medications": [],
            "services": [],
            "language": "arabic" if any('\u0600' <= c <= '\u06FF' for c in original) else "english",
            "raw": original,
            "is_follow_up": context_resolved.get("is_follow_up", False),
            "numbers": numbers if numbers else None
        }

        # Check ngrams against known entities from synonym engine
        for ngram in ngrams:
            # Check for specialty matches
            canonical = self.synonyms.resolve(ngram)
            for spec_key in self.synonyms.arabic_synonyms.keys():
                if canonical == spec_key or ngram == spec_key:
                    if spec_key not in entities["specialties"]:
                        entities["specialties"].append(spec_key)
                    if not entities["specialty"]:
                        entities["specialty"] = spec_key

            # Check for type matches
            type_keys = {"clinic", "hospital", "pharmacy", "laboratory", "radiology", "dental", "emergency", "optical"}
            if canonical in type_keys:
                if canonical not in entities["types"]:
                    entities["types"].append(canonical)
                if not entities["type"]:
                    entities["type"] = canonical

            # Check for symptom matches
            symptom_keys = {"headache", "fever", "cough", "fatigue", "dizziness", "nausea",
                           "chest_pain", "stomach_ache", "back_pain", "insomnia", "anxiety", "skin_rash"}
            if canonical in symptom_keys:
                if canonical not in entities["symptoms"]:
                    entities["symptoms"].append(canonical)

            # Check for medication matches
            med_keys = {"paracetamol", "ibuprofen", "aspirin", "amoxicillin", "omeprazole", "metformin", "insulin"}
            if canonical in med_keys:
                if canonical not in entities["medications"]:
                    entities["medications"].append(canonical)

        # Merge context-resolved entities (don't override newly extracted)
        for key, value in context_resolved.items():
            if key.startswith("_"):
                continue
            if key not in entities or entities[key] is None:
                entities[key] = value
            elif isinstance(entities[key], list) and isinstance(value, list):
                for item in value:
                    if item not in entities[key]:
                        entities[key].append(item)

        return entities

    def rank_providers(
        self,
        providers: List[Dict],
        provider_type: str,
        preferences: Optional[Dict] = None
    ) -> List[Dict]:
        """Rank providers using the provider resolver."""
        if provider_type == "doctor":
            return self.provider_resolver.rank_doctors(providers, preferences)
        elif provider_type in ("clinic", "pharmacy"):
            return self.provider_resolver.rank_clinics(providers, preferences)
        elif provider_type == "hospital":
            return self.provider_resolver.rank_hospitals(providers, preferences)
        return providers

    def get_safety_layer(self) -> MedicalSafetyLayer:
        """Get the medical safety layer for external use."""
        return self.safety

    def get_slot_filler(self) -> SlotFiller:
        """Get the slot filler for external use."""
        return self.slots

    def get_entity_linker(self) -> EntityLinker:
        """Get the entity linker for external use."""
        return self.entity_linker

    def get_context_resolver(self) -> ContextResolver:
        """Get the context resolver for external use."""
        return self.context_resolver