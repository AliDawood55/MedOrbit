"""
Characterization tests — Virtual Doctor clinical safety/routing gaps.

Pins the CURRENT (imperfect) behavior of three live-verified gaps found while
producing docs/virtual_doctor_clinical_voice_improvement_plan.md, before any
fix is implemented:

  A. Arabic thunderclap/sudden-severe-headache is not flagged by
     MedicalSafetyLayer, even though the product's own target red-flag list
     names it explicitly.
  B. The Arabic hematuria phrase "دم بالبول" is not flagged either, while the
     equivalent English concept ("blood in urine") already has a pattern in
     URGENT_PATTERNS_AR — an asymmetry, not a missing concept.
  C. EntityExtractor correctly extracts "stomach_ache" from the Palestinian
     dialect phrase "بطني بوجعني من اليمين" (right-sided belly pain), but
     flows/abdominal_pain.json's match_symptoms only accepts "stomach_pain",
     so interview_engine._detect_chief_complaint() routes it to "generic"
     instead of "abdominal_pain" despite a real symptom being detected.

These tests intentionally assert TODAY'S behavior, including the gaps
themselves — they are expected to PASS against current code and are meant to
start FAILING (by design) once each gap is fixed, at which point the
assertion describing the gap should be flipped to the corrected expectation.
No production code is changed here. No network, Ollama, or database access
occurs anywhere in this file: MedicalSafetyLayer, EntityExtractor, and
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
# A. Arabic thunderclap / sudden-severe-headache safety gap
# ===========================================================================

class TestArabicThunderclapHeadacheSafetyGapCurrentBehavior(unittest.TestCase):
    """CURRENT GAP: a sudden, severe headache ("صداع شديد فجأة" — the classic
    thunderclap/SAH red-flag pattern this project's own audit calls out) does
    not trip either the emergency or the urgent pattern lists today."""

    def setUp(self):
        self.safety = MedicalSafetyLayer()

    def test_sudden_severe_headache_is_not_escalated_today(self):
        result = self.safety.check("صداع شديد فجأة")

        # This is the gap: a thunderclap headache should be at least
        # "urgent", but URGENT_PATTERNS_AR's severity modifier is anchored to
        # "الم"/"وجع" roots, not "صداع", so this phrase matches nothing.
        self.assertEqual(result["severity"], "normal")
        self.assertFalse(result["is_emergency"])
        self.assertFalse(result["is_urgent"])
        self.assertEqual(result["matched_patterns"], [])

    def test_headache_with_nausea_also_not_escalated_today(self):
        """Companion case from the same audit: severe headache + nausea is
        correctly recognized as symptoms by the extractor (see the audit's
        Section 15) but is likewise not escalated by the safety layer."""
        result = self.safety.check("عندي صداع شديد مع غثيان")

        self.assertEqual(result["severity"], "normal")

    def test_contrast_the_generic_severe_pain_pattern_does_escalate(self):
        """Sanity check that URGENT_PATTERNS_AR is not broken outright: the
        generic "severe pain" root (الم شديد) DOES escalate today. This
        isolates gap A to a vocabulary/coverage gap (no pattern anchored on
        "صداع") rather than a wholesale failure of the urgent pattern list."""
        result = self.safety.check("الم شديد")

        self.assertEqual(result["severity"], "urgent")


# ===========================================================================
# B. Arabic hematuria safety gap (asymmetric with the existing English one)
# ===========================================================================

class TestArabicHematuriaSafetyGapCurrentBehavior(unittest.TestCase):
    """CURRENT GAP: "دم بالبول" / "دم في البول" (blood in urine) has no
    Arabic pattern in URGENT_PATTERNS_AR, even though the English concept
    ("blood in urine") already does — see the contrast test below."""

    def setUp(self):
        self.safety = MedicalSafetyLayer()

    def test_arabic_hematuria_phrase_is_not_escalated_today(self):
        result = self.safety.check("عندي دم بالبول")

        self.assertEqual(result["severity"], "normal")
        self.assertFalse(result["is_urgent"])
        self.assertEqual(result["matched_patterns"], [])

    def test_arabic_hematuria_alternate_phrasing_is_also_not_escalated_today(self):
        result = self.safety.check("دم في البول")

        self.assertEqual(result["severity"], "normal")

    def test_dysuria_alone_is_also_not_recognized_today(self):
        """Companion finding: burning urination has no Arabic safety pattern
        either — reported together with hematuria in the same audit case
        ("عندي حرقان بول ودم بالبول")."""
        result = self.safety.check("عندي حرقان بول ودم بالبول")

        self.assertEqual(result["severity"], "normal")

    def test_contrast_the_english_hematuria_pattern_already_exists(self):
        """This is what makes gap B an ASYMMETRY, not a missing concept:
        URGENT_PATTERNS_AR already contains an English "blood in urine"
        alternative (the "blood in (vomit|stool|urine)" pattern) despite the
        Arabic side having no equivalent."""
        result = self.safety.check("blood in urine")

        self.assertEqual(result["severity"], "urgent")
        self.assertTrue(result["is_urgent"])

    def test_contrast_arabic_blood_in_stool_does_already_escalate(self):
        """Further isolates the gap: the Arabic pattern list DOES cover
        blood in stool ("دم في البراز") — urine is the specific omission,
        not Arabic gastrointestinal bleeding coverage in general."""
        result = self.safety.check("دم في البراز")

        self.assertEqual(result["severity"], "urgent")


# ===========================================================================
# C. stomach_ache vs stomach_pain — dialect-detected symptom routes to the
#    wrong (generic) flow instead of abdominal_pain
# ===========================================================================

class TestStomachAcheVsStomachPainMismatchCurrentBehavior(unittest.TestCase):
    """CURRENT GAP: the Palestinian-dialect layer correctly recognizes
    "بطني بوجعني من اليمين" (right-sided belly pain — a classic appendicitis
    presentation) as a stomach symptom, but under the key "stomach_ache",
    while flows/abdominal_pain.json's match_symptoms only accepts
    "stomach_pain" — so chief-complaint detection silently falls through to
    the generic flow instead of the abdominal-pain-specific one."""

    def setUp(self):
        self.extractor = EntityExtractor()

    def test_dialect_phrase_extracts_stomach_ache_symptom(self):
        entities = self.extractor.extract("بطني بوجعني من اليمين")

        self.assertIn("stomach_ache", entities["symptoms"])

    def test_abdominal_pain_flow_only_declares_stomach_pain_as_a_match_symptom(self):
        """Pins the exact source of the mismatch: the flow's own vocabulary,
        read directly rather than assumed."""
        self.assertEqual(FLOWS["abdominal_pain"]["match_symptoms"], ["stomach_pain"])
        self.assertNotIn("stomach_ache", FLOWS["abdominal_pain"]["match_symptoms"])

    def test_dialect_phrase_therefore_routes_to_generic_not_abdominal_pain(self):
        """The end-to-end consequence: a real, correctly-detected right-sided
        abdominal symptom does not reach the abdominal_pain flow today."""
        entities = self.extractor.extract("بطني بوجعني من اليمين")

        complaint = _detect_chief_complaint(entities)

        self.assertEqual(complaint, "generic")

    def test_contrast_the_formal_msa_phrasing_does_route_correctly(self):
        """Isolates the gap to the dialect-mapped key specifically: the
        formal Modern Standard Arabic phrasing ("وجع بطن", listed verbatim
        in medical_entities.json's stomach_pain vocabulary) already extracts
        the matching "stomach_pain" key and routes correctly today."""
        entities = self.extractor.extract("عندي وجع بطن")

        self.assertIn("stomach_pain", entities["symptoms"])
        self.assertEqual(_detect_chief_complaint(entities), "abdominal_pain")


if __name__ == "__main__":
    unittest.main()
