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

    def test_hospital_emergency_department_no_longer_matches_the_poison_bug(self):
        # FIXED by Cluster E2: the "سم " substring bug (embedded in "قسم")
        # no longer fires for this input. Separately, Cluster I's
        # informational-ER-place exemption (see
        # TestClusterEHospitalEmergencyPolicyQuestion below) means the
        # "طوارئ" match is now also exempted at the safety.py layer for
        # this specific place-naming phrasing — so safety.check() itself
        # now returns "normal" with no matched patterns at all.
        result = self.safety.check("قسم الطوارئ في المستشفى")
        self.assertEqual(result["severity"], "normal")
        self.assertEqual(result["matched_patterns"], [])

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
    """Pins the FIXED behavior for the informational-ER-query case.

    Cluster I implemented the approved policy exemption at the safety.py
    layer (MedicalSafetyLayer.check() returns severity="normal" for this
    input — see TestClusterEPoisoningSubstringFalsePositive above).
    Cluster I2 closed the remaining gap: classifier.py's own, independent
    Step 9 override (`if scores["emergency"] >= 1.0: return emergency`)
    now has the same narrow exemption
    (IntentClassifier._is_informational_er_place_query), mirroring
    safety.py's helper. When the exemption applies, the "emergency" intent
    is removed from scoring entirely and normal ranking decides the
    result — which now correctly lands on hospital_emergency, using that
    intent's own pre-existing keywords ("طوارئ" + "قسم الطوارئ"), with no
    intents.json change required.
    """

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_hospital_emergency_department_query_now_classifies_correctly(self):
        # FIXED by Cluster I2: classify() no longer force-returns
        # "emergency" for this input. hospital_emergency's own existing
        # keywords ("طوارئ", "قسم الطوارئ") provide enough signal to win
        # normal ranking outright once the Step 9 override stops
        # short-circuiting before ranking runs.
        result = self.classifier.classify("قسم الطوارئ في المستشفى")
        self.assertEqual(result["intent"], "hospital_emergency")
        self.assertAlmostEqual(result["confidence"], 0.5854, places=3)
        self.assertEqual(sorted(result["matched_keywords"]), sorted(["طوارئ", "قسم الطوارئ"]))

    def test_true_arabic_emergency_word_alone_remains_protected(self):
        # The bare word "طوارئ" alone (no "قسم" prefix) — must remain
        # firing after the fix, since the exemption only applies to the
        # department-as-place phrasing, never to the bare word by itself.
        result = self.classifier.classify("طوارئ")
        self.assertEqual(result["intent"], "emergency")

    def test_symptom_reported_at_er_place_still_forces_emergency(self):
        # A real symptom co-occurring with the ER-place phrasing must still
        # force emergency — the exemption only fires when "طوارئ" is the
        # SOLE matched emergency keyword. Here safety.py's own bypass fires
        # first (severe bleeding is its own protected pattern), so this
        # never even reaches classifier.py's Step 9 exemption logic.
        result = self.classifier.classify("عندي نزيف شديد بقسم الطوارئ")
        self.assertEqual(result["intent"], "emergency")


if __name__ == "__main__":
    unittest.main()
