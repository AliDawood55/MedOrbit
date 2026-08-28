"""Phase 9.4: active symbolic extraction and wording trust-boundary tests."""

import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, reasoning_engine
from virtual_doctor.reasoning_engine import prolog_engine
from tests.test_symbolic_planner_phase2 import (
    ACTIVE, FLOWS, INTAKE, OFF, SHADOW, _FakeInner, _ctx, _fake_session,
    _handle, _symbolic,
)


_needs_prolog = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed")


def _filtered(message, updates, *, topic="duration", complaint="chest_pain", lang="en"):
    symbolic = _symbolic(_FakeInner())
    ctx = _ctx(
        message=message,
        lang=lang,
        chief_complaint=complaint,
        asked_topics=[topic] if topic else [],
    )
    result = planner.PlannerResult(
        reply="question",
        phase="interviewing",
        chief_complaint=complaint,
        profile_updates=dict(updates),
    )
    return symbolic._filter_active_updates(ctx, result)


class TestDeterministicNonAnswers(unittest.TestCase):
    def test_arabic_non_answer_rejected_for_duration(self):
        self.assertEqual({}, _filtered(
            "لا أتذكر", {"duration": "لا أتذكر"}, lang="ar"))

    def test_english_non_answer_rejected_for_duration(self):
        self.assertEqual({}, _filtered(
            "I don't know", {"duration": "I don't know"}))

    def test_non_answer_rejected_for_severity(self):
        self.assertEqual({}, _filtered(
            "not sure", {"severity": "not sure"}, topic="severity", complaint="headache"))

    def test_non_answer_rejected_for_character(self):
        self.assertEqual({}, _filtered(
            "مش عارف", {"character": "مش عارف"}, topic="character", lang="ar"))

    def test_non_answer_rejected_for_location(self):
        self.assertEqual({}, _filtered(
            "ما بعرف", {"location": "ما بعرف"}, topic="location",
            complaint="headache", lang="ar"))

    def test_punctuation_and_whitespace_variants(self):
        for value in ("  I don't know!!!  ", "  not   sure... ", " لا أعرف؟ "):
            with self.subTest(value=value):
                self.assertTrue(planner._is_non_answer(value))

    def test_asr_like_arabic_spacing_variants(self):
        for value in ("ما بتذكر", "مابتذكر", "مش متاكد", "مابقدر احدد"):
            with self.subTest(value=value):
                self.assertTrue(planner._is_non_answer(value, "ar"))

    def test_uncertainty_inside_a_real_answer_does_not_erase_it(self):
        self.assertFalse(planner._is_non_answer("not sure, but it started two hours ago"))


class TestActiveUpdateCompatibility(unittest.TestCase):
    def test_valid_current_topic_answer_is_accepted(self):
        self.assertEqual(
            {"duration": "two hours"},
            _filtered("two hours", {"duration": "two hours"}),
        )

    def test_unrelated_slot_misassignment_is_dropped(self):
        self.assertEqual({}, _filtered(
            "two hours", {"radiation": "left arm"}, topic="duration"))

    def test_valid_multi_fill_is_preserved(self):
        updates = {
            "duration": "two hours", "character": "pressure",
            "radiation": "left arm", "associated_symptoms": "nausea",
        }
        self.assertEqual(updates, _filtered(
            "two hours, pressure, left arm, with nausea", updates))

    def test_invalid_multi_fill_member_is_dropped_only(self):
        self.assertEqual(
            {"duration": "two hours"},
            _filtered("two hours", {
                "duration": "two hours", "radiation": "left arm",
            }),
        )

    def test_off_flow_slot_is_rejected(self):
        self.assertEqual({}, _filtered(
            "severe", {"severity": "severe"}, topic="severity",
            complaint="chest_pain"))

    def test_no_guessed_slot_fallback_is_inserted(self):
        filtered = _filtered(
            "two hours", {"radiation": "left arm"}, topic="duration")
        self.assertNotIn("duration", filtered)
        self.assertNotIn("_profile_after_this_turn", filtered)
        self.assertNotIn("_pending_updates", filtered)

    def test_non_answer_value_is_rejected_even_when_raw_text_differs(self):
        self.assertEqual({}, _filtered(
            "unclear response", {"duration": "I don't know"}))

    def test_unknown_and_other_buckets_do_not_cross_active_boundary(self):
        self.assertEqual({}, _filtered(
            "two hours", {"other": {"admin": "yes"}, "admin": "yes"}))

    def test_python_correction_turn_cannot_be_misfiled_into_current_topic(self):
        symbolic = _symbolic(_FakeInner())
        message = "صحح العمر 31"
        ctx = _ctx(
            message=message, lang="ar", chief_complaint="chest_pain",
            asked_topics=["duration"],
            profile={
                **INTAKE, "age": 31,
                "correction_history": [{"source_text": message}],
            },
        )
        result = planner.PlannerResult(
            reply="سؤال", phase="interviewing", chief_complaint="chest_pain",
            profile_updates={"duration": message})
        self.assertEqual({}, symbolic._filter_active_updates(ctx, result))


@_needs_prolog
class TestPhase94SymbolicIntegration(unittest.IsolatedAsyncioTestCase):
    async def test_accepted_update_survives_repeat_failure_and_advances(self):
        repeat = "When did the chest pain start?"
        inner = _FakeInner(
            reply=None,
            source="llm:wording-invalid",
            profile_updates={"duration": "two hours"},
        )
        original_plan = inner.plan

        async def partial(ctx):
            result = await original_plan(ctx)
            result.wording_valid = False
            return result

        inner.plan = partial
        result = await _symbolic(inner).plan(_ctx(
            lang="en", message="two hours", asked_topics=["duration"],
            asked_questions=[repeat],
        ))
        expected = next(s["question_en"] for s in FLOWS["chest_pain"]["slots"]
                        if s["key"] == "character")
        self.assertEqual(result.profile_updates["duration"], "two hours")
        self.assertEqual(result.reply, expected)

    async def test_deterministic_template_used_after_wording_failure(self):
        inner = _FakeInner(
            reply=None, source="llm:wording-invalid",
            profile_updates={"duration": "two hours"})
        original_plan = inner.plan

        async def partial(ctx):
            result = await original_plan(ctx)
            result.wording_valid = False
            return result

        inner.plan = partial
        result = await _symbolic(inner).plan(_ctx(
            lang="en", message="two hours", asked_topics=["duration"]))
        self.assertIn("template-after-wording-failure", result.source)

    async def test_premature_completion_still_overridden_after_filtering(self):
        inner = _FakeInner(
            reply=None, ready=True, source="llm",
            profile_updates={"duration": "two hours"})
        result = await _symbolic(inner).plan(_ctx(
            lang="en", message="two hours", asked_topics=["duration"]))
        self.assertFalse(result.ready_for_diagnosis)
        self.assertIsNotNone(result.reply)

    async def test_exact_repeat_cannot_survive_when_topic_advanced(self):
        duration = "When did the chest pain start?"
        inner = _FakeInner(
            reply=duration, profile_updates={"duration": "two hours"})
        result = await _symbolic(inner).plan(_ctx(
            lang="en", message="two hours", asked_topics=["duration"],
            asked_questions=[duration]))
        self.assertNotEqual(result.reply, duration)
        self.assertTrue(reasoning_engine.vocabulary.question_matches_topic(
            result.reply, "character"))

    async def test_established_complaint_cannot_drift_to_generic(self):
        inner = _FakeInner(reply="How bad is it?", profile_updates={})
        result = await _symbolic(inner).plan(_ctx(
            lang="en", chief_complaint="chest_pain", message="answer"))
        self.assertEqual(result.chief_complaint, "chest_pain")
        self.assertNotIn("severity", result.profile_updates)

    async def test_prolog_unavailable_preserves_existing_fallback(self):
        inner = _FakeInner(
            reply="existing planner wording",
            profile_updates={"severity": "model-compatible legacy value"})
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("down")):
            result = await _symbolic(inner).plan(_ctx())
        self.assertEqual(result.reply, "existing planner wording")
        self.assertEqual(
            result.profile_updates,
            {"severity": "model-compatible legacy value"})


class TestUnaffectedAuthoritiesAndModes(unittest.IsolatedAsyncioTestCase):
    def test_python_correction_authority_is_unchanged(self):
        profile = {"name": "Sara", "age": 30}
        updated, *_ = interview_engine._apply_correction_layer(
            profile, "interviewing", "chest_pain", "صحح العمر 31", "ar")
        self.assertEqual(updated["age"], 31)

    def test_python_confirmation_authority_is_unchanged(self):
        profile = {
            "pending_confirmation": {
                "field": "name", "heard": "Sara", "suggested": None,
                "question": "Is that right?", "attempts": 0,
            }
        }
        updated, *_ = interview_engine._apply_confirmation_layer(
            profile, "intake", "نعم", "ar")
        self.assertEqual(updated["name"], "Sara")
        self.assertNotIn("pending_confirmation", updated)

    def test_safety_warning_is_decided_from_raw_text_first(self):
        raw = "I have a sudden severe headache"
        verdict = interview_engine._check_safety(raw, "en")
        prefix, urgency, _ = interview_engine._apply_safety_continuation(
            verdict, {"urgency_level": None}, {}, "en", message=raw)
        self.assertEqual(urgency, "urgent")
        self.assertTrue(prefix.startswith("This symptom may need urgent medical evaluation"))

    async def test_off_mode_still_selects_the_legacy_planner(self):
        with patch.dict(os.environ, OFF):
            self.assertIs(interview_engine._select_planner(), interview_engine._planner)

    async def test_shadow_mode_still_selects_the_legacy_planner(self):
        with patch.dict(os.environ, SHADOW):
            self.assertIs(interview_engine._select_planner(), interview_engine._planner)

    @_needs_prolog
    async def test_non_answer_is_not_persisted_as_clinical_value(self):
        session = _fake_session(
            profile={**INTAKE, planner.ASKED_TOPICS_KEY: ["duration"]},
            chief_complaint="chest_pain", language="en")
        model_result = planner.PlannerResult(
            reply="When did the chest pain start?", phase="interviewing",
            chief_complaint="chest_pain", source="llm",
            profile_updates={"duration": "I don't know"})
        with patch.dict(os.environ, ACTIVE), \
                patch.object(planner.LLMPlanner, "plan",
                             new=AsyncMock(return_value=model_result)):
            response, writes = await _handle(
                "I don't know", session, patch_run_planner=False)
        persisted = json.loads(writes[0][4])
        self.assertNotIn("duration", persisted)
        self.assertNotIn("duration", response["profile_snapshot"])

    @_needs_prolog
    async def test_symbolic_bookkeeping_remains_hidden(self):
        session = _fake_session(
            profile={**INTAKE, "duration": "two hours"}, language="en")
        with patch.dict(os.environ, ACTIVE), \
                patch.object(planner.LLMPlanner, "plan",
                             new=AsyncMock(side_effect=planner.PlannerError("down"))):
            response, _ = await _handle("answer", session, patch_run_planner=False)
        self.assertNotIn(planner.ASKED_TOPICS_KEY, response["profile_snapshot"])


if __name__ == "__main__":
    unittest.main()
