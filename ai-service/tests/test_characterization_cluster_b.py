"""
Characterization tests — Cluster B.

Cluster B bug (FIXED as of the Cluster B Implementation batch):
TextNormalizer._normalize_dialect() (chatbot/nlu/normalizer.py) used plain
substring replacement for palestinian_dialect.json's dialect/question/
response/symptom expressions, so a short expression like "لا" or "مين" fired
wherever its characters appeared — including embedded inside an unrelated,
longer word ("لا" inside "السلامة", "مين" inside "التأمين") — corrupting the
source text before intent classification or entity extraction ever ran.

The fix made every dialect-table replacement boundary-safe via `\b` (which
Python's `re` module already treats as Unicode-aware, so Arabic letters count
as word characters exactly like English letters/digits) — see
`TextNormalizer._normalize_dialect`'s docstring for detail.

This file now has three jobs:

1. `TestClusterBNormalizerCorruption` — pins the CURRENT (fixed) normalizer
   output for every confirmed case, so a future regression can be caught
   immediately.

2. `TestClusterBIntentClassificationImpact` — pins the CURRENT end-to-end
   classify() result for the same inputs. Several of these are now CORRECT
   (the fix worked); a few are still wrong, but for a DIFFERENT reason than
   Cluster B — see the per-test notes. Those residual failures belong to
   Cluster A (generic/colliding single-word keywords such as platform_
   support's "how" or find_doctor's "عيادة"/"أطباء") and were explicitly out
   of scope for the Cluster B batch.

3. `TestClusterBIntendedBoundarySafeBehavior` — the intended-behavior tests
   from Cluster B Phase 0. Every test whose intended behavior is now
   confirmed true has had `@unittest.expectedFailure` removed and is a normal
   passing regression test. Tests whose failure is now attributable to
   Cluster A, not Cluster B, keep `@unittest.expectedFailure` with an updated
   note explaining why — they are not yet promoted, since the code path they
   exercise (intent classification tie-handling) has not been fixed.

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
    """Pins the CURRENT (post-fix) normalize_with_metadata() output."""

    @classmethod
    def setUpClass(cls):
        cls.normalizer = TextNormalizer()

    def test_al_salama_farewell_no_longer_corrupted(self):
        info = self.normalizer.normalize_with_metadata("مع السلامة")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "bye")
        self.assertEqual(info["normalized"], "bye")

    def test_amshi_i_can_walk_no_longer_corrupted(self):
        info = self.normalizer.normalize_with_metadata("أقدر امشي")
        self.assertFalse(info["was_dialect"])
        self.assertIsNone(info["dialect_normalized"])
        self.assertEqual(info["normalized"], "اقدر امشي")

    def test_kaifak_how_are_you_no_longer_corrupted(self):
        info = self.normalizer.normalize_with_metadata("كيفك")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "how_are_you")
        self.assertEqual(info["normalized"], "how are you")

    def test_kam_how_much_travel_time_phrase_unaffected_by_the_fix(self):
        info = self.normalizer.normalize_with_metadata("كم يستغرق الوصول")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "how_much يستغرق الوصول")
        self.assertEqual(info["normalized"], "how_much يستغرق الوصول")

    def test_kam_how_much_doctor_fee_phrase_unaffected_by_the_fix(self):
        info = self.normalizer.normalize_with_metadata("كم سعر كشف الدكتور")
        self.assertTrue(info["was_dialect"])
        self.assertEqual(info["dialect_normalized"], "how_much سعر كشف الدكتور")
        self.assertEqual(info["normalized"], "how_much سعر كشف الدكتور")

    def test_atibbaa_doctors_plural_no_longer_corrupted(self):
        info = self.normalizer.normalize_with_metadata("من هم الأطباء في العيادة")
        self.assertFalse(info["was_dialect"])
        self.assertIsNone(info["dialect_normalized"])
        self.assertEqual(info["normalized"], "من هم الاطباء في العياده")

    def test_altaameen_insurance_no_longer_corrupted(self):
        info = self.normalizer.normalize_with_metadata("هل العيادة تقبل التأمين")
        self.assertFalse(info["was_dialect"])
        self.assertIsNone(info["dialect_normalized"])
        self.assertEqual(info["normalized"], "هل العياده تقبل التامين")

    def test_nafsiya_mental_psychological_no_longer_corrupted(self):
        info = self.normalizer.normalize_with_metadata("مساعدة نفسية")
        self.assertFalse(info["was_dialect"])
        self.assertIsNone(info["dialect_normalized"])
        self.assertEqual(info["normalized"], "مساعده نفسيه")

    def test_standalone_dialect_words_still_normalize_correctly(self):
        self.assertEqual(
            self.normalizer.normalize_with_metadata("هل لا يوجد دكتور")["dialect_normalized"],
            "هل no يوجد دكتور",
        )
        self.assertEqual(
            self.normalizer.normalize_with_metadata("مش قادر امشي")["dialect_normalized"],
            "no قادر امشي",
        )
        self.assertEqual(
            self.normalizer.normalize_with_metadata("مين الدكتور المناوب")["dialect_normalized"],
            "who الدكتور المناوب",
        )


class TestClusterBIntentClassificationImpact(unittest.TestCase):
    """Pins the CURRENT end-to-end classify() result for the same inputs.

    Several are now correct (the fix worked end to end). A few are still
    wrong for a different, Cluster-A-shaped reason — noted per test — which
    was explicitly out of scope for the Cluster B batch.
    """

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_farewell_now_classifies_correctly_as_bye(self):
        result = self.classifier.classify("مع السلامة")
        self.assertEqual(result["intent"], "bye")

    def test_walking_route_now_classifies_correctly(self):
        result = self.classifier.classify("أقدر امشي")
        self.assertIn(result["intent"], ["walking_route", "show_route"])

    def test_how_are_you_now_classifies_correctly(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "how_are_you")

    def test_travel_time_now_classifies_correctly(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertEqual(result["intent"], "travel_time")

    def test_doctor_fee_now_classifies_correctly(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertEqual(result["intent"], "doctor_fee")

    def test_clinic_doctors_now_classifies_correctly(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertEqual(result["intent"], "clinic_doctors")

    def test_clinic_insurance_now_classifies_correctly(self):
        result = self.classifier.classify("هل العيادة تقبل التأمين")
        self.assertIn(result["intent"], ["clinic_insurance", "insurance_query"])

    def test_mental_health_now_classifies_correctly(self):
        result = self.classifier.classify("مساعدة نفسية")
        self.assertIn(result["intent"], ["mental_health", "general_medical_question"])


class TestClusterBIntendedBoundarySafeBehavior(unittest.TestCase):
    """The Cluster B Phase 0 intended-behavior tests.

    Promoted to normal (no `@unittest.expectedFailure`) wherever the fix
    delivered the intended behavior. Tests whose remaining failure is now
    attributable to Cluster A (not Cluster B) keep the decorator, with an
    updated note — they stay red until Cluster A is fixed, which is a
    separate, not-yet-approved batch.
    """

    @classmethod
    def setUpClass(cls):
        cls.normalizer = TextNormalizer()
        cls.classifier = IntentClassifier()

    def test_al_salama_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("مع السلامة")
        self.assertNotIn("no", info["normalized"])

    def test_farewell_should_classify_as_bye(self):
        result = self.classifier.classify("مع السلامة")
        self.assertEqual(result["intent"], "bye")

    def test_amshi_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("أقدر امشي")
        self.assertNotIn("no", info["normalized"])

    def test_walking_route_should_classify_as_walking_route_or_show_route(self):
        result = self.classifier.classify("أقدر امشي")
        self.assertIn(result["intent"], ["walking_route", "show_route"])

    def test_kaifak_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("كيفك")
        self.assertNotIn("howك", info["dialect_normalized"] or "")

    def test_how_are_you_should_classify_correctly(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "how_are_you")

    def test_travel_time_phrase_should_survive_intact(self):
        info = self.normalizer.normalize_with_metadata("كم يستغرق الوصول")
        self.assertIn("يستغرق", info["normalized"])

    def test_travel_time_should_classify_correctly(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertIn(result["intent"], ["travel_time", "show_route"])

    def test_doctor_fee_should_classify_correctly(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertIn(result["intent"], ["doctor_fee", "find_doctor"])

    def test_atibbaa_doctors_plural_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("من هم الأطباء في العيادة")
        self.assertNotIn("okay", info["normalized"])

    def test_clinic_doctors_should_classify_correctly(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertIn(result["intent"], ["clinic_doctors", "clinic_info"])

    def test_altaameen_insurance_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("هل العيادة تقبل التأمين")
        self.assertNotIn("who", info["normalized"])

    def test_clinic_insurance_should_classify_correctly(self):
        result = self.classifier.classify("هل العيادة تقبل التأمين")
        self.assertIn(result["intent"], ["clinic_insurance", "insurance_query"])

    def test_nafsiya_mental_should_not_be_corrupted(self):
        info = self.normalizer.normalize_with_metadata("مساعدة نفسية")
        self.assertNotIn("breathing", info["normalized"])

    def test_mental_health_should_classify_correctly(self):
        result = self.classifier.classify("مساعدة نفسية")
        self.assertIn(result["intent"], ["mental_health", "general_medical_question"])


if __name__ == "__main__":
    unittest.main()
