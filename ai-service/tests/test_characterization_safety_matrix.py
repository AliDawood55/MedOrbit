"""
Characterization of the CURRENT safety behaviour, written before Phase 3 adds
any symbolic safety rule.

Phase 3 introduces a second source of urgency. The only way that is a
consolidation rather than a rewrite is if today's answer is written down first
and then required to survive — including, especially, the cases that must stay
NON-urgent.

THE PINNED NEGATIVES ARE THE POINT OF THIS FILE
-----------------------------------------------
The extractor emits ['headache'] for a bare headache and ['headache','nausea']
for headache with nausea, and MedicalSafetyLayer rates both `normal`. So any
symbolic rule keyed on `headache` alone — or on headache plus a common
associated symptom — would escalate a case this system has deliberately pinned
as routine. TestPinnedNegatives is what stops that being introduced by
accident, and it is checked against the symbolic engine too in
test_symbolic_safety_phase3.py.

No Prolog here. This is the legacy baseline, and it must read the same before
and after Phase 3.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.entities.extractor import EntityExtractor
from chatbot.medical.symptom_engine import SymptomSpecialtyEngine
from chatbot.nlu.safety import MedicalSafetyLayer
from virtual_doctor import interview_engine, reasoning

_extractor = EntityExtractor()


def severity_of(text, lang="ar"):
    return interview_engine._check_safety(text, lang)["severity"]


def symptoms_of(text):
    return sorted(_extractor.extract(text).get("symptoms") or [])


# The matrix, as recorded from the running system. (case, text, lang,
# expected MedicalSafetyLayer severity, expected extractor symptoms)
SAFETY_MATRIX = [
    ("thunderclap headache", "عندي صداع شديد فجأة", "ar", "urgent", ["headache"]),
    ("thunderclap alt 1", "صداع مفاجئ شديد", "ar", "urgent", ["headache"]),
    ("thunderclap alt 2", "صداع شديد ومفاجئ", "ar", "urgent", ["headache"]),
    ("worst headache", "أسوأ صداع بحياتي", "ar", "urgent", ["headache"]),
    ("hematuria 1", "في دم في البول", "ar", "urgent", []),
    ("hematuria 2", "دم بالبول", "ar", "urgent", []),
    ("hematuria 3", "بول مع دم", "ar", "urgent", []),
    ("hematuria 4", "تبول دم", "ar", "urgent", []),
    ("severe pain", "عندي الم شديد", "ar", "urgent", []),
    ("seizure", "عندي تشنج", "ar", "urgent", []),
    ("high fever", "حرارة مرتفعة", "ar", "urgent", ["fever"]),
    ("blood in stool", "دم في البراز", "ar", "urgent", []),
    ("fainting", "فقدان الوعي", "ar", "emergency", []),
    ("shortness of breath", "عندي ضيق تنفس", "ar", "emergency", ["shortness_of_breath"]),
    ("difficulty breathing", "صعوبة في التنفس", "ar", "emergency", []),
    ("chest pain (arabic)", "عندي الم صدر", "ar", "emergency", ["chest_pain"]),
    ("chest pain + dyspnea", "الم صدر وضيق تنفس", "ar", "emergency",
     ["chest_pain", "shortness_of_breath"]),
]

# Cases that must NOT be urgent or emergency. Each carries the reason, because
# an unexplained negative is the first thing a later phase "fixes".
PINNED_NEGATIVES = [
    ("bare headache", "عندي صداع", "ar", ["headache"],
     "a headache alone is not a red flag; only the sudden+severe combination is"),
    ("headache + nausea", "عندي صداع وغثيان", "ar", ["headache", "nausea"],
     "explicitly pinned by test_characterization_virtual_doctor_clinical_gaps"),
    ("bare blood word", "شفت دم", "ar", [],
     "the hematuria pattern is anchored to a urine word and must never match bare دم"),
    ("ER as a place", "وين قسم الطوارئ؟", "ar", [],
     "naming the emergency department is a wayfinding query, not a self-report"),
    ("mild headache (en)", "I have a mild headache", "en", ["headache"],
     "no English red-flag pattern matches, and mild is the opposite of severe"),
    ("sudden weakness", "عندي ضعف مفاجئ", "ar", ["fatigue"],
     "no current pattern covers this; recorded so a change is visible"),
]


# ===========================================================================
# 1. MedicalSafetyLayer verdicts
# ===========================================================================

class TestMedicalSafetyLayerMatrix(unittest.TestCase):
    def test_every_recorded_case_keeps_its_severity(self):
        for name, text, lang, expected, _ in SAFETY_MATRIX:
            with self.subTest(case=name):
                self.assertEqual(severity_of(text, lang), expected)

    def test_every_recorded_case_keeps_its_extracted_symptoms(self):
        for name, text, _lang, _sev, expected in SAFETY_MATRIX:
            with self.subTest(case=name):
                self.assertEqual(symptoms_of(text), sorted(expected))

    def test_raw_and_normalized_text_are_both_checked_and_the_worse_wins(self):
        """_check_safety runs the layer twice and keeps the more severe."""
        self.assertEqual(interview_engine._SEVERITY_RANK,
                         {"emergency": 2, "urgent": 1, "normal": 0})
        self.assertEqual(severity_of("عندي صداع شديد فجأة", "ar"), "urgent")


class TestPinnedNegatives(unittest.TestCase):
    """These must stay non-urgent. Phase 3 asserts the same list against the
    symbolic engine, so a new rule cannot quietly escalate one of them."""

    def test_pinned_negative_cases_remain_normal(self):
        for name, text, lang, _syms, reason in PINNED_NEGATIVES:
            with self.subTest(case=name, reason=reason):
                self.assertEqual(severity_of(text, lang), "normal")

    def test_pinned_negatives_extract_the_symptoms_recorded(self):
        """Recorded deliberately: `headache` and `nausea` ARE extracted here.
        A symbolic rule keyed on either would escalate a pinned-routine case."""
        for name, text, _lang, expected, _reason in PINNED_NEGATIVES:
            with self.subTest(case=name):
                self.assertEqual(symptoms_of(text), sorted(expected))


# ===========================================================================
# 2. The urgency lattice and merge
# ===========================================================================

class TestUrgencyMerge(unittest.TestCase):
    def test_more_urgent_is_a_maximum_over_the_lattice(self):
        levels = ["routine", "urgent", "emergency"]
        expected = {
            ("routine", "routine"): "routine", ("routine", "urgent"): "urgent",
            ("routine", "emergency"): "emergency", ("urgent", "routine"): "urgent",
            ("urgent", "urgent"): "urgent", ("urgent", "emergency"): "emergency",
            ("emergency", "routine"): "emergency", ("emergency", "urgent"): "emergency",
            ("emergency", "emergency"): "emergency",
        }
        for a in levels:
            for b in levels:
                with self.subTest(a=a, b=b):
                    self.assertEqual(reasoning._more_urgent(a, b), expected[(a, b)])

    def test_the_merge_is_symmetric(self):
        for a in ["routine", "urgent", "emergency"]:
            for b in ["routine", "urgent", "emergency"]:
                with self.subTest(a=a, b=b):
                    self.assertEqual(reasoning._more_urgent(a, b),
                                     reasoning._more_urgent(b, a))

    def test_two_rank_tables_exist_today_with_different_vocabularies(self):
        """Recorded as-is. interview_engine speaks `normal`, reasoning speaks
        `routine`; they never meet only because _apply_safety_continuation
        returns early on `normal`. Phase 3 must not make them meet."""
        self.assertEqual(interview_engine._SEVERITY_RANK,
                         {"emergency": 2, "urgent": 1, "normal": 0})
        self.assertEqual(reasoning._URGENCY_RANK,
                         {"emergency": 3, "urgent": 2, "routine": 1})
        self.assertEqual(reasoning._URGENCY_RANK.get("normal", 0), 0)


# ===========================================================================
# 3. SymptomSpecialtyEngine — the third urgency source
# ===========================================================================

class TestSymptomSpecialtyEngineTriage(unittest.TestCase):
    def test_emergency_keywords_are_as_recorded(self):
        self.assertEqual(SymptomSpecialtyEngine.EMERGENCY_KEYWORDS_EN, {
            "severe chest pain", "difficulty breathing", "unconscious",
            "severe bleeding", "choking", "poisoning", "suicide"})
        self.assertEqual(SymptomSpecialtyEngine.EMERGENCY_KEYWORDS_AR, {
            "ألم صدري حاد", "صعوبة التنفس", "فقدان الوعي",
            "نزيف حاد", "اختناق", "تسمم", "انتحار"})

    def test_its_levels_share_the_canonical_vocabulary(self):
        """emergency/urgent/routine — the same three words, so normalising its
        output into the lattice needs no translation."""
        import inspect
        source = inspect.getsource(SymptomSpecialtyEngine.match)
        for level in ('"emergency"', '"urgent"', '"routine"'):
            self.assertIn(level, source)


# ===========================================================================
# 4. Safety continuation: warnings, ordering, escalation-only
# ===========================================================================

class _Session(dict):
    pass


def _session(urgency_level=None):
    return _Session({"urgency_level": urgency_level})


class TestSafetyContinuation(unittest.TestCase):
    def test_normal_severity_produces_no_prefix_and_no_urgency(self):
        prefix, urgency, profile = interview_engine._apply_safety_continuation(
            interview_engine._check_safety("عندي صداع", "ar"), _session(), {}, "ar")
        self.assertEqual(prefix, "")
        self.assertIsNone(urgency)
        self.assertEqual(profile, {})

    def test_first_urgent_turn_shows_the_full_warning(self):
        prefix, urgency, profile = interview_engine._apply_safety_continuation(
            interview_engine._check_safety("عندي صداع شديد فجأة", "ar"), _session(), {}, "ar")
        self.assertEqual(urgency, "urgent")
        self.assertEqual(prefix, interview_engine.SAFETY_URGENT_WARNING["ar"])
        self.assertEqual(profile["safety_warning_shown_for"], "urgent")

    def test_a_repeat_turn_at_the_same_tier_shows_the_short_reminder(self):
        safety = interview_engine._check_safety("عندي صداع شديد فجأة", "ar")
        prefix, _, _ = interview_engine._apply_safety_continuation(
            safety, _session("urgent"), {"safety_warning_shown_for": "urgent"}, "ar")
        self.assertEqual(prefix, interview_engine.SAFETY_URGENT_REMINDER["ar"])

    def test_escalating_to_emergency_shows_the_full_emergency_warning(self):
        safety = interview_engine._check_safety("عندي ضيق تنفس", "ar")
        prefix, urgency, profile = interview_engine._apply_safety_continuation(
            safety, _session("urgent"), {"safety_warning_shown_for": "urgent"}, "ar")
        self.assertEqual(urgency, "emergency")
        self.assertTrue(prefix.startswith(safety["response"]))
        self.assertTrue(prefix.endswith(interview_engine.SAFETY_EMERGENCY_CONTINUATION["ar"]))
        self.assertEqual(profile["safety_warning_shown_for"], "emergency")

    def test_session_urgency_never_falls_back_to_a_milder_level(self):
        """Escalation-only across turns: a mild later turn cannot undo it."""
        safety = interview_engine._check_safety("عندي صداع شديد فجأة", "ar")
        _, urgency, _ = interview_engine._apply_safety_continuation(
            safety, _session("emergency"), {"safety_warning_shown_for": "emergency"}, "ar")
        self.assertEqual(urgency, "emergency")

    def test_a_normal_turn_preserves_the_prior_session_urgency(self):
        _, urgency, _ = interview_engine._apply_safety_continuation(
            interview_engine._check_safety("عندي صداع", "ar"), _session("urgent"), {}, "ar")
        self.assertEqual(urgency, "urgent")

    def test_matched_red_flags_accumulate_in_the_profile(self):
        _, _, profile = interview_engine._apply_safety_continuation(
            interview_engine._check_safety("عندي صداع شديد فجأة", "ar"), _session(), {}, "ar")
        self.assertTrue(profile["safety_flags_detected"])

    def test_emergency_wording_is_unchanged(self):
        layer = MedicalSafetyLayer()
        arabic = layer._get_emergency_response("عندي ضيق تنفس")
        self.assertIn("🚨", arabic)
        self.assertIn("101", arabic)
        self.assertIn("تنبيه طبي عاجل", arabic)


class TestSafetyPrefixOrdering(unittest.TestCase):
    """The safety warning is composed OUTERMOST — after the correction prefix —
    so nothing can get in front of it. Phase 3 keeps this exact order."""

    def test_safety_prefix_is_applied_after_the_correction_prefix(self):
        import inspect
        source = inspect.getsource(interview_engine.handle_message)
        correction_at = source.index("reply = f\"{correction_prefix}{reply}\"")
        safety_at = source.index("reply = f\"{safety_prefix}{reply}\"")
        self.assertLess(correction_at, safety_at,
                        "the safety prefix must be applied last, i.e. outermost")

    def test_the_warning_precedes_the_question_in_the_composed_reply(self):
        prefix, _, _ = interview_engine._apply_safety_continuation(
            interview_engine._check_safety("عندي صداع شديد فجأة", "ar"), _session(), {}, "ar")
        composed = f"{prefix}منذ متى بدأ الصداع؟"
        self.assertLess(composed.index(prefix), composed.index("منذ متى"))


if __name__ == "__main__":
    unittest.main()
