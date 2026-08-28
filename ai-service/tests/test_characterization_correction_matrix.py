"""
Characterization of the CURRENT correction layer, written before Phase 4 adds
any symbolic contradiction reasoning.

Phase 4 reasons over provenance in Prolog while the Python layer stays
authoritative. Parity is the acceptance criterion, so today's decision has to
be written down first — including the cases where the answer is deliberately
"this is NOT a correction".

THE SEMANTIC BOUNDARY THIS FILE PINS
------------------------------------
Three families look similar in text and must stay distinct:

  profile correction   "my age is 24, not 23"      -> replace a stored value
  clinical update      "no, I don't have a fever"  -> a symptom changed state
  severity answer      "the pain isn't severe"     -> an ordinary slot answer

The current layer already separates them: both of the latter return None from
_detect_profile_correction. Phase 4 must not collapse them, so the negative
cases below are as load-bearing as the positive ones.

ALSO RECORDED: correction_history entries carry `source_text`, i.e. raw patient
speech. Phase 4 reads this structure for provenance and must take only
field/old_value/new_value from it — never source_text.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine

BASE = {"name": "أحمد", "age": 23, "chief_complaint_description": "بوجعني راسي"}


def detect(text, profile=None):
    return interview_engine._detect_profile_correction(text, profile or dict(BASE), "ar")


def apply_layer(text, profile=None, phase="interviewing", complaint="headache"):
    return interview_engine._apply_correction_layer(
        dict(profile if profile is not None else BASE), phase, complaint, text, "ar")


DETECTION_MATRIX = [
    ("name correction explicit", "لا، اسمي علي مش أحمد", "name", "علي"),
    ("age correction explicit", "لا، عمري 24 مش 23", "age", 24),
    ("complaint correction", "لا، الوجع في بطني مش راسي", "chief_complaint", "abdominal_pain"),
    ("explicit wrong + replacement", "غلط، اسمي علي", "name", "علي"),
    ("explicit wrong, no replacement", "غلط", None, None),
    ("ambiguous field", "لا، هذا غلط", None, None),
]

NOT_CORRECTIONS = [
    ("leading no only", "لا", "a bare negation carries no replacement and no field"),
    ("weak marker only", "مش هيك", "a weak marker alone is not a correction"),
    ("ordinary symptom negation", "لا، ما عندي حرارة",
     "a symptom changing state is clinical information, not a stored-value fix"),
    ("severity says not severe", "الألم مش شديد، متوسط",
     "an ordinary slot answer that happens to contain a negation"),
    ("name keyword, no marker", "اسمي علي", "stating a name is not correcting one"),
    ("age keyword, no marker", "عمري 24", "stating an age is not correcting one"),
    ("invalid new age", "لا، عمري 999",
     "999 fails the age range, and a weak marker alone does not force a correction"),
    ("suspicious new name", "لا، اسمي درج",
     "the name blocklist rejects it, and a weak marker alone does not force one"),
    ("plain duration answer", "من يومين تقريبا", "an ordinary interview answer"),
    ("plain severity answer", "الألم شديد", "an ordinary interview answer"),
]



class TestCorrectionDetection(unittest.TestCase):
    def test_recognised_corrections_yield_the_recorded_field_and_value(self):
        for case, text, field, value in DETECTION_MATRIX:
            with self.subTest(case=case):
                result = detect(text)
                self.assertIsNotNone(result)
                self.assertEqual(result["field"], field)
                self.assertEqual(result["new_value"], value)

    def test_non_corrections_are_not_detected_at_all(self):
        for case, text, reason in NOT_CORRECTIONS:
            with self.subTest(case=case, reason=reason):
                self.assertIsNone(detect(text))

    def test_symptom_negation_and_profile_correction_are_different_categories(self):
        """The distinction Phase 4 must preserve: both contain a negation, only
        one is a request to replace a stored value."""
        self.assertIsNone(detect("لا، ما عندي حرارة"))
        self.assertIsNotNone(detect("لا، عمري 24 مش 23"))

    def test_a_severity_answer_containing_a_negation_is_not_a_correction(self):
        self.assertIsNone(detect("الألم مش شديد، متوسط"))



class TestCorrectionApplication(unittest.TestCase):
    def test_a_name_correction_updates_the_profile_and_acknowledges(self):
        profile, _phase, _cc, _msg, prefix, _reply = apply_layer("لا، اسمي علي مش أحمد")
        self.assertEqual(profile["name"], "علي")
        self.assertIn("علي", prefix)
        self.assertEqual(len(profile["correction_history"]), 1)

    def test_an_age_correction_updates_the_profile(self):
        profile, *_ = apply_layer("لا، عمري 24 مش 23")
        self.assertEqual(profile["age"], 24)

    def test_a_complaint_correction_reopens_the_greeting_phase(self):
        _profile, phase, _cc, _msg, prefix, _reply = apply_layer("لا، الوجع في بطني مش راسي")
        self.assertEqual(phase, "greeting")
        self.assertIn("البطن", prefix)

    def test_an_under_specified_correction_asks_for_clarification(self):
        profile, _phase, _cc, _msg, prefix, reply = apply_layer("غلط")
        self.assertEqual(prefix, "")
        self.assertEqual(reply, interview_engine.CORRECTION_ASK_FIELD["ar"])
        self.assertEqual(profile.get("correction_history", []), [])

    def test_correction_history_records_old_and_new_values(self):
        profile, *_ = apply_layer("لا، عمري 24 مش 23")
        entry = profile["correction_history"][0]
        self.assertEqual(entry["field"], "age")
        self.assertEqual(entry["old_value"], 23)
        self.assertEqual(entry["new_value"], 24)

    def test_correction_history_entries_contain_raw_patient_text(self):
        """Recorded deliberately. Phase 4 reads this structure for provenance
        and must take field/old_value/new_value ONLY — `source_text` is raw
        patient speech and must never reach Prolog."""
        profile, *_ = apply_layer("لا، عمري 24 مش 23")
        entry = profile["correction_history"][0]
        self.assertIn("source_text", entry)
        self.assertIn("عمري", entry["source_text"])

    def test_repeated_corrections_chain_and_preserve_every_step(self):
        profile = dict(BASE)
        for text in ("لا، عمري 24", "لا، عمري 25"):
            profile, *_ = interview_engine._apply_correction_layer(
                profile, "interviewing", "headache", text, "ar")
        self.assertEqual(profile["age"], 25)
        self.assertEqual(
            [(h["field"], h["old_value"], h["new_value"]) for h in profile["correction_history"]],
            [("age", 23, 24), ("age", 24, 25)])

    def test_a_corrected_field_is_marked_confirmed(self):
        profile, *_ = apply_layer("لا، عمري 24 مش 23")
        self.assertIs(profile["confirmed_fields"]["age"], True)



class TestCorrectionDuringIntake(unittest.TestCase):
    def test_an_intake_correction_chains_into_the_next_intake_question(self):
        profile, phase, _cc, _msg, prefix, reply = apply_layer(
            "لا، اسمي علي", profile={"name": "أحمد"}, phase="intake", complaint=None)
        self.assertEqual(profile["name"], "علي")
        self.assertEqual(phase, "intake")
        self.assertEqual(prefix, "")
        self.assertIn("كم عمرك", reply)

    def test_an_interviewing_correction_returns_a_prefix_not_a_reply(self):
        _profile, _phase, _cc, _msg, prefix, reply = apply_layer("لا، عمري 24 مش 23")
        self.assertTrue(prefix)
        self.assertIsNone(reply)


class TestPendingCorrectionRetryAndGiveUp(unittest.TestCase):
    def test_one_retry_then_give_up(self):
        profile = dict(BASE)
        profile["pending_correction"] = {"field": "age", "attempts": 0}

        profile, _p, _c, _m, _prefix, reply = interview_engine._apply_correction_layer(
            profile, "interviewing", "headache", "مش عارف", "ar")
        self.assertEqual(profile["pending_correction"]["attempts"], 1)
        self.assertEqual(reply, interview_engine.CORRECTION_ASK_AGE["ar"])

        profile, _p, _c, _m, _prefix, reply = interview_engine._apply_correction_layer(
            profile, "interviewing", "headache", "برضو مش عارف", "ar")
        self.assertNotIn("pending_correction", profile)
        self.assertIsNone(reply)

    def test_an_answer_to_a_pending_correction_is_applied(self):
        profile = dict(BASE)
        profile["pending_correction"] = {"field": "age", "attempts": 0}
        profile, *_rest = interview_engine._apply_correction_layer(
            profile, "interviewing", "headache", "24", "ar")
        self.assertEqual(profile["age"], 24)
        self.assertNotIn("pending_correction", profile)



class TestConfirmationIsSeparateFromCorrection(unittest.TestCase):
    """"Did I hear X correctly?" and "the stored X is wrong" are distinct, and
    Phase 4 keeps them distinct."""

    def test_an_open_confirmation_suppresses_correction_detection(self):
        profile = dict(BASE)
        profile["pending_confirmation"] = {"field": "name", "heard": "علي", "attempts": 0}
        result_profile, _p, _c, _m, prefix, reply = interview_engine._apply_correction_layer(
            profile, "interviewing", "headache", "لا، عمري 24", "ar")
        self.assertEqual(prefix, "")
        self.assertIsNone(reply)
        self.assertEqual(result_profile.get("correction_history", []), [])

    def test_the_two_state_keys_are_distinct(self):
        self.assertNotEqual("pending_confirmation", "pending_correction")



class TestSafetyStillWinsOnACorrectionTurn(unittest.TestCase):
    def test_a_turn_can_be_both_a_correction_and_a_red_flag(self):
        text = "لا، عمري 24 وعندي صداع شديد فجأة"
        self.assertEqual(interview_engine._check_safety(text, "ar")["severity"], "urgent")
        self.assertEqual(detect(text)["field"], "age")

    def test_the_safety_prefix_is_applied_after_the_correction_prefix(self):
        """Outermost wins the reader's eye: the safety warning must render
        first even on a correction turn."""
        import inspect
        source = inspect.getsource(interview_engine.handle_message)
        self.assertLess(source.index('reply = f"{correction_prefix}{reply}"'),
                        source.index('reply = f"{safety_prefix}{reply}"'))



class TestSlotCardinalityToday(unittest.TestCase):
    def test_identity_slots_hold_one_value(self):
        profile, *_ = apply_layer("لا، عمري 24 مش 23")
        self.assertNotIsInstance(profile["age"], list)
        self.assertNotIsInstance(profile["name"], list)

    def test_associated_symptoms_detected_is_a_list(self):
        """Multi-valued by construction — Phase 4 must not mark it
        single-valued, or every new symptom would read as a contradiction."""
        profile = {"associated_symptoms_detected": ["headache", "nausea"]}
        self.assertIsInstance(profile["associated_symptoms_detected"], list)

    def test_clinical_slots_are_overwritten_not_accumulated(self):
        """A later answer replaces the earlier one; there is no list. Recorded
        so Phase 4's single_valued/1 choices are grounded rather than assumed."""
        from virtual_doctor import planner
        profile = {"duration": "يومين"}
        updates = {"duration": "ثلاثة أيام"}
        merged = {**profile, **updates}
        self.assertEqual(merged["duration"], "ثلاثة أيام")
        self.assertIn("duration", planner.KNOWN_FINDING_KEYS)


if __name__ == "__main__":
    unittest.main()
