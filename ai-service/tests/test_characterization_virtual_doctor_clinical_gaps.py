"""
Characterization tests — Virtual Doctor clinical safety/routing gaps.

Pins the FIXED behavior of three live-verified gaps addressed by the Virtual
Doctor Clinical Safety Gaps Implementation Batch:

  A. Arabic thunderclap/sudden-severe-headache is now flagged as "urgent" by
     MedicalSafetyLayer (chatbot/nlu/safety.py's URGENT_PATTERNS_AR gained a
     dedicated pattern — "صداع" does not share a root with "الم"/"وجع", so it
     was never covered by the existing generic severe-pain pattern).
  B. The Arabic hematuria phrases "دم بالبول" / "دم في البول" are now flagged
     as "urgent" too, bringing Arabic to parity with the English "blood in
     urine" pattern that already existed.
  C. EntityExtractor correctly extracts "stomach_ache" from the Palestinian
     dialect phrase "بطني بوجعني من اليمين" (right-sided belly pain), and
     flows/abdominal_pain.json's match_symptoms now accepts "stomach_ache"
     alongside the pre-existing "stomach_pain", so
     interview_engine._detect_chief_complaint() routes it to "abdominal_pain"
     instead of falling through to "generic".

These tests were originally written (same file, same test names in most
cases) to pin the PRE-fix behavior — see git history for that version. They
are updated here to assert the corrected, desired behavior post-fix, while
the accompanying contrast tests are kept exactly as before to confirm the fix
did not touch unrelated, already-correct behavior (English hematuria, Arabic
blood-in-stool, the generic severe-pain pattern, and the formal MSA
stomach_pain phrasing). No network, Ollama, or database access occurs
anywhere in this file: MedicalSafetyLayer, EntityExtractor, and
interview_engine._detect_chief_complaint()/FLOWS are all pure/local.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.entities.extractor import EntityExtractor
from chatbot.nlu.safety import MedicalSafetyLayer
from virtual_doctor.interview_engine import FLOWS, _detect_chief_complaint


# ===========================================================================
# A. Arabic thunderclap / sudden-severe-headache safety fix
# ===========================================================================

class TestArabicThunderclapHeadacheSafetyFix(unittest.TestCase):
    """FIXED: a sudden, severe headache ("صداع شديد فجأة" — the classic
    thunderclap/SAH red-flag pattern this project's own audit calls out) now
    escalates to "urgent"."""

    def setUp(self):
        self.safety = MedicalSafetyLayer()

    def test_sudden_severe_headache_is_escalated_urgent(self):
        result = self.safety.check("صداع شديد فجأة")

        self.assertEqual(result["severity"], "urgent")
        self.assertFalse(result["is_emergency"])
        self.assertTrue(result["is_urgent"])
        self.assertEqual(len(result["matched_patterns"]), 1)

    def test_other_sudden_severe_headache_phrasings_are_escalated_urgent(self):
        """The other word-order/synonym variants this batch was asked to
        cover, beyond the single primary phrase above."""
        for phrase in (
            "صداع مفاجئ شديد",
            "صداع شديد ومفاجئ",
            "أسوأ صداع",
            "اسوأ صداع",
        ):
            with self.subTest(phrase=phrase):
                result = self.safety.check(phrase)
                self.assertEqual(result["severity"], "urgent")

    def test_headache_with_nausea_is_not_escalated_by_this_fix(self):
        """"عندي صداع شديد مع غثيان" is severe-but-not-sudden — a real symptom
        (correctly recognized by the extractor, per the audit's Section 15)
        that this narrowly-scoped fix does not claim to escalate, since it
        does not match the sudden/thunderclap wording this batch targeted."""
        result = self.safety.check("عندي صداع شديد مع غثيان")

        self.assertEqual(result["severity"], "normal")

    def test_contrast_the_generic_severe_pain_pattern_still_escalates(self):
        """Sanity check that the pre-existing generic "severe pain" root
        (الم شديد) is unchanged by this batch."""
        result = self.safety.check("الم شديد")

        self.assertEqual(result["severity"], "urgent")

    def test_contrast_bare_headache_alone_remains_normal(self):
        """The new pattern is anchored to severity+suddenness, not to the
        word "صداع" alone — an ordinary headache report must not become
        urgent as a side effect of this fix."""
        result = self.safety.check("عندي صداع")

        self.assertEqual(result["severity"], "normal")


# ===========================================================================
# B. Arabic hematuria safety fix (brings Arabic to parity with English)
# ===========================================================================

class TestArabicHematuriaSafetyFix(unittest.TestCase):
    """FIXED: "دم بالبول" / "دم في البول" (blood in urine) now escalate to
    "urgent" in Arabic, matching the English "blood in urine" pattern that
    already existed."""

    def setUp(self):
        self.safety = MedicalSafetyLayer()

    def test_arabic_hematuria_phrase_is_escalated_urgent(self):
        result = self.safety.check("عندي دم بالبول")

        self.assertEqual(result["severity"], "urgent")
        self.assertTrue(result["is_urgent"])
        self.assertEqual(len(result["matched_patterns"]), 1)

    def test_arabic_hematuria_alternate_phrasing_is_escalated_urgent(self):
        result = self.safety.check("دم في البول")

        self.assertEqual(result["severity"], "urgent")

    def test_other_hematuria_phrasings_are_escalated_urgent(self):
        for phrase in ("بول مع دم", "تبول دم"):
            with self.subTest(phrase=phrase):
                result = self.safety.check(phrase)
                self.assertEqual(result["severity"], "urgent")

    def test_dysuria_plus_hematuria_combined_phrase_is_escalated_urgent(self):
        """The combined case from the same audit ("عندي حرقان بول ودم
        بالبول") now escalates because of the hematuria half — dysuria
        (burning urination) alone still has no dedicated pattern, which this
        narrowly-scoped batch did not add."""
        result = self.safety.check("عندي حرقان بول ودم بالبول")

        self.assertEqual(result["severity"], "urgent")

    def test_contrast_the_english_hematuria_pattern_is_unchanged(self):
        result = self.safety.check("blood in urine")

        self.assertEqual(result["severity"], "urgent")
        self.assertTrue(result["is_urgent"])

    def test_contrast_arabic_blood_in_stool_is_unchanged(self):
        result = self.safety.check("دم في البراز")

        self.assertEqual(result["severity"], "urgent")

    def test_contrast_bare_blood_word_alone_remains_normal(self):
        """The new pattern is anchored to a urine-context word every time —
        the bare word "دم" alone must not become urgent as a side effect."""
        result = self.safety.check("دم")

        self.assertEqual(result["severity"], "normal")


# ===========================================================================
# C. stomach_ache vs stomach_pain — routing fix
# ===========================================================================

class TestStomachAcheVsStomachPainRoutingFix(unittest.TestCase):
    """FIXED: flows/abdominal_pain.json's match_symptoms now accepts
    "stomach_ache" alongside "stomach_pain", so the Palestinian-dialect
    phrase "بطني بوجعني من اليمين" (right-sided belly pain — a classic
    appendicitis presentation) correctly routes to the abdominal_pain flow."""

    def setUp(self):
        self.extractor = EntityExtractor()

    def test_dialect_phrase_extracts_stomach_ache_symptom(self):
        entities = self.extractor.extract("بطني بوجعني من اليمين")

        self.assertIn("stomach_ache", entities["symptoms"])

    def test_abdominal_pain_flow_now_declares_both_stomach_keys(self):
        """Pins the exact fix: stomach_ache was added, stomach_pain was kept."""
        self.assertIn("stomach_pain", FLOWS["abdominal_pain"]["match_symptoms"])
        self.assertIn("stomach_ache", FLOWS["abdominal_pain"]["match_symptoms"])

    def test_dialect_phrase_now_routes_to_abdominal_pain(self):
        """The end-to-end fix: a real, correctly-detected right-sided
        abdominal symptom now reaches the abdominal_pain flow."""
        entities = self.extractor.extract("بطني بوجعني من اليمين")

        complaint = _detect_chief_complaint(entities)

        self.assertEqual(complaint, "abdominal_pain")

    def test_contrast_the_formal_msa_phrasing_still_routes_correctly(self):
        """The pre-existing, already-correct path (formal MSA "وجع بطن",
        extracting "stomach_pain") is unchanged by this fix."""
        entities = self.extractor.extract("عندي وجع بطن")

        self.assertIn("stomach_pain", entities["symptoms"])
        self.assertEqual(_detect_chief_complaint(entities), "abdominal_pain")

    def test_contrast_unrelated_flows_are_unchanged(self):
        """Only abdominal_pain's match_symptoms was touched by this batch."""
        self.assertEqual(FLOWS["headache"]["match_symptoms"], ["headache"])
        self.assertEqual(FLOWS["chest_pain"]["match_symptoms"], ["chest_pain"])
        self.assertEqual(FLOWS["fever_cough"]["match_symptoms"], ["fever", "cough"])
        self.assertEqual(FLOWS["rash"]["match_symptoms"], ["skin_rash"])


if __name__ == "__main__":
    unittest.main()
