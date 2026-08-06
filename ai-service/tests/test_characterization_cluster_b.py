"""
Characterization tests — Cluster B (Phase 0).

Cluster B bug: TextNormalizer._normalize_dialect() (chatbot/nlu/normalizer.py),
driven by chatbot/nlu/data/palestinian_dialect.json's question_expressions /
response_expressions / symptom_expressions tables, replaces short Arabic
dialect/question words wherever their characters appear in the string —
including embedded inside unrelated, longer words — instead of only at
matched word boundaries. This corrupts the source text before intent
classification or entity extraction ever runs.

This phase intentionally does NOT fix anything. It has two jobs:

1. Pin down the CURRENT (buggy) normalizer output and downstream intent
   classification result for every confirmed Cluster B example, so a future
   fix can be verified as changing exactly these values and nothing else
   upstream/downstream of them.

2. Encode the INTENDED (boundary-safe) behavior as `@unittest.expectedFailure`
   tests. These currently fail (as expected — the bug is still present) and
   will start reporting "unexpected success" once Cluster B is actually
   fixed, at which point the `@unittest.expectedFailure` decorator should be
   removed and the test promoted to a normal passing regression test.

No production code is modified or exercised differently than by importing
and calling the existing public normalizer/classifier interfaces.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.nlu.normalizer import TextNormalizer
from chatbot.intent.classifier import IntentClassifier


class TestClusterBNormalizerCorruption(unittest.TestCase):
    """Pins the CURRENT corrupted normalize_with_metadata() output.

    Each case is a short standalone dialect/question word from
    palestinian_dialect.json (لا، مش، كيف، كم، طب، مين، نفسي) being replaced
    even though it only appears embedded inside a longer, unrelated word.
    """

    @classmethod
    def setUpClass(cls):
        cls.normalizer = TextNormalizer()

    def test_la_no_corrupts_farewell_al_salama(self):
        # "لا" (no) -> "no" fires inside "السلامة" (safety/peace), the second
        # half of the farewell phrase "مع السلامة" (goodbye).
        info = self.normalizer.normalize_with_metadata("مع السلامة")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "مع السnoمة")
        self.assertEqual(info["normalized"], "مع السnoمه")

    def test_mish_no_corrupts_amshi_i_can_walk(self):
        # "مش" (not/no) -> "no" fires inside "امشي" (I walk).
        info = self.normalizer.normalize_with_metadata("أقدر امشي")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "أقدر اnoي")
        self.assertEqual(info["normalized"], "اقدر اnoي")

    def test_kaif_how_corrupts_kaifak_how_are_you(self):
        # "كيف" (how) -> "how" fires inside "كيفك" (how are you, colloquial),
        # destroying the exact phrase how_are_you's own keyword list needs.
        info = self.normalizer.normalize_with_metadata("كيفك")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "howك")
        self.assertEqual(info["normalized"], "howك")

    def test_kam_how_much_breaks_travel_time_phrase(self):
        # "كم" (how much/many) -> "how_much" is a whole-word substitution
        # here (not embedded), but it still destroys the multi-word Arabic
        # keyword phrase "كم يستغرق" that travel_time depends on, and
        # introduces the literal substring "how" (via "how_much") that
        # collides with platform_support's generic "how" keyword.
        info = self.normalizer.normalize_with_metadata("كم يستغرق الوصول")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "how_much يستغرق الوصول")
        self.assertEqual(info["normalized"], "how_much يستغرق الوصول")

    def test_kam_how_much_breaks_doctor_fee_phrase(self):
        # Same "كم" -> "how_much" substitution, destroying doctor_fee's own
        # keyword phrase "كم سعر".
        info = self.normalizer.normalize_with_metadata("كم سعر كشف الدكتور")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "how_much سعر كشف الدكتور")
        self.assertEqual(info["normalized"], "how_much سعر كشف الدكتور")

    def test_tib_okay_corrupts_atibbaa_doctors_plural(self):
        # "طب" (medicine root, from a "طيب"/"okay" style dialect entry) ->
        # "okay" fires inside "أطباء" (doctors, plural) — corrupting a core
        # clinical vocabulary word, not just a colloquial phrase.
        info = self.normalizer.normalize_with_metadata("من هم الأطباء في العيادة")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "من هم الأokayاء في العيادة")
        self.assertEqual(info["normalized"], "من هم الاokayاء في العياده")

    def test_meen_who_corrupts_altaameen_insurance(self):
        # "مين" (who) -> "who" fires inside "التأمين" (the insurance),
        # destroying the word insurance-related intents need to match.
        info = self.normalizer.normalize_with_metadata("هل العيادة تقبل التأمين")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "هل العيادة تقبل التأwho")
        self.assertEqual(info["normalized"], "هل العياده تقبل التاwho")

    def test_nafsi_breathing_corrupts_nafsiya_mental_psychological(self):
        # "نفسي" (breathing-related dialect expression) -> "breathing" fires
        # inside "نفسية" (psychological/mental, as in "مساعدة نفسية" =
        # "psychological help") — an entirely different, unrelated meaning.
        info = self.normalizer.normalize_with_metadata("مساعدة نفسية")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "مساعدة breathingة")
        self.assertEqual(info["normalized"], "مساعده breathingه")


class TestClusterBIntentClassificationImpact(unittest.TestCase):
    """Pins the CURRENT (wrong) end-to-end classify() result caused by the
    normalizer corruption above. These mirror the failing assertions in
    tests/test_nlu_pipeline.py's TestEndToEnd / TestIntentClassifier classes
    (Cluster B failures) but assert the actual buggy value, not the intended
    one, so this file documents reality rather than duplicating those
    failures under a different name.
    """

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_farewell_currently_misclassified_as_no_negation(self):
        result = self.classifier.classify("مع السلامة")
        self.assertEqual(result["intent"], "no_negation")
        self.assertIn("no", result["matched_keywords"])

    def test_walking_route_currently_misclassified_as_no_negation(self):
        result = self.classifier.classify("أقدر امشي")
        self.assertEqual(result["intent"], "no_negation")
        self.assertIn("no", result["matched_keywords"])

    def test_how_are_you_currently_misclassified_as_platform_support(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "platform_support")
        self.assertIn("how", result["matched_keywords"])

    def test_travel_time_currently_misclassified_as_platform_support(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertEqual(result["intent"], "platform_support")
        self.assertIn("how", result["matched_keywords"])

    def test_doctor_fee_currently_falls_back_to_unknown(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertEqual(result["intent"], "unknown")

    def test_clinic_doctors_currently_falls_back_to_unknown(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertEqual(result["intent"], "unknown")

    def test_clinic_insurance_currently_misclassified_as_find_doctor(self):
        result = self.classifier.classify("هل العيادة تقبل التأمين")
        self.assertEqual(result["intent"], "find_doctor")
        self.assertIn("عيادة", result["matched_keywords"])

    def test_mental_health_currently_misclassified_as_platform_support(self):
        result = self.classifier.classify("مساعدة نفسية")
        self.assertEqual(result["intent"], "platform_support")
        self.assertIn("مساعدة", result["matched_keywords"])


class TestClusterBIntendedBoundarySafeBehavior(unittest.TestCase):
    """Encodes the INTENDED, boundary-safe behavior for the same inputs.

    Marked @unittest.expectedFailure: these currently fail (the bug is still
    present) and are expected to. Once Cluster B is fixed, each of these will
    report "unexpected success" — at that point remove the decorator and this
    class becomes the real regression test for the fix.
    """

    @classmethod
    def setUpClass(cls):
        cls.normalizer = TextNormalizer()
        cls.classifier = IntentClassifier()

    @unittest.expectedFailure
    def test_al_salama_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("مع السلامة")
        self.assertNotIn("no", info["normalized"])
        self.assertIn("السلامة", info["normalized"])

    @unittest.expectedFailure
    def test_farewell_should_classify_as_bye(self):
        result = self.classifier.classify("مع السلامة")
        self.assertEqual(result["intent"], "bye")

    @unittest.expectedFailure
    def test_amshi_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("أقدر امشي")
        self.assertNotIn("no", info["normalized"])

    @unittest.expectedFailure
    def test_walking_route_should_classify_as_walking_route_or_show_route(self):
        result = self.classifier.classify("أقدر امشي")
        self.assertIn(result["intent"], ["walking_route", "show_route"])

    @unittest.expectedFailure
    def test_kaifak_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("كيفك")
        self.assertNotIn("how", info["normalized"])

    @unittest.expectedFailure
    def test_how_are_you_should_classify_correctly(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "how_are_you")

    @unittest.expectedFailure
    def test_travel_time_phrase_should_survive_intact(self):
        info = self.normalizer.normalize_with_metadata("كم يستغرق الوصول")
        self.assertNotIn("how_much", info["normalized"])

    @unittest.expectedFailure
    def test_travel_time_should_classify_correctly(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertIn(result["intent"], ["travel_time", "show_route"])

    @unittest.expectedFailure
    def test_doctor_fee_should_classify_correctly(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertIn(result["intent"], ["doctor_fee", "find_doctor"])

    @unittest.expectedFailure
    def test_atibbaa_doctors_plural_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("من هم الأطباء في العيادة")
        self.assertNotIn("okay", info["normalized"])

    @unittest.expectedFailure
    def test_clinic_doctors_should_classify_correctly(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertIn(result["intent"], ["clinic_doctors", "clinic_info"])

    @unittest.expectedFailure
    def test_altaameen_insurance_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("هل العيادة تقبل التأمين")
        self.assertNotIn("who", info["normalized"])

    @unittest.expectedFailure
    def test_clinic_insurance_should_classify_correctly(self):
        result = self.classifier.classify("هل العيادة تقبل التأمين")
        self.assertIn(result["intent"], ["clinic_insurance", "insurance_query"])

    @unittest.expectedFailure
    def test_nafsiya_mental_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("مساعدة نفسية")
        self.assertNotIn("breathing", info["normalized"])

    @unittest.expectedFailure
    def test_mental_health_should_classify_correctly(self):
        result = self.classifier.classify("مساعدة نفسية")
        self.assertIn(result["intent"], ["mental_health", "general_medical_question"])


if __name__ == "__main__":
    unittest.main()
