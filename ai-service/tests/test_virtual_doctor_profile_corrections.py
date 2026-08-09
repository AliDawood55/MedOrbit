"""
Virtual Doctor flexible profile correction (Batch 1) — behavior tests.

The patient must be able to fix a stored fact at ANY point in the
conversation, not only while a yes/no pending_confirmation happens to be
open. Before this batch there was no correction path at all outside that
narrow window: "لا، اسمي علي" mid-interview was just fed to the planner as
an ordinary answer.

Design under test (interview_engine._apply_correction_layer and helpers):
deterministic detection ahead of the planner, the value applied to
patient_profile, an append-only correction_history audit trail, and ONE
clarification question when the intent is clear but the field or value is
not. The LLM is never asked whether something is a correction.

THE FALSE-POSITIVE GUARD IS THE IMPORTANT PART. "مش" is far too common to
mean "correction" on its own — a patient answering "الألم مش شديد، متوسط"
is describing severity, not correcting the complaint. A weak marker
therefore only counts when a replacement value of the right TYPE can
actually be extracted; the last test class pins that.

No real DB, Ollama, STT, TTS, or network access anywhere in this file.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, report_generator


def _profile(**overrides):
    base = {"name": "أحمد", "age": 23, "chief_complaint_description": "عندي صداع"}
    base.update(overrides)
    return base


def _fake_session(profile=None, phase="interviewing", chief_complaint="headache",
                  session_id="public-id", language="ar"):
    return {
        "id": "row-id", "session_id": session_id, "language": language,
        "phase": phase, "chief_complaint": chief_complaint,
        "patient_profile": json.dumps(profile if profile is not None else _profile()),
        "urgency_level": None,
        "recommended_specialty_id": None, "differential": None,
        "created_at": None,
    }


async def _run_turn(message, fake_session, planner_result=None):
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=fake_session)
    fake_pool.execute = AsyncMock()

    default_plan = planner_result or planner.PlannerResult(
        reply="من متى بلّش؟", phase="interviewing", source="static",
    )
    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(
            interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
        stack.enter_context(patch.object(
            interview_engine, "_build_turn_context", new=AsyncMock(return_value={
                "history": [], "chunks": [], "context_block": "",
                "memory_ms": 0.0, "rag_ms": 0.0})))
        stack.enter_context(patch.object(
            interview_engine, "_run_planner", new=AsyncMock(return_value=default_plan)))
        stack.enter_context(patch.object(
            interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
        result = await interview_engine.handle_message(fake_session["session_id"], message)

    update = [c for c in fake_pool.execute.call_args_list
              if "UPDATE virtual_doctor_sessions" in c.args[0]][0]
    next_session = dict(fake_session)
    next_session["phase"] = update.args[2]
    next_session["chief_complaint"] = update.args[3]
    next_session["patient_profile"] = update.args[4]
    return result, next_session


# ===========================================================================
# 1. Name correction
# ===========================================================================

class TestNameCorrection(unittest.IsolatedAsyncioTestCase):
    async def test_rejection_with_new_name_updates_profile(self):
        result, next_session = await _run_turn("لا، اسمي علي", _fake_session())

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(profile["name"], "علي")
        self.assertIn("عدّلت الاسم", result["reply"])
        self.assertTrue(profile["confirmed_fields"]["name"])

    async def test_contrastive_and_imperative_phrasings(self):
        for message in ("اسمي علي مش أحمد", "صحح اسمي لعلي"):
            with self.subTest(message=message):
                _, next_session = await _run_turn(message, _fake_session())
                self.assertEqual(json.loads(next_session["patient_profile"])["name"], "علي")

    async def test_bare_wrong_name_asks_one_clarification_question(self):
        result, next_session = await _run_turn("اسمي غلط", _fake_session())

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(result["reply"], interview_engine.CORRECTION_ASK_NAME["ar"])
        self.assertEqual(profile["name"], "أحمد")  # not guessed at
        self.assertEqual(profile["pending_correction"]["field"], "name")

    async def test_clarification_answer_is_applied_next_turn(self):
        _, pending = await _run_turn("اسمي غلط", _fake_session())
        result, next_session = await _run_turn("علي", pending)

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(profile["name"], "علي")
        self.assertNotIn("pending_correction", profile)


# ===========================================================================
# 2. Age correction
# ===========================================================================

class TestAgeCorrection(unittest.IsolatedAsyncioTestCase):
    async def test_contrastive_age_picks_the_affirmed_number(self):
        """Both orderings must yield 24. _extract_age alone returns the FIRST
        in-range number, which is the REJECTED one in "أنا مش 23، عمري 24"."""
        for message in ("عمري 24 مش 23", "أنا مش 23، عمري 24", "صحح العمر 24"):
            with self.subTest(message=message):
                result, next_session = await _run_turn(message, _fake_session())
                profile = json.loads(next_session["patient_profile"])
                self.assertEqual(profile["age"], 24)
                self.assertIn("عدّلت العمر", result["reply"])

    async def test_bare_wrong_age_asks_one_clarification_question(self):
        result, next_session = await _run_turn("عمري غلط", _fake_session())

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(result["reply"], interview_engine.CORRECTION_ASK_AGE["ar"])
        self.assertEqual(profile["age"], 23)  # unchanged until they say


# ===========================================================================
# 2b. Follow-up: no duplicated acknowledgement when a correction lands
#     mid-intake
# ===========================================================================

class TestNoDuplicatedAcknowledgement(unittest.IsolatedAsyncioTestCase):
    """Follow-up fix, originally reported against the Levantine-era wording:
    an age correction that lands BEFORE the chief complaint has been asked
    concatenated CORRECTION_APPLIED_AGE with ASK_COMPLAINT — both of which
    used to open with "تمام" — producing "تمام، عدّلت العمر لـ24 سنة. تمام،
    شو بتشعر اليوم؟". The formal-Arabic style reversal (MedOrbit Virtual
    Doctor — Formal Arabic Voice Quality Upgrade) removed "تمام" from every
    template, so the specific duplicated-filler-word bug can no longer recur
    by construction — no template opens with a repeatable filler word
    anymore. This test now pins the CURRENT well-formed, non-duplicated
    concatenation instead. The fixture in the other tests in this file
    already has chief_complaint_description set, so it never actually
    exercises this path; this class uses a mid-intake profile (name + age,
    no complaint yet) specifically to reproduce it."""

    async def test_age_correction_mid_intake_has_no_duplicated_opener(self):
        mid_intake_session = _fake_session(
            profile={"name": "أحمد", "age": 23, "chief_complaint_description": None},
            phase="intake", chief_complaint=None,
        )

        result, next_session = await _run_turn("عمري 24 مش 23", mid_intake_session)

        self.assertEqual(
            result["reply"],
            "عدّلت العمر لـ24 سنة. ما الأعراض التي تشعر بها اليوم؟",
        )
        # No leftover dialect filler, and no doubled-up opener of any kind.
        self.assertNotIn("تمام", result["reply"])
        self.assertEqual(result["reply"].count("عدّلت العمر"), 1)
        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(profile["age"], 24)
        self.assertEqual(len(profile["correction_history"]), 1)  # still recorded


# ===========================================================================
# 3. Chief complaint correction
# ===========================================================================

class TestChiefComplaintCorrection(unittest.IsolatedAsyncioTestCase):
    async def test_pain_moved_from_head_to_abdomen_reroutes_complaint(self):
        result, next_session = await _run_turn(
            "الوجع مش بالرأس، بالبطن", _fake_session(chief_complaint="headache"),
        )

        self.assertEqual(next_session["chief_complaint"], "abdominal_pain")
        self.assertIn("الوجع في البطن", result["reply"])
        # The planner still runs and still asks the next clinical question.
        self.assertIn("من متى بلّش؟", result["reply"])

    async def test_i_meant_phrasing_also_reroutes(self):
        _, next_session = await _run_turn(
            "أنا مش قصدي صداع، قصدي وجع بطن", _fake_session(chief_complaint="headache"),
        )

        self.assertEqual(next_session["chief_complaint"], "abdominal_pain")


# ===========================================================================
# 4. Correction history audit trail
# ===========================================================================

class TestCorrectionHistory(unittest.IsolatedAsyncioTestCase):
    async def test_history_records_old_and_new_values(self):
        _, next_session = await _run_turn("لا، اسمي علي", _fake_session())

        history = json.loads(next_session["patient_profile"])["correction_history"]
        self.assertEqual(len(history), 1)
        entry = history[0]
        self.assertEqual(entry["field"], "name")
        self.assertEqual(entry["old_value"], "أحمد")
        self.assertEqual(entry["new_value"], "علي")
        self.assertEqual(entry["source_text"], "لا، اسمي علي")
        self.assertTrue(entry["confirmed"])

    async def test_history_is_append_only_across_turns(self):
        _, session = await _run_turn("لا، اسمي علي", _fake_session())
        _, session = await _run_turn("عمري 24 مش 23", session)

        history = json.loads(session["patient_profile"])["correction_history"]
        self.assertEqual([e["field"] for e in history], ["name", "age"])


# ===========================================================================
# 5. The report reflects corrected values
# ===========================================================================

class TestReportUsesCorrectedValues(unittest.IsolatedAsyncioTestCase):
    async def test_report_shows_corrected_name_and_age_and_no_bookkeeping_rows(self):
        _, session = await _run_turn("لا، اسمي علي", _fake_session())
        _, session = await _run_turn("عمري 24 مش 23", session)

        fake_pool = AsyncMock()
        fake_pool.fetchrow = AsyncMock(return_value=session)
        with patch.object(report_generator, "get_pool", new=AsyncMock(return_value=fake_pool)):
            report = await report_generator.build_report_data(session["session_id"])

        self.assertEqual(report["patient_info"]["name"], "علي")
        self.assertEqual(report["patient_info"]["age"], 24)
        # Corrected fields are confirmed, so they render unlabelled.
        html = report_generator._render_html(report)
        self.assertIn("<td>علي</td>", html)
        self.assertNotIn("غير مؤكد", html)
        # Bookkeeping keys must never surface as clinical symptom rows.
        for key in ("correction_history", "pending_correction", "name_repeat_attempts"):
            self.assertNotIn(key, report["symptoms_summary"])


# ===========================================================================
# 6. False positives: ordinary answers must NOT be treated as corrections
# ===========================================================================

class TestOrdinaryAnswersAreNotCorrections(unittest.IsolatedAsyncioTestCase):
    async def test_severity_answer_containing_mish_is_left_alone(self):
        """"الألم مش شديد، متوسط" is a severity ANSWER. Treating it as a
        complaint correction would silently corrupt the chief complaint."""
        result, next_session = await _run_turn(
            "الألم مش شديد، متوسط", _fake_session(chief_complaint="headache"),
        )

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(next_session["chief_complaint"], "headache")
        self.assertNotIn("correction_history", profile)
        self.assertEqual(result["reply"], "من متى بلّش؟")  # straight from the planner

    async def test_bare_no_and_plain_answers_are_left_alone(self):
        for message in ("لا", "نعم", "من يومين", "لا، ما عندي غثيان"):
            with self.subTest(message=message):
                _, next_session = await _run_turn(message, _fake_session())
                profile = json.loads(next_session["patient_profile"])
                self.assertNotIn("correction_history", profile)
                self.assertEqual(profile["name"], "أحمد")


# ===========================================================================
# 7. Safety behaviour is unaffected by the correction layer
# ===========================================================================

class TestSafetyStillWinsOverCorrections(unittest.IsolatedAsyncioTestCase):
    async def test_urgent_symptom_still_warns_and_continues(self):
        result, next_session = await _run_turn("عندي دم بالبول", _fake_session())

        self.assertEqual(result["urgency_level"], "urgent")
        self.assertNotEqual(result["phase"], "complete")
        self.assertIn("تقييمًا طبيًا عاجلًا", result["reply"])

    async def test_safety_warning_precedes_a_correction_acknowledgement(self):
        """A red flag outranks bookkeeping: if a turn both corrects a fact and
        trips the safety layer, the warning must come first in the reply."""
        result, next_session = await _run_turn("عمري 24 مش 23 وعندي دم بالبول", _fake_session())

        reply = result["reply"]
        self.assertEqual(json.loads(next_session["patient_profile"])["age"], 24)
        self.assertEqual(result["urgency_level"], "urgent")
        self.assertIn("تقييمًا طبيًا عاجلًا", reply)
        self.assertLess(reply.index("تقييمًا طبيًا عاجلًا"), reply.index("عدّلت العمر"))

    async def test_messy_compound_name_correction_is_declined_not_guessed(self):
        """A name correction buried in a compound sentence ("لا، اسمي علي،
        وعندي دم بالبول") is deliberately NOT applied: the only candidate the
        extractor can see is "علي، وعندي دم بالبول", which is sentence-shaped,
        and storing a guess would be worse than leaving the old value. The
        safety half of the same turn must still fire normally."""
        result, next_session = await _run_turn("لا، اسمي علي، وعندي دم بالبول", _fake_session())

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(profile["name"], "أحمد")            # unchanged, not guessed
        self.assertNotIn("correction_history", profile)
        self.assertEqual(result["urgency_level"], "urgent")  # safety unaffected
        self.assertIn("تقييمًا طبيًا عاجلًا", result["reply"])


if __name__ == "__main__":
    unittest.main()
