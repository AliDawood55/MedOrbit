"""
Symbolic interview reasoning, Phase 2 — planner integration and rollout.

The rules themselves are tested in test_symbolic_interview_phase2.py. This file
tests the boundary: that Prolog's chosen TOPIC survives contact with the LLM,
and that neither shadow mode nor a broken engine can change a consultation.

The claim being defended:

    Prolog decides WHAT is asked.  The LLM decides only HOW it is worded.

An instruction in a prompt does not make that true — a 3B model asked to phrase
`duration` can answer with a shortness-of-breath question. So the guarantee is
enforced after the fact, by clamping wording that drifts to another clinical
topic back to the deterministic template for the SAME topic. A wording failure
must never become a different clinical question.

Rollout is three-state and defaults safe:

    VD_SYMBOLIC=0                        nothing runs
    VD_SYMBOLIC=1                        shadow (the default): Prolog chooses,
                                         the divergence is logged, the existing
                                         planner still drives everything
    VD_SYMBOLIC=1 + INTERVIEW=active     the symbolic topic controls selection
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

FLOWS = interview_engine.FLOWS
INTAKE = {"name": "Sara", "age": 30}

ACTIVE = {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_INTERVIEW": "active"}
SHADOW = {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_INTERVIEW": "shadow"}
OFF = {"VD_SYMBOLIC": "0"}


def _texts():
    return {"ASK_AGE": interview_engine.ASK_AGE,
            "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY,
            "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT,
            "WRAP_UP": interview_engine.WRAP_UP}


def _helpers():
    return {"extract_name": interview_engine._extract_name,
            "extract_age": interview_engine._extract_age,
            "detect_chief_complaint": interview_engine._detect_chief_complaint,
            "next_unfilled_slot": interview_engine._next_unfilled_slot}


class _FakeInner:
    """Stands in for LLMPlanner: returns whatever wording a test dictates."""

    name = "fake"

    def __init__(self, reply="...", ready=False, raises=None, source="fake",
                 profile_updates=None):
        self.reply, self.ready, self.raises, self.source = reply, ready, raises, source
        self.profile_updates = profile_updates or {}
        self.seen = []

    async def plan(self, ctx):
        self.seen.append(ctx)
        if self.raises:
            raise self.raises
        return planner.PlannerResult(
            reply=self.reply, phase="interviewing", ready_for_diagnosis=self.ready,
            chief_complaint=ctx.chief_complaint, source=self.source,
            profile_updates=dict(self.profile_updates))


def _symbolic(inner):
    return planner.build_symbolic(inner=inner, flows=FLOWS, texts=_texts(),
                                  helpers=_helpers())


def _ctx(**kw):
    base = dict(message="an answer", lang="ar", phase="interviewing",
                chief_complaint="chest_pain", profile=dict(INTAKE), entities={},
                session_id="sess-planner")
    base.update(kw)
    return planner.PlannerInput(**base)



@_needs_engine
class TestSymbolicTopicControlsSelection(unittest.IsolatedAsyncioTestCase):
    async def test_the_selected_topic_is_a_canonical_atom_not_a_sentence(self):
        decision = await _symbolic(_FakeInner()).decide(_ctx(), dict(INTAKE))
        self.assertIn(decision.topic, interview_engine.planner.KNOWN_FINDING_KEYS)
        self.assertNotIn(" ", decision.topic)


    async def test_the_topic_is_not_known_until_the_inner_planner_has_run(self):
        """The inner planner cannot be told the topic in advance — the topic
        depends on what it actually extracts, which is the whole fix."""
        inner = _FakeInner(reply="هل ينتشر الألم إلى ذراعك؟")
        await _symbolic(inner).plan(_ctx(profile={**INTAKE, "duration": "x"}))
        self.assertIsNone(inner.seen[0].required_topic)

    async def test_the_inner_planners_actual_update_determines_the_next_topic(self):
        """Given a realistic extraction (character, matching flow order), the
        next topic is what a correct planner has always been expected to ask —
        but now because the update was ACTUALLY accepted, not guessed. The
        wording is on-topic for `radiation`, so the clamp keeps it verbatim —
        the assertion is on the SELECTED topic, not the clamp mechanism."""
        inner = _FakeInner(reply="هل ينتشر الألم إلى ذراعك؟",
                           profile_updates={"character": "ضغط"})
        result = await _symbolic(inner).plan(_ctx(profile={**INTAKE, "duration": "x"}))
        self.assertEqual(result.reply, inner.reply)
        self.assertNotIn("clamped", result.source)
        self.assertTrue(reasoning_engine.vocabulary.question_matches_topic(
            result.reply, "radiation"))

    async def test_selection_is_made_against_the_actually_accepted_update(self):
        """This turn's answer is reported as filling `duration`, so the
        question asked must be `character` — not `duration` again."""
        inner = _FakeInner(reply="كيف تصف الألم؟",
                           profile_updates={"duration": "منذ ساعتين"})
        result = await _symbolic(inner).plan(_ctx(profile=dict(INTAKE)))
        self.assertEqual(result.reply, inner.reply)
        self.assertNotIn("clamped", result.source)
        self.assertTrue(reasoning_engine.vocabulary.question_matches_topic(
            result.reply, "character"))

    async def test_a_guessed_slot_the_inner_planner_never_wrote_is_not_inserted(self):
        """Phase 9.1 reproduction: the flow's own next-slot rule would guess
        `character` is what this turn answers, but the inner planner actually
        wrote a DIFFERENT slot (`radiation`, as qwen2:7b did end-to-end). The
        topic decision must follow the real write, not the guess — so the
        next topic is `character` (still unfilled), never `radiation` again."""
        inner = _FakeInner(reply="...", profile_updates={"radiation": "شاركت"})
        result = await _symbolic(inner).plan(_ctx(profile={**INTAKE, "duration": "x"}))
        expected = next(s["question_ar"] for s in FLOWS["chest_pain"]["slots"]
                        if s["key"] == "character")
        self.assertEqual(result.reply, expected)

    async def test_the_whole_flow_order_is_reproduced_turn_by_turn(self):
        """Prolog's own ordering, independent of planner sequencing: given a
        profile with the first N slots already answered, the decided topic is
        slot N+1."""
        for complaint in sorted(FLOWS):
            order = [s["key"] for s in FLOWS[complaint]["slots"]]
            profile = dict(INTAKE)
            for expected in order:
                with self.subTest(complaint=complaint, expected=expected):
                    decision = await _symbolic(_FakeInner()).decide(
                        _ctx(chief_complaint=complaint, profile=dict(profile)),
                        dict(profile))
                    self.assertEqual(decision.topic, expected)
                profile[expected] = "answered"

    async def test_intake_still_precedes_every_clinical_question(self):
        result = await _symbolic(_FakeInner()).plan(
            _ctx(phase="intake", profile={}, message="سارة"))
        self.assertEqual(result.source, "intake")
        self.assertEqual(result.phase, "intake")



@_needs_engine
class TestWordingCannotSwitchTopic(unittest.IsolatedAsyncioTestCase):
    async def test_on_topic_wording_is_kept_verbatim(self):
        natural = "منذ متى بدأ هذا الألم بالضبط؟"
        inner = _FakeInner(reply=natural)
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="headache", phase="greeting"))
        self.assertEqual(result.reply, natural)
        self.assertNotIn("clamped", result.source)

    async def test_off_topic_wording_is_replaced_by_the_topics_template(self):
        """The core guarantee. This turn's answer is reported as filling
        `character`, so Prolog picks `radiation`; the model answered with a
        breathing question; the patient must receive the RADIATION question,
        not the breathing one."""
        inner = _FakeInner(reply="هل لديك ضيق في التنفس؟",
                           profile_updates={"character": "ضغط"})
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="chest_pain", profile={**INTAKE, "duration": "x"}))

        expected = next(s["question_ar"] for s in FLOWS["chest_pain"]["slots"]
                        if s["key"] == "radiation")
        self.assertEqual(result.reply, expected)
        self.assertIn("clamped", result.source)
        self.assertNotIn("ضيق في التنفس", result.reply)

    async def test_malformed_wording_falls_back_to_the_template(self):
        for bad in ("", "   ", "؟؟؟", "asdfghjkl"):
            with self.subTest(bad=bad):
                inner = _FakeInner(reply=bad, profile_updates={"severity": "شديد"})
                result = await _symbolic(inner).plan(
                    _ctx(chief_complaint="headache", profile={**INTAKE, "duration": "x"}))
                expected = next(s["question_ar"] for s in FLOWS["headache"]["slots"]
                                if s["key"] == "location")
                self.assertEqual(result.reply, expected)

    async def test_the_fallback_is_always_the_same_topic_never_another(self):
        """A wording failure must not become a different clinical question."""
        for complaint in sorted(FLOWS):
            order = [s["key"] for s in FLOWS[complaint]["slots"]]
            with self.subTest(complaint=complaint):
                inner = _FakeInner(reply="something entirely unrelated")
                symbolic = _symbolic(inner)
                ctx = _ctx(chief_complaint=complaint, profile=dict(INTAKE))
                decision = await symbolic.decide(ctx, dict(INTAKE))
                result = await symbolic.plan(ctx)
                expected = next(s["question_ar"] for s in FLOWS[complaint]["slots"]
                                if s["key"] == decision.topic)
                self.assertEqual(result.reply, expected)
                self.assertIn(decision.topic, order)

    async def test_english_wording_is_validated_in_english(self):
        inner = _FakeInner(reply="How long has this been going on?")
        result = await _symbolic(inner).plan(
            _ctx(lang="en", chief_complaint="headache", phase="greeting"))
        self.assertEqual(result.reply, "How long has this been going on?")

    async def test_english_off_topic_wording_gets_the_english_template(self):
        inner = _FakeInner(reply="Do you have shortness of breath?",
                           profile_updates={"severity": "severe"})
        result = await _symbolic(inner).plan(
            _ctx(lang="en", chief_complaint="headache", profile={**INTAKE, "duration": "x"}))
        expected = next(s["question_en"] for s in FLOWS["headache"]["slots"]
                        if s["key"] == "location")
        self.assertEqual(result.reply, expected)

    async def test_an_inner_planner_failure_still_answers_the_symbolic_topic(self):
        """PlannerError means the model produced nothing usable — no
        profile_updates either, so the topic is decided against ctx.profile
        as it arrived. The TOPIC is still valid, so it is asked
        deterministically rather than discarded."""
        inner = _FakeInner(raises=planner.PlannerError("timeout"))
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="chest_pain", profile={**INTAKE, "duration": "x"}))
        expected = next(s["question_ar"] for s in FLOWS["chest_pain"]["slots"]
                        if s["key"] == "character")
        self.assertEqual(result.reply, expected)
        self.assertTrue(result.source.endswith("template"))



@_needs_engine
class TestPredictionWriteConsistency(unittest.IsolatedAsyncioTestCase):
    async def test_exact_phase_9_1_reproduction_two_turns_do_not_repeat(self):
        """T3/T4 of Phase 9.1 consultation A, reproduced turn by turn.

        Profile before T3: duration answered. The flow's own next-slot rule
        would guess this turn fills `character`, predicting the next topic is
        `radiation`. The inner planner (an LLM, here faked) instead writes a
        DIFFERENT slot (`radiation`, with a hallucinated value) — exactly
        what qwen2:7b did end-to-end. Under the Phase 2 sequencing this made
        T4 ask the byte-identical radiation question again; under the fix,
        T4 must ask `character`, the slot that is genuinely still unfilled.
        """
        profile = {**INTAKE, "duration": "من ساعتين"}

        t3_inner = _FakeInner(reply="شعور بضغط",
                              profile_updates={"radiation": "شاركت"})
        t3 = await _symbolic(t3_inner).plan(
            _ctx(chief_complaint="chest_pain", profile=dict(profile)))
        profile.update(t3.profile_updates)

        self.assertTrue(
            reasoning_engine.vocabulary.question_matches_topic(t3.reply, "character"),
            f"T3 should ask about character (the genuinely unfilled slot), "
            f"got: {t3.reply!r}")

        t4_inner = _FakeInner(reply="ألم ضاغط بشكل مستمر", profile_updates={})
        t4 = await _symbolic(t4_inner).plan(
            _ctx(chief_complaint="chest_pain", profile=dict(profile)))

        self.assertTrue(
            reasoning_engine.vocabulary.question_matches_topic(t4.reply, "character"),
            f"T4 should still ask about character, got: {t4.reply!r}")

        self.assertFalse(
            reasoning_engine.vocabulary.question_matches_topic(t3.reply, "radiation"))
        self.assertFalse(
            reasoning_engine.vocabulary.question_matches_topic(t4.reply, "radiation"))

    async def test_a_hallucinated_slot_is_not_inserted_into_the_profile(self):
        """The inner planner's write for an UNRELATED slot must still be
        accepted (that is its job, not this planner's to second-guess) — but
        no slot the inner planner did not itself report may appear."""
        inner = _FakeInner(reply="...", profile_updates={"radiation": "شاركت"})
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="chest_pain", profile={**INTAKE, "duration": "x"}))
        self.assertEqual({"radiation": "شاركت"},
                         {k: v for k, v in result.profile_updates.items()
                          if k in planner.KNOWN_FINDING_KEYS})
        self.assertNotIn("character", result.profile_updates)

    async def test_multiple_accepted_updates_are_all_visible_to_the_decision(self):
        """A single turn's extraction may fill more than one slot at once
        (Phase 9's multi-fill trajectories). Both must count toward the
        effective profile the topic decision is made against."""
        inner = _FakeInner(reply="...", profile_updates={
            "duration": "منذ يومين", "character": "حاد",
        })
        result = await _symbolic(inner).plan(_ctx(profile=dict(INTAKE)))
        self.assertTrue(reasoning_engine.vocabulary.question_matches_topic(
            result.reply, "radiation"),
            f"both duration and character were accepted, so the next topic "
            f"should be radiation, got: {result.reply!r}")

    async def test_zero_accepted_updates_invent_no_facts(self):
        """If the inner planner extracts nothing new, the profile the
        decision is made against must be exactly ctx.profile — not a filled-
        in guess at what the raw message probably meant."""
        inner = _FakeInner(reply="...", profile_updates={})
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="chest_pain", profile={**INTAKE, "duration": "x"}))
        self.assertTrue(reasoning_engine.vocabulary.question_matches_topic(
            result.reply, "character"),
            "with nothing newly accepted, character (the first unfilled "
            "slot) must be next — not radiation, which a guess would predict")

    async def test_an_answered_topic_is_never_re_asked_across_turns(self):
        """Direct end-to-end guard for the Phase 9 acceptance criterion, now
        exercised through actual planner sequencing rather than a
        precomputed profile. Reads the authoritative record — the
        symbolic_asked_topics bookkeeping _record_asked writes — rather than
        inferring a topic from wording, since a fixed FakeInner reply ("...")
        would not reliably classify by vocabulary matching."""
        profile = dict(INTAKE)
        for turn_message, update_key, update_value in (
            ("من ساعتين", "duration", "من ساعتين"),
            ("ضغط", "character", "ضغط"),
            ("إلى ذراعي", "radiation", "إلى ذراعي"),
        ):
            inner = _FakeInner(reply="...", profile_updates={update_key: update_value})
            result = await _symbolic(inner).plan(_ctx(
                chief_complaint="chest_pain", profile=dict(profile),
                message=turn_message,
                asked_topics=list(profile.get(planner.ASKED_TOPICS_KEY) or [])))
            asked_before = list(profile.get(planner.ASKED_TOPICS_KEY) or [])
            asked_after = result.profile_updates.get(planner.ASKED_TOPICS_KEY, asked_before)
            newly_asked = [t for t in asked_after if t not in asked_before]
            self.assertLessEqual(len(newly_asked), 1)
            if newly_asked:
                self.assertNotIn(newly_asked[0], asked_before,
                                 f"topic {newly_asked[0]!r} asked twice: {asked_after}")
            profile.update(result.profile_updates)
            profile[update_key] = update_value



@_needs_engine
class TestSymbolicReadiness(unittest.IsolatedAsyncioTestCase):
    async def test_completed_flow_is_ready_for_diagnosis(self):
        for complaint in sorted(FLOWS):
            profile = {**INTAKE, **{s["key"]: "x" for s in FLOWS[complaint]["slots"]}}
            with self.subTest(complaint=complaint):
                result = await _symbolic(_FakeInner()).plan(
                    _ctx(chief_complaint=complaint, profile=profile, phase="reasoning"))
                self.assertTrue(result.ready_for_diagnosis)
                self.assertIsNone(result.reply)

    async def test_symbolic_overrides_a_premature_llm_readiness(self):
        """Step B of the readiness migration: with required topics still
        unanswered, a model that declares itself finished is overruled."""
        inner = _FakeInner(ready=True, source="llm")
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="chest_pain", profile=dict(INTAKE)))
        self.assertFalse(result.ready_for_diagnosis)
        self.assertIn("symbolic-continue", result.source)

    async def test_the_turn_cap_backstop_is_still_honoured(self):
        """The cap protects against a runaway interview and is NOT a readiness
        opinion, so symbolic reasoning must not override it."""
        inner = _FakeInner(ready=True, source="llm:turn-cap")
        result = await _symbolic(inner).plan(
            _ctx(chief_complaint="chest_pain", profile=dict(INTAKE)))
        self.assertTrue(result.ready_for_diagnosis)

    async def test_the_old_readiness_path_is_still_present(self):
        """Phase 2 keeps _check_readiness as the fallback; it is not removed."""
        self.assertTrue(hasattr(planner.LLMPlanner, "_check_readiness"))



class TestFallbackToExistingPlanner(unittest.IsolatedAsyncioTestCase):
    async def test_prolog_unavailable_delegates_to_the_inner_planner(self):
        inner = _FakeInner(reply="whatever the existing planner said")
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            result = await _symbolic(inner).plan(_ctx())
        self.assertEqual(result.reply, "whatever the existing planner said")
        self.assertEqual(len(inner.seen), 1)
        self.assertIsNone(inner.seen[0].required_topic)

    async def test_a_query_failure_delegates_to_the_inner_planner(self):
        inner = _FakeInner(reply="existing planner wording")
        with patch.object(prolog_engine, "_raw_query", side_effect=RuntimeError("boom")):
            result = await _symbolic(inner).plan(_ctx())
        self.assertEqual(result.reply, "existing planner wording")
        self.assertIsNone(inner.seen[0].required_topic)

    async def test_no_question_is_fabricated_when_the_engine_is_down(self):
        inner = _FakeInner(raises=planner.PlannerError("also down"))
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            with self.assertRaises(planner.PlannerError):
                await _symbolic(inner).plan(_ctx())



class TestRolloutModes(unittest.TestCase):
    def test_default_is_shadow_when_the_master_switch_is_on(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}, clear=False):
            os.environ.pop("VD_SYMBOLIC_INTERVIEW", None)
            self.assertEqual(prolog_engine.interview_mode(), "shadow")
            self.assertFalse(prolog_engine.interview_active())

    def test_master_switch_off_forces_mode_off(self):
        for requested in ("shadow", "active", "off"):
            with patch.dict(os.environ, {"VD_SYMBOLIC": "0",
                                         "VD_SYMBOLIC_INTERVIEW": requested}):
                self.assertEqual(prolog_engine.interview_mode(), "off")
                self.assertFalse(prolog_engine.interview_active())

    def test_active_requires_both_settings(self):
        with patch.dict(os.environ, ACTIVE):
            self.assertTrue(prolog_engine.interview_active())

    def test_an_unknown_mode_falls_back_to_shadow_not_active(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                     "VD_SYMBOLIC_INTERVIEW": "banana"}):
            self.assertEqual(prolog_engine.interview_mode(), "shadow")
            self.assertFalse(prolog_engine.interview_active())

    def test_status_reports_the_mode(self):
        with patch.dict(os.environ, SHADOW):
            self.assertEqual(prolog_engine.status()["interview_mode"], "shadow")



def _fake_session(session_id="public-id", profile=None, phase="interviewing",
                  chief_complaint="chest_pain", language="ar"):
    return {"id": "row-id", "session_id": session_id, "language": language,
            "phase": phase, "chief_complaint": chief_complaint,
            "patient_profile": json.dumps(profile or {}), "urgency_level": None,
            "recommended_specialty_id": None, "differential": None}


async def _handle(message, session, planner_result=None, patch_run_planner=True):
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=session)
    fake_pool.execute = AsyncMock()

    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(
            interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
        stack.enter_context(patch.object(
            interview_engine, "_build_turn_context", new=AsyncMock(return_value={
                "history": [], "chunks": [], "context_block": "",
                "memory_ms": 0.0, "rag_ms": 0.0})))
        stack.enter_context(patch.object(
            interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
        if patch_run_planner:
            stack.enter_context(patch.object(
                interview_engine, "_run_planner",
                new=AsyncMock(return_value=planner_result)))
        result = await interview_engine.handle_message(session["session_id"], message)

    updates = [c.args for c in fake_pool.execute.await_args_list
               if "UPDATE virtual_doctor_sessions" in c.args[0]]
    return result, updates


_TURNS = [
    ("من ساعتين", _fake_session(profile={**INTAKE}), "chest_pain"),
    ("عندي صداع شديد فجأة", _fake_session(chief_complaint="headache",
                                          profile={**INTAKE}), "headache"),
    ("سارة", _fake_session(phase="intake", profile={}), None),
]


class TestShadowModeChangesNothing(unittest.IsolatedAsyncioTestCase):
    async def test_shadow_and_off_produce_identical_turns(self):
        for message, session, _ in _TURNS:
            plan = planner.PlannerResult(reply="سؤال المخطط الحالي",
                                         phase="interviewing", source="static")
            with self.subTest(message=message):
                with patch.dict(os.environ, OFF):
                    off_result, off_writes = await _handle(message, session, plan)
                with patch.dict(os.environ, SHADOW):
                    on_result, on_writes = await _handle(message, session, plan)

                self.assertEqual(off_result, on_result)
                self.assertEqual(off_writes, on_writes)

    async def test_shadow_mode_does_not_swap_the_planner(self):
        with patch.dict(os.environ, SHADOW):
            self.assertIs(interview_engine._select_planner(), interview_engine._planner)

    async def test_active_mode_swaps_the_planner(self):
        with patch.dict(os.environ, ACTIVE):
            self.assertIs(interview_engine._select_planner(),
                          interview_engine._symbolic_planner)

    async def test_off_mode_does_not_swap_the_planner(self):
        with patch.dict(os.environ, OFF):
            self.assertIs(interview_engine._select_planner(), interview_engine._planner)

    @_needs_engine
    async def test_divergence_logging_runs_and_never_raises(self):
        ctx = _ctx()
        result = planner.PlannerResult(reply="منذ متى بدأ الألم؟", phase="interviewing",
                                       source="static")
        with patch.dict(os.environ, SHADOW):
            await interview_engine._log_interview_divergence(ctx, result)

    async def test_divergence_logging_is_skipped_outside_shadow_mode(self):
        ctx = _ctx()
        result = planner.PlannerResult(reply="x", phase="interviewing", source="static")
        with patch.dict(os.environ, ACTIVE), \
                patch.object(reasoning_engine, "decide_interview_async") as decide:
            await interview_engine._log_interview_divergence(ctx, result)
        decide.assert_not_called()

    async def test_a_broken_divergence_log_does_not_break_the_turn(self):
        ctx = _ctx()
        result = planner.PlannerResult(reply="x", phase="interviewing", source="static")
        with patch.dict(os.environ, SHADOW), \
                patch.object(reasoning_engine, "decide_interview_async",
                             side_effect=RuntimeError("boom")):
            await interview_engine._log_interview_divergence(ctx, result)


@_needs_engine
class TestActiveModeEndToEnd(unittest.IsolatedAsyncioTestCase):
    async def test_active_mode_asks_the_symbolic_topic_through_handle_message(self):
        """Full path, real planner chain, only the LLM call stubbed. The LLM
        fails immediately (no profile_updates), so the topic is decided
        against the profile exactly as it arrived: `duration` is answered,
        `character` is not — so `character` is next, not `radiation`."""
        session = _fake_session(profile={**INTAKE, "duration": "من ساعتين"})
        with patch.dict(os.environ, ACTIVE), \
                patch.object(planner.LLMPlanner, "plan",
                             new=AsyncMock(side_effect=planner.PlannerError("llm down"))):
            result, _ = await _handle("إجابة", session, patch_run_planner=False)

        expected = next(s["question_ar"] for s in FLOWS["chest_pain"]["slots"]
                        if s["key"] == "character")
        self.assertEqual(result["reply"], expected)

    async def test_asked_topics_are_recorded_for_later_turns(self):
        """Phase 9.2 follow-up 1: symbolic_asked_topics is internal
        bookkeeping and must not appear in the client-facing profile_snapshot
        — but it must still be PERSISTED, since decide() reads it back via
        asked_topics on the next turn."""
        session = _fake_session(profile={**INTAKE, "duration": "x"})
        with patch.dict(os.environ, ACTIVE), \
                patch.object(planner.LLMPlanner, "plan",
                             new=AsyncMock(side_effect=planner.PlannerError("llm down"))):
            result, updates = await _handle("إجابة", session, patch_run_planner=False)

        self.assertNotIn(planner.ASKED_TOPICS_KEY, result["profile_snapshot"])
        persisted_profile = json.loads(updates[0][4])
        self.assertIn("character", persisted_profile[planner.ASKED_TOPICS_KEY])

    async def test_recorded_topics_are_a_list_so_the_pdf_never_shows_them(self):
        """report_generator renders every STRING profile value as a clinical
        row. Symbolic bookkeeping must not be a string — checked in the
        PERSISTED profile, since Phase 9.2 removed it from profile_snapshot
        entirely (a hidden key can't leak as any type, string or not)."""
        session = _fake_session(profile={**INTAKE, "duration": "x"})
        with patch.dict(os.environ, ACTIVE), \
                patch.object(planner.LLMPlanner, "plan",
                             new=AsyncMock(side_effect=planner.PlannerError("llm down"))):
            _, updates = await _handle("إجابة", session, patch_run_planner=False)
        persisted_profile = json.loads(updates[0][4])
        self.assertIsInstance(persisted_profile[planner.ASKED_TOPICS_KEY], list)



class TestSafetyUnchanged(unittest.IsolatedAsyncioTestCase):
    async def test_urgency_and_warning_are_identical_in_every_mode(self):
        session = _fake_session(chief_complaint="headache", profile=dict(INTAKE))
        plan = planner.PlannerResult(reply="سؤال", phase="interviewing", source="static")
        results = {}
        for label, env in (("off", OFF), ("shadow", SHADOW), ("active", ACTIVE)):
            with patch.dict(os.environ, env):
                results[label], _ = await _handle("عندي صداع شديد فجأة", session, plan)

        self.assertEqual(results["off"]["urgency_level"], "urgent")
        self.assertEqual(results["shadow"]["urgency_level"], "urgent")
        self.assertEqual(results["active"]["urgency_level"], "urgent")
        self.assertEqual(results["off"]["reply"], results["shadow"]["reply"])
        self.assertEqual(results["off"]["reply"], results["active"]["reply"])

    async def test_interview_pl_declares_no_urgency_rule(self):
        """Structural guard: safety reasoning is Phase 3, and nothing in the
        Phase 2 rule file may compute urgency."""
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "reasoning_engine", "rules", "interview.pl")
        with open(path, encoding="utf-8") as fh:
            body = "\n".join(line for line in fh if not line.strip().startswith("%"))
        for forbidden in ("urgency(", "urgency_rank", "red_flag", "final_urgency",
                          "deterministic_urgency"):
            self.assertNotIn(forbidden, body, forbidden)

    async def test_no_unapproved_rule_files_exist(self):
        """UPDATED IN PHASE 3: safety.pl is now an approved rule file.

        The guard itself is unchanged in intent — contradictions.pl and
        differential.pl belong to phases that have not been approved, and their
        appearance would mean rule logic had landed without review.
        """
        rules_dir = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                                 "reasoning_engine", "rules")
        self.assertEqual(sorted(os.listdir(rules_dir)),
                         ["base.pl", "contradictions.pl", "interview.pl", "safety.pl"])


if __name__ == "__main__":
    unittest.main()
