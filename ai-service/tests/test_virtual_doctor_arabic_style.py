"""
Virtual Doctor Arabic Conversation Style — behavior tests.

Real user feedback that originally motivated a Levantine/dialect pass:
"طريقة كلامه مستفزة وغير حقيقية" (the way it talks is grating and doesn't
feel real). That dialect pass was later reversed by an explicit product
decision (MedOrbit Virtual Doctor — Formal Arabic Voice Quality Upgrade):
the dialect wording itself drew the same "not real"-style feedback it was
meant to fix, so every template now uses simplified formal Modern Standard
Arabic (فصحى مبسطة) instead. This file was updated in that reversal to pin
CURRENT wording/behavior rather than the dialect it originally asserted —
the authoritative pin for the new formal-style constants lives in
test_virtual_doctor_formal_arabic_style.py; this file is now primarily a
regression guard against the specific stiff/robotic phrases named in the
original task, plus the safety-continuation mechanism itself.

No production medical/diagnosis/safety-detection logic is touched by this
batch, and none of these tests exercise it — they check WORDING only:
presence of natural phrasing, absence of the specific stiff/robotic phrases
named in the task, and (for the safety-continuation case) that the
underlying mechanism — warn-but-continue, not hard-stop — is unaffected by
the wording change.

Tests avoid asserting full paragraphs (the wording is allowed to keep
evolving) in favor of substring/negative assertions, per the task's own
guidance. Where a full multi-turn flow is needed (test 6), this reuses the
same DB/RAG/planner-mocking harness as
tests/test_virtual_doctor_safety_continuation.py — no real DB, Ollama, STT,
TTS, or network access anywhere in this file. Test 7 mocks only
`requests.post` to capture the outgoing prompt without a real Ollama call.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, reasoning
from virtual_doctor.planner import LLMPlanner, PlannerInput

_ROBOTIC_PHRASES = (
    "ما الذي يزعجك اليوم",
    "تشرّفت بمعرفتك",
    "هل سمعت اسمك بشكل صحيح",
)


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
    """Runs handle_message() once, no real DB/Ollama — same harness as
    test_virtual_doctor_safety_continuation.py."""
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

    return result, fake_pool



class TestGreetingIsNatural(unittest.TestCase):
    def test_greeting_asks_for_name_without_stiff_phrasing(self):
        greeting = interview_engine.GREETING["ar"]

        self.assertIn("اسمك", greeting)
        self.assertNotIn("مرحباً، أنا مساعد الطبيب الافتراضي", greeting)
        self.assertLess(len(greeting), 80)



class TestAskAgeIsNatural(unittest.TestCase):
    def test_intake_turn_after_name_asks_age_without_formal_filler(self):
        ctx = PlannerInput(
            message="علي", lang="ar", phase="intake", chief_complaint=None,
            profile={}, entities={},
        )
        result = planner._intake_turn(
            ctx,
            texts={
                "ASK_AGE": interview_engine.ASK_AGE,
                "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY,
                "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT,
                "WRAP_UP": interview_engine.WRAP_UP,
            },
            extract_name=interview_engine._extract_name,
            extract_age=interview_engine._extract_age,
        )

        self.assertIn("علي", result.reply)
        self.assertIn("كم عمرك", result.reply)
        self.assertNotIn("تشرّفت بمعرفتك", result.reply)



class TestAskChiefComplaintIsNatural(unittest.TestCase):
    def test_intake_turn_after_age_asks_complaint_without_stiff_phrasing(self):
        ctx = PlannerInput(
            message="25", lang="ar", phase="intake", chief_complaint=None,
            profile={"name": "علي"}, entities={},
        )
        result = planner._intake_turn(
            ctx,
            texts={
                "ASK_AGE": interview_engine.ASK_AGE,
                "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY,
                "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT,
                "WRAP_UP": interview_engine.WRAP_UP,
            },
            extract_name=interview_engine._extract_name,
            extract_age=interview_engine._extract_age,
        )

        self.assertEqual(result.phase, "greeting")
        self.assertNotIn("ما الذي يزعجك اليوم", result.reply)
        self.assertLess(len(result.reply), 40)



class TestSuspiciousNameConfirmationIsNatural(unittest.TestCase):
    def test_confirmation_question_is_short_and_not_stiff(self):
        _, _, _, reply = interview_engine._apply_confirmation_layer(
            {}, "intake", "درج", "ar",
        )

        self.assertIn("درج", reply)
        for phrase in _ROBOTIC_PHRASES:
            self.assertNotIn(phrase, reply)
        self.assertLess(len(reply), 60)



class TestMisheardHeadacheConfirmationIsNatural(unittest.TestCase):
    def test_confirmation_question_matches_expected_wording_not_shock(self):
        _, _, _, reply = interview_engine._apply_confirmation_layer(
            {}, "greeting", "عندي صدق شديد فجأة", "ar",
        )

        self.assertEqual(reply, "هل تقصد صداع شديد بدأ فجأة؟")
        self.assertNotIn("الصدمة", reply)
        self.assertLess(len(reply), 40)



class TestUrgentContinuationIsConciseAndContinues(unittest.IsolatedAsyncioTestCase):
    async def test_hematuria_warns_concisely_and_keeps_interviewing(self):
        fake_session = _fake_session(chief_complaint="headache")
        plan = planner.PlannerResult(
            reply="بتحس بحرقان لما تتبول؟", phase="interviewing", source="static",
        )

        result, _ = await _run_turn("عندي دم بالبول", fake_session, plan)

        self.assertEqual(result["urgency_level"], "urgent")
        self.assertNotEqual(result["phase"], "complete")
        self.assertIn("تقييمًا طبيًا عاجلًا", result["reply"])
        self.assertNotIn("بس خليني", result["reply"])
        self.assertIn("سأطرح عليك", result["reply"])



class TestLLMPlannerPromptCarriesArabicStyleRules(unittest.IsolatedAsyncioTestCase):
    def _make_planner(self):
        return LLMPlanner(
            texts={},
            helpers={"extract_name": lambda m: m, "extract_age": lambda m: None},
            validators={
                "text_matches_language": reasoning._text_matches_language,
                "looks_coherent": reasoning._looks_coherent,
            },
        )

    async def _captured_prompt(self, lang: str) -> str:
        captured = {}

        def fake_post(url, json=None, timeout=None):  # noqa: A002 - matches requests.post signature
            captured["payload"] = json
            response = MagicMock()
            response.raise_for_status = MagicMock()
            response.json.return_value = {
                "message": {"content": "{\"next_question\": \"ok\", \"findings\": {}}"},
            }
            return response

        ctx = PlannerInput(
            message="عندي صداع" if lang == "ar" else "I have a headache",
            lang=lang, phase="interviewing", chief_complaint="headache",
            profile={}, entities={}, history=[], chunks=[], context_block="",
            turn_index=2, asked_questions=[],
        )
        with patch.object(planner.requests, "post", side_effect=fake_post):
            await self._make_planner()._ask(ctx)
        return captured["payload"]["messages"][1]["content"]

    async def test_arabic_prompt_contains_style_constraints(self):
        prompt = await self._captured_prompt("ar")

        self.assertIn("EXACTLY ONE question", prompt)
        self.assertIn("Modern Standard Arabic", prompt)
        self.assertIn("NOT Levantine/Palestinian dialect", prompt)
        self.assertIn("definitive diagnosis", prompt)
        self.assertIn("one short sentence", prompt)

    async def test_english_prompt_does_not_carry_the_arabic_specific_rule(self):
        """The Arabic style bullet is gated on ctx.lang == "ar" — it must not
        leak into English-language turns."""
        prompt = await self._captured_prompt("en")

        self.assertNotIn("Modern Standard Arabic", prompt)



class TestStaticFallbackAvoidsWorstRoboticPhrases(unittest.TestCase):
    def test_top_level_intake_templates_are_clean(self):
        for template in (
            interview_engine.GREETING, interview_engine.ASK_AGE,
            interview_engine.ASK_COMPLAINT, interview_engine.WRAP_UP,
        ):
            for phrase in _ROBOTIC_PHRASES:
                self.assertNotIn(phrase, template["ar"])

    def test_flow_json_questions_are_clean(self):
        """flows/*.json were not rewritten by this batch (they were already
        clinically-precise formal Arabic, not the specific robotic phrases
        named in the task) — this is a regression guard, not a change."""
        for flow in interview_engine.FLOWS.values():
            for slot in flow.get("slots", []):
                question = slot.get("question_ar", "")
                for phrase in _ROBOTIC_PHRASES:
                    self.assertNotIn(phrase, question)


if __name__ == "__main__":
    unittest.main()
