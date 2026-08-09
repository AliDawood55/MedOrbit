"""
Virtual Doctor STT Confirmation + Clinical Correction Layer — behavior tests.

Problem under test: the interview engine used to treat every STT transcript
as ground truth — a misheard name ("درج") was stored as-is, and a garbled
chief complaint ("عندي صدق شديد فجأة" instead of "عندي صداع شديد فجأة") was
routed/reasoned about literally, with no chance for the patient to correct
it. This is not acceptable for a medical voice consultation.

Design under test (interview_engine._apply_confirmation_layer and its
helpers): a suspicious name or a likely ASR-garbled chief complaint is held
in profile["pending_confirmation"] instead of being stored/routed
immediately, and the interview asks a short confirmation/clarification
question. The NEXT patient turn is checked against any pending confirmation
first (confirm / correct / unclear, deterministically classified — never the
LLM's decision) before anything else runs. See _apply_confirmation_layer()'s
docstring in interview_engine.py for the full design.

Every test here runs interview_engine.handle_message() end-to-end with the
DB pool, per-turn RAG/memory context, and doctor-turn history all mocked —
no real DB, Ollama, STT, TTS, or network access anywhere in this file.
_run_turn() below additionally threads whatever one turn persisted into the
next fake "session" dict, so multi-turn confirmation sequences (tests 4, 5,
8) can be simulated without a real database. This follows the same mocking
style as tests/test_virtual_doctor_safety_continuation.py.

The deterministic pieces this feature depends on (_is_suspicious_name,
_detect_high_risk_correction, _apply_silent_asr_corrections,
_classify_confirmation_reply, chatbot.entities.extractor.EntityExtractor)
are exercised for real, unmocked — they are pure/local and safe to call
directly.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner


def _fake_session(session_id="public-id", phase="intake", profile=None,
                  chief_complaint=None, urgency_level=None, language="ar"):
    return {
        "id": "row-id", "session_id": session_id, "language": language,
        "phase": phase, "chief_complaint": chief_complaint,
        "patient_profile": json.dumps(profile or {}),
        "urgency_level": urgency_level,
        "recommended_specialty_id": None, "differential": None,
    }


async def _run_turn(message, fake_session, planner_result=None):
    """Runs handle_message() once against fake_session and returns
    (result, next_session, run_planner_mock). next_session is fake_session
    updated with whatever this turn persisted via the UPDATE ...
    virtual_doctor_sessions call, so a caller can feed it straight into the
    next _run_turn() to simulate a real multi-turn conversation without a
    database."""
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=fake_session)
    fake_pool.execute = AsyncMock()

    build_context_mock = AsyncMock(return_value={
        "history": [], "chunks": [], "context_block": "",
        "memory_ms": 0.0, "rag_ms": 0.0,
    })
    run_planner_mock = AsyncMock(return_value=planner_result)

    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(
            interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
        stack.enter_context(patch.object(
            interview_engine, "_build_turn_context", new=build_context_mock))
        stack.enter_context(patch.object(
            interview_engine, "_run_planner", new=run_planner_mock))
        stack.enter_context(patch.object(
            interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
        result = await interview_engine.handle_message(fake_session["session_id"], message)

    update_calls = [
        c for c in fake_pool.execute.call_args_list
        if "UPDATE virtual_doctor_sessions" in c.args[0]
    ]
    assert len(update_calls) == 1, "expected exactly one session UPDATE per turn"
    (_sql, _session_id, persisted_phase, persisted_chief_complaint,
     persisted_profile_json, persisted_urgency, _specialty_id,
     _differential_json) = update_calls[0].args

    next_session = dict(fake_session)
    next_session["phase"] = persisted_phase
    next_session["chief_complaint"] = persisted_chief_complaint
    next_session["patient_profile"] = persisted_profile_json
    next_session["urgency_level"] = persisted_urgency

    return result, next_session, run_planner_mock


# ===========================================================================
# 1. Suspicious name requires confirmation
# ===========================================================================

class TestSuspiciousNameRequiresConfirmation(unittest.IsolatedAsyncioTestCase):
    async def test_object_word_heard_as_name_asks_confirmation_not_stored(self):
        fake_session = _fake_session(phase="intake")

        result, next_session, run_planner_mock = await _run_turn("درج", fake_session)

        self.assertIn("درج", result["reply"])
        self.assertIn("هل هذا اسمك", result["reply"])
        run_planner_mock.assert_not_called()

        persisted_profile = json.loads(next_session["patient_profile"])
        self.assertIn("pending_confirmation", persisted_profile)
        self.assertEqual(persisted_profile["pending_confirmation"]["field"], "name")
        self.assertNotIn("name", persisted_profile)  # not stored, confirmed or not


# ===========================================================================
# 2. Normal name proceeds normally
# ===========================================================================

class TestNormalNameProceedsNormally(unittest.IsolatedAsyncioTestCase):
    async def test_ordinary_name_stored_without_confirmation(self):
        fake_session = _fake_session(phase="intake")
        plan = planner.PlannerResult(
            reply="تشرّفت بمعرفتك يا علي. كم عمرك؟", phase="intake",
            profile_updates={"name": "علي"}, source="intake",
        )

        result, next_session, run_planner_mock = await _run_turn("علي", fake_session, plan)

        run_planner_mock.assert_called_once()
        ctx = run_planner_mock.call_args.args[0]
        self.assertEqual(ctx.message, "علي")  # unchanged — not suspicious
        self.assertIn("علي", result["reply"])

        persisted_profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("pending_confirmation", persisted_profile)
        self.assertEqual(persisted_profile.get("name"), "علي")


# ===========================================================================
# 3. Misheard headache chief complaint asks confirmation
# ===========================================================================

class TestMisheardHeadacheAsksConfirmation(unittest.IsolatedAsyncioTestCase):
    async def test_asr_garbled_headache_asks_confirmation_not_shock(self):
        fake_session = _fake_session(phase="greeting")

        result, next_session, run_planner_mock = await _run_turn(
            "عندي صدق شديد فجأة", fake_session,
        )

        self.assertIn("هل تقصد صداع شديد بدأ فجأة؟", result["reply"])
        self.assertNotIn("صدمة", result["reply"])
        run_planner_mock.assert_not_called()
        self.assertIsNone(result.get("differential"))  # no final diagnosis yet

        persisted_profile = json.loads(next_session["patient_profile"])
        self.assertEqual(persisted_profile["pending_confirmation"]["field"], "chief_complaint")
        self.assertEqual(persisted_profile["pending_confirmation"]["heard"], "عندي صدق شديد فجأة")


# ===========================================================================
# 4. Confirmed correction applies
# ===========================================================================

class TestConfirmedCorrectionApplies(unittest.IsolatedAsyncioTestCase):
    async def test_yes_applies_suggested_headache_and_continues(self):
        fake_session = _fake_session(phase="greeting")
        _, pending_session, _ = await _run_turn("عندي صدق شديد فجأة", fake_session)

        headache_question = "هل الصداع في جانب واحد أم في كل الرأس؟"
        plan = planner.PlannerResult(
            reply=headache_question, phase="interviewing",
            chief_complaint="headache", source="static",
        )
        result, next_session, run_planner_mock = await _run_turn("نعم", pending_session, plan)

        run_planner_mock.assert_called_once()
        ctx = run_planner_mock.call_args.args[0]
        self.assertEqual(ctx.message, "صداع شديد بدأ فجأة")  # resolved value, not "نعم"

        self.assertEqual(result["chief_complaint"], "headache")
        self.assertIn(headache_question, result["reply"])

        persisted_profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("pending_confirmation", persisted_profile)
        self.assertTrue(persisted_profile["confirmed_fields"]["chief_complaint"])


# ===========================================================================
# 5. User correction applies
# ===========================================================================

class TestUserCorrectionApplies(unittest.IsolatedAsyncioTestCase):
    async def test_rejection_with_correction_uses_corrected_text(self):
        fake_session = _fake_session(phase="greeting")
        _, pending_session, _ = await _run_turn("عندي صدق شديد فجأة", fake_session)

        headache_question = "منذ متى بدأ الصداع؟"
        plan = planner.PlannerResult(
            reply=headache_question, phase="interviewing",
            chief_complaint="headache", source="static",
        )
        result, next_session, run_planner_mock = await _run_turn(
            "لا، قصدي صداع شديد", pending_session, plan,
        )

        run_planner_mock.assert_called_once()
        ctx = run_planner_mock.call_args.args[0]
        self.assertEqual(ctx.message, "صداع شديد")  # the corrected text

        self.assertIn(headache_question, result["reply"])

        persisted_profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("pending_confirmation", persisted_profile)
        self.assertEqual(persisted_profile["chief_complaint_description"], "صداع شديد")


# ===========================================================================
# 6. ASR fatigue correction
# ===========================================================================

class TestAsrFatigueCorrection(unittest.IsolatedAsyncioTestCase):
    async def test_meaningless_word_corrected_before_storage(self):
        fake_session = _fake_session(phase="greeting")
        plan = planner.PlannerResult(
            reply="منذ متى وأنت تشعر بالإرهاق؟", phase="interviewing",
            chief_complaint="generic", source="static",
        )

        result, next_session, run_planner_mock = await _run_turn(
            "أشعر بإرهاف وتعب شديد", fake_session, plan,
        )

        run_planner_mock.assert_called_once()
        ctx = run_planner_mock.call_args.args[0]
        self.assertIn("إرهاق", ctx.message)
        self.assertNotIn("إرهاف", ctx.message)  # meaningless word never reaches the planner

        persisted_profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("إرهاف", persisted_profile.get("chief_complaint_description", ""))


# ===========================================================================
# 7. Flank/urinary vocabulary preserved as clinically relevant
# ===========================================================================

class TestFlankUrinaryVocabularyPreserved(unittest.IsolatedAsyncioTestCase):
    async def test_unrecognized_flank_terms_get_focused_question_not_generic(self):
        fake_session = _fake_session(phase="greeting")

        result, next_session, run_planner_mock = await _run_turn(
            "عندي وجع بالخاصرة وجفاف وأملاح", fake_session,
        )

        run_planner_mock.assert_not_called()
        self.assertIn("الخاصرة", result["reply"])
        self.assertNotIn("منذ متى وأنت تعاني من هذا؟", result["reply"])  # the generic flow's question

        persisted_profile = json.loads(next_session["patient_profile"])
        terms = persisted_profile["uncertain_fields"]["clinical_terms"]
        self.assertIn("flank_pain", terms)
        self.assertIn("dehydration_context", terms)
        self.assertIn("urinary_or_dehydration_context", terms)
        self.assertEqual(next_session["phase"], "interviewing")


# ===========================================================================
# 8. No infinite confirmation loop
# ===========================================================================

class TestNoInfiniteConfirmationLoop(unittest.IsolatedAsyncioTestCase):
    async def test_two_unclear_replies_falls_back_instead_of_looping_forever(self):
        fake_session = _fake_session(phase="intake")
        _, pending_session, _ = await _run_turn("درج", fake_session)

        # First unclear reply: a simpler repeat question, still pending.
        retry_result, retry_session, retry_planner_mock = await _run_turn(
            "ايش قصدك؟", pending_session,
        )
        retry_planner_mock.assert_not_called()
        self.assertIn("أعد ذكر اسمك", retry_result["reply"])
        retry_profile = json.loads(retry_session["patient_profile"])
        self.assertEqual(retry_profile["pending_confirmation"]["attempts"], 1)

        # Second unclear reply: gives up rather than asking a third time —
        # proceeds with the originally-heard name, marked unconfirmed.
        final_result, final_session, final_planner_mock = await _run_turn(
            "مش فاهم عليك", retry_session,
        )
        final_planner_mock.assert_not_called()
        final_profile = json.loads(final_session["patient_profile"])
        self.assertNotIn("pending_confirmation", final_profile)
        self.assertEqual(final_profile["name"], "درج")
        self.assertFalse(final_profile["confirmed_fields"]["name"])
        self.assertIn("كم عمرك", final_result["reply"])  # interview keeps moving


if __name__ == "__main__":
    unittest.main()
