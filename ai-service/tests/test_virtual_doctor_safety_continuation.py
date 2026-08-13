"""
Virtual Doctor Safety-Continuation Interview Mode — behavior tests.

Product decision under test: urgent/emergency safety detections no longer
hard-stop the interview (interview_engine.handle_message() used to return
immediately with phase='complete' the moment MedicalSafetyLayer flagged a
turn). Instead:
  - the deterministic safety layer's severity is escalated into the session's
    urgency_level, never downgraded (reasoning._more_urgent, reused);
  - a short, deterministic warning (never delegated to the LLM) is prepended
    to the reply, in full the first time a tier is reached and as a brief
    reminder on repeat turns at the same tier;
  - the planner still runs and still produces the next question, optionally
    nudged (never overridden) toward a red-flag-relevant topic via
    PlannerInput.safety_hint;
  - phase stays 'interviewing' unless the planner independently decides the
    interview is ready for diagnosis.

Every test here runs interview_engine.handle_message() end-to-end with the
DB pool, per-turn RAG/memory context, and doctor-turn history all mocked —
no real DB, Ollama, or network access anywhere in this file. Only
_run_planner's return value is configured per test, following the same
mocking style as tests/test_characterization_rag_phase0.py's
TestEmergencyContinuesIntoPlannerAndRetrieval.

The deterministic pieces this feature depends on (MedicalSafetyLayer,
EntityExtractor, interview_engine._check_safety/_apply_safety_continuation)
are exercised for real, unmocked — they are pure/local and safe to call
directly, exactly as tests/test_characterization_virtual_doctor_clinical_gaps.py
already does.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner


def _fake_session(session_id="public-id", urgency_level=None, profile=None,
                  phase="interviewing", chief_complaint=None, language="ar"):
    return {
        "id": "row-id", "session_id": session_id, "language": language,
        "phase": phase, "chief_complaint": chief_complaint,
        "patient_profile": json.dumps(profile or {}),
        "urgency_level": urgency_level,
        "recommended_specialty_id": None, "differential": None,
    }


async def _handle(message, fake_session, planner_result=None):
    """Run handle_message() end-to-end with the DB pool, per-turn RAG/memory
    context, and doctor-turn history mocked. Returns (result, run_planner_mock,
    fake_pool) so each test can additionally inspect what the planner was
    called with and what got persisted."""
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

    return result, run_planner_mock, fake_pool


# ===========================================================================
# 1. Urgent headache continues the interview
# ===========================================================================

class TestUrgentHeadacheContinuesInterview(unittest.IsolatedAsyncioTestCase):
    async def test_urgent_warning_and_follow_up_question_both_present(self):
        fake_session = _fake_session(chief_complaint="headache")
        mocked_next_question = "منذ متى بدأ الصداع بالضبط؟"
        plan = planner.PlannerResult(reply=mocked_next_question, phase="interviewing", source="static")

        result, run_planner_mock, _ = await _handle("عندي صداع شديد فجأة", fake_session, plan)

        self.assertEqual(interview_engine._check_safety("عندي صداع شديد فجأة", "ar")["severity"], "urgent")
        self.assertEqual(result["urgency_level"], "urgent")
        self.assertIn("تقييمًا طبيًا عاجلًا", result["reply"])  # urgent warning present
        self.assertIn(mocked_next_question, result["reply"])     # follow-up question present
        run_planner_mock.assert_called_once()                    # planner NOT skipped
        self.assertNotEqual(result["phase"], "complete")         # not force-completed


# ===========================================================================
# 2. Hematuria continues a focused (not purely generic-escalation) interview
# ===========================================================================

class TestHematuriaContinuesFocusedInterview(unittest.IsolatedAsyncioTestCase):
    async def test_focused_question_present_not_generic_escalation_only(self):
        fake_session = _fake_session(chief_complaint=None)
        mocked_next_question = "هل تشعر بحرقان أثناء التبول أو ألم في الخاصرة؟"
        plan = planner.PlannerResult(reply=mocked_next_question, phase="interviewing", source="static")

        result, run_planner_mock, _ = await _handle("عندي دم بالبول", fake_session, plan)

        self.assertEqual(result["urgency_level"], "urgent")
        self.assertIn("تقييمًا طبيًا عاجلًا", result["reply"])
        self.assertIn(mocked_next_question, result["reply"])
        # Not JUST the escalation message: the reply is strictly longer than
        # the warning text alone once the focused question is appended.
        self.assertGreater(len(result["reply"]), len(interview_engine.SAFETY_URGENT_WARNING["ar"]))

        # Requirement: prioritize red-flag-related questions. The planner was
        # actually handed a hint describing what the safety layer matched.
        ctx = run_planner_mock.call_args.args[0]
        self.assertIsNotNone(ctx.safety_hint)
        self.assertIn("بول", ctx.safety_hint)


# ===========================================================================
# 3. Emergency behavior remains safety-first
# ===========================================================================

class TestEmergencyRemainsSafetyFirst(unittest.IsolatedAsyncioTestCase):
    async def test_mid_interview_emergency_keeps_warning_and_asks_one_short_question(self):
        """Existing emergency phrase reused from test_emergency_localization.py
        ("طوارئ") — mid-interview case: the planner is not yet ready for
        diagnosis, so this turn should combine the FULL canned emergency
        warning (Red Crescent/101, never removed) with the brief continuation
        lead-in and exactly one focused question."""
        fake_session = _fake_session(chief_complaint="chest_pain")
        one_question = "هل بدأ الألم فجأة؟"
        plan = planner.PlannerResult(reply=one_question, phase="interviewing", source="static")

        result, run_planner_mock, _ = await _handle("طوارئ", fake_session, plan)

        self.assertEqual(result["urgency_level"], "emergency")
        self.assertNotEqual(result["phase"], "complete")
        self.assertIn("الهلال الأحمر الفلسطيني", result["reply"])
        self.assertIn("101", result["reply"])
        self.assertIn(interview_engine.SAFETY_EMERGENCY_CONTINUATION["ar"].strip(), result["reply"])
        self.assertIn(one_question, result["reply"])
        run_planner_mock.assert_called_once()

    async def test_llm_reasoning_cannot_downgrade_emergency_urgency(self):
        """The interview reaches readiness in the SAME turn safety fired (the
        planner decided ready_for_diagnosis=True) and reasoning.run_reasoning
        reports "routine" — deliberately lower than what the safety layer
        already found. The final urgency must still be "emergency": this is
        exactly the downgrade the escalate-only merge in handle_message()
        must prevent now that the interview no longer hard-stops."""
        fake_session = _fake_session(chief_complaint="chest_pain")
        plan = planner.PlannerResult(
            reply=None, phase="interviewing", ready_for_diagnosis=True, source="static",
        )
        fake_reasoning_result = {
            "reply": "يُقترح مراجعة طبيب عام.",
            "urgency_level": "routine",  # deliberately lower than emergency
            "recommended_specialty_id": "11111111-1111-1111-1111-111111111111",
            "recommended_specialty_name_en": "General Practice",
            "recommended_specialty_name_ar": "طب عام",
            "differential": {"conditions": []},
            "confidence": 0.4,
        }

        with patch.object(interview_engine.reasoning, "run_reasoning",
                          new=AsyncMock(return_value=fake_reasoning_result)), \
             patch.object(interview_engine.memory, "load_recent", new=AsyncMock(return_value=[])), \
             patch.object(interview_engine.planner, "warm", new=MagicMock()):
            result, _, _ = await _handle("طوارئ", fake_session, plan)

        # Emergency warning remains strong.
        self.assertIn("الهلال الأحمر الفلسطيني", result["reply"])
        self.assertIn("101", result["reply"])
        # Not downgraded by the LLM/reasoning's own "routine" opinion.
        self.assertEqual(result["urgency_level"], "emergency")
        # No final diagnosis language and no false reassurance.
        for phrase in ("كل شيء بخير", "لا داعي للقلق", "everything is fine", "nothing to worry"):
            self.assertNotIn(phrase, result["reply"])


# ===========================================================================
# 4. Normal message: existing behavior unchanged
# ===========================================================================

class TestNormalSeverityBehaviorUnchanged(unittest.IsolatedAsyncioTestCase):
    async def test_normal_message_reply_is_exactly_the_planners_question(self):
        fake_session = _fake_session(chief_complaint="headache")
        planner_question = "هل الألم في جانب واحد أم في كل الرأس؟"
        plan = planner.PlannerResult(reply=planner_question, phase="interviewing", source="static")

        result, run_planner_mock, _ = await _handle("عندي صداع", fake_session, plan)

        self.assertEqual(interview_engine._check_safety("عندي صداع", "ar")["severity"], "normal")
        self.assertIsNone(result["urgency_level"])
        # No safety prefix at all: byte-for-byte the planner's own reply,
        # exactly matching pre-batch behavior for normal-severity turns.
        self.assertEqual(result["reply"], planner_question)

        ctx = run_planner_mock.call_args.args[0]
        self.assertIsNone(ctx.safety_hint)


# ===========================================================================
# 5. Safety signal persisted
# ===========================================================================

class TestSafetySignalPersisted(unittest.IsolatedAsyncioTestCase):
    """LIMITATION: the current schema has no dedicated structured red_flags
    column/table — "red flags as an explicit, stored, per-turn list" remains
    unimplemented. This test verifies the signal reaches the two fields that
    DO exist today: the session's urgency_level column, and a lightweight,
    additive audit trail inside the existing patient_profile JSONB column
    (safety_warning_shown_for / safety_flags_detected) — no schema/migration
    change was made or is required for this."""

    async def test_urgent_signal_persisted_into_urgency_level_and_profile(self):
        fake_session = _fake_session(chief_complaint="headache")
        plan = planner.PlannerResult(reply="سؤال متابعة.", phase="interviewing", source="static")

        result, _, fake_pool = await _handle("صداع شديد فجأة", fake_session, plan)

        update_calls = [
            c for c in fake_pool.execute.call_args_list
            if "UPDATE virtual_doctor_sessions" in c.args[0]
        ]
        self.assertEqual(len(update_calls), 1)
        (_sql, _session_id, _phase, _chief_complaint, profile_json,
         urgency_level_arg, _specialty_id, _differential_json) = update_calls[0].args

        persisted_profile = json.loads(profile_json)

        self.assertEqual(urgency_level_arg, "urgent")
        self.assertEqual(persisted_profile["safety_warning_shown_for"], "urgent")
        self.assertIn("صداع شديد فجأة", persisted_profile["safety_flags_detected"])
        self.assertEqual(result["urgency_level"], "urgent")


if __name__ == "__main__":
    unittest.main()
