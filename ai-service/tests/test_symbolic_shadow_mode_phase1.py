"""
Symbolic reasoning layer, Phase 1 — shadow mode changes nothing.

This is the file that makes Phase 1 safe to merge. The symbolic layer now runs
inside handle_message(), so the load-bearing claim is not "the new code works"
but "the old code still does exactly what it did".

The strongest available form of that claim is a differential test: run the same
consultation turn twice through the real handle_message() — once with
VD_SYMBOLIC=0 and once with VD_SYMBOLIC=1 — and require the reply, phase,
urgency, chief complaint, profile snapshot AND the exact arguments persisted to
PostgreSQL to be identical. Not "similar": equal.

Also pinned here: the layer must be inert when the flag is off (no engine boot,
no fact building at all), and a fault inside it must be swallowed. An
observation-only layer that can break a consultation is worse than no layer.

Mocking follows tests/test_virtual_doctor_safety_continuation.py — DB pool,
per-turn RAG/memory context and doctor-turn history are mocked; the safety
layer, entity extractor and every deterministic helper run for real.
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
    """Run handle_message() with the DB, RAG/memory and history mocked.

    Returns (result, persisted_update_args) so a test can compare both what the
    patient saw and what was written to the session row.
    """
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=fake_session)
    fake_pool.execute = AsyncMock()

    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(
            interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
        stack.enter_context(patch.object(
            interview_engine, "_build_turn_context", new=AsyncMock(return_value={
                "history": [], "chunks": [], "context_block": "",
                "memory_ms": 0.0, "rag_ms": 0.0})))
        stack.enter_context(patch.object(
            interview_engine, "_run_planner", new=AsyncMock(return_value=planner_result)))
        stack.enter_context(patch.object(
            interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
        result = await interview_engine.handle_message(fake_session["session_id"], message)

    updates = [c for c in fake_pool.execute.await_args_list
               if "UPDATE virtual_doctor_sessions" in c.args[0]]
    return result, [c.args for c in updates]


_TURNS = [
    ("عندي صداع شديد فجأة", _fake_session(chief_complaint="headache"),
     planner.PlannerResult(reply="منذ متى بدأ الصداع؟", phase="interviewing", source="static")),
    ("عندي ضيق تنفس", _fake_session(chief_complaint="chest_pain"),
     planner.PlannerResult(reply="هل يوجد ألم في الصدر؟", phase="interviewing", source="static")),
    ("من يومين تقريبا", _fake_session(chief_complaint="headache",
                                      profile={"name": "سارة", "age": 30}),
     planner.PlannerResult(reply="ما شدة الألم؟", phase="interviewing",
                           profile_updates={"duration": "من يومين تقريبا"}, source="static")),
    ("اسمي سارة", _fake_session(phase="intake"),
     planner.PlannerResult(reply="كم عمرك؟", phase="intake",
                           profile_updates={"name": "سارة"}, source="intake")),
]



class TestDisabledByDefault(unittest.IsolatedAsyncioTestCase):
    async def test_observe_turn_returns_none_when_the_flag_is_absent(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("VD_SYMBOLIC", None)
            self.assertIsNone(await reasoning_engine.observe_turn("s1"))

    async def test_no_facts_are_built_at_all_when_disabled(self):
        """Inert, not merely ignored — the flag is checked before any work."""
        with patch.dict(os.environ, {"VD_SYMBOLIC": "0"}), \
                patch.object(reasoning_engine.fact_builder, "build_facts") as build:
            await reasoning_engine.observe_turn("s1", entities={"symptoms": ["headache"]})
        build.assert_not_called()

    async def test_the_engine_is_not_booted_when_disabled(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "0"}), \
                patch.object(prolog_engine, "_load_engine") as load:
            await reasoning_engine.observe_turn("s1")
        load.assert_not_called()



class TestShadowModeChangesNothing(unittest.IsolatedAsyncioTestCase):
    async def _run_both(self, message, session, plan):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "0"}):
            off_result, off_writes = await _handle(message, session, plan)
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}):
            on_result, on_writes = await _handle(message, session, plan)
        return (off_result, off_writes), (on_result, on_writes)

    async def test_every_turn_is_identical_with_the_flag_on_and_off(self):
        for message, session, plan in _TURNS:
            with self.subTest(message=message):
                (off, _), (on, _) = await self._run_both(
                    message, session, plan)

                self.assertEqual(off["reply"], on["reply"])
                self.assertEqual(off["phase"], on["phase"])
                self.assertEqual(off["urgency_level"], on["urgency_level"])
                self.assertEqual(off["chief_complaint"], on["chief_complaint"])
                self.assertEqual(off["profile_snapshot"], on["profile_snapshot"])
                self.assertEqual(off, on)

    async def test_what_is_persisted_to_postgres_is_identical(self):
        """The reply is only half of it — the session row must match too, or
        the NEXT turn diverges even though this one looked the same."""
        for message, session, plan in _TURNS:
            with self.subTest(message=message):
                (_, off_writes), (_, on_writes) = await self._run_both(
                    message, session, plan)
                self.assertEqual(off_writes, on_writes)
                self.assertTrue(off_writes)

    async def test_the_planner_is_called_with_identical_input(self):
        """Compared field by field, minus EntityExtractor's own wall-clock
        measurement: entities["_processing_ms"] differs between ANY two runs,
        flag or no flag, so including it would test the clock rather than the
        behaviour."""
        message, session, plan = _TURNS[0]
        calls = {}
        for flag in ("0", "1"):
            fake_pool = AsyncMock()
            fake_pool.fetchrow = AsyncMock(return_value=session)
            fake_pool.execute = AsyncMock()
            run_planner = AsyncMock(return_value=plan)
            with patch.dict(os.environ, {"VD_SYMBOLIC": flag}), \
                    contextlib.ExitStack() as stack:
                stack.enter_context(patch.object(
                    interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
                stack.enter_context(patch.object(
                    interview_engine, "_build_turn_context", new=AsyncMock(return_value={
                        "history": [], "chunks": [], "context_block": "",
                        "memory_ms": 0.0, "rag_ms": 0.0})))
                stack.enter_context(patch.object(
                    interview_engine, "_run_planner", new=run_planner))
                stack.enter_context(patch.object(
                    interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
                await interview_engine.handle_message(session["session_id"], message)
            ctx = run_planner.await_args.args[0]
            calls[flag] = {
                field: dict(value, _processing_ms=None) if field == "entities" else value
                for field, value in vars(ctx).items()
            }

        self.assertEqual(calls["0"], calls["1"])
        self.assertEqual(calls["0"]["safety_hint"], calls["1"]["safety_hint"])
        self.assertEqual(calls["0"]["profile"], calls["1"]["profile"])

    async def test_the_symbolic_layer_really_did_run_when_enabled(self):
        """Guards against the comparison above passing vacuously because the
        shadow call was never reached."""
        message, session, plan = _TURNS[0]
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}), \
                patch.object(reasoning_engine, "observe_turn",
                             new=AsyncMock(return_value=None)) as observe:
            await _handle(message, session, plan)
        observe.assert_awaited_once()
        self.assertEqual(observe.await_args.kwargs["chief_complaint"], "headache")
        self.assertIn("safety_result", observe.await_args.kwargs)

    async def test_no_extra_database_round_trips_are_made_when_enabled(self):
        """Shadow mode is fed only values already in hand. Adding a query for
        it would change this turn's I/O, which "no behaviour change" includes."""
        message, session, plan = _TURNS[0]
        counts = {}
        for flag in ("0", "1"):
            fake_pool = AsyncMock()
            fake_pool.fetchrow = AsyncMock(return_value=session)
            fake_pool.execute = AsyncMock()
            with patch.dict(os.environ, {"VD_SYMBOLIC": flag}), \
                    contextlib.ExitStack() as stack:
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
                await interview_engine.handle_message(session["session_id"], message)
            counts[flag] = (fake_pool.execute.await_count, fake_pool.fetchrow.await_count)

        self.assertEqual(counts["0"], counts["1"])



class TestShadowFailuresAreSwallowed(unittest.IsolatedAsyncioTestCase):
    async def test_a_raising_fact_builder_does_not_break_the_turn(self):
        message, session, plan = _TURNS[0]
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}), \
                patch.object(reasoning_engine.fact_builder, "build_facts",
                             side_effect=RuntimeError("builder exploded")):
            result, _ = await _handle(message, session, plan)
        self.assertIn("منذ متى بدأ الصداع؟", result["reply"])
        self.assertEqual(result["urgency_level"], "urgent")

    async def test_a_raising_engine_does_not_break_the_turn(self):
        message, session, plan = _TURNS[0]
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}), \
                patch.object(reasoning_engine, "reason",
                             side_effect=RuntimeError("engine exploded")):
            result, _ = await _handle(message, session, plan)
        self.assertIn("منذ متى بدأ الصداع؟", result["reply"])
        self.assertEqual(result["urgency_level"], "urgent")

    async def test_a_missing_prolog_runtime_does_not_break_the_turn(self):
        message, session, plan = _TURNS[1]
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}), \
                patch.object(prolog_engine, "_ensure_engine",
                             side_effect=prolog_engine.PrologUnavailable("no swipl")):
            result, _ = await _handle(message, session, plan)
        self.assertEqual(result["urgency_level"], "emergency")

    async def test_observe_turn_swallows_and_returns_none(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}), \
                patch.object(reasoning_engine.fact_builder, "build_facts",
                             side_effect=RuntimeError("nope")):
            self.assertIsNone(await reasoning_engine.observe_turn("s1"))



@unittest.skipUnless(prolog_engine.available(),
                     "SWI-Prolog/pyswip not installed on this machine")
class TestShadowObservationIsMeaningful(unittest.IsolatedAsyncioTestCase):
    async def test_an_urgent_turn_is_observed_with_evidence(self):
        safety = interview_engine._check_safety("عندي صداع شديد فجأة", "ar")
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}):
            result = await reasoning_engine.observe_turn(
                "sess-shadow",
                profile={"age": 30, "duration": "من يومين"},
                entities={"symptoms": ["headache"]},
                chief_complaint="headache",
                safety_result=safety,
            )

        self.assertIsNotNone(result)
        self.assertTrue(result.available)
        self.assertEqual(result.urgency.level, "urgent")
        self.assertTrue(result.urgency.rules)
        self.assertIn("headache", result.knowledge.symptoms)
        self.assertIn("duration", result.knowledge.answered)
        self.assertIn("radiation", result.knowledge.unanswered)
        self.assertGreater(result.query_ms, 0.0)

    async def test_the_store_is_left_empty_after_an_observation(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}):
            await reasoning_engine.observe_turn(
                "sess-shadow", entities={"symptoms": ["headache"]})
        self.assertEqual(prolog_engine._fact_count_all(), 0)


if __name__ == "__main__":
    unittest.main()
