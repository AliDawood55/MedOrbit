"""
Symbolic interview reasoning, Phase 2 — the rules themselves.

Direct tests of rules/interview.pl through fact_builder, with no LLM and no
planner in the path. If something here fails, the rule base is wrong; the
planner-integration tests live in test_symbolic_planner_phase2.py.

The centrepiece is TestParityWithStaticFlow: for every flow, in every reachable
state, the topic Prolog selects must equal the slot
interview_engine._next_unfilled_slot would have picked. That is what makes
Phase 2 a migration rather than a redesign, and it is checked exhaustively
rather than on a few samples.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine
from virtual_doctor.reasoning_engine import fact_builder, prolog_engine, vocabulary

_needs_engine = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed on this machine"
)

FLOWS = interview_engine.FLOWS
INTAKE = {"name": "Sara", "age": 30}
SESSION = "sess-interview"


def decide(complaint, profile, *, asked=(), safety=(), flow_slots=None, session=SESSION):
    """One symbolic interview decision, straight through the real path."""
    from virtual_doctor import reasoning_engine

    slots = flow_slots if flow_slots is not None else FLOWS[complaint]["slots"]
    fact_set = fact_builder.build_facts(
        session, profile=profile, chief_complaint=complaint,
        flow_slots=slots, asked_topics=asked, safety_topics=safety,
    )
    return reasoning_engine.decide_interview(
        fact_set, vocabulary.slug_session_key(session))


def order_of(complaint):
    return [s["key"] for s in FLOWS[complaint]["slots"]]


# ===========================================================================
# 1. Parity with the flow the system uses today
# ===========================================================================

@_needs_engine
class TestParityWithStaticFlow(unittest.TestCase):
    def test_symbolic_topic_equals_next_unfilled_slot_in_every_state(self):
        """Exhaustive: 6 flows x every prefix of answered slots."""
        for complaint in sorted(FLOWS):
            order = order_of(complaint)
            profile = dict(INTAKE)
            for answered_count in range(len(order) + 1):
                expected_slot = interview_engine._next_unfilled_slot(
                    FLOWS[complaint], profile)
                expected = expected_slot["key"] if expected_slot else None
                with self.subTest(complaint=complaint, answered=answered_count):
                    decision = decide(complaint, profile)
                    self.assertTrue(decision.available)
                    self.assertEqual(decision.topic, expected)
                    self.assertEqual(decision.complete, expected is None)
                if answered_count < len(order):
                    profile[order[answered_count]] = "answered"

    def test_ranked_order_is_the_flows_declared_order(self):
        for complaint in sorted(FLOWS):
            with self.subTest(complaint=complaint):
                self.assertEqual(list(decide(complaint, INTAKE).ranked),
                                 order_of(complaint))

    def test_a_gap_is_selected_even_when_later_slots_are_filled(self):
        profile = {**INTAKE, "duration": "x", "radiation": "x",
                   "associated_symptoms": "x"}
        self.assertEqual(decide("chest_pain", profile).topic, "character")


# ===========================================================================
# 2. Knowledge state: answered, asked, outstanding
# ===========================================================================

@_needs_engine
class TestKnowledgeState(unittest.TestCase):
    def test_an_unanswered_topic_is_selected(self):
        self.assertEqual(decide("headache", INTAKE).topic, "duration")

    def test_an_answered_topic_is_never_selected_again(self):
        for complaint in sorted(FLOWS):
            order = order_of(complaint)
            for answered in order:
                with self.subTest(complaint=complaint, answered=answered):
                    decision = decide(complaint, {**INTAKE, answered: "x"})
                    self.assertNotEqual(decision.topic, answered)
                    self.assertNotIn(answered, decision.ranked)
                    self.assertNotIn(answered, decision.unanswered)

    def test_no_repeat_across_a_whole_multi_turn_interview(self):
        """Walk a full consultation; every topic must appear exactly once."""
        for complaint in sorted(FLOWS):
            with self.subTest(complaint=complaint):
                profile, seen = dict(INTAKE), []
                for _ in range(len(order_of(complaint))):
                    decision = decide(complaint, profile, asked=seen)
                    self.assertIsNotNone(decision.topic)
                    self.assertNotIn(decision.topic, seen)
                    seen.append(decision.topic)
                    profile[decision.topic] = "answered"
                self.assertEqual(sorted(seen), sorted(order_of(complaint)))
                self.assertTrue(decide(complaint, profile, asked=seen).complete)

    def test_asked_but_unanswered_is_reported(self):
        decision = decide("headache", INTAKE, asked=("duration",))
        self.assertEqual(decision.asked_unanswered, ("duration",))

    def test_asked_but_unanswered_is_still_offered_again(self):
        """Preserves today's behaviour: the current application re-offers a
        topic the patient did not actually answer. Gating on asked/2 here would
        change when interviews end, which Phase 2 must not do."""
        self.assertEqual(decide("headache", INTAKE, asked=("duration",)).topic, "duration")

    def test_an_answered_topic_is_not_reported_as_asked_unanswered(self):
        decision = decide("headache", {**INTAKE, "duration": "x"}, asked=("duration",))
        self.assertEqual(decision.asked_unanswered, ())

    def test_outstanding_lists_only_required_slots_of_the_active_flow(self):
        decision = decide("headache", {**INTAKE, "duration": "x"})
        self.assertEqual(set(decision.unanswered),
                         set(order_of("headache")) - {"duration"})


# ===========================================================================
# 3. Relevance — the vocabulary is not the question list
# ===========================================================================

@_needs_engine
class TestRelevanceExcludesIrrelevantTopics(unittest.TestCase):
    def test_topics_the_active_flow_does_not_declare_are_never_selected(self):
        for complaint in sorted(FLOWS):
            declared = set(order_of(complaint))
            irrelevant = vocabulary.CLINICAL_SLOTS - declared
            with self.subTest(complaint=complaint):
                ranked = set(decide(complaint, INTAKE).ranked)
                self.assertEqual(ranked & irrelevant, set())

    def test_radiation_is_not_asked_during_a_headache_consultation(self):
        self.assertNotIn("radiation", decide("headache", INTAKE).ranked)

    def test_exposure_is_not_asked_during_a_rash_consultation(self):
        self.assertNotIn("exposure", decide("rash", INTAKE).ranked)

    def test_radiation_is_asked_during_a_chest_pain_consultation(self):
        self.assertIn("radiation", decide("chest_pain", INTAKE).ranked)

    def test_no_flow_slots_means_no_topic_and_no_completion(self):
        """No active flow is not the same as a finished interview."""
        decision = decide("headache", INTAKE, flow_slots=[])
        self.assertIsNone(decision.topic)
        self.assertFalse(decision.complete)


# ===========================================================================
# 4. Dependencies
# ===========================================================================

@_needs_engine
class TestIntakeDependency(unittest.TestCase):
    """The one dependency the application has today: name and age precede
    every clinical question."""

    def test_no_clinical_topic_before_intake_is_complete(self):
        for profile in ({}, {"name": "Sara"}, {"age": 30}):
            with self.subTest(profile=profile):
                decision = decide("headache", profile)
                self.assertIsNone(decision.topic)
                self.assertEqual(decision.ranked, ())

    def test_topics_become_available_once_intake_is_complete(self):
        self.assertEqual(decide("headache", INTAKE).topic, "duration")

    def test_an_unmet_dependency_never_makes_the_interview_look_complete(self):
        """The dangerous failure mode: no relevant question because a
        dependency is unmet must NOT read as "nothing left to ask"."""
        answered = {s: "x" for s in order_of("headache")}
        decision = decide("headache", answered)
        self.assertIsNone(decision.topic)
        self.assertFalse(decision.complete)

    def test_an_implausible_age_does_not_satisfy_intake(self):
        decision = decide("headache", {"name": "Sara", "age": 999})
        self.assertIsNone(decision.topic)


# ===========================================================================
# 5. Priority
# ===========================================================================

@_needs_engine
class TestPriority(unittest.TestCase):
    def test_priority_follows_the_flows_declared_position(self):
        for complaint in sorted(FLOWS):
            order = order_of(complaint)
            profile = dict(INTAKE)
            for expected in order:
                with self.subTest(complaint=complaint, expected=expected):
                    self.assertEqual(decide(complaint, profile).topic, expected)
                profile[expected] = "x"

    def test_ordinary_topics_sit_in_the_normal_band(self):
        decision = decide("headache", INTAKE)
        self.assertGreaterEqual(decision.priority, 100)

    def test_a_safety_indicated_topic_is_asked_first(self):
        decision = decide("chest_pain", INTAKE, safety=("associated_symptoms",))
        self.assertEqual(decision.topic, "associated_symptoms")
        self.assertLess(decision.priority, 100)

    def test_safety_priority_does_not_change_which_topics_are_relevant(self):
        plain = decide("chest_pain", INTAKE)
        flagged = decide("chest_pain", INTAKE, safety=("associated_symptoms",))
        self.assertEqual(set(plain.ranked), set(flagged.ranked))

    def test_safety_priority_carries_no_urgency_of_its_own(self):
        """Ordering only. Phase 2 must not produce an urgency verdict —
        interview.pl contains no urgency rule, and a safety-flagged interview
        turn adds no urgency fact."""
        from virtual_doctor import reasoning_engine

        fact_set = fact_builder.build_facts(
            SESSION, profile=INTAKE, chief_complaint="chest_pain",
            flow_slots=FLOWS["chest_pain"]["slots"],
            safety_topics=("associated_symptoms",))
        self.assertEqual(
            [f for f in fact_set.facts if f.predicate == "deterministic_urgency"], [])

        result = reasoning_engine.reason(fact_set, vocabulary.slug_session_key(SESSION))
        self.assertEqual(result.urgency.level, "routine")
        self.assertEqual(result.urgency.rules, ())

    def test_an_answered_safety_topic_does_not_win(self):
        decision = decide("chest_pain", {**INTAKE, "associated_symptoms": "x"},
                          safety=("associated_symptoms",))
        self.assertEqual(decision.topic, "duration")

    def test_selection_is_deterministic_across_repeated_runs(self):
        first = decide("chest_pain", INTAKE)
        for _ in range(10):
            repeat = decide("chest_pain", INTAKE)
            self.assertEqual(repeat.topic, first.topic)
            self.assertEqual(repeat.ranked, first.ranked)

    def test_equal_priorities_break_by_topic_name_deterministically(self):
        """A genuine tie: two topics at the SAME position.

        Facts are built directly here because the normal path enumerates flow
        slots, so it can never produce two equal positions — which is itself
        worth knowing, and is asserted separately below. The tie-break must
        still be defined, because sorting on priority alone would leave the
        winner up to clause order.
        """
        from virtual_doctor import reasoning_engine
        from virtual_doctor.reasoning_engine.result_models import Fact, FactSet

        key = vocabulary.slug_session_key("sess-tie")
        facts = (
            Fact(session=key, predicate="intake", subject="name", value="true"),
            Fact(session=key, predicate="patient_attr", subject="age", value=30),
            Fact(session=key, predicate="required_slot", subject="severity", value=0),
            Fact(session=key, predicate="required_slot", subject="duration", value=0),
            Fact(session=key, predicate="required_slot", subject="location", value=0),
        )
        for _ in range(5):
            decision = reasoning_engine.decide_interview(FactSet(facts=facts), key)
            self.assertEqual(decision.ranked, ("duration", "location", "severity"))
            self.assertEqual(decision.topic, "duration")

    def test_the_normal_path_cannot_produce_equal_priorities(self):
        """Flow slots are enumerated, so every topic has a distinct position and
        the tie-break above is a guarantee rather than a routine occurrence."""
        for complaint in sorted(FLOWS):
            with self.subTest(complaint=complaint):
                fact_set = fact_builder.build_facts(
                    SESSION, profile=INTAKE, chief_complaint=complaint,
                    flow_slots=FLOWS[complaint]["slots"])
                positions = [f.value for f in fact_set.facts
                             if f.predicate == "required_slot"]
                self.assertEqual(len(positions), len(set(positions)))


# ===========================================================================
# 6. Completion
# ===========================================================================

@_needs_engine
class TestInterviewCompletion(unittest.TestCase):
    def test_incomplete_while_any_required_topic_is_missing(self):
        for complaint in sorted(FLOWS):
            order = order_of(complaint)
            for missing in order:
                profile = {**INTAKE, **{s: "x" for s in order if s != missing}}
                with self.subTest(complaint=complaint, missing=missing):
                    decision = decide(complaint, profile)
                    self.assertFalse(decision.complete)
                    self.assertEqual(decision.topic, missing)

    def test_complete_once_every_required_topic_is_answered(self):
        for complaint in sorted(FLOWS):
            profile = {**INTAKE, **{s: "x" for s in order_of(complaint)}}
            with self.subTest(complaint=complaint):
                decision = decide(complaint, profile)
                self.assertTrue(decision.complete)
                self.assertIsNone(decision.topic)

    def test_optional_topics_never_block_completion(self):
        """An unanswered OPTIONAL slot leaves the interview complete, while
        still being offered as a question if there is time."""
        slots = [{"key": "duration", "required": True},
                 {"key": "triggers", "required": False}]
        decision = decide("generic", {**INTAKE, "duration": "x"}, flow_slots=slots)
        self.assertTrue(decision.complete)
        self.assertEqual(decision.unanswered, ())
        self.assertIn("triggers", decision.ranked)

    def test_optional_topics_are_still_selectable(self):
        slots = [{"key": "duration", "required": True},
                 {"key": "triggers", "required": False}]
        self.assertEqual(decide("generic", INTAKE, flow_slots=slots).topic, "duration")


# ===========================================================================
# 7. Session isolation, concurrency, security
# ===========================================================================

@_needs_engine
class TestSessionIsolationAndConcurrency(unittest.TestCase):
    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_two_sessions_do_not_share_interview_state(self):
        a = decide("chest_pain", INTAKE, session="sess-a")
        b = decide("headache", {**INTAKE, "duration": "x"}, session="sess-b")
        self.assertEqual(a.topic, "duration")
        self.assertEqual(b.topic, "severity")
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_no_facts_leak_after_a_decision(self):
        decide("chest_pain", INTAKE)
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_concurrent_decisions_stay_isolated_and_error_free(self):
        from concurrent.futures import ThreadPoolExecutor

        errors, results = [], []

        def worker(index):
            complaint = ["chest_pain", "headache", "rash", "fever_cough"][index % 4]
            try:
                for _ in range(15):
                    decision = decide(complaint, INTAKE, session=f"sess-t{index}")
                    if not decision.available:
                        errors.append(decision.degraded_reason)
                        return
                    results.append((complaint, decision.topic))
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{type(exc).__name__}: {exc}")

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(worker, range(8)))

        self.assertEqual(errors, [])
        self.assertEqual({topic for _, topic in results}, {"duration"})
        self.assertEqual(prolog_engine._fact_count_all(), 0)


@_needs_engine
class TestInterviewIdentifierInjectionResistance(unittest.TestCase):
    # Hostile AND meaningless: no canonical topic exists, so nothing survives.
    #
    # Deliberately excludes payloads that DO normalise onto a real topic —
    # "Duration" and "\\+duration" both fold to `duration`, because
    # normalize_english lowercases and strips punctuation. That is the
    # allow-list mapping working, not leaking: whatever the input looked like,
    # the output is a member of a fixed set. Pinned separately below.
    HOSTILE = [
        "duration), halt, f(x", "X", "_", "x.\n:- halt.",
        "'quoted'", "duration; halt", "duration-1", "not_a_topic",
        None, 42, True, ["duration"],
    ]

    NORMALISES_TO_CANONICAL = [("Duration", "duration"), ("\\+duration", "duration"),
                               ("  duration  ", "duration"), ("DURATION", "duration")]

    def test_hostile_flow_slot_keys_never_become_topics(self):
        decision = decide("generic", INTAKE,
                          flow_slots=[{"key": h, "required": True} for h in self.HOSTILE])
        self.assertIsNone(decision.topic)
        self.assertEqual(decision.ranked, ())
        self.assertFalse(decision.complete)

    def test_hostile_asked_topics_are_rejected(self):
        fact_set = fact_builder.build_facts(
            SESSION, profile=INTAKE, chief_complaint="headache",
            flow_slots=FLOWS["headache"]["slots"], asked_topics=self.HOSTILE)
        self.assertEqual([f for f in fact_set.facts if f.predicate == "asked"], [])
        self.assertEqual(len(fact_set.rejected), len(self.HOSTILE))

    def test_hostile_safety_topics_are_rejected(self):
        fact_set = fact_builder.build_facts(
            SESSION, profile=INTAKE, chief_complaint="headache",
            flow_slots=FLOWS["headache"]["slots"], safety_topics=self.HOSTILE)
        self.assertEqual([f for f in fact_set.facts if f.predicate == "safety_topic"], [])

    def test_obfuscated_topic_names_normalise_onto_the_canonical_atom(self):
        """Whatever the surface form, what reaches Prolog is a member of the
        fixed topic set — never the raw string."""
        for payload, expected in self.NORMALISES_TO_CANONICAL:
            with self.subTest(payload=payload):
                self.assertFalse(vocabulary.is_safe_atom(payload))
                self.assertEqual(vocabulary.canonical_slot(payload), expected)
                self.assertIn(expected, vocabulary.CLINICAL_SLOTS)

    def test_every_emitted_topic_is_a_safe_atom_whatever_the_input(self):
        fact_set = fact_builder.build_facts(
            SESSION, profile=INTAKE, chief_complaint="headache",
            flow_slots=[{"key": h, "required": True}
                        for h in self.HOSTILE + [p for p, _ in self.NORMALISES_TO_CANONICAL]],
            asked_topics=self.HOSTILE,
            safety_topics=self.HOSTILE)
        for fact in fact_set.facts:
            with self.subTest(fact=fact):
                self.assertTrue(vocabulary.is_safe_atom(fact.subject))

    def test_the_engine_survives_and_still_answers_afterwards(self):
        decide("generic", INTAKE,
               flow_slots=[{"key": h, "required": True} for h in self.HOSTILE])
        self.assertEqual(decide("headache", INTAKE).topic, "duration")
        self.assertEqual(prolog_engine._fact_count_all(), 0)


# ===========================================================================
# 8. Failure behaviour
# ===========================================================================

class TestInterviewFailureBehaviour(unittest.TestCase):
    def test_prolog_unavailable_yields_no_topic_and_no_completion(self):
        """Never fabricate a question, and never let "the reasoner is down"
        read as "we have everything we need"."""
        from unittest.mock import patch
        from virtual_doctor import reasoning_engine

        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            decision = reasoning_engine.decide_interview(
                fact_builder.build_facts(SESSION), vocabulary.slug_session_key(SESSION))

        self.assertFalse(decision.available)
        self.assertIsNone(decision.topic)
        self.assertFalse(decision.complete)
        self.assertIn("no swipl", decision.degraded_reason)

    def test_a_query_failure_degrades_the_same_way(self):
        from unittest.mock import patch
        from virtual_doctor import reasoning_engine

        with patch.object(prolog_engine, "_raw_query", side_effect=RuntimeError("boom")):
            decision = reasoning_engine.decide_interview(
                fact_builder.build_facts(SESSION), vocabulary.slug_session_key(SESSION))

        self.assertFalse(decision.available)
        self.assertIsNone(decision.topic)
        self.assertFalse(decision.complete)


# ===========================================================================
# 9. Topic anchors — calibration of the wording clamp
# ===========================================================================

class TestTopicAnchorCalibration(unittest.TestCase):
    def test_every_flow_question_passes_its_own_topics_anchors(self):
        """The flow questions ARE the deterministic fallback. If one failed its
        own topic check, the clamp would reject the very text it falls back to."""
        for complaint, flow in FLOWS.items():
            for slot in flow["slots"]:
                for lang in ("ar", "en"):
                    with self.subTest(complaint=complaint, slot=slot["key"], lang=lang):
                        self.assertTrue(vocabulary.question_matches_topic(
                            slot[f"question_{lang}"], slot["key"]))

    def test_a_question_about_another_topic_is_rejected(self):
        self.assertFalse(vocabulary.question_matches_topic(
            "هل لديك ضيق في التنفس؟", "duration"))
        self.assertFalse(vocabulary.question_matches_topic(
            "Do you have shortness of breath?", "duration"))

    def test_arabic_and_english_wording_both_validate(self):
        self.assertTrue(vocabulary.question_matches_topic("منذ متى بدأ الألم؟", "duration"))
        self.assertTrue(vocabulary.question_matches_topic("How long has it lasted?", "duration"))
        self.assertTrue(vocabulary.question_matches_topic(
            "هل ينتشر الألم إلى ذراعك؟", "radiation"))
        self.assertTrue(vocabulary.question_matches_topic(
            "Does the pain spread to your arm?", "radiation"))

    def test_empty_and_malformed_wording_is_rejected(self):
        for bad in ("", "   ", None, 42, ["x"]):
            with self.subTest(bad=bad):
                self.assertFalse(vocabulary.question_matches_topic(bad, "duration"))

    def test_an_unknown_topic_never_validates(self):
        self.assertFalse(vocabulary.question_matches_topic("anything at all", "not_a_topic"))

    def test_infer_topic_recognises_the_flow_questions(self):
        """Used only for divergence logging, so it may return None; it must not
        return the WRONG topic for the system's own question text."""
        for complaint, flow in FLOWS.items():
            for slot in flow["slots"]:
                for lang in ("ar", "en"):
                    with self.subTest(complaint=complaint, slot=slot["key"], lang=lang):
                        inferred = vocabulary.infer_topic(slot[f"question_{lang}"])
                        self.assertIn(inferred, (slot["key"], None))


if __name__ == "__main__":
    unittest.main()
