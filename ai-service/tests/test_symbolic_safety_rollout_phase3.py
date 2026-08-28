"""
Symbolic safety, Phase 3 — rollout modes and end-to-end integration.

The rule logic is tested in test_symbolic_safety_phase3.py. This file tests the
consultation: that shadow mode changes nothing a patient sees, that active mode
can only escalate, and that the mandatory safety warning still comes FIRST.

WARNING ORDER IS THE POINT OF TestWarningPrecedesEverything
-----------------------------------------------------------
Phase 2 lets a red flag reorder the interview so `associated_symptoms` is asked
first. That was approved on one condition: the deterministic warning is still
composed and presented BEFORE the safety-relevant follow-up question, never
after, and question priority may not delay, suppress, weaken, replace or reword
it. The safety prefix is applied outermost in handle_message, after the
correction prefix, which is what makes that true — and it is asserted here on
the composed reply rather than inferred from the code.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, reasoning_engine
from virtual_doctor.reasoning_engine import prolog_engine

_needs_engine = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed on this machine"
)

OFF = {"VD_SYMBOLIC": "0"}
SHADOW = {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_SAFETY": "shadow",
          "VD_SYMBOLIC_INTERVIEW": "shadow"}
ACTIVE = {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_SAFETY": "active",
          "VD_SYMBOLIC_INTERVIEW": "shadow"}

INTAKE = {"name": "Sara", "age": 30}


def _fake_session(session_id="public-id", profile=None, phase="interviewing",
                  chief_complaint="chest_pain", language="ar", urgency_level=None):
    return {"id": "row-id", "session_id": session_id, "language": language,
            "phase": phase, "chief_complaint": chief_complaint,
            "patient_profile": json.dumps(profile if profile is not None else dict(INTAKE)),
            "urgency_level": urgency_level,
            "recommended_specialty_id": None, "differential": None}


async def _handle(message, session, planner_result=None):
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=session)
    fake_pool.execute = AsyncMock()

    plan = planner_result or planner.PlannerResult(
        reply="سؤال المتابعة", phase="interviewing", source="static")

    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(
            interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
        stack.enter_context(patch.object(
            interview_engine, "_build_turn_context", new=AsyncMock(return_value={
                "history": [], "chunks": [], "context_block": "",
                "memory_ms": 0.0, "rag_ms": 0.0})))
        stack.enter_context(patch.object(
            interview_engine, "_run_planner", new=AsyncMock(return_value=plan)))
        stack.enter_context(patch.object(
            interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
        result = await interview_engine.handle_message(session["session_id"], message)

    writes = [c.args for c in fake_pool.execute.await_args_list
              if "UPDATE virtual_doctor_sessions" in c.args[0]]
    return result, writes


_TURNS = [
    ("عندي صداع شديد فجأة", "headache", "urgent"),
    ("عندي ضيق تنفس", "chest_pain", "emergency"),
    ("عندي صداع", "headache", None),
    ("من يومين تقريبا", "headache", None),
]



class TestSafetyRolloutModes(unittest.TestCase):
    def test_default_is_shadow_when_the_master_switch_is_on(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}, clear=False):
            os.environ.pop("VD_SYMBOLIC_SAFETY", None)
            self.assertEqual(prolog_engine.safety_mode(), "shadow")
            self.assertFalse(prolog_engine.safety_active())

    def test_master_switch_off_forces_mode_off(self):
        for requested in ("shadow", "active", "off"):
            with patch.dict(os.environ, {"VD_SYMBOLIC": "0",
                                         "VD_SYMBOLIC_SAFETY": requested}):
                self.assertEqual(prolog_engine.safety_mode(), "off")
                self.assertFalse(prolog_engine.safety_active())

    def test_an_invalid_mode_falls_back_to_shadow_never_active(self):
        for bad in ("banana", "ACTIVE!", "1", "", "on"):
            with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                         "VD_SYMBOLIC_SAFETY": bad}):
                with self.subTest(value=bad):
                    self.assertEqual(prolog_engine.safety_mode(), "shadow")
                    self.assertFalse(prolog_engine.safety_active())

    def test_active_requires_both_settings(self):
        with patch.dict(os.environ, ACTIVE):
            self.assertTrue(prolog_engine.safety_active())

    def test_safety_and_interview_modes_are_independent(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                     "VD_SYMBOLIC_SAFETY": "active",
                                     "VD_SYMBOLIC_INTERVIEW": "shadow"}):
            self.assertTrue(prolog_engine.safety_active())
            self.assertFalse(prolog_engine.interview_active())

    def test_status_reports_both_modes_and_the_budget(self):
        with patch.dict(os.environ, SHADOW):
            status = prolog_engine.status()
        self.assertEqual(status["safety_mode"], "shadow")
        self.assertEqual(status["interview_mode"], "shadow")
        self.assertEqual(status["inference_limit"], prolog_engine.INFERENCE_LIMIT)



class TestShadowModeIsInvisible(unittest.IsolatedAsyncioTestCase):
    async def test_every_turn_is_identical_off_versus_shadow(self):
        for message, complaint, _expected in _TURNS:
            session = _fake_session(chief_complaint=complaint)
            with self.subTest(message=message):
                with patch.dict(os.environ, OFF):
                    off_result, off_writes = await _handle(message, session)
                with patch.dict(os.environ, SHADOW):
                    on_result, on_writes = await _handle(message, session)
                self.assertEqual(off_result, on_result)
                self.assertEqual(off_writes, on_writes)

    async def test_no_symbolic_urgency_is_passed_to_the_continuation_in_shadow(self):
        session = _fake_session(chief_complaint="headache")
        real = interview_engine._apply_safety_continuation
        seen = {}

        def spy(*args, **kwargs):
            seen["symbolic_urgency"] = kwargs.get("symbolic_urgency")
            return real(*args, **kwargs)

        with patch.dict(os.environ, SHADOW), \
                patch.object(interview_engine, "_apply_safety_continuation", side_effect=spy):
            await _handle("عندي ضيق تنفس", session)
        self.assertIsNone(seen["symbolic_urgency"])

    async def test_the_symbolic_layer_really_ran_in_shadow(self):
        """Guards against the equality above passing vacuously."""
        session = _fake_session(chief_complaint="headache")
        with patch.dict(os.environ, SHADOW), \
                patch.object(interview_engine, "_observe_symbolic_safety",
                             new=AsyncMock(return_value=None)) as observe:
            await _handle("عندي صداع شديد فجأة", session)
        observe.assert_awaited_once()

    async def test_off_mode_does_not_run_the_symbolic_layer_at_all(self):
        session = _fake_session(chief_complaint="headache")
        with patch.dict(os.environ, OFF), \
                patch.object(reasoning_engine, "decide_safety_async") as decide:
            await _handle("عندي صداع شديد فجأة", session)
        decide.assert_not_called()



@_needs_engine
class TestActiveModeOnlyEscalates(unittest.IsolatedAsyncioTestCase):
    async def test_pinned_routine_turns_stay_routine_in_active_mode(self):
        """The whole rule set was shaped so this holds. Checked end to end."""
        for message in ("عندي صداع", "عندي صداع وغثيان", "شفت دم", "وين قسم الطوارئ؟"):
            session = _fake_session(chief_complaint="headache")
            with self.subTest(message=message):
                with patch.dict(os.environ, OFF):
                    off_result, _ = await _handle(message, session)
                with patch.dict(os.environ, ACTIVE):
                    on_result, _ = await _handle(message, session)
                self.assertEqual(off_result["urgency_level"], on_result["urgency_level"])
                self.assertEqual(off_result["reply"], on_result["reply"])

    async def test_a_deterministic_urgent_turn_is_not_lowered(self):
        session = _fake_session(chief_complaint="headache")
        with patch.dict(os.environ, ACTIVE):
            result, _ = await _handle("عندي صداع شديد فجأة", session)
        self.assertEqual(result["urgency_level"], "urgent")

    async def test_a_deterministic_emergency_turn_is_not_lowered(self):
        session = _fake_session(chief_complaint="chest_pain")
        with patch.dict(os.environ, ACTIVE):
            result, _ = await _handle("عندي ضيق تنفس", session)
        self.assertEqual(result["urgency_level"], "emergency")

    async def test_prior_session_urgency_survives_a_mild_later_turn(self):
        """Escalation-only across turns, with the symbolic layer live."""
        for prior in ("urgent", "emergency"):
            session = _fake_session(chief_complaint="headache", urgency_level=prior)
            with self.subTest(prior=prior):
                with patch.dict(os.environ, ACTIVE):
                    result, _ = await _handle("من يومين تقريبا", session)
                self.assertEqual(result["urgency_level"], prior)

    async def test_a_symbolic_failure_in_active_mode_falls_back_safely(self):
        session = _fake_session(chief_complaint="headache")
        with patch.dict(os.environ, OFF):
            baseline, _ = await _handle("عندي صداع شديد فجأة", session)
        with patch.dict(os.environ, ACTIVE), \
                patch.object(prolog_engine, "_ensure_engine",
                             side_effect=prolog_engine.PrologUnavailable("no swipl")):
            result, _ = await _handle("عندي صداع شديد فجأة", session)
        self.assertEqual(result["urgency_level"], baseline["urgency_level"])
        self.assertEqual(result["reply"], baseline["reply"])

    async def test_an_unavailable_reasoner_is_never_read_as_routine(self):
        session = _fake_session(chief_complaint="chest_pain")
        with patch.dict(os.environ, ACTIVE), \
                patch.object(reasoning_engine, "decide_safety_async",
                             new=AsyncMock(return_value=reasoning_engine.SafetyVerdict
                                           .unavailable("down"))):
            result, _ = await _handle("عندي ضيق تنفس", session)
        self.assertEqual(result["urgency_level"], "emergency")



class TestWarningPrecedesEverything(unittest.IsolatedAsyncioTestCase):
    async def test_the_warning_precedes_the_follow_up_question(self):
        session = _fake_session(chief_complaint="chest_pain")
        question = "هل لديك غثيان أو تعرق؟"
        plan = planner.PlannerResult(reply=question, phase="interviewing", source="static")
        for env in (OFF, SHADOW, ACTIVE):
            with self.subTest(env=env.get("VD_SYMBOLIC_SAFETY", "off")):
                with patch.dict(os.environ, env):
                    result, _ = await _handle("عندي صداع شديد فجأة", session, plan)
                reply = result["reply"]
                self.assertIn(question, reply)
                self.assertLess(reply.index(interview_engine.SAFETY_URGENT_WARNING["ar"][:20]),
                                reply.index(question))

    async def test_the_warning_precedes_a_correction_acknowledgement(self):
        """The safety prefix is applied outermost, so a correction turn cannot
        get in front of it."""
        session = _fake_session(chief_complaint="headache",
                                profile={"name": "سارة", "age": 23})
        with patch.dict(os.environ, SHADOW):
            result, _ = await _handle("لا، عمري ٢٤ وعندي صداع شديد فجأة", session)
        reply = result["reply"]
        warning = interview_engine.SAFETY_URGENT_WARNING["ar"][:20]
        if "عدّلت العمر" in reply:
            self.assertLess(reply.index(warning), reply.index("عدّلت العمر"))

    async def test_the_emergency_warning_text_is_unchanged(self):
        session = _fake_session(chief_complaint="chest_pain")
        for env in (OFF, SHADOW, ACTIVE):
            with self.subTest(env=env.get("VD_SYMBOLIC_SAFETY", "off")):
                with patch.dict(os.environ, env):
                    result, _ = await _handle("عندي ضيق تنفس", session)
                self.assertIn("🚨", result["reply"])
                self.assertIn("101", result["reply"])
                self.assertIn(interview_engine.SAFETY_EMERGENCY_CONTINUATION["ar"],
                              result["reply"])

    async def test_repeated_warning_behaviour_is_unchanged(self):
        """Full warning on the first turn at a tier, short reminder after."""
        first = _fake_session(chief_complaint="headache")
        repeat = _fake_session(chief_complaint="headache", urgency_level="urgent",
                               profile={**INTAKE, "safety_warning_shown_for": "urgent"})
        for env in (OFF, SHADOW, ACTIVE):
            with self.subTest(env=env.get("VD_SYMBOLIC_SAFETY", "off")):
                with patch.dict(os.environ, env):
                    first_result, _ = await _handle("عندي صداع شديد فجأة", first)
                    repeat_result, _ = await _handle("عندي صداع شديد فجأة", repeat)
                self.assertIn(interview_engine.SAFETY_URGENT_WARNING["ar"],
                              first_result["reply"])
                self.assertIn(interview_engine.SAFETY_URGENT_REMINDER["ar"],
                              repeat_result["reply"])

    async def test_phase_2_question_ordering_still_works(self):
        with patch.dict(os.environ, {**SHADOW, "VD_SYMBOLIC_INTERVIEW": "active"}):
            self.assertIs(interview_engine._select_planner(),
                          interview_engine._symbolic_planner)
            self.assertTrue(prolog_engine.interview_active())



@_needs_engine
class TestDivergenceCounters(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        interview_engine._SAFETY_DIVERGENCE.reset()

    async def test_counters_record_turns_and_agreement(self):
        session = _fake_session(chief_complaint="headache")
        with patch.dict(os.environ, SHADOW):
            await _handle("عندي صداع", session)
        counters = interview_engine.safety_divergence_counters()
        self.assertEqual(counters["turns"], 1)
        self.assertEqual(counters["available"], 1)
        self.assertEqual(counters["agree"], 1)
        self.assertEqual(counters["downgraded"], 0)

    async def test_downgrades_are_counted_and_must_stay_zero(self):
        session = _fake_session(chief_complaint="chest_pain")
        with patch.dict(os.environ, SHADOW):
            for message, _c, _u in _TURNS:
                await _handle(message, session)
        self.assertEqual(interview_engine.safety_divergence_counters()["downgraded"], 0)

    async def test_rule_hits_are_recorded_by_rule_id(self):
        session = _fake_session(chief_complaint="chest_pain",
                                profile={**INTAKE, "associated_symptoms_detected":
                                         ["chest_pain", "shortness_of_breath"]})
        with patch.dict(os.environ, SHADOW):
            await _handle("من ساعتين", session)
        hits = interview_engine.safety_divergence_counters()["rule_hits"]
        self.assertIn("chest_pain_with_dyspnea", hits)

    async def test_counters_carry_no_patient_data(self):
        session = _fake_session(chief_complaint="headache")
        with patch.dict(os.environ, SHADOW):
            await _handle("عندي صداع شديد فجأة", session)
        blob = json.dumps(interview_engine.safety_divergence_counters(), ensure_ascii=False)
        self.assertNotIn("سارة", blob)
        self.assertNotIn("صداع", blob)
        self.assertNotIn("public-id", blob)


if __name__ == "__main__":
    unittest.main()
