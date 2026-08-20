"""
Symbolic corrections, Phase 4 — rollout, parity and end-to-end integration.

PARITY IS THE ACCEPTANCE CRITERION
----------------------------------
Phase 4 runs alongside the Python correction layer, which stays authoritative.
Active mode should not even be recommended unless the symbolic decision agrees
with the legacy one on every characterized case. TestParityWithLegacyLayer runs
both over the same corpus and produces that table; if it fails, the phase does
not ship.

The other property is the ordinary one: shadow mode is invisible. Every turn
must be byte-identical with the flag off and on, including what is persisted.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, reasoning_engine
from virtual_doctor.reasoning_engine import prolog_engine, vocabulary

from test_characterization_correction_matrix import DETECTION_MATRIX, NOT_CORRECTIONS

_needs_engine = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed on this machine"
)

OFF = {"VD_SYMBOLIC": "0"}
SHADOW = {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_CORRECTIONS": "shadow",
          "VD_SYMBOLIC_INTERVIEW": "shadow", "VD_SYMBOLIC_SAFETY": "shadow"}
ACTIVE = {**SHADOW, "VD_SYMBOLIC_CORRECTIONS": "active"}

BASE = {"name": "أحمد", "age": 23, "chief_complaint_description": "بوجعني راسي"}


def _fake_session(session_id="public-id", profile=None, phase="interviewing",
                  chief_complaint="headache", language="ar", urgency_level=None):
    return {"id": "row-id", "session_id": session_id, "language": language,
            "phase": phase, "chief_complaint": chief_complaint,
            "patient_profile": json.dumps(profile if profile is not None else dict(BASE)),
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


# ===========================================================================
# 1. Parity with the legacy correction layer
# ===========================================================================

@_needs_engine
class TestParityWithLegacyLayer(unittest.TestCase):
    """Both decisions over the same corpus. The symbolic layer is asked the
    question the Python layer answers: which identity slot does this turn
    correct, if any?"""

    def _both(self, text, profile):
        legacy = interview_engine._detect_profile_correction(text, dict(profile), "ar")
        legacy_field = (legacy or {}).get("field")

        # Apply the legacy correction to get the post-turn state, then ask the
        # symbolic layer about the resulting provenance — the same state a real
        # turn would leave behind.
        applied, *_ = interview_engine._apply_correction_layer(
            dict(profile), "interviewing", "headache", text, "ar")
        decision, _ = self._decide(applied, legacy)
        return legacy_field, decision.profile_correction_slot

    @staticmethod
    def _decide(profile, candidate):
        fact_set = reasoning_engine.fact_builder.build_facts(
            "s-parity", profile=profile, correction_candidate=candidate)
        return reasoning_engine.decide_corrections(
            fact_set, vocabulary.slug_session_key("s-parity")), fact_set

    def test_recognised_corrections_agree(self):
        for case, text, field, _value in DETECTION_MATRIX:
            if field is None:
                continue  # under-specified; covered below
            with self.subTest(case=case):
                legacy_field, symbolic_field = self._both(text, BASE)
                self.assertEqual(legacy_field, field)
                self.assertEqual(symbolic_field, field,
                                 f"{case}: legacy={legacy_field} symbolic={symbolic_field}")

    def test_non_corrections_agree_that_nothing_was_corrected(self):
        for case, text, reason in NOT_CORRECTIONS:
            with self.subTest(case=case, reason=reason):
                legacy_field, symbolic_field = self._both(text, BASE)
                self.assertIsNone(legacy_field)
                self.assertIsNone(symbolic_field)

    def test_under_specified_corrections_agree_on_no_field(self):
        for case, text, field, _value in DETECTION_MATRIX:
            if field is not None:
                continue
            with self.subTest(case=case):
                legacy_field, symbolic_field = self._both(text, BASE)
                self.assertIsNone(legacy_field)
                self.assertIsNone(symbolic_field)

    def test_the_full_parity_table_has_no_disagreements(self):
        disagreements = []
        for case, text, *_ in DETECTION_MATRIX:
            legacy_field, symbolic_field = self._both(text, BASE)
            if legacy_field != symbolic_field:
                disagreements.append((case, legacy_field, symbolic_field))
        for case, text, _reason in NOT_CORRECTIONS:
            legacy_field, symbolic_field = self._both(text, BASE)
            if legacy_field != symbolic_field:
                disagreements.append((case, legacy_field, symbolic_field))
        self.assertEqual(disagreements, [])


# ===========================================================================
# 2. Rollout modes
# ===========================================================================

class TestCorrectionRolloutModes(unittest.TestCase):
    def test_default_is_shadow_when_the_master_switch_is_on(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}, clear=False):
            os.environ.pop("VD_SYMBOLIC_CORRECTIONS", None)
            self.assertEqual(prolog_engine.correction_mode(), "shadow")
            self.assertFalse(prolog_engine.correction_active())

    def test_master_switch_off_forces_mode_off(self):
        for requested in ("shadow", "active", "off"):
            with patch.dict(os.environ, {"VD_SYMBOLIC": "0",
                                         "VD_SYMBOLIC_CORRECTIONS": requested}):
                self.assertEqual(prolog_engine.correction_mode(), "off")

    def test_an_invalid_mode_falls_back_to_shadow_never_active(self):
        for bad in ("banana", "ACTIVE!", "1", "", "on"):
            with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                         "VD_SYMBOLIC_CORRECTIONS": bad}):
                with self.subTest(value=bad):
                    self.assertEqual(prolog_engine.correction_mode(), "shadow")
                    self.assertFalse(prolog_engine.correction_active())

    def test_the_three_rollout_flags_are_independent(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                     "VD_SYMBOLIC_CORRECTIONS": "active",
                                     "VD_SYMBOLIC_INTERVIEW": "shadow",
                                     "VD_SYMBOLIC_SAFETY": "shadow"}):
            self.assertTrue(prolog_engine.correction_active())
            self.assertFalse(prolog_engine.interview_active())
            self.assertFalse(prolog_engine.safety_active())


# ===========================================================================
# 3. Shadow mode is invisible
# ===========================================================================

TURNS = [
    ("لا، عمري 24 مش 23", dict(BASE)),
    ("لا، اسمي علي مش أحمد", dict(BASE)),
    ("غلط", dict(BASE)),
    ("لا، ما عندي حرارة", dict(BASE)),
    ("من يومين تقريبا", dict(BASE)),
    ("لا، عمري 24 وعندي صداع شديد فجأة", dict(BASE)),
]


class TestShadowModeIsInvisible(unittest.IsolatedAsyncioTestCase):
    async def test_every_turn_is_identical_off_versus_shadow(self):
        for message, profile in TURNS:
            session = _fake_session(profile=profile)
            with self.subTest(message=message):
                with patch.dict(os.environ, OFF):
                    off_result, off_writes = await _handle(message, session)
                with patch.dict(os.environ, SHADOW):
                    on_result, on_writes = await _handle(message, session)
                self.assertEqual(off_result, on_result)
                self.assertEqual(off_writes, on_writes)

    async def test_active_mode_is_also_invisible_in_phase_4(self):
        """Phase 4 ships active as a flag but Python still decides everything;
        no mutation path reads the symbolic result yet."""
        for message, profile in TURNS:
            session = _fake_session(profile=profile)
            with self.subTest(message=message):
                with patch.dict(os.environ, OFF):
                    off_result, _ = await _handle(message, session)
                with patch.dict(os.environ, ACTIVE):
                    on_result, _ = await _handle(message, session)
                self.assertEqual(off_result, on_result)

    async def test_the_symbolic_layer_really_ran(self):
        session = _fake_session()
        with patch.dict(os.environ, SHADOW), \
                patch.object(interview_engine, "_observe_symbolic_corrections",
                             new=AsyncMock(return_value=None)) as observe:
            await _handle("لا، عمري 24 مش 23", session)
        observe.assert_awaited_once()

    async def test_off_mode_does_not_run_the_symbolic_layer(self):
        session = _fake_session()
        with patch.dict(os.environ, OFF), \
                patch.object(reasoning_engine, "decide_corrections_async") as decide:
            await _handle("لا، عمري 24 مش 23", session)
        decide.assert_not_called()

    async def test_a_symbolic_failure_does_not_break_the_turn(self):
        session = _fake_session()
        with patch.dict(os.environ, OFF):
            baseline, _ = await _handle("لا، عمري 24 مش 23", session)
        with patch.dict(os.environ, SHADOW), \
                patch.object(reasoning_engine, "decide_corrections_async",
                             side_effect=RuntimeError("boom")):
            result, _ = await _handle("لا، عمري 24 مش 23", session)
        self.assertEqual(result, baseline)


# ===========================================================================
# 4. Legacy layer is untouched and still authoritative
# ===========================================================================

class TestLegacyCorrectionLayerIntact(unittest.TestCase):
    def test_every_legacy_correction_function_still_exists(self):
        for name in ("_apply_correction_layer", "_detect_profile_correction",
                     "_extract_corrected_name", "_extract_corrected_age",
                     "_extract_corrected_chief_complaint", "_record_correction",
                     "_apply_profile_correction"):
            self.assertTrue(hasattr(interview_engine, name), name)

    def test_the_confirmation_layer_is_untouched(self):
        for name in ("_apply_confirmation_layer", "_resolve_pending_confirmation",
                     "_classify_confirmation_reply", "_start_pending_confirmation"):
            self.assertTrue(hasattr(interview_engine, name), name)

    def test_correction_history_is_still_written_by_python(self):
        profile, *_ = interview_engine._apply_correction_layer(
            dict(BASE), "interviewing", "headache", "لا، عمري 24 مش 23", "ar")
        self.assertEqual(len(profile["correction_history"]), 1)
        self.assertEqual(profile["age"], 24)

    def test_prolog_never_mutates_the_profile(self):
        """Even in active mode: the symbolic layer returns a decision, and the
        profile it was handed is not modified."""
        profile = {"age": 24, "correction_history": [
            {"field": "age", "old_value": 23, "new_value": 24, "source_text": "x"}]}
        snapshot = json.dumps(profile, sort_keys=True, ensure_ascii=False)
        fact_set = reasoning_engine.fact_builder.build_facts(
            "s-mut", profile=profile, correction_candidate=None)
        reasoning_engine.decide_corrections(fact_set, vocabulary.slug_session_key("s-mut"))
        self.assertEqual(json.dumps(profile, sort_keys=True, ensure_ascii=False), snapshot)


# ===========================================================================
# 5. Safety and interview interaction
# ===========================================================================

class TestSafetyStillFirstOnACorrectionTurn(unittest.IsolatedAsyncioTestCase):
    async def test_the_safety_warning_precedes_the_correction_acknowledgement(self):
        session = _fake_session(profile=dict(BASE))
        for env in (OFF, SHADOW, ACTIVE):
            with self.subTest(env=env.get("VD_SYMBOLIC_CORRECTIONS", "off")):
                with patch.dict(os.environ, env):
                    result, _ = await _handle("لا، عمري ٢٤ وعندي صداع شديد فجأة", session)
                reply = result["reply"]
                warning = interview_engine.SAFETY_URGENT_WARNING["ar"][:20]
                self.assertIn(warning, reply)
                if "عدّلت العمر" in reply:
                    self.assertLess(reply.index(warning), reply.index("عدّلت العمر"))

    async def test_urgency_is_unchanged_by_the_correction_layer(self):
        session = _fake_session(profile=dict(BASE))
        for env in (OFF, SHADOW, ACTIVE):
            with patch.dict(os.environ, env):
                result, _ = await _handle("لا، عمري 24 وعندي صداع شديد فجأة", session)
            with self.subTest(env=env.get("VD_SYMBOLIC_CORRECTIONS", "off")):
                self.assertEqual(result["urgency_level"], "urgent")


@_needs_engine
class TestInterviewSeesCorrectedState(unittest.TestCase):
    def test_a_corrected_slot_still_counts_as_answered(self):
        """A correction replaces a value; it does not un-answer the topic."""
        from virtual_doctor import interview_engine as ie

        profile = {"name": "Sara", "age": 30, "duration": "ثلاثة أيام",
                   "correction_history": [{"field": "duration", "old_value": "يومين",
                                           "new_value": "ثلاثة أيام", "source_text": "x"}]}
        fact_set = reasoning_engine.fact_builder.build_facts(
            "s-iv", profile=profile, chief_complaint="headache",
            flow_slots=ie.FLOWS["headache"]["slots"])
        decision = reasoning_engine.decide_interview(
            fact_set, vocabulary.slug_session_key("s-iv"))
        self.assertNotIn("duration", decision.ranked)      # not offered again
        self.assertNotIn("duration", decision.unanswered)  # still counts as answered
        self.assertEqual(decision.topic, "severity")

    def test_an_unresolved_correction_leaves_the_slot_unanswered(self):
        from virtual_doctor import interview_engine as ie

        profile = {"name": "Sara", "age": 30}
        fact_set = reasoning_engine.fact_builder.build_facts(
            "s-iv2", profile=profile, chief_complaint="headache",
            flow_slots=ie.FLOWS["headache"]["slots"])
        decision = reasoning_engine.decide_interview(
            fact_set, vocabulary.slug_session_key("s-iv2"))
        self.assertIn("duration", decision.unanswered)


# ===========================================================================
# 6. Divergence counters
# ===========================================================================

@_needs_engine
class TestCorrectionDivergenceCounters(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        interview_engine._CORRECTION_DIVERGENCE.reset()

    async def test_counters_record_agreement(self):
        session = _fake_session(profile=dict(BASE))
        with patch.dict(os.environ, SHADOW):
            await _handle("لا، عمري 24 مش 23", session)
        counters = interview_engine.correction_divergence_counters()
        self.assertEqual(counters["turns"], 1)
        self.assertEqual(counters["available"], 1)

    async def test_counters_carry_no_patient_data(self):
        session = _fake_session(profile=dict(BASE))
        with patch.dict(os.environ, SHADOW):
            for message, _profile in TURNS:
                await _handle(message, session)
        blob = json.dumps(interview_engine.correction_divergence_counters(),
                          ensure_ascii=False)
        for leak in ("أحمد", "علي", "عمري", "public-id", "v_"):
            self.assertNotIn(leak, blob)

    async def test_kind_hits_are_recorded(self):
        session = _fake_session(profile={
            "age": 24, "correction_history": [
                {"field": "age", "old_value": 23, "new_value": 24, "source_text": "x"}]})
        with patch.dict(os.environ, SHADOW):
            await _handle("من يومين تقريبا", session)
        hits = interview_engine.correction_divergence_counters()["kind_hits"]
        self.assertIn("single_value_conflict", hits)


if __name__ == "__main__":
    unittest.main()
