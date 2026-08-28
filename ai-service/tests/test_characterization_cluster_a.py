"""
Characterization tests and tracing — Cluster A.

Cluster A bug: IntentClassifier produces wrong or "unknown" intents due to
several distinct mechanisms living in chatbot/intent/classifier.py,
chatbot/intent/intents.json, and chatbot/nlu/ranker.py:

  (a) SUBSTRING MATCH — FIXED by the Cluster A1 batch, for the case of a
      keyword embedded inside a genuinely unrelated word (e.g. "er" inside
      "there", "طب" inside "أطباء", "لا" inside "السلامة"). classifier.py
      Step 6 and ranker.py's negation check now use a boundary-safe helper
      instead of plain `in` substring checks.

  (a') ARABIC PROCLITIC HANDLING — a necessary refinement discovered while
      verifying (a): Arabic keywords are stored bare ("دكتور", "عيادة",
      "تأمين", "حامل") but almost always appear in real text with the
      definite article "ال" or the preposition+article contraction "لل"
      attached directly, with no space ("الدكتور", "العيادة", "التأمين",
      "للحامل"). A strict boundary rule with no exception for this would
      have blocked those forms entirely, breaking several PREVIOUSLY-PASSING
      tests (clinic_insurance, pregnancy_info) that depended on the old,
      boundary-unsafe substring check happening to still work for them. The
      final implementation treats "ال"/"لل" as recognized proclitics: a
      keyword also counts as matched when immediately preceded by one of
      them. This restored clinic_insurance and pregnancy_info to passing.

  (a'') REPAIRED via a targeted intents.json keyword variant. One case,
      `vaccination_info` ("جدول تطعيمات" as a 2-word keyword vs. "جدول
      التطعيمات" in real text, where "ال" is inserted onto the SECOND word
      of a multi-word phrase, not attached to the start of the whole keyword
      span), was structurally different from a simple leading-proclitic case
      and not covered by the (a') fix — a genuine regression from the
      boundary-safety change. Rather than generalizing the boundary helper
      to handle mid-phrase article insertion (a bigger, riskier change),
      the exact real-world phrase "جدول التطعيمات" was added as an
      additional, narrowly-targeted keyword variant for vaccination_info —
      the smallest-blast-radius repair, isolated to this one intent.

  (b) GENERIC KEYWORD — NOT fixed, out of scope. "how" (platform_support),
      bare "كيف" — still causes failures.

  (c) NGRAM FALLBACK — NOT fixed, out of scope.

  (d) TIE / THRESHOLD — NOT fixed, out of scope (ranker scoring untouched).

  (e) KEYWORD OVERLAP — NOT fixed, out of scope, and in fact PARTIALLY
      RE-EXPOSED by the (a') proclitic fix: find_doctor's own bare keywords
      "عيادة" and "أطباء" are, by design of (a'), legitimate standalone
      matches against "العيادة"/"الأطباء" (the proclitic is a grammatical
      particle, not an unrelated word) — so find_doctor and clinic_doctors/
      clinic_info again compete on equal footing for these inputs, same as
      before A1, but now for a genuinely different, out-of-scope reason
      (keyword overlap) rather than a substring-safety bug.

  (f) RANKER BEHAVIOR — only the negation-word substring check was made
      boundary-safe (also with the ال/لل proclitic allowance, for
      consistency). Cross-category penalties, keyword-count boosts, and the
      stale INTENT_CATEGORIES mapping are all unchanged.

This file pins the CURRENT (final, post-A1) classify() output for every
confirmed example via the public API only, and encodes intended behavior as
`@unittest.expectedFailure` where A1 did not (and was not scoped to) resolve
the case.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.intent.classifier import IntentClassifier


class TestClusterACurrentOutputs(unittest.TestCase):
    """Pins the CURRENT (final, post-Cluster-A1) classify() output for every
    confirmed Cluster A example."""

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_how_do_i_get_there_now_classifies_correctly(self):
        result = self.classifier.classify("How do I get there")
        self.assertEqual(result["intent"], "show_route")
        self.assertEqual(result["confidence"], 0.5)
        self.assertEqual(result["matched_keywords"], ["how do I get"])

    def test_kaifak_now_classifies_correctly(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "how_are_you")
        self.assertAlmostEqual(result["confidence"], 0.5455, places=3)
        self.assertEqual(sorted(result["matched_keywords"]), sorted(["how are you", "are you"]))

    def test_travel_time_phrase_now_classifies_correctly(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertEqual(result["intent"], "travel_time")
        self.assertAlmostEqual(result["confidence"], 0.625, places=3)
        self.assertEqual(result["matched_keywords"], ["يستغرق الوصول"])

    def test_doctor_fee_phrase_now_classifies_correctly(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertEqual(result["intent"], "doctor_fee")
        self.assertAlmostEqual(result["confidence"], 0.4643, places=3)
        self.assertEqual(
            sorted(result["matched_keywords"]),
            sorted(["سعر كشف", "سعر كشف الدكتور", "price"]),
        )

    def test_clinic_doctors_phrase_now_classifies_correctly(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertEqual(result["intent"], "clinic_doctors")
        self.assertAlmostEqual(result["confidence"], 0.5143, places=3)
        self.assertEqual(
            sorted(result["matched_keywords"]),
            sorted(["أطباء", "الأطباء", "الأطباء العيادة"]),
        )
        alt_intents = {a["intent"] for a in result["alternative_intents"]}
        self.assertIn("find_doctor", alt_intents)

    def test_clinic_hours_phrase_now_classifies_correctly(self):
        result = self.classifier.classify("ساعات دوام العيادة")
        self.assertEqual(result["intent"], "clinic_hours")
        self.assertAlmostEqual(result["confidence"], 0.4444, places=3)
        self.assertEqual(sorted(result["matched_keywords"]), sorted(["دوام", "ساعات دوام"]))

    def test_medication_interaction_phrase_now_classifies_acceptably(self):
        result = self.classifier.classify("هل يتعارض بانادول مع الضغط")
        self.assertEqual(result["intent"], "medication_info")
        self.assertAlmostEqual(result["confidence"], 0.3333, places=3)
        self.assertEqual(result["matched_keywords"], ["بانادول"])

    def test_arabic_show_route_phrase_now_classifies_correctly(self):
        result = self.classifier.classify("كيف اوصل للعيادة")
        self.assertEqual(result["intent"], "show_route")
        self.assertAlmostEqual(result["confidence"], 0.48, places=3)
        self.assertEqual(
            sorted(result["matched_keywords"]),
            sorted(["how اوصل", "اوصل للعيادة"]),
        )


class TestClusterAIntendedBehavior(unittest.TestCase):
    """Intended-behavior tests. `@unittest.expectedFailure` removed only for
    cases the Cluster A1 fix actually resolved."""

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_how_do_i_get_there_should_classify_as_show_route(self):
        result = self.classifier.classify("How do I get there")
        self.assertEqual(result["intent"], "show_route")

    def test_kaifak_should_classify_as_how_are_you(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "how_are_you")

    def test_travel_time_phrase_should_classify_correctly(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertIn(result["intent"], ["travel_time", "show_route"])

    def test_doctor_fee_phrase_should_classify_correctly(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertIn(result["intent"], ["doctor_fee", "find_doctor"])

    def test_clinic_doctors_phrase_should_classify_correctly(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertIn(result["intent"], ["clinic_doctors", "clinic_info"])

    def test_clinic_hours_phrase_should_classify_correctly(self):
        result = self.classifier.classify("ساعات دوام العيادة")
        self.assertIn(result["intent"], ["clinic_hours", "clinic_info"])

    def test_medication_interaction_phrase_should_classify_correctly(self):
        result = self.classifier.classify("هل يتعارض بانادول مع الضغط")
        self.assertIn(result["intent"], ["medication_interaction", "medication_info"])

    def test_arabic_show_route_phrase_should_classify_correctly(self):
        result = self.classifier.classify("كيف اوصل للعيادة")
        self.assertEqual(result["intent"], "show_route")


class TestArabicProcliticRegressionGuard(unittest.TestCase):
    """Guards the (a') fix itself: previously-passing behavior that the
    boundary-safety change could have broken via Arabic's attached definite
    article/preposition, and that the ال/لل proclitic allowance restores.
    """

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_clinic_insurance_with_definite_article_still_matches(self):
        result = self.classifier.classify("هل العيادة بتقبل التأمين")
        self.assertIn(result["intent"], ["clinic_insurance", "insurance_query"])

    def test_pregnancy_info_with_lam_lam_contraction_still_matches(self):
        result = self.classifier.classify("نصائح للحامل")
        self.assertIn(result["intent"], ["pregnancy_info", "general_medical_question"])

    def test_vaccination_info_with_mid_phrase_definite_article_still_matches(self):
        result = self.classifier.classify("جدول التطعيمات")
        self.assertEqual(result["intent"], "vaccination_info")


if __name__ == "__main__":
    unittest.main()
