"""
Phase 9 — is the symbolic interview safe to make authoritative?

Phase 2 proved STATIC parity: one profile in, same topic out. That says nothing
about how a consultation unfolds. This file replays multi-turn trajectories
across all six flows and asserts the properties that would have to hold before
VD_SYMBOLIC_INTERVIEW=active could be recommended:

    no topic already answered is asked again
    no topic outside the active flow is ever chosen
    no required slot is skipped by declaring the interview complete
    a red flag reorders the interview but never displaces the warning
    two patients with the same complaint but different known facts diverge
    every failure mode falls back to the existing planner

FULLY DETERMINISTIC. Topic selection is Prolog plus the flow files; no model is
involved, so these belong in the unit suite rather than in a nightly job. The
wording layer is a separate concern and is verified through the clamp, not by
generating text.
"""

import asyncio
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "benchmarks"))

from virtual_doctor import interview_engine, planner, reasoning_engine
from virtual_doctor.planner import PlannerInput, PlannerResult
from virtual_doctor.reasoning_engine import fact_builder, prolog_engine, vocabulary
from virtual_doctor.reasoning_engine.result_models import InterviewDecision

try:
    from interview_trajectories import PAIRS, TRAJECTORIES, total_turns
    from replay_interview import classify, flow_for, legacy_topic, symbolic_decision
    _HAVE = True
except ImportError:  # pragma: no cover - stripped runtime image
    _HAVE = False

_needs = unittest.skipUnless(
    _HAVE and prolog_engine.available(),
    "benchmarks/ or SWI-Prolog not available")


def run(coro):
    return asyncio.run(coro)


def _replay():
    rows = []
    for trajectory in TRAJECTORIES:
        complaint = trajectory["complaint"]
        for index, turn in enumerate(trajectory["turns"]):
            decision = symbolic_decision(f"{trajectory['id']}-{index}", complaint, turn)
            rows.append((trajectory, index, turn, complaint, decision))
    return rows



@_needs
class TestTrajectoryInvariants(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = _replay()

    def _declared(self, complaint):
        return [s.get("key") for s in flow_for(complaint).get("slots", [])]

    def _answered(self, complaint, profile):
        declared = self._declared(complaint)
        return {k for k, v in profile.items()
                if k in declared and isinstance(v, str) and v.strip()}

    def test_the_suite_covers_every_flow(self):
        complaints = {t["complaint"] for t in TRAJECTORIES}
        self.assertEqual(
            {"chest_pain", "abdominal_pain", "fever_cough", "headache", "rash", "generic"},
            complaints)

    def test_the_suite_is_multi_turn(self):
        self.assertGreaterEqual(total_turns(), 40)
        self.assertGreaterEqual(len(TRAJECTORIES), 12)

    def test_never_asks_a_topic_the_patient_already_answered(self):
        """The single most visible interview bug there is."""
        for trajectory, index, turn, complaint, decision in self.rows:
            if decision.topic is None:
                continue
            answered = self._answered(complaint, turn["profile"])
            self.assertNotIn(decision.topic, answered,
                             f"{trajectory['id']}#{index} re-asked {decision.topic}")

    def test_never_chooses_a_topic_outside_the_active_flow(self):
        for trajectory, index, _, complaint, decision in self.rows:
            if decision.topic is None:
                continue
            self.assertIn(decision.topic, self._declared(complaint),
                          f"{trajectory['id']}#{index}: {decision.topic}")

    def test_every_chosen_topic_is_canonical_vocabulary(self):
        for _, _, _, _, decision in self.rows:
            if decision.topic is None:
                continue
            self.assertIn(decision.topic, vocabulary.CLINICAL_SLOTS)

    def test_never_declares_completion_while_a_required_slot_is_unfilled(self):
        for trajectory, index, turn, complaint, decision in self.rows:
            if not (decision.available and decision.complete):
                continue
            missing = set(self._declared(complaint)) - self._answered(complaint, turn["profile"])
            self.assertEqual(set(), missing,
                             f"{trajectory['id']}#{index} complete with {sorted(missing)}")

    def test_matches_the_expected_topic_on_every_turn(self):
        for trajectory, index, turn, _, decision in self.rows:
            self.assertEqual(turn["expected_topic"], decision.topic,
                             f"{trajectory['id']}#{index} ({turn['note']})")

    def test_the_ranked_list_never_contains_an_answered_topic(self):
        for trajectory, index, turn, complaint, decision in self.rows:
            answered = self._answered(complaint, turn["profile"])
            for topic in decision.ranked:
                self.assertNotIn(topic, answered, f"{trajectory['id']}#{index}")

    def test_the_chosen_topic_is_always_the_head_of_the_ranked_list(self):
        for _, _, _, _, decision in self.rows:
            if decision.ranked:
                self.assertEqual(decision.ranked[0], decision.topic)

    def test_selection_is_reproducible(self):
        """Same facts, same answer — twice. A planner that reorders between
        runs makes every other assertion here meaningless."""
        for trajectory, index, turn, complaint, _ in self.rows[:12]:
            first = symbolic_decision(f"rep-{trajectory['id']}-{index}", complaint, turn)
            second = symbolic_decision(f"rep-{trajectory['id']}-{index}", complaint, turn)
            self.assertEqual(first.topic, second.topic)
            self.assertEqual(first.ranked, second.ranked)



@_needs
class TestLegacyComparison(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = _replay()

    def test_no_symbolic_decision_is_invalid(self):
        for trajectory, index, turn, complaint, decision in self.rows:
            label = classify(turn, complaint, legacy_topic(complaint, turn["profile"]),
                             decision.topic)
            self.assertNotEqual("SYMBOLIC_INVALID", label, f"{trajectory['id']}#{index}")

    def test_legacy_never_wins(self):
        """Not "symbolic differs" — symbolic matching the flow-derived
        expectation where legacy does not."""
        for trajectory, index, turn, complaint, decision in self.rows:
            label = classify(turn, complaint, legacy_topic(complaint, turn["profile"]),
                             decision.topic)
            self.assertNotEqual("LEGACY_BETTER", label, f"{trajectory['id']}#{index}")

    def test_they_agree_on_every_turn_that_is_not_safety_flagged_or_intake_gated(self):
        """Parity is the floor. Divergence must have a reason."""
        for trajectory, index, turn, complaint, decision in self.rows:
            if turn["safety_flagged"] or "intake" in trajectory["categories"]:
                continue
            self.assertEqual(legacy_topic(complaint, turn["profile"]), decision.topic,
                             f"{trajectory['id']}#{index} diverged with no reason")



@_needs
class TestPatientSpecificPaths(unittest.TestCase):
    def _topic(self, trajectory_id, turn_index):
        trajectory = next(t for t in TRAJECTORIES if t["id"] == trajectory_id)
        turn = trajectory["turns"][turn_index]
        decision = symbolic_decision(f"{trajectory_id}-{turn_index}",
                                     trajectory["complaint"], turn)
        return decision.topic, turn

    def test_same_complaint_different_facts_gives_a_different_question(self):
        for left, right, turn_index in PAIRS:
            left_topic, _ = self._topic(left, turn_index)
            right_topic, _ = self._topic(right, turn_index)
            self.assertNotEqual(
                left_topic, right_topic,
                f"{left} and {right} got the same question despite different facts")

    def test_every_pair_shares_a_complaint(self):
        for left, right, _ in PAIRS:
            self.assertEqual(
                next(t for t in TRAJECTORIES if t["id"] == left)["complaint"],
                next(t for t in TRAJECTORIES if t["id"] == right)["complaint"])

    def test_volunteering_several_findings_shortens_the_interview(self):
        """head_b answers three slots in one utterance. It must reach the last
        remaining topic immediately rather than walking the flow."""
        topic, _ = self._topic("head_b", 0)
        self.assertEqual("associated_symptoms", topic)
        stepwise, _ = self._topic("head_a", 0)
        self.assertEqual("duration", stepwise)

    def test_an_incomplete_intake_blocks_every_clinical_topic(self):
        topic, _ = self._topic("intake_missing", 0)
        self.assertIsNone(topic)



@_needs
class TestSafetyPriority(unittest.TestCase):
    def _decision(self, complaint, profile, safety):
        turn = {"profile": {"name": "T", "age": 30, **profile},
                "entities": {"symptoms": []}, "safety_flagged": safety,
                "asked_topics": []}
        return symbolic_decision("safety-test", complaint, turn)

    def test_a_red_flag_pulls_the_follow_up_topic_to_the_front(self):
        flagged = self._decision("chest_pain", {}, "emergency")
        routine = self._decision("chest_pain", {}, None)
        self.assertEqual(fact_builder.SAFETY_FOLLOW_UP_TOPIC, flagged.topic)
        self.assertEqual("duration", routine.topic)

    def test_the_safety_topic_gets_the_safety_band(self):
        flagged = self._decision("chest_pain", {}, "emergency")
        self.assertLess(flagged.priority, 100)

    def test_ordinary_topics_stay_in_the_normal_band(self):
        routine = self._decision("chest_pain", {}, None)
        self.assertGreaterEqual(routine.priority, 100)

    def test_reordering_does_not_drop_any_topic(self):
        flagged = self._decision("chest_pain", {}, "emergency")
        routine = self._decision("chest_pain", {}, None)
        self.assertEqual(set(routine.ranked), set(flagged.ranked))

    def test_an_answered_safety_topic_does_not_keep_being_asked(self):
        flagged = self._decision("chest_pain", {"associated_symptoms": "sweating"},
                                 "emergency")
        self.assertNotEqual(fact_builder.SAFETY_FOLLOW_UP_TOPIC, flagged.topic)

    def test_the_planner_cannot_influence_urgency(self):
        """interview.pl must contribute no urgency clause — that is safety.pl's
        job, and mixing them would let question ordering change a verdict."""
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "reasoning_engine", "rules", "interview.pl")
        with open(path, encoding="utf-8") as handle:
            source = "\n".join(line for line in handle
                               if not line.strip().startswith("%"))
        self.assertNotIn("urgency(", source)
        self.assertNotIn("red_flag(", source)

    def test_the_warning_is_composed_outside_the_planner_and_lands_first(self):
        """The Phase 3 guarantee: reordering questions may not displace the
        mandatory warning, because the warning never passes through a planner."""
        from virtual_doctor import response
        reply = response.compose("سؤال المتابعة", mandatory_warning="تحذير\n\n")
        self.assertTrue(reply.startswith("تحذير\n\n"))
        self.assertTrue(hasattr(interview_engine, "_apply_safety_continuation"))



@_needs
class TestCorrectionAndUnanswered(unittest.TestCase):
    def _topic(self, trajectory_id, turn_index):
        trajectory = next(t for t in TRAJECTORIES if t["id"] == trajectory_id)
        turn = trajectory["turns"][turn_index]
        return symbolic_decision(f"{trajectory_id}-{turn_index}",
                                 trajectory["complaint"], turn).topic

    def test_a_corrected_field_is_not_treated_as_unanswered(self):
        before = self._topic("head_correction", 0)
        after = self._topic("head_correction", 1)
        self.assertEqual("location", before)
        self.assertEqual("location", after,
                         "correcting severity must not re-open severity")

    def test_an_asked_but_unanswered_topic_is_re_offered(self):
        """Pins the EXISTING policy rather than changing it: interview.pl
        records asked_unanswered/2 but deliberately does not gate on it."""
        self.assertEqual("duration", self._topic("head_unanswered", 1))

    def test_asked_unanswered_is_still_observable(self):
        trajectory = next(t for t in TRAJECTORIES if t["id"] == "head_unanswered")
        decision = symbolic_decision("obs", trajectory["complaint"],
                                     trajectory["turns"][1])
        self.assertIn("duration", decision.asked_unanswered)



class TestTopicClamp(unittest.TestCase):
    """No Prolog needed: the clamp is pure Python and applies to whatever
    wording arrives."""

    def _planner(self):
        return planner.build_symbolic(
            inner=None, flows=interview_engine.FLOWS,
            texts={"ASK_AGE": interview_engine.ASK_AGE,
                   "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY,
                   "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT,
                   "WRAP_UP": interview_engine.WRAP_UP},
            helpers={"extract_name": interview_engine._extract_name,
                     "extract_age": interview_engine._extract_age,
                     "detect_chief_complaint": interview_engine._detect_chief_complaint,
                     "next_unfilled_slot": interview_engine._next_unfilled_slot})

    def _ctx(self, topic="duration", lang="ar"):
        return PlannerInput(message="x", lang=lang, phase="interviewing",
                            chief_complaint="chest_pain", profile={}, entities={},
                            history=[], chunks=[], context_block="",
                            turn_index=1, asked_questions=[], required_topic=topic)

    def test_on_topic_wording_is_kept(self):
        text = "منذ متى تشعر بهذا الألم؟"
        result = self._planner().enforce_topic(
            self._ctx(), PlannerResult(reply=text, phase="interviewing"), "duration")
        self.assertEqual(text, result.reply)

    def test_wording_that_drifts_to_another_topic_is_replaced(self):
        drifted = "هل ينتشر الألم إلى ذراعك؟"
        result = self._planner().enforce_topic(
            self._ctx(), PlannerResult(reply=drifted, phase="interviewing"), "duration")
        self.assertNotEqual(drifted, result.reply)

    def test_the_replacement_asks_the_same_topic(self):
        result = self._planner().enforce_topic(
            self._ctx(), PlannerResult(reply="هل ينتشر الألم إلى ذراعك؟", phase="interviewing"), "duration")
        self.assertTrue(vocabulary.question_matches_topic(result.reply, "duration"),
                        result.reply)

    def test_the_replacement_is_the_flows_own_question(self):
        """The deterministic fallback is not a new string invented for the
        purpose — it is what the static flow has always asked."""
        symbolic = self._planner()
        template = symbolic.template_for("duration", "chest_pain", "ar")
        self.assertIsNotNone(template)
        self.assertTrue(vocabulary.question_matches_topic(template, "duration"))

    def test_every_flow_template_passes_its_own_topic_clamp(self):
        """If a template failed its own clamp, a rejection would have nowhere
        safe to land."""
        symbolic = self._planner()
        checked = 0
        for complaint, flow in interview_engine.FLOWS.items():
            for slot in flow.get("slots", []):
                topic = vocabulary.canonical_slot(slot.get("key"))
                if topic is None:
                    continue
                for lang in ("ar", "en"):
                    template = symbolic.template_for(topic, complaint, lang)
                    if not template:
                        continue
                    self.assertTrue(vocabulary.question_matches_topic(template, topic),
                                    f"{complaint}/{topic}/{lang}")
                    checked += 1
        self.assertGreater(checked, 20)



class TestFallback(unittest.TestCase):
    def test_symbolic_is_not_consulted_unless_the_mode_is_active(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                     "VD_SYMBOLIC_INTERVIEW": "shadow"}):
            self.assertIs(interview_engine._planner, interview_engine._select_planner())
        with patch.dict(os.environ, {"VD_SYMBOLIC": "0"}):
            self.assertIs(interview_engine._planner, interview_engine._select_planner())

    def test_active_mode_selects_the_symbolic_wrapper(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                     "VD_SYMBOLIC_INTERVIEW": "active"}):
            self.assertIs(interview_engine._symbolic_planner,
                          interview_engine._select_planner())

    def test_an_unavailable_engine_yields_no_topic_and_no_completion(self):
        decision = InterviewDecision.unavailable("engine down")
        self.assertFalse(decision.available)
        self.assertIsNone(decision.topic)
        self.assertFalse(decision.complete,
                         "an unavailable reasoner must never look finished")

    def test_prolog_unavailable_degrades_rather_than_raising(self):
        with patch.object(prolog_engine, "session_scope",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            decision = reasoning_engine.decide_interview(
                fact_builder.build_facts("s"), vocabulary.slug_session_key("s"))
        self.assertFalse(decision.available)
        self.assertIsNone(decision.topic)

    def test_an_inference_cutoff_degrades_rather_than_raising(self):
        with patch.object(prolog_engine, "session_scope",
                          side_effect=prolog_engine.PrologBudgetExceeded("too many")):
            decision = reasoning_engine.decide_interview(
                fact_builder.build_facts("s"), vocabulary.slug_session_key("s"))
        self.assertFalse(decision.available)

    def test_an_arbitrary_fault_degrades_rather_than_raising(self):
        with patch.object(prolog_engine, "session_scope", side_effect=RuntimeError("boom")):
            decision = reasoning_engine.decide_interview(
                fact_builder.build_facts("s"), vocabulary.slug_session_key("s"))
        self.assertFalse(decision.available)

    def test_fact_building_failure_degrades_rather_than_raising(self):
        with patch.object(fact_builder, "build_facts", side_effect=ValueError("bad")):
            decision = run(reasoning_engine.decide_interview_async("s"))
        self.assertFalse(decision.available)

    def test_no_next_question_is_distinct_from_unavailable(self):
        """"Nothing left to ask" and "the reasoner is down" demand opposite
        actions, so they must never be represented the same way."""
        nothing = InterviewDecision(available=True, topic=None, complete=True)
        broken = InterviewDecision.unavailable("down")
        self.assertTrue(nothing.available)
        self.assertFalse(broken.available)
        self.assertTrue(nothing.complete)
        self.assertFalse(broken.complete)

    def test_the_static_planner_remains_the_universal_fallback(self):
        self.assertTrue(hasattr(planner, "StaticPlanner"))
        self.assertTrue(hasattr(interview_engine, "_next_unfilled_slot"))



class TestDefaultsUnchanged(unittest.TestCase):
    def test_symbolic_is_off_by_default(self):
        saved = {k: os.environ.pop(k, None)
                 for k in ("VD_SYMBOLIC", "VD_SYMBOLIC_INTERVIEW")}
        try:
            self.assertFalse(prolog_engine.enabled())
            self.assertEqual("off", prolog_engine.interview_mode())
            self.assertFalse(prolog_engine.interview_active())
        finally:
            for key, value in saved.items():
                if value is not None:
                    os.environ[key] = value

    def test_the_interview_mode_default_is_not_active(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC": "1"}):
            os.environ.pop("VD_SYMBOLIC_INTERVIEW", None)
            self.assertEqual("shadow", prolog_engine.interview_mode())

    def test_an_invalid_mode_is_never_active(self):
        for bad in ("on", "1", "ACTIVE!", "yes", ""):
            with patch.dict(os.environ, {"VD_SYMBOLIC": "1",
                                         "VD_SYMBOLIC_INTERVIEW": bad}):
                self.assertFalse(prolog_engine.interview_active(), bad)

    def test_no_differential_rule_file_was_created(self):
        rules = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                             "reasoning_engine", "rules")
        self.assertFalse(os.path.exists(os.path.join(rules, "differential.pl")))


if __name__ == "__main__":
    unittest.main()
