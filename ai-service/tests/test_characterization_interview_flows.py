"""
Characterization of the CURRENT interview question order, written before any
symbolic replacement exists.

Phase 2 migrates "which clinical topic do we ask next" from JSON flow order
into Prolog. The only honest way to claim that is a migration rather than a
redesign is to pin today's answer first, from today's code, and then require
the symbolic engine to reproduce it exactly.

So this file deliberately contains no Prolog. It records, as executable facts:

  * the slot list and ORDER each flow declares
  * that every flow slot is required, with no per-slot conditions
  * that the flow slot vocabulary and planner.KNOWN_FINDING_KEYS are the same
    set — the two ends of the pipeline agree on what a topic is
  * exactly which slot StaticPlanner asks next, for every reachable state of
    every flow
  * that intake precedes every clinical question
  * that a filled slot is never revisited

test_symbolic_interview_phase2.py then asserts the symbolic engine returns the
SAME topic for the same states. If a later phase intends to change the
interview, one of these tests has to be edited deliberately — which is the
point of writing them down.
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner

_FLOWS_DIR = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor", "flows")


def _load_flow(name):
    with open(os.path.join(_FLOWS_DIR, f"{name}.json"), encoding="utf-8") as fh:
        return json.load(fh)


# The machine-readable mapping this phase is migrating. complaint -> ordered
# slots, read off flows/*.json at the time of writing.
EXPECTED_FLOW_ORDER = {
    "abdominal_pain": ["duration", "location_character", "associated_symptoms", "triggers"],
    "chest_pain": ["duration", "character", "radiation", "associated_symptoms"],
    "fever_cough": ["duration", "severity", "associated_symptoms", "exposure"],
    "generic": ["duration", "severity", "associated_symptoms"],
    "headache": ["duration", "severity", "location", "associated_symptoms"],
    "rash": ["duration", "appearance", "location", "associated_symptoms"],
}

EXPECTED_MATCH_SYMPTOMS = {
    "abdominal_pain": ["stomach_pain", "stomach_ache"],
    "chest_pain": ["chest_pain"],
    "fever_cough": ["fever", "cough"],
    "generic": [],
    "headache": ["headache"],
    "rash": ["skin_rash"],
}


# ===========================================================================
# 1. The flow files themselves
# ===========================================================================

class TestFlowDefinitions(unittest.TestCase):
    def test_slot_order_is_exactly_as_recorded(self):
        for complaint, expected in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                flow = _load_flow(complaint)
                self.assertEqual([s["key"] for s in flow["slots"]], expected)

    def test_match_symptoms_are_exactly_as_recorded(self):
        for complaint, expected in EXPECTED_MATCH_SYMPTOMS.items():
            with self.subTest(complaint=complaint):
                self.assertEqual(_load_flow(complaint)["match_symptoms"], expected)

    def test_every_slot_in_every_flow_is_required(self):
        """There is no optional slot today. A symbolic model that makes some
        slots optional would change when the interview ends."""
        for complaint in EXPECTED_FLOW_ORDER:
            with self.subTest(complaint=complaint):
                self.assertTrue(all(s["required"] for s in _load_flow(complaint)["slots"]))

    def test_slots_declare_no_conditions_only_a_key_and_two_questions(self):
        """Today a slot's relevance is decided ENTIRELY by which flow lists it
        — there is no per-slot dependency field. Any dependency the symbolic
        layer adds beyond flow membership is therefore new behaviour."""
        for complaint in EXPECTED_FLOW_ORDER:
            for slot in _load_flow(complaint)["slots"]:
                with self.subTest(complaint=complaint, slot=slot["key"]):
                    self.assertEqual(set(slot), {"key", "required", "question_en", "question_ar"})

    def test_duration_is_the_first_question_of_every_flow(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                self.assertEqual(order[0], "duration")

    def test_flow_vocabulary_equals_the_planners_finding_keys(self):
        union = {slot for order in EXPECTED_FLOW_ORDER.values() for slot in order}
        self.assertEqual(union, planner.KNOWN_FINDING_KEYS)

    def test_loaded_flows_match_the_files(self):
        self.assertEqual(set(interview_engine.FLOWS), set(EXPECTED_FLOW_ORDER))
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                self.assertEqual(
                    [s["key"] for s in interview_engine.FLOWS[complaint]["slots"]], order)

    def test_every_slot_has_both_language_questions_nonempty(self):
        for complaint in EXPECTED_FLOW_ORDER:
            for slot in _load_flow(complaint)["slots"]:
                with self.subTest(complaint=complaint, slot=slot["key"]):
                    self.assertTrue(slot["question_en"].strip())
                    self.assertTrue(slot["question_ar"].strip())


# ===========================================================================
# 2. _next_unfilled_slot — the behaviour being migrated
# ===========================================================================

class TestNextUnfilledSlotOrder(unittest.TestCase):
    """The whole of today's question selection, in one function: walk the
    flow's slots in declared order, return the first one the profile has not
    filled. Every state of every flow is enumerated here."""

    def _next(self, complaint, profile):
        slot = interview_engine._next_unfilled_slot(
            interview_engine.FLOWS[complaint], profile)
        return slot["key"] if slot else None

    def test_empty_profile_selects_the_first_slot(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                self.assertEqual(self._next(complaint, {}), order[0])

    def test_progressively_filling_slots_walks_the_declared_order(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            profile = {}
            for expected in order:
                with self.subTest(complaint=complaint, expected=expected):
                    self.assertEqual(self._next(complaint, profile), expected)
                profile[expected] = "answered"
            with self.subTest(complaint=complaint, expected=None):
                self.assertIsNone(self._next(complaint, profile))

    def test_a_gap_is_selected_even_when_later_slots_are_already_filled(self):
        """Order is by declaration, not by what happens to be missing last."""
        profile = {"duration": "x", "radiation": "x", "associated_symptoms": "x"}
        self.assertEqual(self._next("chest_pain", profile), "character")

    def test_an_answered_slot_is_never_selected_again(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            for filled in order:
                with self.subTest(complaint=complaint, filled=filled):
                    self.assertNotEqual(self._next(complaint, {filled: "answered"}), filled)

    def test_empty_string_counts_as_unfilled(self):
        """Falsy, not absent: today's check is `not profile.get(key)`."""
        self.assertEqual(self._next("headache", {"duration": ""}), "duration")

    def test_slots_outside_the_flow_do_not_affect_selection(self):
        profile = {"radiation": "x", "exposure": "x", "appearance": "x"}
        self.assertEqual(self._next("headache", profile), "duration")

    def test_all_slots_filled_means_no_next_slot(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                self.assertIsNone(self._next(complaint, {k: "x" for k in order}))


# ===========================================================================
# 3. Complaint detection
# ===========================================================================

class TestChiefComplaintDetection(unittest.TestCase):
    def test_each_match_symptom_routes_to_its_complaint(self):
        for complaint, symptoms in EXPECTED_MATCH_SYMPTOMS.items():
            for symptom in symptoms:
                with self.subTest(complaint=complaint, symptom=symptom):
                    self.assertEqual(
                        interview_engine._detect_chief_complaint({"symptoms": [symptom]}),
                        complaint)

    def test_unknown_symptoms_fall_back_to_generic(self):
        self.assertEqual(
            interview_engine._detect_chief_complaint({"symptoms": ["insomnia"]}), "generic")
        self.assertEqual(interview_engine._detect_chief_complaint({"symptoms": []}), "generic")
        self.assertEqual(interview_engine._detect_chief_complaint({}), "generic")


# ===========================================================================
# 4. StaticPlanner end to end — intake first, then the flow in order
# ===========================================================================

class TestStaticPlannerQuestionSequence(unittest.IsolatedAsyncioTestCase):
    def _planner(self):
        return planner.StaticPlanner(
            flows=interview_engine.FLOWS,
            texts={"ASK_AGE": interview_engine.ASK_AGE,
                   "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY,
                   "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT,
                   "WRAP_UP": interview_engine.WRAP_UP},
            helpers={"extract_name": interview_engine._extract_name,
                     "extract_age": interview_engine._extract_age,
                     "detect_chief_complaint": interview_engine._detect_chief_complaint,
                     "next_unfilled_slot": interview_engine._next_unfilled_slot},
        )

    def _ctx(self, **kw):
        base = dict(message="x", lang="en", phase="interviewing", chief_complaint="headache",
                    profile={}, entities={})
        base.update(kw)
        return planner.PlannerInput(**base)

    async def test_intake_asks_name_then_age_before_any_clinical_question(self):
        p = self._planner()
        result = await p.plan(self._ctx(phase="intake", profile={}, message="Sara"))
        self.assertEqual(result.phase, "intake")
        self.assertIn("old", result.reply)

        result = await p.plan(self._ctx(phase="intake", profile={"name": "Sara"}, message="30"))
        self.assertEqual(result.phase, "greeting")
        self.assertEqual(result.profile_updates["age"], 30)

    async def test_clinical_questions_follow_the_declared_flow_order(self):
        """The sequence a real consultation produces, per flow."""
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            profile = {"name": "Sara", "age": 30}
            for index, expected_next in enumerate(order[1:], start=1):
                with self.subTest(complaint=complaint, step=index):
                    result = await self._planner().plan(self._ctx(
                        phase="interviewing", chief_complaint=complaint,
                        profile=dict(profile), message="an answer"))
                    expected_question = next(
                        s[f"question_en"] for s in interview_engine.FLOWS[complaint]["slots"]
                        if s["key"] == expected_next)
                    self.assertEqual(result.reply, expected_question)
                    self.assertFalse(result.ready_for_diagnosis)
                profile[order[index - 1]] = "answered"

    async def test_interview_is_ready_only_once_every_flow_slot_is_filled(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                profile = {"name": "Sara", "age": 30}
                profile.update({k: "x" for k in order[:-1]})
                result = await self._planner().plan(self._ctx(
                    phase="interviewing", chief_complaint=complaint, profile=profile))
                self.assertTrue(result.ready_for_diagnosis)
                self.assertIsNone(result.reply)

    async def test_a_partially_filled_flow_is_not_ready(self):
        for complaint, order in EXPECTED_FLOW_ORDER.items():
            with self.subTest(complaint=complaint):
                result = await self._planner().plan(self._ctx(
                    phase="interviewing", chief_complaint=complaint,
                    profile={"name": "Sara", "age": 30, order[0]: "x"}))
                self.assertFalse(result.ready_for_diagnosis)

    async def test_greeting_turn_selects_the_complaint_and_asks_its_first_question(self):
        """The greeting turn stores the complaint DESCRIPTION, not a slot, so
        the first clinical question asked is still the flow's first slot."""
        result = await self._planner().plan(self._ctx(
            phase="greeting", chief_complaint=None, profile={"name": "Sara", "age": 30},
            entities={"symptoms": ["chest_pain"]}, message="my chest hurts"))
        self.assertEqual(result.chief_complaint, "chest_pain")
        self.assertEqual(result.phase, "interviewing")
        self.assertEqual(result.profile_updates["chief_complaint_description"], "my chest hurts")
        self.assertNotIn("duration", result.profile_updates)
        chest_duration = next(
            s["question_en"] for s in interview_engine.FLOWS["chest_pain"]["slots"]
            if s["key"] == "duration")
        self.assertEqual(result.reply, chest_duration)

    async def test_an_interviewing_turn_fills_the_current_slot_then_asks_the_next(self):
        """THE semantics Phase 2 has to reproduce, stated on its own.

        A turn does two things: it stores this answer into the first unfilled
        slot, and only THEN picks the next question. So the topic asked is
        always computed against the POST-UPDATE profile — selecting against
        the pre-update profile would re-ask the question just answered.
        """
        result = await self._planner().plan(self._ctx(
            phase="interviewing", chief_complaint="chest_pain", message="since this morning",
            profile={"name": "Sara", "age": 30}))

        self.assertEqual(result.profile_updates["duration"], "since this morning")
        chest_character = next(
            s["question_en"] for s in interview_engine.FLOWS["chest_pain"]["slots"]
            if s["key"] == "character")
        self.assertEqual(result.reply, chest_character)

    async def test_an_unknown_complaint_uses_the_generic_flow(self):
        """An off-vocabulary complaint falls back to generic: with duration
        already filled, this turn fills severity and asks associated_symptoms."""
        result = await self._planner().plan(self._ctx(
            phase="interviewing", chief_complaint="something_unmapped", message="moderate",
            profile={"name": "Sara", "age": 30, "duration": "x"}))
        self.assertEqual(result.profile_updates["severity"], "moderate")
        generic_assoc = next(
            s["question_en"] for s in interview_engine.FLOWS["generic"]["slots"]
            if s["key"] == "associated_symptoms")
        self.assertEqual(result.reply, generic_assoc)


# ===========================================================================
# 5. LLMPlanner's turn cap and readiness gate
# ===========================================================================

class TestLLMPlannerInterviewBounds(unittest.TestCase):
    def test_turn_cap_and_readiness_thresholds_are_as_recorded(self):
        self.assertEqual(planner.MAX_INTERVIEW_TURNS, 6)
        self.assertEqual(planner.COMPLETENESS_MIN_FINDINGS, 3)
        self.assertEqual(planner.COMPLETENESS_MIN_TURNS, 2)

    def test_known_summary_counts_filled_clinical_fields(self):
        known = planner._known_summary(
            {"duration": "2 days", "severity": "severe",
             "associated_symptoms_detected": ["nausea"], "chief_complaint_description": "skip"})
        self.assertEqual(set(known), {"duration", "severity", "associated_symptoms_detected"})


if __name__ == "__main__":
    unittest.main()
