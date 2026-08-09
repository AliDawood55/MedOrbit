"""
Symbolic safety reasoning, Phase 3 — the rules and the urgency merge.

The single property this file exists to defend:

    NOTHING HERE CAN LOWER AN URGENCY.

MedicalSafetyLayer runs first, on raw text, and is permanent. Its verdict
enters Prolog as deterministic_urgency/3 and final_urgency/2 is a maximum, so
a symbolic rule can raise a verdict and has no expressible way to reduce one.
That is asserted from every direction below: floor vs symbolic in all four
combinations, assertion order, session history, and an engine that is simply
unavailable.

The second property, equally load-bearing, is that the pinned-routine cases
stay routine. TestPinnedNegativesStayRoutine re-runs the exact list from
test_characterization_safety_matrix.py through the symbolic engine, because the
extractor DOES emit ['headache'] and ['headache','nausea'] for cases this
system deliberately rates normal — so a rule keyed on either would escalate
them. There is no such rule, and this is what keeps it that way.
"""

import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, reasoning, reasoning_engine
from virtual_doctor.reasoning_engine import fact_builder, prolog_engine, vocabulary
from virtual_doctor.reasoning_engine.result_models import Fact, FactSet, RedFlag, SafetyVerdict

from test_characterization_safety_matrix import PINNED_NEGATIVES

_needs_engine = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed on this machine"
)

SESSION = "sess-safety"


def verdict(*, symptoms=(), profile=None, safety_result=None, session=SESSION):
    fact_set = fact_builder.build_facts(
        session, profile=profile or {}, entities={"symptoms": list(symptoms)},
        safety_result=safety_result)
    return reasoning_engine.decide_safety(fact_set, vocabulary.slug_session_key(session))


def floor(severity):
    """A minimal MedicalSafetyLayer-shaped result at a given severity."""
    return {"severity": severity, "matched_patterns": [
        {"type": severity, "matched": "x", "pattern": "p"}], "response": "BODY"}


# ===========================================================================
# 1. Red flags fire on structured facts, with evidence
# ===========================================================================

@_needs_engine
class TestRedFlagsFromStructuredFacts(unittest.TestCase):
    def test_chest_pain_with_dyspnea_is_an_emergency(self):
        v = verdict(symptoms=["chest_pain", "shortness_of_breath"])
        self.assertEqual(v.symbolic_urgency, "emergency")
        self.assertIn("chest_pain_with_dyspnea", [f.rule_id for f in v.red_flags])

    def test_each_single_symptom_rule_fires_at_its_recorded_level(self):
        cases = [
            (["shortness_of_breath"], "dyspnea", "emergency"),
            (["unconscious"], "unconscious", "emergency"),
            (["severe_bleeding"], "severe_bleeding", "emergency"),
            (["hematuria"], "hematuria", "urgent"),
            (["seizure"], "seizure", "urgent"),
        ]
        for symptoms, rule_id, urgency in cases:
            with self.subTest(rule=rule_id):
                v = verdict(symptoms=symptoms)
                self.assertEqual(v.symbolic_urgency, urgency)
                self.assertIn(rule_id, [f.rule_id for f in v.red_flags])

    def test_severity_answers_escalate_pain_symptoms(self):
        v = verdict(symptoms=["headache"], profile={"severity": "شديد"})
        self.assertEqual(v.symbolic_urgency, "urgent")
        self.assertIn("severe_pain", [f.rule_id for f in v.red_flags])

    def test_severe_chest_pain_reaches_emergency(self):
        v = verdict(symptoms=["chest_pain"], profile={"severity": "شديد"})
        self.assertEqual(v.symbolic_urgency, "emergency")
        self.assertIn("severe_chest_pain", [f.rule_id for f in v.red_flags])

    def test_no_facts_yields_routine_and_no_rules(self):
        v = verdict()
        self.assertTrue(v.available)
        self.assertEqual(v.symbolic_urgency, "routine")
        self.assertEqual(v.red_flags, ())


# ===========================================================================
# 2. Pinned negatives — the constraint that shaped the rule set
# ===========================================================================

@_needs_engine
class TestPinnedNegativesStayRoutine(unittest.TestCase):
    def test_every_pinned_negative_stays_routine_symbolically(self):
        """The same list the legacy characterization pins, run through Prolog.

        `headache` and `headache`+`nausea` are extracted for cases rated
        normal, so any rule keyed on them would escalate a pinned-routine case.
        """
        for name, text, lang, symptoms, reason in PINNED_NEGATIVES:
            with self.subTest(case=name, reason=reason):
                v = verdict(symptoms=symptoms,
                            safety_result=interview_engine._check_safety(text, lang))
                self.assertEqual(v.symbolic_urgency, "routine")
                self.assertEqual(v.urgency, "routine")
                self.assertEqual(v.red_flags, ())

    def test_no_rule_keys_on_headache_alone(self):
        self.assertEqual(verdict(symptoms=["headache"]).red_flags, ())

    def test_no_rule_keys_on_headache_with_nausea(self):
        self.assertEqual(verdict(symptoms=["headache", "nausea"]).red_flags, ())

    def test_no_rule_keys_on_chest_pain_alone(self):
        """Arabic chest pain already reaches emergency through the raw-text
        layer; English "chest pain" is routine today. Escalating the symptom
        alone would change English behaviour with no pinned basis."""
        self.assertEqual(verdict(symptoms=["chest_pain"]).red_flags, ())

    def test_no_rule_keys_on_fever_alone(self):
        self.assertEqual(verdict(symptoms=["fever"]).red_flags, ())


# ===========================================================================
# 3. The deterministic floor can never be lowered
# ===========================================================================

@_needs_engine
class TestDeterministicFloorIsNeverLowered(unittest.TestCase):
    def test_all_four_floor_versus_symbolic_combinations(self):
        cases = [
            ("emergency", [], "emergency"),
            ("urgent", [], "urgent"),
            ("urgent", ["chest_pain", "shortness_of_breath"], "emergency"),
            ("normal", ["hematuria"], "urgent"),
            ("normal", [], "routine"),
            ("emergency", ["hematuria"], "emergency"),
        ]
        for severity, symptoms, expected in cases:
            with self.subTest(floor=severity, symptoms=symptoms):
                v = verdict(symptoms=symptoms, safety_result=floor(severity))
                self.assertEqual(v.urgency, expected)

    def test_symbolic_routine_never_reduces_an_emergency_floor(self):
        v = verdict(symptoms=["headache"], safety_result=floor("emergency"))
        self.assertEqual(v.symbolic_urgency, "routine")
        self.assertEqual(v.urgency, "emergency")

    def test_symbolic_routine_never_reduces_an_urgent_floor(self):
        v = verdict(symptoms=["headache"], safety_result=floor("urgent"))
        self.assertEqual(v.symbolic_urgency, "routine")
        self.assertEqual(v.urgency, "urgent")

    def test_fact_assertion_order_does_not_change_the_result(self):
        """Two orderings of the same facts must agree, or the merge is not a
        maximum but an accident of clause order."""
        key = vocabulary.slug_session_key(SESSION)
        facts = [
            Fact(session=key, predicate="deterministic_urgency",
                 subject="safety_urgent_05", value="urgent"),
            Fact(session=key, predicate="symptom", subject="chest_pain", value="present"),
            Fact(session=key, predicate="symptom", subject="shortness_of_breath",
                 value="present"),
        ]
        forward = reasoning_engine.decide_safety(FactSet(facts=tuple(facts)), key)
        backward = reasoning_engine.decide_safety(FactSet(facts=tuple(reversed(facts))), key)
        self.assertEqual(forward.urgency, "emergency")
        self.assertEqual(backward.urgency, "emergency")
        self.assertEqual([f.rule_id for f in forward.red_flags],
                         [f.rule_id for f in backward.red_flags])


# ===========================================================================
# 4. Multiple rules: maximum wins, all evidence survives
# ===========================================================================

@_needs_engine
class TestMultipleRedFlags(unittest.TestCase):
    def _multi(self):
        return verdict(symptoms=["chest_pain", "shortness_of_breath"],
                       profile={"severity": "شديد"})

    def test_the_maximum_urgency_wins(self):
        self.assertEqual(self._multi().symbolic_urgency, "emergency")

    def test_every_rule_that_fired_is_preserved(self):
        rules = {f.rule_id for f in self._multi().red_flags}
        self.assertEqual(rules, {"chest_pain_with_dyspnea", "dyspnea",
                                 "severe_chest_pain", "severe_pain"})

    def test_a_lower_severity_rule_is_not_discarded(self):
        """severe_pain is urgent while others are emergency. It must still be
        in the trace — the maximum decides the verdict, not what is recorded."""
        flags = {f.rule_id: f.urgency for f in self._multi().red_flags}
        self.assertEqual(flags["severe_pain"], "urgent")

    def test_evidence_ordering_is_deterministic(self):
        signatures = {
            tuple((f.rule_id, f.urgency, f.evidence) for f in self._multi().red_flags)
            for _ in range(20)
        }
        self.assertEqual(len(signatures), 1)

    def test_red_flags_are_sorted_severity_first_then_rule_id(self):
        flags = self._multi().red_flags
        keys = [(-f.rank, f.rule_id) for f in flags]
        self.assertEqual(keys, sorted(keys))

    def test_the_top_flag_is_the_most_severe(self):
        top = self._multi().top
        self.assertEqual(top.urgency, "emergency")
        self.assertEqual(top.rule_id, "chest_pain_with_dyspnea")

    def test_evidence_contains_only_canonical_atoms(self):
        for flag in self._multi().red_flags:
            for atom in flag.evidence:
                with self.subTest(rule=flag.rule_id, atom=atom):
                    self.assertTrue(vocabulary.is_safe_atom(atom))

    def test_rule_ids_are_stable_canonical_atoms(self):
        for flag in self._multi().red_flags:
            with self.subTest(rule=flag.rule_id):
                self.assertTrue(vocabulary.is_safe_atom(flag.rule_id))


# ===========================================================================
# 5. The canonical merge
# ===========================================================================

class TestCanonicalUrgencyMerge(unittest.TestCase):
    def test_merge_is_a_maximum_over_the_lattice(self):
        levels = ["routine", "urgent", "emergency"]
        for a in levels:
            for b in levels:
                with self.subTest(a=a, b=b):
                    expected = a if vocabulary.URGENCY_RANK[a] >= vocabulary.URGENCY_RANK[b] else b
                    self.assertEqual(reasoning_engine.merge_urgency(a, b), expected)

    def test_legacy_normal_maps_to_routine_at_the_boundary(self):
        self.assertEqual(reasoning_engine.merge_urgency("normal"), "routine")
        self.assertEqual(reasoning_engine.merge_urgency("normal", "urgent"), "urgent")

    def test_none_and_unknown_contribute_nothing(self):
        """"I have no opinion" must not vote for calm."""
        self.assertEqual(reasoning_engine.merge_urgency(None, "urgent"), "urgent")
        self.assertEqual(reasoning_engine.merge_urgency("banana", "emergency"), "emergency")
        self.assertEqual(reasoning_engine.merge_urgency(None, None), "routine")

    def test_there_is_exactly_one_rank_table_in_the_service(self):
        """Phase 3 requirement: no independent rank implementations remain."""
        self.assertEqual(reasoning._URGENCY_RANK, dict(vocabulary.URGENCY_RANK))
        self.assertEqual(interview_engine._SEVERITY_RANK,
                         {"normal": 0, "urgent": 1, "emergency": 2})
        for level in ("urgent", "emergency"):
            self.assertEqual(interview_engine._SEVERITY_RANK[level],
                             vocabulary.URGENCY_RANK[level] - 1)

    @_needs_engine
    def test_prolog_ranking_still_matches_python(self):
        for level, expected in vocabulary.URGENCY_RANK.items():
            self.assertEqual(
                prolog_engine.query("urgency_rank({level}, R)", level=level),
                [{"R": expected}])


# ===========================================================================
# 6. The LLM is not authoritative
# ===========================================================================

class TestLLMCannotDowngrade(unittest.TestCase):
    def test_llm_routine_cannot_lower_a_rule_engine_urgent(self):
        self.assertEqual(reasoning._more_urgent("urgent", "routine"), "urgent")

    def test_llm_routine_cannot_lower_an_emergency(self):
        self.assertEqual(reasoning._more_urgent("emergency", "routine"), "emergency")

    def test_llm_emergency_may_escalate(self):
        self.assertEqual(reasoning._more_urgent("routine", "emergency"), "emergency")

    @_needs_engine
    def test_llm_routine_cannot_lower_a_symbolic_emergency(self):
        v = verdict(symptoms=["chest_pain", "shortness_of_breath"])
        self.assertEqual(reasoning_engine.merge_urgency(v.urgency, "routine"), "emergency")

    def test_llm_routine_cannot_lower_the_deterministic_layer(self):
        self.assertEqual(reasoning_engine.merge_urgency("urgent", "routine"), "urgent")
        self.assertEqual(reasoning_engine.merge_urgency("emergency", "routine"), "emergency")


# ===========================================================================
# 7. Failure behaviour
# ===========================================================================

class TestSafetyFailureBehaviour(unittest.TestCase):
    def test_unavailable_carries_no_urgency_at_all(self):
        """Never "routine". A reasoner that could not run has said nothing, and
        recording silence as reassurance is the failure this must not have."""
        v = SafetyVerdict.unavailable("no swipl")
        self.assertFalse(v.available)
        self.assertIsNone(v.urgency)
        self.assertIsNone(v.symbolic_urgency)
        self.assertEqual(v.red_flags, ())
        self.assertFalse(v.escalates_over("routine"))

    def test_prolog_unavailable_degrades_cleanly(self):
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            v = reasoning_engine.decide_safety(FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(v.available)
        self.assertIsNone(v.urgency)

    def test_a_query_exception_degrades_cleanly(self):
        with patch.object(prolog_engine, "_raw_query", side_effect=RuntimeError("boom")):
            v = reasoning_engine.decide_safety(FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(v.available)
        self.assertIn("boom", v.degraded_reason)

    def test_a_consult_failure_degrades_cleanly(self):
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable(
                              "rule file missing: safety.pl")):
            v = reasoning_engine.decide_safety(FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(v.available)
        self.assertIn("safety.pl", v.degraded_reason)

    def test_a_budget_exhaustion_degrades_cleanly(self):
        with patch.object(prolog_engine, "_raw_query",
                          side_effect=prolog_engine.PrologBudgetExceeded("too many")):
            v = reasoning_engine.decide_safety(FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(v.available)
        self.assertIn("budget_exceeded", v.degraded_reason)

    @_needs_engine
    def test_malformed_rows_are_dropped_not_guessed_at(self):
        """Dropping can only LOSE an escalation, never invent one — the safe
        direction when a result cannot be validated."""
        bad = [{"RuleId": "Bad Rule", "Urgency": "urgent", "Evidence": ["x"]},
               {"RuleId": "ok_rule", "Urgency": "banana", "Evidence": []},
               {"RuleId": None, "Urgency": "urgent", "Evidence": []}]
        real = prolog_engine._raw_query

        def fake(goal, **kw):
            if "safety_evidence" in goal:
                return bad
            return real(goal, **kw)

        with patch.object(prolog_engine, "_raw_query", side_effect=fake):
            v = reasoning_engine.decide_safety(FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertTrue(v.available)
        self.assertEqual(v.red_flags, ())


# ===========================================================================
# 8. Bounded execution
# ===========================================================================

@_needs_engine
class TestBoundedExecution(unittest.TestCase):
    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_the_inference_limit_is_a_core_builtin_on_this_engine(self):
        """call_with_time_limit/2 needs library(time), which the container's
        swi-prolog-core does not ship. This is the mechanism that works on
        both 9.2.9 and 10.0.2."""
        rows = prolog_engine.query(
            "current_predicate(call_with_inference_limit/3) -> R = {yes} ; R = {no}",
            yes="yes", no="no")
        self.assertEqual(rows, [{"R": "yes"}])

    def test_a_runaway_goal_is_cut_off(self):
        prolog_engine.query("assertz((vd_test_loop :- vd_test_loop))")
        with self.assertRaises(prolog_engine.PrologBudgetExceeded):
            prolog_engine.query("vd_test_loop")
        prolog_engine.query("retractall(vd_test_loop)")

    def test_the_engine_still_works_after_a_cut_off(self):
        prolog_engine.query("assertz((vd_test_loop2 :- vd_test_loop2))")
        with self.assertRaises(prolog_engine.PrologBudgetExceeded):
            prolog_engine.query("vd_test_loop2")
        self.assertEqual(prolog_engine.query("urgency_rank({l}, R)", l="urgent"),
                         [{"R": 2}])
        prolog_engine.query("retractall(vd_test_loop2)")

    def test_session_facts_are_cleaned_up_after_a_cut_off(self):
        """Cleanup runs in `finally` and is deliberately unbounded, so it still
        succeeds on the path where a rule just exhausted its budget."""
        key = vocabulary.slug_session_key(SESSION)
        facts = (Fact(session=key, predicate="symptom", subject="chest_pain",
                      value="present"),)
        prolog_engine.query("assertz((vd_test_loop3 :- vd_test_loop3))")
        with self.assertRaises(prolog_engine.PrologBudgetExceeded):
            with prolog_engine.session_scope(key, facts) as session:
                session.query("vd_test_loop3")
        self.assertEqual(prolog_engine._fact_count_all(), 0)
        prolog_engine.query("retractall(vd_test_loop3)")

    def test_a_normal_safety_query_is_far_below_the_budget(self):
        self.assertGreaterEqual(prolog_engine.INFERENCE_LIMIT, 100000)
        v = verdict(symptoms=["chest_pain", "shortness_of_breath"],
                    profile={"severity": "شديد"})
        self.assertTrue(v.available)


# ===========================================================================
# 9. Security
# ===========================================================================

@_needs_engine
class TestSafetySecurityBoundary(unittest.TestCase):
    HOSTILE = ["chest_pain), halt, f(x", "Evil", "_", "x.\n:- halt.", "'q'",
               "شديد جدا", None, 42, True, ["chest_pain"]]

    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_hostile_symptoms_produce_no_red_flags(self):
        v = verdict(symptoms=self.HOSTILE)
        self.assertEqual(v.red_flags, ())
        self.assertEqual(v.symbolic_urgency, "routine")

    def test_a_severity_value_never_reaches_prolog_as_raw_text(self):
        """The security property is that only canonical atoms cross, not that
        nothing crosses.

        "severe); halt, x(" NORMALISES to the canonical `severe` — punctuation
        is stripped and the allow-list matches on substring, which is the same
        behaviour that correctly maps a real answer like "the pain is severe,
        help me" onto `severe`. What must never happen is the raw string
        becoming a term, and that is what is asserted here.
        """
        for payload in ("severe); halt, x(", "Severe'", "\x00severe",
                        "الألم شديد جدا", "mild but honestly severe"):
            with self.subTest(payload=payload):
                fact_set = fact_builder.build_facts(
                    SESSION, profile={"severity": payload},
                    entities={"symptoms": ["headache"]})
                for fact in fact_set.facts:
                    self.assertTrue(vocabulary.is_safe_atom(fact.subject))
                    if isinstance(fact.value, str):
                        self.assertTrue(vocabulary.is_safe_atom(fact.value))
                slots = {f.subject: f.value for f in fact_set.facts if f.predicate == "slot"}
                self.assertIn(slots.get("severity"),
                              (None, "severe", "mild", "moderate", vocabulary.UNKNOWN_VALUE))

    def test_an_unrecognisable_severity_answer_escalates_nothing(self):
        """Free text with no canonical severity collapses to unknown_value, and
        unknown_value fires no rule."""
        for payload in ("Evil", "asdfghjkl", "x.\n:- halt.", "12345"):
            with self.subTest(payload=payload):
                v = verdict(symptoms=["headache"], profile={"severity": payload})
                self.assertEqual(v.red_flags, ())
                self.assertEqual(v.symbolic_urgency, "routine")

    def test_a_hostile_safety_severity_cannot_forge_a_floor(self):
        v = verdict(safety_result={"severity": "emergency); halt, x(",
                                   "matched_patterns": [], "response": None})
        self.assertEqual(v.urgency, "routine")

    def test_rule_ids_come_only_from_the_static_rule_file(self):
        """Rule ids are application constants. Nothing a patient or a model
        produces can become one."""
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "reasoning_engine", "rules", "safety.pl")
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        for rule_id in ("chest_pain_with_dyspnea", "dyspnea", "unconscious",
                        "severe_bleeding", "severe_chest_pain", "hematuria",
                        "seizure", "severe_pain"):
            self.assertIn(rule_id, body)

    def test_the_engine_survives_a_hostile_turn(self):
        verdict(symptoms=self.HOSTILE, profile={"severity": "Evil"})
        self.assertEqual(verdict(symptoms=["hematuria"]).symbolic_urgency, "urgent")
        self.assertEqual(prolog_engine._fact_count_all(), 0)


# ===========================================================================
# 10. Session isolation and concurrency, with safety.pl loaded
# ===========================================================================

@_needs_engine
class TestSafetyConcurrencyAndIsolation(unittest.TestCase):
    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_two_sessions_do_not_share_red_flags(self):
        a = verdict(symptoms=["chest_pain", "shortness_of_breath"], session="s-a")
        b = verdict(symptoms=["headache"], session="s-b")
        self.assertEqual(a.symbolic_urgency, "emergency")
        self.assertEqual(b.symbolic_urgency, "routine")
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_no_facts_leak_after_a_safety_decision(self):
        verdict(symptoms=["chest_pain", "shortness_of_breath"])
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_concurrent_safety_queries_stay_correct_and_error_free(self):
        from concurrent.futures import ThreadPoolExecutor

        errors, seen = [], []

        def worker(index):
            symptoms, expected = [
                (["chest_pain", "shortness_of_breath"], "emergency"),
                (["hematuria"], "urgent"),
                (["headache"], "routine"),
                (["unconscious"], "emergency"),
            ][index % 4]
            try:
                for _ in range(15):
                    v = verdict(symptoms=symptoms, session=f"s-t{index}")
                    if not v.available or v.symbolic_urgency != expected:
                        errors.append(f"{index}: {v.symbolic_urgency} != {expected}")
                        return
                    seen.append(v.symbolic_urgency)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{type(exc).__name__}: {exc}")

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(worker, range(8)))

        self.assertEqual(errors, [])
        self.assertEqual(len(seen), 8 * 15)
        self.assertEqual(prolog_engine._fact_count_all(), 0)


# ===========================================================================
# 11. Structural separation of concerns
# ===========================================================================

class TestRuleFileSeparation(unittest.TestCase):
    def _body(self, name):
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "reasoning_engine", "rules", name)
        with open(path, encoding="utf-8") as fh:
            return "\n".join(line for line in fh if not line.strip().startswith("%"))

    def test_interview_pl_still_defines_no_urgency(self):
        body = self._body("interview.pl")
        for forbidden in ("urgency(", "urgency_rank", "red_flag", "final_urgency",
                          "deterministic_urgency"):
            self.assertNotIn(forbidden, body, forbidden)

    def test_safety_pl_generates_no_patient_facing_language(self):
        """Warning wording stays in Python templates. A rule file that emitted
        a sentence would put patient-facing text outside review."""
        body = self._body("safety.pl")
        self.assertNotIn('"', body)
        for arabic_marker in ("ال", "من", "في"):
            self.assertNotIn(arabic_marker, body)
        for forbidden in ("question", "reply", "message", "warning_text"):
            self.assertNotIn(forbidden, body)

    def test_safety_pl_declares_urgency_multifile(self):
        """Without this, consulting safety.pl would REPLACE base.pl's clause and
        silently drop the deterministic floor."""
        with open(os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                               "reasoning_engine", "rules", "safety.pl"),
                  encoding="utf-8") as fh:
            body = fh.read()
        self.assertIn(":- multifile(urgency/2).", body)

    @_needs_engine
    def test_the_deterministic_floor_clause_survived_loading_safety_pl(self):
        """The consequence of the above, asserted behaviourally: a floor-only
        session must still reach its floor level."""
        v = verdict(safety_result=floor("emergency"))
        self.assertEqual(v.symbolic_urgency, "routine")
        self.assertEqual(v.urgency, "emergency")


if __name__ == "__main__":
    unittest.main()
