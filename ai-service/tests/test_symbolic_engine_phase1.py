"""
Symbolic reasoning layer, Phase 1 — engine lifecycle, concurrency, isolation.

What this file pins is the INFRASTRUCTURE contract, not any clinical rule:
Phase 1 ships rules/base.pl only, and base.pl deliberately contains no red
flags, no interview logic, no contradictions and no differential.

Three properties here are non-negotiable and each was derived from a failure
reproduced against pyswip 0.3.3 during the Phase 0 audit rather than from
theory:

  * PySwip is not concurrency-safe. `Prolog._queryIsOpen` is a CLASS
    attribute, so 8 unsynchronised threads produced 4 NestedQueryErrors. The
    engine must serialize every operation through one lock.
  * A raw Prolog object or a live query generator must never escape the
    module. A generator held across an await is how the nested-query failure
    gets reintroduced.
  * Facts must not survive their session, including when the caller raises.

The engine boots a real SWI-Prolog. Where SWI-Prolog is genuinely absent these
tests skip rather than fail — but the unavailability PATH is still tested
unconditionally, by simulating the failure, because that path is what protects
a production consultation.
"""

import os
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import reasoning_engine
from virtual_doctor.reasoning_engine import prolog_engine, vocabulary
from virtual_doctor.reasoning_engine.result_models import Fact, ReasoningResult

_ENGINE_PRESENT = prolog_engine.available()
_needs_engine = unittest.skipUnless(
    _ENGINE_PRESENT, "SWI-Prolog/pyswip not installed on this machine"
)

SESSION = "s_phase1test"


def _facts(session=SESSION, **_kw):
    return [
        Fact(session=session, predicate="symptom", subject="chest_pain", value="present"),
        Fact(session=session, predicate="symptom", subject="nausea", value="present"),
        Fact(session=session, predicate="answered", subject="duration", value="true"),
        Fact(session=session, predicate="patient_attr", subject="age", value=41),
    ]



class TestEngineAvailability(unittest.TestCase):
    @_needs_engine
    def test_engine_reports_available_and_loads_base_rules(self):
        self.assertTrue(prolog_engine.available())
        status = prolog_engine.status()
        self.assertTrue(status["loaded"])
        self.assertIsNone(status["load_error"])
        self.assertEqual(status["rule_files"],
                         ["base.pl", "interview.pl", "safety.pl", "contradictions.pl"])
        self.assertIsNotNone(status["prolog_version"])

    @_needs_engine
    def test_no_rules_beyond_the_current_phase_are_loaded(self):
        """UPDATED IN PHASES 2, 3 AND 4 (interview.pl, safety.pl,
        contradictions.pl), each time deliberately, as those phases were
        approved.

        The valuable half is unchanged and is why this test still exists: the
        rule base must never quietly gain a file from a phase that has not been
        approved — differential.pl belongs to Phase 5. Loading order matters
        too: base.pl defines the urgency lattice and declares urgency/2
        multifile, so it must be consulted before safety.pl adds clauses to it.
        """
        self.assertEqual(prolog_engine.RULE_FILES,
                         ("base.pl", "interview.pl", "safety.pl", "contradictions.pl"))
        self.assertNotIn("differential.pl", prolog_engine.RULE_FILES)
        self.assertLess(prolog_engine.RULE_FILES.index("base.pl"),
                        prolog_engine.RULE_FILES.index("safety.pl"))

    def test_status_never_raises_even_when_the_engine_is_broken(self):
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            status = prolog_engine.status()
        self.assertIn("loaded", status)
        self.assertIn("enabled", status)



class TestPrologUnavailableFallback(unittest.TestCase):
    def test_reason_returns_explicit_absence_not_a_fabricated_verdict(self):
        """The one thing that must never happen: inventing an urgency.

        `unavailable` carries urgency=None, so a caller that forgets to check
        `available` sees an obvious hole rather than a confident "routine".
        """
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            result = reasoning_engine.reason(reasoning_engine.FactSet(), SESSION)

        self.assertFalse(result.available)
        self.assertIsNone(result.urgency)
        self.assertIn("no swipl", result.degraded_reason)

    def test_unexpected_engine_error_also_degrades_instead_of_raising(self):
        with patch.object(prolog_engine, "_raw_query", side_effect=RuntimeError("boom")):
            result = reasoning_engine.reason(reasoning_engine.FactSet(), SESSION)
        self.assertFalse(result.available)
        self.assertIsNone(result.urgency)
        self.assertIn("boom", result.degraded_reason)

    def test_unavailable_result_reports_no_urgency_in_its_log_fields(self):
        fields = ReasoningResult.unavailable("missing runtime").as_log_fields()
        self.assertIsNone(fields["urgency"])
        self.assertEqual(fields["urgency_rules"], [])
        self.assertEqual(fields["degraded_reason"], "missing runtime")



@_needs_engine
class TestSessionIsolation(unittest.TestCase):
    def setUp(self):
        prolog_engine.reset_for_tests()

    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_facts_are_removed_when_the_scope_exits(self):
        with prolog_engine.session_scope(SESSION, _facts()) as session:
            self.assertEqual(len(session.query("symptom({s}, X)")), 2)
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_facts_are_removed_even_when_the_caller_raises(self):
        """Cleanup lives in `finally`, so an exception inside the `with` body
        must not leave a consultation's facts behind for the next patient."""
        with self.assertRaises(ValueError):
            with prolog_engine.session_scope(SESSION, _facts()):
                raise ValueError("caller exploded mid-turn")
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_one_session_cannot_see_another_sessions_facts(self):
        with prolog_engine.session_scope("s_alpha", _facts("s_alpha")) as alpha:
            self.assertEqual(len(alpha.query("symptom({s}, X)")), 2)
        with prolog_engine.session_scope("s_beta", []) as beta:
            self.assertEqual(beta.query("symptom({s}, X)"), [])

    def test_a_fact_from_a_different_session_is_refused(self):
        """Defence in depth: the scope will not assert a fact whose own
        session atom disagrees with the scope it was handed to."""
        with self.assertRaises(vocabulary.OutOfVocabulary):
            with prolog_engine.session_scope("s_alpha", _facts("s_beta")):
                pass
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_repeated_turns_do_not_accumulate_facts(self):
        for _ in range(5):
            with prolog_engine.session_scope(SESSION, _facts()) as session:
                self.assertEqual(len(session.query("symptom({s}, X)")), 2)
        self.assertEqual(prolog_engine._fact_count_all(), 0)



@_needs_engine
class TestConcurrentAccess(unittest.TestCase):
    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_many_threads_query_without_nested_query_errors(self):
        """Reproduces the Phase 0 audit scenario, through the locked API.

        Unsynchronised, this shape killed 4 of 8 threads with
        NestedQueryError. Through prolog_engine it must be silent.
        """
        errors = []

        def worker(index):
            try:
                for _ in range(40):
                    rows = prolog_engine.query("urgency_rank({level}, R)", level="urgent")
                    if not rows:
                        errors.append(f"thread {index}: empty result")
                        return
            except Exception as exc:  # noqa: BLE001 - the assertion is "none of these"
                errors.append(f"thread {index}: {type(exc).__name__}: {exc}")

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(worker, range(8)))

        self.assertEqual(errors, [])

    def test_concurrent_sessions_never_observe_each_others_facts(self):
        """The scope holds the lock for its whole body, so two consultations
        cannot have facts in the store at the same time. Each thread must see
        exactly its own two symptoms, never four."""
        observed = []
        errors = []

        def worker(index):
            key = f"s_thread{index}"
            try:
                for _ in range(20):
                    with prolog_engine.session_scope(key, _facts(key)) as session:
                        observed.append(len(session.query("symptom({s}, X)")))
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{key}: {type(exc).__name__}: {exc}")

        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(worker, range(6)))

        self.assertEqual(errors, [])
        self.assertEqual(set(observed), {2})
        self.assertEqual(prolog_engine._fact_count_all(), 0)



class TestNoRawPrologObjectIsExposed(unittest.TestCase):
    def test_package_exports_no_pyswip_objects(self):
        for name in reasoning_engine.__all__:
            self.assertNotIn("pyswip", repr(getattr(reasoning_engine, name)).lower())
        self.assertNotIn("Prolog", reasoning_engine.__all__)

    @_needs_engine
    def test_query_returns_a_materialized_list_not_a_generator(self):
        """A generator handed back to a caller could be advanced after the lock
        was released — which is exactly what raises NestedQueryError."""
        rows = prolog_engine.query("urgency_rank({level}, R)", level="urgent")
        self.assertIsInstance(rows, list)
        for row in rows:
            self.assertIsInstance(row, dict)

    @_needs_engine
    def test_session_handle_carries_only_a_session_atom(self):
        with prolog_engine.session_scope(SESSION, []) as session:
            self.assertEqual(session.__slots__, ("_key",))
            self.assertEqual(session.key, SESSION)
            self.assertFalse(hasattr(session, "__dict__"))

    @_needs_engine
    def test_results_are_plain_python_values(self):
        with prolog_engine.session_scope(SESSION, _facts()) as session:
            rows = session.query("patient_attr({s}, age, V)")
        self.assertEqual(rows, [{"V": 41}])



@_needs_engine
class TestCanonicalUrgencyLattice(unittest.TestCase):
    def test_prolog_ranking_matches_the_python_vocabulary(self):
        """One lattice, mirrored in two languages — this is the test that stops
        them drifting into the two independent rankings the audit found."""
        for level, expected in vocabulary.URGENCY_RANK.items():
            rows = prolog_engine.query("urgency_rank({level}, R)", level=level)
            self.assertEqual(rows, [{"R": expected}], level)

    def test_no_urgency_facts_defaults_to_routine_never_to_nothing(self):
        with prolog_engine.session_scope(SESSION, []) as session:
            self.assertEqual(session.query("final_urgency({s}, U)"), [{"U": "routine"}])

    def test_final_urgency_takes_the_maximum_so_it_can_only_escalate(self):
        """Invariant S13. Two verdicts of different severity present at once
        must resolve to the higher one, whichever order they were asserted."""
        facts = [
            Fact(session=SESSION, predicate="deterministic_urgency",
                 subject="safety_urgent_05", value="urgent"),
            Fact(session=SESSION, predicate="deterministic_urgency",
                 subject="safety_emergency_02", value="emergency"),
        ]
        with prolog_engine.session_scope(SESSION, facts) as session:
            self.assertEqual(session.query("final_urgency({s}, U)"), [{"U": "emergency"}])

        with prolog_engine.session_scope(SESSION, list(reversed(facts))) as session:
            self.assertEqual(session.query("final_urgency({s}, U)"), [{"U": "emergency"}])

    def test_urgency_evidence_names_the_rule_behind_the_verdict(self):
        facts = [Fact(session=SESSION, predicate="deterministic_urgency",
                      subject="safety_urgent_05", value="urgent")]
        with prolog_engine.session_scope(SESSION, facts) as session:
            rows = session.query("urgency_evidence({s}, U, Rule)")
        self.assertEqual(rows, [{"U": "urgent", "Rule": "safety_urgent_05"}])



class TestFeatureFlagDefaultsOff(unittest.TestCase):
    def test_flag_absent_means_disabled(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("VD_SYMBOLIC", None)
            self.assertFalse(prolog_engine.enabled())

    def test_explicit_zero_means_disabled(self):
        for value in ("0", "false", "False", "no", "off", ""):
            with patch.dict(os.environ, {"VD_SYMBOLIC": value}):
                self.assertFalse(prolog_engine.enabled(), value)

    def test_truthy_values_enable_it(self):
        for value in ("1", "true", "TRUE", "yes", "on"):
            with patch.dict(os.environ, {"VD_SYMBOLIC": value}):
                self.assertTrue(prolog_engine.enabled(), value)


if __name__ == "__main__":
    unittest.main()
