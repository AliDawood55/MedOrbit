r"""
Characterization tests and tracing — Cluster E (Phase 0).

Cluster E: chatbot/nlu/safety.py's MedicalSafetyLayer contains confirmed
regex defects in EMERGENCY_PATTERNS_AR (a list despite the "_AR" suffix
containing both Arabic and English patterns) that cause false-positive
emergency bypasses. safety.py runs BEFORE intent classification
(classifier.py Step 3, before Step 6's keyword matching), so when it fires,
IntentClassifier.classify() short-circuits entirely and returns
intent="emergency" — the rest of the pipeline (Steps 4-10, all keyword
matching, ranking, etc.) never runs. This is confirmed directly: the early
return branch in classify() reuses safety.check()'s own matched_patterns as
its matched_keywords, so classify()'s output for these inputs is identical
in shape to safety.check()'s own output.

Two independent regex defects are confirmed:

1. The " Cardi" bug — one alternative inside the combined pattern
   `r"( Cardi|heart\s+attack|stroke|severe\s+bleeding)"` is an incomplete
   fragment (almost certainly meant to be something like "cardiac arrest").
   Under re.IGNORECASE, " Cardi" matches any text containing a space
   followed by "cardi" — including inside "cardiologist". The other three
   alternatives in the SAME pattern (heart attack, stroke, severe bleeding)
   are legitimate and must not be touched if only " Cardi" is fixed.

2. The "سم " bug — one alternative inside
   `r"(تسمم|سم\s+|جرعة\s+زائدة)"` (poisoning) is the bare root "سم"
   (poison) followed by `\s+`, with NO left word-boundary. Since "سم" is
   the last two letters of several extremely common, unrelated Arabic
   words — "جسم" (body), "اسم" (name), "رسم" (fee/drawing), "قسم"
   (department/section) — any of those words followed by a space falsely
   triggers a full emergency bypass. This is confirmed to have a materially
   broader blast radius than the one failing test (test_hospital_emergency)
   suggests: "اسم" (name) in particular is asked in virtually every
   onboarding/intake flow.

A third issue, for `test_hospital_emergency` specifically, is NOT a regex
bug: even after fixing the "سم " defect, the pattern
`r"(طوارئ|حالة\s+طارئة|إسعاف|اسعاف)"` still correctly, legitimately matches
"طوارئ" (emergency) in "قسم الطوارئ في المستشفى" ("the emergency department
at the hospital") — a genuine, word-bounded, intentional match. Whether an
informational query naming "the emergency department" as a place should
still trigger the full safety bypass is a product/safety policy question,
not a bug, and is explicitly NOT addressed by this phase.

This phase does NOT fix anything. It only pins current behavior.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.intent.classifier import IntentClassifier


class TestClusterECardiFalsePositive(unittest.TestCase):
    """Pins the confirmed " Cardi" regex defect and the true-emergency
    alternatives in the SAME pattern that must remain protected."""

    @classmethod
    def setUpClass(cls):
        cls.safety = MedicalSafetyLayer()
        cls.classifier = IntentClassifier()

    def test_cardiologist_no_longer_a_false_positive_emergency(self):
        # FIXED by Cluster E1: the broken " Cardi" alternative was replaced
        # with "cardiac\s+arrest". Asking for a cardiologist no longer
        # matches any emergency pattern.
        result = self.safety.check("I need a cardiologist")
        self.assertEqual(result["severity"], "normal")
        self.assertFalse(result["bypass_intent_routing"])
        self.assertEqual(result["matched_patterns"], [])

    def test_cardiologist_no_longer_short_circuits_intent_classification(self):
        # Confirms the normal classification pipeline (Steps 4-10) now runs
        # for this input instead of being short-circuited by safety.py.
        result = self.classifier.classify("I need a cardiologist")
        self.assertNotEqual(result["intent"], "emergency")

    def test_cardiac_arrest_is_protected_by_the_new_alternative(self):
        # The replacement phrase itself must fire — this is the specific,
        # complete phrase " Cardi" was almost certainly meant to represent.
        result = self.safety.check("I think he is in cardiac arrest")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])
        matched = result["matched_patterns"][0]
        self.assertEqual(matched["matched"], "cardiac arrest")
        self.assertEqual(matched["pattern"], r"(cardiac\s+arrest|heart\s+attack|stroke|severe\s+bleeding)")

    def test_true_heart_attack_remains_protected(self):
        # Same combined pattern's "heart\s+attack" alternative — must
        # remain firing after the " Cardi" fragment was replaced.
        result = self.safety.check("I think I am having a heart attack")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])

    def test_true_stroke_remains_protected(self):
        result = self.safety.check("stroke symptoms right now")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])

    def test_true_severe_bleeding_remains_protected(self):
        result = self.safety.check("severe bleeding from a wound")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])


class TestClusterEPoisoningSubstringFalsePositive(unittest.TestCase):
    """Pins the FIXED "سم " regex (now boundary-safe via \\b) and confirms
    the true poisoning/overdose alternatives in the same pattern still
    fire correctly."""

    @classmethod
    def setUpClass(cls):
        cls.safety = MedicalSafetyLayer()

    def test_hospital_emergency_department_now_matches_only_the_legitimate_pattern(self):
        # FIXED by Cluster E2: the "سم " substring bug (embedded in "قسم")
        # no longer fires. Only the legitimate "طوارئ" match remains — this
        # is the pure Cluster I policy question now, not a bug (see
        # TestClusterEHospitalEmergencyPolicyQuestion below).
        result = self.safety.check("قسم الطوارئ في المستشفى")
        self.assertEqual(result["severity"], "emergency")
        patterns_matched = [m["pattern"] for m in result["matched_patterns"]]
        self.assertNotIn(r"(تسمم|\bسم\s+|جرعة\s+زائدة)", patterns_matched)
        self.assertIn(r"(طوارئ|حالة\s+طارئة|إسعاف|اسعاف)", patterns_matched)
        self.assertEqual(len(result["matched_patterns"]), 1)

    def test_body_word_no_longer_a_false_positive_emergency(self):
        # FIXED: "جسم" (body) followed by a space — unrelated to poisoning.
        result = self.safety.check("جسم كامل")
        self.assertEqual(result["severity"], "normal")
        self.assertEqual(result["matched_patterns"], [])

    def test_name_word_no_longer_a_false_positive_emergency(self):
        # FIXED: "اسم" (name) followed by a space — asked in virtually
        # every intake/onboarding flow. This was the highest real-world
        # blast radius of the confirmed false positives.
        result = self.safety.check("اسم كامل")
        self.assertEqual(result["severity"], "normal")
        self.assertEqual(result["matched_patterns"], [])

    def test_fee_or_drawing_word_no_longer_a_false_positive_emergency(self):
        # FIXED: "رسم" (fee/drawing) followed by a space — unrelated to
        # poisoning.
        result = self.safety.check("رسم توضيحي")
        self.assertEqual(result["severity"], "normal")
        self.assertEqual(result["matched_patterns"], [])

    def test_standalone_poison_word_is_still_protected(self):
        # The intended, legitimate use of the bare "سم" alternative — a
        # real standalone poison word — must still fire after the fix.
        result = self.safety.check("سم قاتل")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])
        self.assertEqual(result["matched_patterns"][0]["matched"], "سم ")

    def test_true_poisoning_remains_protected(self):
        # The "تسمم" alternative — a real poisoning word — must remain
        # firing after the fix.
        result = self.safety.check("تسمم غذائي")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])

    def test_true_overdose_remains_protected(self):
        result = self.safety.check("جرعة زائدة من الدواء")
        self.assertEqual(result["severity"], "emergency")
        self.assertTrue(result["bypass_intent_routing"])


class TestClusterEHospitalEmergencyPolicyQuestion(unittest.TestCase):
    """Pins current behavior for the informational-ER-query case, which is
    a policy question, not purely a bug — see module docstring."""

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_hospital_emergency_department_query_currently_bypasses_routing(self):
        # Unchanged by Cluster E2: the "سم " bug (embedded in "قسم") is
        # fixed, but "طوارئ" still legitimately, correctly matches on its
        # own — this is now purely the Cluster I policy question (should an
        # informational query naming the ER as a place be exempted from the
        # bypass?), not a bug. Explicitly out of scope for E1/E2.
        result = self.classifier.classify("قسم الطوارئ في المستشفى")
        self.assertEqual(result["intent"], "emergency")
        self.assertEqual(result["confidence"], 1.0)

    def test_true_arabic_emergency_word_alone_remains_protected(self):
        # The bare word "طوارئ" alone (no "قسم" prefix, so the "سم " bug
        # cannot also be a factor here) — must remain firing after any fix.
        result = self.classifier.classify("طوارئ")
        self.assertEqual(result["intent"], "emergency")


if __name__ == "__main__":
    unittest.main()
