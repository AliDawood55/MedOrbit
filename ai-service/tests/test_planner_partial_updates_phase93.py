"""Phase 9.3: accepted extraction survives later wording failure safely."""

import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, reasoning
from virtual_doctor.reasoning_engine import prolog_engine
from tests.test_symbolic_planner_phase2 import _fake_session, _handle


FLOWS = interview_engine.FLOWS
ACTIVE = {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_INTERVIEW": "active"}
INTAKE = {"name": "Sara", "age": 30}


def _llm() -> planner.LLMPlanner:
    return planner.LLMPlanner(
        texts={},
        helpers={"extract_name": lambda value: value, "extract_age": lambda value: None},
        validators={
            "text_matches_language": reasoning._text_matches_language,
            "looks_coherent": reasoning._looks_coherent,
        },
    )


def _ctx(**overrides) -> planner.PlannerInput:
    values = dict(
        message="two hours",
        lang="en",
        phase="interviewing",
        chief_complaint="chest_pain",
        profile=dict(INTAKE),
        entities={},
        asked_questions=["How long has this been going on?"],
        session_id="phase-93",
    )
    values.update(overrides)
    return planner.PlannerInput(**values)


def _symbolic(inner) -> planner.SymbolicPlanner:
    return planner.build_symbolic(
        inner=inner,
        flows=FLOWS,
        texts={
            "ASK_AGE": interview_engine.ASK_AGE,
            "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY,
            "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT,
            "WRAP_UP": interview_engine.WRAP_UP,
        },
        helpers={
            "extract_name": interview_engine._extract_name,
            "extract_age": interview_engine._extract_age,
        },
    )


def _response(findings, question="How long has this been going on?"):
    return {
        "chief_complaint": "chest_pain",
        "findings": findings,
        "next_question": question,
    }


class TestLLMPartialResultContract(unittest.IsolatedAsyncioTestCase):
    async def test_valid_update_survives_repeat_wording_failure(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({"duration": "two hours"}))

        result = await llm.plan(_ctx())

        self.assertFalse(result.wording_valid)
        self.assertIsNone(result.reply)
        self.assertEqual(result.profile_updates, {"duration": "two hours"})

    async def test_malformed_response_preserves_nothing(self):
        llm = _llm()
        llm._ask = AsyncMock(side_effect=planner.PlannerError("unparseable JSON"))

        with self.assertRaises(planner.PlannerError):
            await llm.plan(_ctx())

    async def test_invalid_slot_is_not_promoted_by_wording_failure(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({"admin_override": "yes"}))

        with self.assertRaises(planner.PlannerError):
            await llm.plan(_ctx())

    async def test_malformed_values_are_not_promoted(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({
            "duration": ["two hours"], "severity": "   ", "age": "99",
        }))

        with self.assertRaises(planner.PlannerError):
            await llm.plan(_ctx())

    async def test_multiple_valid_updates_all_survive(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({
            "duration": "two hours", "character": "pressure",
        }))

        result = await llm.plan(_ctx())

        self.assertEqual(result.profile_updates, {
            "duration": "two hours", "character": "pressure",
        })

    async def test_zero_valid_updates_invents_nothing(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({}))

        with self.assertRaises(planner.PlannerError):
            await llm.plan(_ctx())

    async def test_each_post_acceptance_wording_failure_returns_partial(self):
        cases = (
            ("", "en"),
            ("How long has this been going on?", "en"),
            ("كم شدة الألم؟", "en"),
            ("xkq zzz plq?", "en"),
        )
        for question, lang in cases:
            with self.subTest(question=question):
                llm = _llm()
                llm._ask = AsyncMock(return_value=_response(
                    {"duration": "two hours"}, question))
                result = await llm.plan(_ctx(lang=lang))
                self.assertFalse(result.wording_valid)
                self.assertEqual(result.profile_updates["duration"], "two hours")


@unittest.skipUnless(prolog_engine.available(), "SWI-Prolog/pyswip not installed")
class TestSymbolicPartialResultIntegration(unittest.IsolatedAsyncioTestCase):
    async def test_handle_message_persists_update_before_sending_advanced_template(self):
        partial = planner.PlannerResult(
            reply=None,
            phase="interviewing",
            profile_updates={"duration": "two hours"},
            chief_complaint="chest_pain",
            source="llm:wording-invalid",
            wording_valid=False,
        )
        session = _fake_session(
            profile=dict(INTAKE), chief_complaint="chest_pain", language="en")

        with patch.dict(os.environ, ACTIVE), \
                patch.object(planner.LLMPlanner, "plan", new=AsyncMock(return_value=partial)):
            response, writes = await _handle(
                "two hours", session, patch_run_planner=False)

        character = next(slot["question_en"] for slot in FLOWS["chest_pain"]["slots"]
                         if slot["key"] == "character")
        persisted = json.loads(writes[0][4])
        self.assertEqual(response["reply"], character)
        self.assertEqual(response["profile_snapshot"]["duration"], "two hours")
        self.assertEqual(persisted["duration"], "two hours")
        self.assertNotIn(planner.ASKED_TOPICS_KEY, response["profile_snapshot"])

    async def test_prolog_sees_surviving_updates_and_templates_advanced_topic(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({
            "duration": "two hours", "character": "pressure",
        }))

        with patch.dict(os.environ, ACTIVE):
            result = await _symbolic(llm).plan(_ctx())

        radiation = next(slot["question_en"] for slot in FLOWS["chest_pain"]["slots"]
                         if slot["key"] == "radiation")
        self.assertEqual(result.reply, radiation)
        self.assertTrue(result.wording_valid)
        self.assertEqual(result.profile_updates["duration"], "two hours")
        self.assertEqual(result.profile_updates["character"], "pressure")
        self.assertIn("radiation", result.profile_updates[planner.ASKED_TOPICS_KEY])
        self.assertNotEqual(result.reply, _ctx().asked_questions[0])

    async def test_repeat_failure_does_not_stall_across_turns(self):
        profile = dict(INTAKE)
        replies = []
        for findings in (
            {"duration": "two hours", "character": "pressure"},
            {"radiation": "left arm"},
        ):
            llm = _llm()
            llm._ask = AsyncMock(return_value=_response(findings))
            with patch.dict(os.environ, ACTIVE):
                result = await _symbolic(llm).plan(_ctx(
                    profile=dict(profile),
                    asked_topics=list(profile.get(planner.ASKED_TOPICS_KEY) or []),
                ))
            replies.append(result.reply)
            profile.update(result.profile_updates)

        self.assertNotEqual(replies[0], replies[1])
        self.assertIn("radiation", profile)
        self.assertNotIn("_profile_after_this_turn", profile)
        self.assertNotIn("_pending_updates", profile)

    async def test_premature_ready_keeps_same_turn_updates_and_continues(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response({"character": "pressure"}))
        llm._check_readiness = AsyncMock(return_value=True)
        ctx = _ctx(
            profile={**INTAKE, "duration": "two hours", "location": "chest"},
            turn_index=planner.COMPLETENESS_MIN_TURNS,
        )

        with patch.dict(os.environ, ACTIVE):
            result = await _symbolic(llm).plan(ctx)

        self.assertFalse(result.ready_for_diagnosis)
        self.assertEqual(result.profile_updates["character"], "pressure")
        self.assertIsNotNone(result.reply)
        self.assertIn("symbolic-continue", result.source)

    async def test_off_flow_wording_cannot_escape_with_surviving_update(self):
        llm = _llm()
        llm._ask = AsyncMock(return_value=_response(
            {"duration": "two hours"}, "What is your favorite color?"))

        with patch.dict(os.environ, ACTIVE):
            result = await _symbolic(llm).plan(_ctx(asked_questions=[]))

        character = next(slot["question_en"] for slot in FLOWS["chest_pain"]["slots"]
                         if slot["key"] == "character")
        self.assertEqual(result.reply, character)
        self.assertEqual(result.profile_updates["duration"], "two hours")


class TestLegacyModeContract(unittest.IsolatedAsyncioTestCase):
    async def test_non_symbolic_partial_result_still_uses_static_fallback(self):
        partial = planner.PlannerResult(
            reply=None,
            phase="interviewing",
            profile_updates={"duration": "two hours"},
            chief_complaint="chest_pain",
            source="llm:wording-invalid",
            wording_valid=False,
        )
        primary = MagicMock(name="primary")
        primary.name = "llm"
        primary.plan = AsyncMock(return_value=partial)
        fallback = MagicMock(name="fallback")
        fallback.plan = AsyncMock(return_value=planner.PlannerResult(
            reply="static question", phase="interviewing", source="static"))

        with patch.dict(os.environ, {"VD_SYMBOLIC": "0"}), \
                patch.object(interview_engine, "_planner", primary), \
                patch.object(interview_engine, "_fallback_planner", fallback):
            result = await interview_engine._run_planner(_ctx())

        self.assertEqual(result.reply, "static question")
        self.assertEqual(result.profile_updates, {})
        self.assertEqual(result.source, "llm->static")


if __name__ == "__main__":
    unittest.main()
