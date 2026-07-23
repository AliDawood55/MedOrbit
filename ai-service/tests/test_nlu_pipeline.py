"""
MedOrbit NLU Pipeline — Comprehensive Test Suite
"""

import sys
import os
import json
import time
import unittest
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from chatbot.intent.classifier import IntentClassifier
from chatbot.entities.extractor import EntityExtractor
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.nlu.slots import SlotFiller
from chatbot.nlu.normalizer import TextNormalizer
from chatbot.nlu.synonyms import SynonymEngine
from chatbot.nlu.tokens import Tokenizer
from chatbot.nlu.ranker import IntentRanker
from chatbot.nlu.context_resolver import ContextResolver
from chatbot.nlu.pipeline import NLUPipeline


class TestNormalizer(unittest.TestCase):
    def setUp(self):
        self.normalizer = TextNormalizer()

    def test_arabic_normalization(self):
        result = self.normalizer.normalize("مرحبا")
        self.assertIn("مرحبا", result)

    def test_english_normalization(self):
        result = self.normalizer.normalize("Hello")
        self.assertEqual(result, "hello")

    def test_spell_correction_misspelled_hospital(self):
        result = self.normalizer.normalize_with_metadata("مستشفا")
        self.assertTrue(result["was_corrected"])
        # After normalization: ى→ي, so "مستشفى" becomes "مستشفي"
        self.assertIn("مستشفي", result["normalized"])

    def test_spell_correction_pharmacy(self):
        result = self.normalizer.normalize_with_metadata("صيدليه")
        self.assertTrue(result["was_corrected"])
        # After normalization: ة→ه, so "صيدلية" becomes "صيدليه"
        self.assertIn("صيدليه", result["normalized"])

    def test_spell_correction_english_hospital(self):
        result = self.normalizer.normalize_with_metadata("hospetal")
        self.assertTrue(result["was_corrected"])
        self.assertIn("hospital", result["normalized"])

    def test_dialect_pain_expression(self):
        result = self.normalizer.normalize_with_metadata("راسي بوجعني")
        self.assertTrue(result["was_dialect"])

    def test_dialect_stomach_expression(self):
        result = self.normalizer.normalize_with_metadata("بطني بتوجع")
        self.assertTrue(result["was_dialect"])

    def test_dialect_breathing_expression(self):
        result = self.normalizer.normalize_with_metadata("نفسي ضايق")
        self.assertTrue(result["was_dialect"])

    def test_dialect_dizziness(self):
        result = self.normalizer.normalize_with_metadata("دوخت")
        self.assertTrue(result["was_dialect"])

    def test_dialect_fatigue(self):
        result = self.normalizer.normalize_with_metadata("حاس حالي تعبان")
        self.assertTrue(result["was_dialect"])

    def test_fuzzy_match_exact(self):
        match = self.normalizer.fuzzy_match("doctor", ["doctor", "nurse", "clinic"])
        self.assertIsNotNone(match)
        self.assertEqual(match[0], "doctor")

    def test_fuzzy_match_close(self):
        match = self.normalizer.fuzzy_match("docotr", ["doctor", "nurse"])
        self.assertIsNotNone(match)
        self.assertEqual(match[0], "doctor")

    def test_fuzzy_match_no_match(self):
        match = self.normalizer.fuzzy_match("xyzabc", ["doctor", "nurse"])
        self.assertIsNone(match)

    def test_mixed_arabic_english(self):
        result = self.normalizer.normalize_with_metadata("I need دكتور")
        self.assertEqual(result["language"], "arabic")


class TestSynonymEngine(unittest.TestCase):
    def setUp(self):
        self.synonyms = SynonymEngine()

    def test_resolve_doctor_arabic(self):
        self.assertEqual(self.synonyms.resolve("طبيب"), "doctor")

    def test_resolve_hospital_arabic(self):
        self.assertEqual(self.synonyms.resolve("مستشفى"), "hospital")

    def test_resolve_pharmacy_arabic(self):
        self.assertEqual(self.synonyms.resolve("صيدلية"), "pharmacy")

    def test_resolve_headache_arabic(self):
        self.assertEqual(self.synonyms.resolve("صداع"), "headache")

    def test_resolve_heart_attack(self):
        self.assertEqual(self.synonyms.resolve("heart attack"), "cardiac_arrest")

    def test_get_synonyms_doctor(self):
        syns = self.synonyms.get_synonyms("doctor")
        self.assertTrue(len(syns) > 0)
        self.assertIn("طبيب", syns)

    def test_get_all_canonical_forms(self):
        forms = self.synonyms.get_all_canonical_forms()
        self.assertTrue(len(forms) > 50)
        self.assertIn("doctor", forms)
        self.assertIn("headache", forms)

    def test_expand_query(self):
        expanded = self.synonyms.expand_query("doctor")
        self.assertIn("doctor", expanded)


class TestTokenizer(unittest.TestCase):
    def setUp(self):
        self.tokenizer = Tokenizer()

    def test_tokenize_arabic(self):
        tokens = self.tokenizer.tokenize("بدي دكتور قلب")
        self.assertTrue(len(tokens) >= 2)

    def test_tokenize_english(self):
        tokens = self.tokenizer.tokenize("I need a cardiologist")
        self.assertIn("cardiologist", tokens)

    def test_tokenize_with_positions(self):
        tokens = self.tokenizer.tokenize_with_positions("hello doctor")
        self.assertEqual(len(tokens), 2)
        self.assertEqual(tokens[0]["text"], "hello")

    def test_extract_ngrams(self):
        ngrams = self.tokenizer.extract_ngrams(["chest", "pain", "doctor"], max_n=2)
        self.assertIn("chest pain", ngrams)

    def test_stem_english_ing(self):
        self.assertEqual(self.tokenizer.stem_english("running"), "run")

    def test_stem_english_ed(self):
        self.assertEqual(self.tokenizer.stem_english("stopped"), "stop")

    def test_stem_english_ment(self):
        self.assertEqual(self.tokenizer.stem_english("treatment"), "treat")

    def test_stem_arabic_prefix(self):
        stem = self.tokenizer.stem_arabic("المستشفى")
        self.assertNotEqual(stem, "المستشفى")

    def test_extract_numbers_integers(self):
        nums = self.tokenizer.extract_numbers("I am 30 years old")
        self.assertTrue(any(n["value"] == 30 for n in nums))

    def test_extract_numbers_ordinal(self):
        nums = self.tokenizer.extract_numbers("the second one")
        self.assertTrue(any(n["value"] == 2 for n in nums))


class TestSafetyLayer(unittest.TestCase):
    def setUp(self):
        self.safety = MedicalSafetyLayer()

    def test_emergency_heart_attack_arabic(self):
        result = self.safety.check("عندي نوبة قلبية")
        self.assertTrue(result["is_emergency"])
        self.assertTrue(result["bypass_intent_routing"])

    def test_emergency_heart_attack_english(self):
        result = self.safety.check("I think I'm having a heart attack")
        self.assertTrue(result["is_emergency"])
        self.assertTrue(result["bypass_intent_routing"])

    def test_emergency_breathing_english(self):
        result = self.safety.check("I can't breathe")
        self.assertTrue(result["is_emergency"])

    def test_emergency_stroke(self):
        result = self.safety.check("I think I'm having a stroke")
        self.assertTrue(result["is_emergency"])

    def test_emergency_severe_bleeding(self):
        result = self.safety.check("severe bleeding")
        self.assertTrue(result["is_emergency"])

    def test_emergency_suicide(self):
        result = self.safety.check("I want to kill myself")
        self.assertTrue(result["is_emergency"])

    def test_emergency_poisoning(self):
        result = self.safety.check("تسمم")
        self.assertTrue(result["is_emergency"])

    def test_urgent_high_fever(self):
        result = self.safety.check("حرارة مرتفعة جدا")
        self.assertTrue(result["is_urgent"])

    def test_urgent_severe_pain(self):
        result = self.safety.check("severe pain in my chest")
        self.assertTrue(result["is_urgent"])

    def test_normal_message(self):
        result = self.safety.check("أريد موعد عند طبيب")
        self.assertFalse(result["is_emergency"])
        self.assertFalse(result["is_urgent"])
        self.assertEqual(result["severity"], "normal")

    def test_emergency_response_arabic(self):
        result = self.safety.check("طوارئ")
        self.assertIn("🚨", result["response"])

    def test_emergency_response_english(self):
        result = self.safety.check("emergency")
        self.assertIn("🚨", result["response"])


class TestIntentClassifier(unittest.TestCase):
    def setUp(self):
        self.classifier = IntentClassifier()

    def test_find_doctor_arabic(self):
        result = self.classifier.classify("بدي دكتور قلب")
        self.assertEqual(result["intent"], "find_doctor")
        self.assertGreater(result["confidence"], 0.3)

    def test_find_doctor_english(self):
        result = self.classifier.classify("I need a cardiologist")
        self.assertEqual(result["intent"], "find_doctor")
        self.assertGreater(result["confidence"], 0.3)

    def test_find_nearest_arabic(self):
        result = self.classifier.classify("أقرب عيادة")
        self.assertEqual(result["intent"], "find_nearest")
        self.assertGreater(result["confidence"], 0.3)

    def test_find_nearest_english(self):
        result = self.classifier.classify("Nearest pharmacy near me")
        self.assertEqual(result["intent"], "find_nearest")
        self.assertGreater(result["confidence"], 0.3)

    def test_symptom_analysis_arabic(self):
        result = self.classifier.classify("عندي صداع شديد")
        self.assertEqual(result["intent"], "symptom_analysis")
        self.assertGreater(result["confidence"], 0.3)

    def test_symptom_analysis_english(self):
        result = self.classifier.classify("I have a headache")
        self.assertEqual(result["intent"], "symptom_analysis")
        self.assertGreater(result["confidence"], 0.3)

    def test_medication_info_arabic(self):
        result = self.classifier.classify("معلومات عن بانادول")
        self.assertEqual(result["intent"], "medication_info")
        self.assertGreater(result["confidence"], 0.3)

    def test_medication_info_english(self):
        result = self.classifier.classify("What is paracetamol used for")
        self.assertEqual(result["intent"], "medication_info")
        self.assertGreater(result["confidence"], 0.3)

    def test_book_appointment_arabic(self):
        result = self.classifier.classify("بدي احجز موعد")
        self.assertEqual(result["intent"], "book_appointment")
        self.assertGreater(result["confidence"], 0.3)

    def test_book_appointment_english(self):
        result = self.classifier.classify("I want to book an appointment")
        self.assertEqual(result["intent"], "book_appointment")
        self.assertGreater(result["confidence"], 0.3)

    def test_show_route_arabic(self):
        result = self.classifier.classify("كيف اوصل للعيادة")
        self.assertEqual(result["intent"], "show_route")
        self.assertGreater(result["confidence"], 0.3)

    def test_show_route_english(self):
        result = self.classifier.classify("How do I get there")
        self.assertEqual(result["intent"], "show_route")
        self.assertGreater(result["confidence"], 0.3)

    def test_small_talk_arabic(self):
        result = self.classifier.classify("مرحبا")
        self.assertEqual(result["intent"], "small_talk")
        self.assertGreater(result["confidence"], 0.3)

    def test_small_talk_english(self):
        result = self.classifier.classify("Hello")
        self.assertEqual(result["intent"], "small_talk")
        self.assertGreater(result["confidence"], 0.3)

    def test_thanks_arabic(self):
        result = self.classifier.classify("شكرا")
        self.assertEqual(result["intent"], "thanks")
        self.assertGreater(result["confidence"], 0.3)

    def test_emergency_detection(self):
        result = self.classifier.classify("طوارئ")
        self.assertTrue(result.get("is_emergency", False))

    def test_emergency_english(self):
        result = self.classifier.classify("This is an emergency")
        self.assertTrue(result.get("is_emergency", False))

    def test_follow_up_context(self):
        context = {"lastIntent": "find_doctor", "currentTopic": "find_doctor"}
        result = self.classifier.classify("the second one", context=context)
        self.assertIn(result["intent"], ["find_doctor", "unknown"])

    def test_pipeline_logging(self):
        result = self.classifier.classify("بدي دكتور")
        self.assertIn("_pipeline", result)
        self.assertIn("_processing_ms", result)

    def test_alternative_intents(self):
        result = self.classifier.classify("doctor")
        self.assertIn("alternative_intents", result)

    def test_empty_input(self):
        result = self.classifier.classify("")
        self.assertEqual(result["intent"], "unknown")

    def test_mixed_arabic_english(self):
        result = self.classifier.classify("I need دكتور قلب")
        self.assertIn(result["intent"], ["find_doctor", "find_nearest"])


class TestEntityExtractor(unittest.TestCase):
    def setUp(self):
        self.extractor = EntityExtractor()

    def test_extract_specialty_cardiology(self):
        result = self.extractor.extract("بدي دكتور قلب")
        self.assertEqual(result["specialty"], "cardiology")

    def test_extract_specialty_english(self):
        result = self.extractor.extract("I need a cardiologist")
        self.assertEqual(result["specialty"], "cardiology")

    def test_extract_type_clinic_arabic(self):
        result = self.extractor.extract("أقرب عيادة")
        self.assertEqual(result["type"], "clinic")

    def test_extract_type_pharmacy_arabic(self):
        result = self.extractor.extract("أقرب صيدلية")
        self.assertEqual(result["type"], "pharmacy")

    def test_extract_type_hospital_arabic(self):
        result = self.extractor.extract("أقرب مستشفى")
        self.assertEqual(result["type"], "hospital")

    def test_extract_symptom_headache(self):
        result = self.extractor.extract("عندي صداع")
        self.assertIn("headache", result["symptoms"])

    def test_extract_symptom_fever(self):
        result = self.extractor.extract("عندي حرارة")
        self.assertIn("fever", result["symptoms"])

    def test_extract_symptom_stomach(self):
        result = self.extractor.extract("بطني بتوجع")
        self.assertIn("stomach_ache", result["symptoms"])

    def test_extract_location_nablus(self):
        result = self.extractor.extract("في نابلس")
        self.assertEqual(result["location"], "nablus")

    def test_extract_medication(self):
        result = self.extractor.extract("معلومات عن بانادول")
        self.assertIn("paracetamol", result["medications"])

    def test_extract_dialect_pain(self):
        result = self.extractor.extract("راسي بوجعني")
        self.assertTrue(result["was_dialect"])
        self.assertIn("headache", result["symptoms"])

    def test_extract_dialect_stomach(self):
        result = self.extractor.extract("كرشي بوجعني")
        self.assertTrue(result["was_dialect"])
        self.assertIn("stomach_ache", result["symptoms"])

    def test_extract_dialect_dizziness(self):
        result = self.extractor.extract("دوخت")
        self.assertTrue(result["was_dialect"])
        self.assertIn("dizziness", result["symptoms"])

    def test_extract_dialect_fatigue(self):
        result = self.extractor.extract("حاس حالي تعبان")
        self.assertTrue(result["was_dialect"])
        self.assertIn("fatigue", result["symptoms"])

    def test_extract_spell_corrected(self):
        result = self.extractor.extract("مستشفا")
        self.assertTrue(result["was_corrected"])

    def test_context_resolution(self):
        context = {"entities": {"specialty": "cardiology", "type": "clinic"}}
        result = self.extractor.extract("the second one", context=context)
        self.assertTrue(result.get("is_follow_up", False))

    def test_processing_time_logged(self):
        result = self.extractor.extract("بدي دكتور")
        self.assertIn("_processing_ms", result)

    def test_empty_input(self):
        result = self.extractor.extract("")
        self.assertIsNone(result["specialty"])


class TestSlotFiller(unittest.TestCase):
    def setUp(self):
        self.slots = SlotFiller()

    def test_initialize_state(self):
        state = self.slots.initialize_state("conv1", "find_doctor", {"specialty": "cardiology"})
        self.assertEqual(state["intent"], "find_doctor")
        self.assertEqual(state["filled_slots"]["specialty"], "cardiology")

    def test_missing_slots_detected(self):
        state = self.slots.initialize_state("conv1", "find_doctor", {})
        self.assertIn("specialty", state["missing_slots"])

    def test_update_state_fills_slot(self):
        self.slots.initialize_state("conv1", "find_doctor", {})
        state = self.slots.update_state("conv1", "find_doctor", {"specialty": "cardiology"})
        self.assertEqual(state["filled_slots"]["specialty"], "cardiology")
        self.assertNotIn("specialty", state["missing_slots"])

    def test_get_next_question(self):
        self.slots.initialize_state("conv1", "find_doctor", {})
        question = self.slots.get_next_question("conv1", "ar")
        self.assertIsNotNone(question)
        self.assertEqual(question["slot"], "specialty")

    def test_get_next_question_english(self):
        self.slots.initialize_state("conv1", "find_doctor", {})
        question = self.slots.get_next_question("conv1", "en")
        self.assertIsNotNone(question)
        self.assertIn("specialty", question["question"].lower())

    def test_clear_state(self):
        self.slots.initialize_state("conv1", "find_doctor", {})
        self.slots.clear_state("conv1")
        state = self.slots.get_state_summary("conv1")
        self.assertFalse(state["active"])

    def test_extract_age_arabic(self):
        result = self.slots.extract_slot_values("عمري 30 سنة", "ar")
        self.assertEqual(result.get("age"), 30)

    def test_extract_age_english(self):
        result = self.slots.extract_slot_values("I am 30 years old", "en")
        self.assertEqual(result.get("age"), 30)

    def test_extract_duration_arabic(self):
        result = self.slots.extract_slot_values("من 3 أيام", "ar")
        self.assertIsNotNone(result.get("duration"))

    def test_extract_duration_english(self):
        result = self.slots.extract_slot_values("for 3 days", "en")
        self.assertIsNotNone(result.get("duration"))


class TestContextResolver(unittest.TestCase):
    def setUp(self):
        self.resolver = ContextResolver()

    def test_follow_up_detection_short(self):
        resolved = self.resolver.resolve("there", {"lastIntent": "find_doctor", "entities": {}})
        self.assertTrue(resolved.get("is_follow_up"))

    def test_ordinal_resolution_english(self):
        resolved = self.resolver.resolve("the second one", {"lastIntent": "find_doctor", "entities": {}})
        self.assertEqual(resolved.get("ordinal_index"), 1)

    def test_entity_inheritance(self):
        context = {"entities": {"specialty": "cardiology", "type": "clinic"}, "lastIntent": "find_doctor"}
        resolved = self.resolver.resolve("tell me more", context)
        self.assertEqual(resolved.get("specialty"), "cardiology")

    def test_navigation_detection(self):
        resolved = self.resolver.resolve("take me there", {"lastIntent": "find_nearest", "entities": {}})
        self.assertEqual(resolved.get("intent_override"), "show_route")

    def test_navigation_arabic(self):
        resolved = self.resolver.resolve("اوصلني", {"lastIntent": "find_nearest", "entities": {}})
        self.assertEqual(resolved.get("intent_override"), "show_route")

    def test_no_context(self):
        resolved = self.resolver.resolve("hello", None)
        self.assertEqual(resolved, {})

    def test_selection_reference(self):
        ref = self.resolver.get_selection_reference("the second doctor")
        self.assertIsNotNone(ref)
        self.assertEqual(ref["index"], 1)
        self.assertEqual(ref["entity_type"], "doctor")


class TestIntentRanker(unittest.TestCase):
    def setUp(self):
        self.ranker = IntentRanker()

    def test_rank_single_intent(self):
        ranked = self.ranker.rank({"find_doctor": 3.0}, {"find_doctor": ["doctor"]}, "I need a doctor")
        self.assertEqual(len(ranked), 1)
        self.assertEqual(ranked[0]["intent"], "find_doctor")

    def test_rank_multiple_intents(self):
        ranked = self.ranker.rank(
            {"find_doctor": 2.0, "find_nearest": 1.0},
            {"find_doctor": ["doctor"], "find_nearest": ["near"]},
            "I need a doctor near me"
        )
        self.assertEqual(len(ranked), 2)
        self.assertEqual(ranked[0]["intent"], "find_doctor")

    def test_rank_unknown_fallback(self):
        ranked = self.ranker.rank({}, {}, "xyz")
        self.assertEqual(ranked[0]["intent"], "unknown")

    def test_get_best_intent(self):
        ranked = [{"intent": "find_doctor", "confidence": 0.8}]
        best = self.ranker.get_best_intent(ranked)
        self.assertEqual(best["intent"], "find_doctor")

    def test_get_alternatives(self):
        ranked = [
            {"intent": "find_doctor", "confidence": 0.8},
            {"intent": "find_nearest", "confidence": 0.2}
        ]
        alts = self.ranker.get_alternatives(ranked)
        self.assertEqual(len(alts), 1)
        self.assertEqual(alts[0]["intent"], "find_nearest")

    def test_is_confident(self):
        ranked = [{"intent": "find_doctor", "confidence": 0.8, "is_fallback": False}]
        self.assertTrue(self.ranker.is_confident(ranked))

    def test_is_not_confident(self):
        ranked = [{"intent": "unknown", "confidence": 0.0, "is_fallback": True}]
        self.assertFalse(self.ranker.is_confident(ranked))


class TestNLUPipeline(unittest.TestCase):
    def setUp(self):
        self.pipeline = NLUPipeline()

    def test_pipeline_emergency(self):
        result = self.pipeline.process(
            "طوارئ",
            {"emergency": 1.0},
            {"emergency": ["طوارئ"]}
        )
        self.assertTrue(result["bypass_normal_routing"])
        self.assertEqual(result["intent"], "emergency")

    def test_pipeline_normal(self):
        result = self.pipeline.process(
            "بدي دكتور قلب",
            {"find_doctor": 2.0},
            {"find_doctor": ["دكتور", "قلب"]}
        )
        self.assertFalse(result["bypass_normal_routing"])
        self.assertEqual(result["intent"], "find_doctor")

    def test_pipeline_with_context(self):
        context = {"lastIntent": "find_doctor", "entities": {"specialty": "cardiology"}}
        result = self.pipeline.process(
            "the second one",
            {"find_doctor": 0.5},
            {"find_doctor": ["doctor"]},
            conversation_context=context
        )
        self.assertIn("entities", result)

    def test_pipeline_safety_integration(self):
        safety = self.pipeline.get_safety_layer()
        result = safety.check("I can't breathe")
        self.assertTrue(result["is_emergency"])

    def test_pipeline_slot_filler(self):
        slots = self.pipeline.get_slot_filler()
        self.assertIsNotNone(slots)

    def test_pipeline_entity_linker(self):
        linker = self.pipeline.get_entity_linker()
        self.assertIsNotNone(linker)

    def test_pipeline_context_resolver(self):
        resolver = self.pipeline.get_context_resolver()
        self.assertIsNotNone(resolver)


class TestEndToEnd(unittest.TestCase):
    def setUp(self):
        self.classifier = IntentClassifier()
        self.extractor = EntityExtractor()
        self.safety = MedicalSafetyLayer()

    def _run_pipeline(self, message, context=None):
        safety = self.safety.check(message)
        intent = self.classifier.classify(message, context=context)
        entities = self.extractor.extract(message, context=context)
        return {"safety": safety, "intent": intent, "entities": entities}

    def test_full_conversation_arabic(self):
        r1 = self._run_pipeline("بدي دكتور قلب")
        self.assertEqual(r1["intent"]["intent"], "find_doctor")
        self.assertEqual(r1["entities"]["specialty"], "cardiology")
        self.assertFalse(r1["safety"]["is_emergency"])
        context = {"lastIntent": "find_doctor", "entities": r1["entities"]}
        r2 = self._run_pipeline("الثاني", context=context)
        self.assertTrue(r2["entities"].get("is_follow_up", False) or r2["intent"]["intent"] != "unknown")

    def test_full_conversation_english(self):
        r1 = self._run_pipeline("I need a cardiologist")
        self.assertEqual(r1["intent"]["intent"], "find_doctor")
        self.assertEqual(r1["entities"]["specialty"], "cardiology")

    def test_emergency_bypasses_normal(self):
        r = self._run_pipeline("I can't breathe")
        self.assertTrue(r["safety"]["is_emergency"])
        self.assertTrue(r["safety"]["bypass_intent_routing"])

    def test_emergency_arabic(self):
        r = self._run_pipeline("عندي نوبة قلبية")
        self.assertTrue(r["safety"]["is_emergency"])

    def test_clinic_search(self):
        r = self._run_pipeline("أقرب عيادة في نابلس")
        self.assertEqual(r["intent"]["intent"], "find_nearest")
        self.assertEqual(r["entities"]["type"], "clinic")
        self.assertEqual(r["entities"]["location"], "nablus")

    def test_pharmacy_search(self):
        r = self._run_pipeline("أقرب صيدلية")
        self.assertEqual(r["intent"]["intent"], "find_nearest")
        self.assertEqual(r["entities"]["type"], "pharmacy")

    def test_hospital_search(self):
        r = self._run_pipeline("Nearest hospital")
        self.assertEqual(r["intent"]["intent"], "find_nearest")
        self.assertEqual(r["entities"]["type"], "hospital")

    def test_hospital_search_with_where_prefix(self):
        r = self._run_pipeline("وين أقرب مستشفى")
        self.assertEqual(r["intent"]["intent"], "find_nearest")
        self.assertEqual(r["entities"]["type"], "hospital")

    def test_pharmacy_search_bare_proximity_phrasing(self):
        # No "أقرب" here — relies on bare "قريب"/"قريبة" keywords so this
        # doesn't lose to the competing find_pharmacy intent.
        r = self._run_pipeline("بدي صيدلية قريبة")
        self.assertEqual(r["intent"]["intent"], "find_nearest")
        self.assertEqual(r["entities"]["type"], "pharmacy")

    def test_medication_question(self):
        r = self._run_pipeline("معلومات عن بانادول")
        self.assertEqual(r["intent"]["intent"], "medication_info")
        self.assertIn("paracetamol", r["entities"]["medications"])

    def test_appointment_booking(self):
        r = self._run_pipeline("بدي احجز موعد")
        self.assertEqual(r["intent"]["intent"], "book_appointment")

    def test_route_request(self):
        r = self._run_pipeline("كيف اوصل للعيادة")
        self.assertEqual(r["intent"]["intent"], "show_route")

    def test_symptom_arabic_dialect(self):
        r = self._run_pipeline("راسي بوجعني")
        self.assertTrue(r["entities"]["was_dialect"])
        self.assertIn("headache", r["entities"]["symptoms"])

    def test_symptom_palestinian_stomach(self):
        r = self._run_pipeline("كرشي بوجعني")
        self.assertTrue(r["entities"]["was_dialect"])
        self.assertIn("stomach_ache", r["entities"]["symptoms"])

    def test_misspelled_pharmacy(self):
        r = self._run_pipeline("أقرب صيدليه")
        self.assertTrue(r["entities"]["was_corrected"])
        self.assertEqual(r["entities"]["type"], "pharmacy")

    def test_misspelled_hospital(self):
        r = self._run_pipeline("مستشفا")
        self.assertTrue(r["entities"]["was_corrected"])

    def test_greeting(self):
        r = self._run_pipeline("مرحبا")
        self.assertEqual(r["intent"]["intent"], "small_talk")

    def test_thanks(self):
        r = self._run_pipeline("شكرا")
        self.assertEqual(r["intent"]["intent"], "thanks")

    def test_farewell(self):
        r = self._run_pipeline("مع السلامة")
        self.assertEqual(r["intent"]["intent"], "bye")

    def test_how_are_you(self):
        r = self._run_pipeline("كيفك")
        self.assertEqual(r["intent"]["intent"], "how_are_you")

    def test_yes_confirmation(self):
        r = self._run_pipeline("نعم")
        self.assertEqual(r["intent"]["intent"], "yes_confirmation")

    def test_no_negation(self):
        r = self._run_pipeline("لا")
        self.assertEqual(r["intent"]["intent"], "no_negation")

    def test_doctor_by_specialty_dermatology(self):
        r = self._run_pipeline("ابحث عن طبيب جلدية")
        self.assertEqual(r["intent"]["intent"], "find_doctor")
        self.assertEqual(r["entities"]["specialty"], "dermatology")

    def test_doctor_by_specialty_orthopedic(self):
        r = self._run_pipeline("بدي دكتور عظام")
        self.assertEqual(r["intent"]["intent"], "find_doctor")
        self.assertEqual(r["entities"]["specialty"], "orthopedics")

    def test_doctor_by_specialty_children(self):
        r = self._run_pipeline("I need a pediatrician")
        self.assertEqual(r["intent"]["intent"], "find_doctor")
        self.assertEqual(r["entities"]["specialty"], "pediatrics")

    def test_doctor_rating_query(self):
        r = self._run_pipeline("أفضل دكتور قلب")
        self.assertIn(r["intent"]["intent"], ["doctor_rating", "find_doctor"])

    def test_clinic_hours(self):
        r = self._run_pipeline("ساعات دوام العيادة")
        self.assertIn(r["intent"]["intent"], ["clinic_hours", "clinic_info"])

    def test_clinic_phone(self):
        r = self._run_pipeline("رقم تلفون العيادة")
        self.assertIn(r["intent"]["intent"], ["clinic_phone", "clinic_info"])

    def test_clinic_address(self):
        r = self._run_pipeline("وين موقع العيادة")
        self.assertIn(r["intent"]["intent"], ["clinic_address", "clinic_info"])

    def test_clinic_services(self):
        r = self._run_pipeline("ما هي خدمات العيادة")
        self.assertIn(r["intent"]["intent"], ["clinic_services", "clinic_info"])

    def test_clinic_insurance(self):
        r = self._run_pipeline("هل العيادة بتقبل التأمين")
        self.assertIn(r["intent"]["intent"], ["clinic_insurance", "insurance_query"])

    def test_clinic_doctors(self):
        r = self._run_pipeline("من هم الأطباء في العيادة")
        self.assertIn(r["intent"]["intent"], ["clinic_doctors", "clinic_info"])

    def test_hospital_departments(self):
        r = self._run_pipeline("ما هي أقسام المستشفى")
        self.assertIn(r["intent"]["intent"], ["hospital_departments", "find_hospital"])

    def test_pharmacy_24h(self):
        r = self._run_pipeline("صيدلية 24 ساعة")
        self.assertIn(r["intent"]["intent"], ["pharmacy_24h", "find_pharmacy"])

    def test_travel_time(self):
        r = self._run_pipeline("كم يستغرق الوصول")
        self.assertIn(r["intent"]["intent"], ["travel_time", "show_route"])

    def test_walking_route(self):
        r = self._run_pipeline("أقدر امشي")
        self.assertIn(r["intent"]["intent"], ["walking_route", "show_route"])

    def test_driving_route(self):
        r = self._run_pipeline("المسافة بالسيارة")
        self.assertIn(r["intent"]["intent"], ["driving_route", "travel_time"])

    def test_cancel_appointment(self):
        r = self._run_pipeline("بدي ألغي الموعد")
        self.assertIn(r["intent"]["intent"], ["cancel_appointment", "book_appointment"])

    def test_reschedule_appointment(self):
        r = self._run_pipeline("بدي أغير الموعد")
        self.assertIn(r["intent"]["intent"], ["reschedule_appointment", "book_appointment"])

    def test_medication_dosage(self):
        r = self._run_pipeline("كم جرعة البانادول")
        self.assertIn(r["intent"]["intent"], ["medication_dosage", "medication_info"])

    def test_medication_side_effects(self):
        r = self._run_pipeline("ما هي الأعراض الجانبية")
        self.assertIn(r["intent"]["intent"], ["medication_side_effects", "medication_info"])

    def test_medication_interaction(self):
        r = self._run_pipeline("هل يتعارض البانادول مع الضغط")
        self.assertIn(r["intent"]["intent"], ["medication_interaction", "medication_info"])

    def test_lab_results(self):
        r = self._run_pipeline("نتائج تحاليل")
        self.assertIn(r["intent"]["intent"], ["lab_result_query", "medical_history"])

    def test_medical_history(self):
        r = self._run_pipeline("تاريخي الطبي")
        self.assertEqual(r["intent"]["intent"], "medical_history")

    def test_insurance_query(self):
        r = self._run_pipeline("هل التأمين يغطي")
        self.assertIn(r["intent"]["intent"], ["insurance_query", "platform_support"])

    def test_platform_support(self):
        r = self._run_pipeline("كيف أسجل")
        self.assertEqual(r["intent"]["intent"], "platform_support")

    def test_bmi_calculator(self):
        r = self._run_pipeline("احسب كتلة جسمي")
        self.assertIn(r["intent"]["intent"], ["bmi_calculator", "general_medical_question"])

    def test_nutrition_advice(self):
        r = self._run_pipeline("نصائح غذائية")
        self.assertIn(r["intent"]["intent"], ["nutrition_advice", "general_medical_question"])

    def test_exercise_advice(self):
        r = self._run_pipeline("تمارين مناسبة")
        self.assertIn(r["intent"]["intent"], ["exercise_advice", "general_medical_question"])

    def test_pregnancy_info(self):
        r = self._run_pipeline("نصائح للحامل")
        self.assertIn(r["intent"]["intent"], ["pregnancy_info", "general_medical_question"])

    def test_children_health(self):
        r = self._run_pipeline("طفلي عنده حرارة")
        self.assertIn(r["intent"]["intent"], ["children_health", "symptom_analysis"])

    def test_vaccination_info(self):
        r = self._run_pipeline("جدول التطعيمات")
        self.assertIn(r["intent"]["intent"], ["vaccination_info", "general_medical_question"])

    def test_mental_health(self):
        r = self._run_pipeline("مساعدة نفسية")
        self.assertIn(r["intent"]["intent"], ["mental_health", "general_medical_question"])

    def test_sick_leave(self):
        r = self._run_pipeline("بدي اجازة مرضية")
        self.assertIn(r["intent"]["intent"], ["sick_leave", "platform_support"])

    def test_general_medical_question(self):
        r = self._run_pipeline("ما هو مرض السكر")
        self.assertEqual(r["intent"]["intent"], "general_medical_question")

    def test_doctor_fee(self):
        r = self._run_pipeline("كم سعر كشف الدكتور")
        self.assertIn(r["intent"]["intent"], ["doctor_fee", "find_doctor"])

    def test_doctor_language(self):
        r = self._run_pipeline("دكتور يتحدث الإنجليزية")
        self.assertIn(r["intent"]["intent"], ["doctor_language", "find_doctor"])

    def test_doctor_gender(self):
        r = self._run_pipeline("بدي دكتورة")
        self.assertIn(r["intent"]["intent"], ["doctor_gender", "find_doctor"])

    def test_clinic_parking(self):
        r = self._run_pipeline("هل يوجد موقف سيارات")
        self.assertIn(r["intent"]["intent"], ["clinic_parking", "clinic_info"])

    def test_hospital_emergency(self):
        r = self._run_pipeline("قسم الطوارئ في المستشفى")
        self.assertIn(r["intent"]["intent"], ["hospital_emergency", "find_hospital"])

    def test_pharmacy_medication_available(self):
        r = self._run_pipeline("هل في صيدلية عندها بانادول")
        self.assertIn(r["intent"]["intent"], ["pharmacy_medication", "find_pharmacy"])

    def test_appointment_status(self):
        r = self._run_pipeline("حالة موعدي")
        self.assertIn(r["intent"]["intent"], ["appointment_status", "book_appointment"])

    def test_medication_alternative(self):
        r = self._run_pipeline("في بديل للبانادول")
        self.assertIn(r["intent"]["intent"], ["medication_alternative", "medication_info"])

    def test_lab_interpretation(self):
        r = self._run_pipeline("تفسير نتيجة السكر")
        self.assertIn(r["intent"]["intent"], ["lab_interpret", "lab_result_query"])

    def test_feedback(self):
        r = self._run_pipeline("عندي اقتراح")
        self.assertIn(r["intent"]["intent"], ["feedback", "platform_support"])

    def test_settings(self):
        r = self._run_pipeline("تغيير الإعدادات")
        self.assertIn(r["intent"]["intent"], ["settings", "platform_support"])


class TestPerformance(unittest.TestCase):
    def setUp(self):
        self.classifier = IntentClassifier()
        self.extractor = EntityExtractor()
        self.safety = MedicalSafetyLayer()

    def test_classifier_speed(self):
        start = time.time()
        for _ in range(10):
            self.classifier.classify("بدي دكتور قلب في نابلس")
        elapsed = (time.time() - start) * 1000
        avg = elapsed / 10
        self.assertLess(avg, 100, f"Classifier too slow: {avg:.2f}ms avg")

    def test_extractor_speed(self):
        start = time.time()
        for _ in range(10):
            self.extractor.extract("عندي صداع شديد وحرارة من 3 أيام")
        elapsed = (time.time() - start) * 1000
        avg = elapsed / 10
        self.assertLess(avg, 50, f"Extractor too slow: {avg:.2f}ms avg")

    def test_safety_speed(self):
        start = time.time()
        for _ in range(100):
            self.safety.check("I think I'm having a heart attack")
        elapsed = (time.time() - start) * 1000
        avg = elapsed / 100
        self.assertLess(avg, 10, f"Safety too slow: {avg:.2f}ms avg")

    def test_full_pipeline_speed(self):
        start = time.time()
        for _ in range(5):
            msg = "بدي دكتور قلب في نابلس"
            self.safety.check(msg)
            self.classifier.classify(msg)
            self.extractor.extract(msg)
        elapsed = (time.time() - start) * 1000
        avg = elapsed / 5
        self.assertLess(avg, 200, f"Pipeline too slow: {avg:.2f}ms avg")


if __name__ == '__main__':
    unittest.main(verbosity=2)