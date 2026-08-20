"""
Symbolic contradiction and correction reasoning, Phase 4 — rules and security.

Two properties this file exists to defend.

1. NO PATIENT NAME EVER BECOMES PROLOG SOURCE.
   A name is arbitrary free text and the allow-list is not widened for it.
   Contradiction reasoning only ever asks "is this the same value as that
   one?", which a stable opaque token answers exactly as well. Every fact
   crossing the boundary is checked for that here.

2. THREE LOOKALIKE CATEGORIES STAY APART.
   "no, I don't have a fever" (clinical), "the pain isn't severe, it's
   moderate" (slot answer) and "my age is 24, not 23" (correction) all contain
   a negation. Only the last replaces a stored value. Collapsing them is the
   obvious wrong turn and TestSemanticCategories is what prevents it.

Rollout and end-to-end behaviour live in
test_symbolic_corrections_rollout_phase4.py.
"""

import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import reasoning_engine
from virtual_doctor.reasoning_engine import fact_builder, prolog_engine, vocabulary
from virtual_doctor.reasoning_engine.result_models import FactSet, StatedFact

_needs_engine = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed on this machine"
)

SESSION = "sess-corrections"


def history(field, *pairs, source="raw patient text that must not leak"):
    return [{"field": field, "old_value": old, "new_value": new,
             "source_text": source, "confirmed": True} for old, new in pairs]


def decide(profile=None, candidate=None, session=SESSION, **kw):
    fact_set = fact_builder.build_facts(
        session, profile=profile or {}, correction_candidate=candidate, **kw)
    return reasoning_engine.decide_corrections(
        fact_set, vocabulary.slug_session_key(session)), fact_set


# ===========================================================================
# 1. The general single-valued contradiction rule
# ===========================================================================

@_needs_engine
class TestGeneralContradiction(unittest.TestCase):
    def test_an_age_change_is_a_single_value_conflict(self):
        decision, _ = decide({"age": 24, "correction_history": history("age", (23, 24))})
        self.assertEqual(len(decision.contradictions), 1)
        found = decision.contradictions[0]
        self.assertEqual(found.slot, "age")
        self.assertEqual(found.old_value, 23)
        self.assertEqual(found.new_value, 24)
        self.assertEqual(found.kind, "single_value_conflict")

    def test_a_name_change_is_a_single_value_conflict(self):
        decision, _ = decide({"name": "علي",
                              "correction_history": history("name", ("أحمد", "علي"))})
        self.assertEqual(decision.profile_correction_slot, "name")

    def test_the_same_value_restated_is_not_a_contradiction(self):
        decision, _ = decide({"age": 24, "correction_history": history("age", (24, 24))})
        self.assertEqual(decision.contradictions, ())

    def test_one_value_with_no_history_is_not_a_contradiction(self):
        decision, _ = decide({"age": 24, "name": "أحمد"})
        self.assertEqual(decision.contradictions, ())

    def test_the_latest_statement_wins_across_a_chain(self):
        decision, fact_set = decide(
            {"age": 25, "correction_history": history("age", (23, 24), (24, 25))})
        turns = sorted((s.value, s.turn) for s in fact_set.stated if s.slot == "age")
        self.assertEqual(turns, [(23, 0), (24, 1), (25, 2)])
        self.assertEqual(len(decision.contradictions), 1)
        self.assertEqual(decision.contradictions[0].new_value, 25)
        self.assertEqual(decision.contradictions[0].old_value, 24)

    def test_an_older_statement_never_overrides_a_newer_one(self):
        decision, _ = decide(
            {"age": 25, "correction_history": history("age", (23, 24), (24, 25))})
        self.assertGreater(decision.contradictions[0].new_turn,
                           decision.contradictions[0].old_turn)

    def test_assertion_order_does_not_change_the_result(self):
        """Facts are asserted in whatever order the builder emits. Sorting
        inside the rules is what makes the answer independent of that."""
        key = vocabulary.slug_session_key(SESSION)
        statements = [
            StatedFact(session=key, slot="age", value=23, turn=0),
            StatedFact(session=key, slot="age", value=24, turn=1),
            StatedFact(session=key, slot="age", value=25, turn=2),
        ]
        forward = reasoning_engine.decide_corrections(
            FactSet(stated=tuple(statements)), key)
        backward = reasoning_engine.decide_corrections(
            FactSet(stated=tuple(reversed(statements))), key)
        self.assertEqual([c.as_log_fields() for c in forward.contradictions],
                         [c.as_log_fields() for c in backward.contradictions])
        self.assertEqual(forward.contradictions[0].new_value, 25)

    def test_the_result_is_deterministic_across_repeated_runs(self):
        signatures = set()
        for _ in range(15):
            decision, _ = decide(
                {"age": 25, "name": "علي",
                 "correction_history": history("age", (23, 24), (24, 25))
                 + history("name", ("أحمد", "علي"))})
            signatures.add(tuple(c.as_log_fields()["field"] for c in decision.contradictions))
        self.assertEqual(len(signatures), 1)

    def test_there_are_no_field_specific_contradiction_predicates(self):
        """One general rule over single_valued/1, not one predicate per field."""
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "reasoning_engine", "rules", "contradictions.pl")
        with open(path, encoding="utf-8") as fh:
            body = "\n".join(l for l in fh if not l.strip().startswith("%"))
        for forbidden in ("age_contradiction", "name_contradiction",
                          "age_correction", "name_correction"):
            self.assertNotIn(forbidden, body)


# ===========================================================================
# 2. The semantic boundary
# ===========================================================================

@_needs_engine
class TestSemanticCategories(unittest.TestCase):
    def test_symptom_negation_is_not_a_profile_correction(self):
        """Case C. fever present, later denied — clinical information, not a
        request to replace a stored value."""
        decision, _ = decide({}, entities={"symptoms": ["fever"]},
                             denied_symptoms=["fever"])
        self.assertEqual(decision.contradictions, ())
        self.assertIsNone(decision.profile_correction_slot)

    def test_a_severity_change_is_a_clinical_state_update(self):
        """Case D. The slot is single-valued, so it IS a contradiction — but it
        is classified as an update, not a correction of a wrong record."""
        decision, _ = decide(
            {"severity": "moderate",
             "correction_history": history("severity", ("severe", "moderate"))})
        self.assertEqual(decision.kind_for("severity"), "clinical_state_update")
        self.assertIsNone(decision.profile_correction_slot)

    def test_clinical_and_identity_slots_are_classified_differently(self):
        decision, _ = decide(
            {"age": 24, "severity": "moderate",
             "correction_history": history("age", (23, 24))
             + history("severity", ("severe", "moderate"))})
        self.assertEqual(decision.kind_for("age"), "single_value_conflict")
        self.assertEqual(decision.kind_for("severity"), "clinical_state_update")
        self.assertEqual(decision.profile_correction_slot, "age")

    def test_associated_symptoms_is_never_a_contradiction(self):
        """Multi-valued: a patient accumulating symptoms is not contradicting
        themselves. Marking it single-valued would make every new symptom a
        conflict."""
        decision, _ = decide(
            {"associated_symptoms": "تعرق",
             "correction_history": history("associated_symptoms", ("غثيان", "تعرق"))})
        self.assertEqual(decision.contradictions, ())
        self.assertIsNone(decision.kind_for("associated_symptoms"))

    def test_an_ambiguous_correction_is_named_not_guessed(self):
        """Case E: "غلط" alone. Intent without a field."""
        decision, _ = decide({"age": 23}, candidate={"field": None, "new_value": None})
        self.assertEqual(decision.kind_for("unknown_slot"), "ambiguous_correction")
        self.assertIsNone(decision.profile_correction_slot)

    def test_a_known_field_with_no_usable_value_is_uncertain_not_ambiguous(self):
        decision, _ = decide({"age": 23}, candidate={"field": "age", "new_value": None})
        self.assertEqual(decision.kind_for("age"), "uncertain_correction")

    def test_a_candidate_matching_the_stored_value_is_no_contradiction(self):
        decision, _ = decide({"age": 23}, candidate={"field": "age", "new_value": 23})
        self.assertEqual(decision.kind_for("age"), "no_contradiction")
        self.assertEqual(decision.contradictions, ())

    def test_slot_cardinality_matches_the_python_vocabulary(self):
        """contradictions.pl restates the clinical slot list; this stops the two
        drifting apart."""
        rows = prolog_engine.query("clinical_slot(S)")
        self.assertEqual({r["S"] for r in rows},
                         set(vocabulary.CLINICAL_SLOTS) - {"associated_symptoms"})
        self.assertEqual({r["S"] for r in prolog_engine.query("multi_valued(S)")},
                         {"associated_symptoms"})


# ===========================================================================
# 3. Free text never crosses the boundary
# ===========================================================================

@_needs_engine
class TestNoRawTextReachesProlog(unittest.TestCase):
    NAMES = ["أحمد", "علي", "Ahmad O'Brien", "مريم-سارة", "X'; halt. --",
             "Robert'); DROP TABLE", "名前", "a" * 200]

    def test_no_name_appears_in_any_emitted_fact(self):
        for name in self.NAMES:
            with self.subTest(name=name[:20]):
                _decision, fact_set = decide(
                    {"name": name, "correction_history": history("name", ("أحمد", name))})
                for statement in fact_set.stated:
                    self.assertNotIn(name, str(statement.value))
                    self.assertTrue(
                        vocabulary.is_value_token(statement.value)
                        or isinstance(statement.value, int)
                        or vocabulary.is_safe_atom(statement.value))

    def test_correction_history_source_text_never_reaches_prolog(self):
        """correction_history carries raw patient speech in `source_text`. Only
        field/old_value/new_value are read."""
        secret = "لا، عمري 24 مش 23 وهذا نص خام"
        _decision, fact_set = decide(
            {"age": 24, "correction_history": history("age", (23, 24), source=secret)})
        blob = " ".join(str(s.value) for s in fact_set.stated)
        blob += " ".join(f"{f.predicate}{f.subject}{f.value}" for f in fact_set.facts)
        self.assertNotIn("نص خام", blob)
        self.assertNotIn(secret, blob)

    def test_tokens_are_stable_across_calls(self):
        """Provenance is rebuilt from the database every turn, so the same
        stored value must always yield the same token."""
        first = vocabulary.value_token("أحمد")
        for _ in range(10):
            self.assertEqual(vocabulary.value_token("أحمد"), first)

    def test_tokens_collapse_trivial_variants(self):
        self.assertEqual(vocabulary.value_token("أحمد "), vocabulary.value_token("أحمد"))

    def test_different_values_get_different_tokens(self):
        self.assertNotEqual(vocabulary.value_token("أحمد"), vocabulary.value_token("علي"))

    def test_tokens_are_valid_atoms(self):
        for name in self.NAMES:
            with self.subTest(name=name[:20]):
                token = vocabulary.value_token(name)
                self.assertTrue(vocabulary.is_safe_atom(token))
                self.assertTrue(vocabulary.is_value_token(token))

    def test_integers_and_canonical_atoms_are_not_tokenised(self):
        """Readability where it is safe: an age of 23 is `23` in the trace."""
        self.assertEqual(vocabulary.value_token(23), 23)
        self.assertEqual(vocabulary.value_token("severe"), "severe")

    def test_empty_values_produce_no_token(self):
        """Absence is not a value; a token for "" would make two unanswered
        fields look equal."""
        for empty in ("", "   ", None):
            self.assertIsNone(vocabulary.value_token(empty))

    def test_injection_payloads_in_values_cannot_execute(self):
        payloads = ["v_1), halt, x(", "X", "_", "x.\n:- halt.", "'q'", True, 3.5, ["x"]]
        for payload in payloads:
            with self.subTest(payload=repr(payload)[:30]):
                _decision, fact_set = decide(
                    {"name": payload,
                     "correction_history": history("name", ("أحمد", payload))})
                for statement in fact_set.stated:
                    self.assertTrue(
                        isinstance(statement.value, int)
                        or vocabulary.is_safe_atom(statement.value))
        self.assertEqual(prolog_engine.query("urgency_rank({l}, R)", l="urgent"),
                         [{"R": 2}])

    def test_a_hand_built_statement_cannot_smuggle_raw_text(self):
        key = vocabulary.slug_session_key(SESSION)
        for bad in ("أحمد", "Ahmad", "x.\n:- halt.", "Evil", ""):
            with self.subTest(bad=bad):
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    StatedFact(session=key, slot="name", value=bad, turn=0)

    def test_a_statement_rejects_a_bad_turn_index(self):
        key = vocabulary.slug_session_key(SESSION)
        for bad in (-1, "0", True, None, 1.5):
            with self.subTest(bad=bad):
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    StatedFact(session=key, slot="age", value=23, turn=bad)


# ===========================================================================
# 4. Provenance construction
# ===========================================================================

@_needs_engine
class TestProvenanceBuilding(unittest.TestCase):
    def test_duplicate_values_are_collapsed(self):
        """"said 24 twice" must not look like a contradiction."""
        _decision, fact_set = decide(
            {"age": 24, "correction_history": history("age", (24, 24), (24, 24))})
        ages = [s for s in fact_set.stated if s.slot == "age"]
        self.assertEqual(len(ages), 1)

    def test_turn_indices_are_contiguous_and_ordered(self):
        _decision, fact_set = decide(
            {"age": 26, "correction_history": history("age", (23, 24), (24, 25), (25, 26))})
        turns = sorted(s.turn for s in fact_set.stated if s.slot == "age")
        self.assertEqual(turns, [0, 1, 2, 3])

    def test_a_candidate_is_appended_after_the_history(self):
        _decision, fact_set = decide(
            {"age": 24, "correction_history": history("age", (23, 24))},
            candidate={"field": "age", "new_value": 25})
        ages = sorted((s.turn, s.value) for s in fact_set.stated if s.slot == "age")
        self.assertEqual(ages, [(0, 23), (1, 24), (2, 25)])

    def test_malformed_history_entries_are_ignored(self):
        for bad_history in ("not a list", [None], [{"no_field": 1}], [{"field": 123}], {}):
            with self.subTest(history=repr(bad_history)[:30]):
                decision, _ = decide({"age": 24, "correction_history": bad_history})
                self.assertTrue(decision.available)

    def test_provenance_is_rebuilt_identically_from_the_same_state(self):
        profile = {"age": 25, "name": "علي",
                   "correction_history": history("age", (23, 24), (24, 25))}
        first = decide(profile)[1]
        second = decide(profile)[1]
        self.assertEqual(sorted((s.slot, s.value, s.turn) for s in first.stated),
                         sorted((s.slot, s.value, s.turn) for s in second.stated))

    def test_the_provenance_slot_list_matches_the_rule_file(self):
        rows = prolog_engine.query("identity_slot(S)")
        self.assertEqual({r["S"] for r in rows},
                         set(fact_builder.PROVENANCE_IDENTITY_SLOTS))


# ===========================================================================
# 5. Failure behaviour
# ===========================================================================

class TestCorrectionFailureBehaviour(unittest.TestCase):
    def test_unavailable_asserts_nothing_about_the_turn(self):
        decision = reasoning_engine.CorrectionDecision.unavailable("no swipl")
        self.assertFalse(decision.available)
        self.assertEqual(decision.contradictions, ())
        self.assertEqual(decision.kinds, ())
        self.assertIsNone(decision.profile_correction_slot)

    def test_prolog_unavailable_degrades_cleanly(self):
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable("no swipl")):
            decision = reasoning_engine.decide_corrections(
                FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(decision.available)
        self.assertIn("no swipl", decision.degraded_reason)

    def test_a_consult_failure_degrades_cleanly(self):
        with patch.object(prolog_engine, "_ensure_engine",
                          side_effect=prolog_engine.PrologUnavailable(
                              "rule file missing: contradictions.pl")):
            decision = reasoning_engine.decide_corrections(
                FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(decision.available)
        self.assertIn("contradictions.pl", decision.degraded_reason)

    def test_a_query_exception_degrades_cleanly(self):
        with patch.object(prolog_engine, "_raw_query", side_effect=RuntimeError("boom")):
            decision = reasoning_engine.decide_corrections(
                FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(decision.available)
        self.assertIn("boom", decision.degraded_reason)

    def test_a_budget_exhaustion_degrades_cleanly(self):
        with patch.object(prolog_engine, "_raw_query",
                          side_effect=prolog_engine.PrologBudgetExceeded("too many")):
            decision = reasoning_engine.decide_corrections(
                FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertFalse(decision.available)
        self.assertIn("budget_exceeded", decision.degraded_reason)

    @_needs_engine
    def test_malformed_rows_are_dropped_not_guessed_at(self):
        bad = [{"Slot": "Bad Slot", "Old": 1, "New": 2, "OldTurn": 0, "NewTurn": 1},
               {"Slot": "age", "Old": 1, "New": 2, "OldTurn": "x", "NewTurn": 1}]
        real = prolog_engine._raw_query

        def fake(goal, **kw):
            return bad if "contradiction(" in goal else real(goal, **kw)

        with patch.object(prolog_engine, "_raw_query", side_effect=fake):
            decision = reasoning_engine.decide_corrections(
                FactSet(), vocabulary.slug_session_key(SESSION))
        self.assertTrue(decision.available)
        self.assertEqual(decision.contradictions, ())

    @_needs_engine
    def test_facts_are_cleaned_up_after_an_exception_inside_the_scope(self):
        key = vocabulary.slug_session_key(SESSION)
        statements = (StatedFact(session=key, slot="age", value=23, turn=0),)
        with self.assertRaises(ValueError):
            with prolog_engine.session_scope(key, FactSet(stated=statements)):
                raise ValueError("caller exploded")
        self.assertEqual(prolog_engine._fact_count_all(), 0)


# ===========================================================================
# 6. Isolation and concurrency
# ===========================================================================

@_needs_engine
class TestCorrectionIsolationAndConcurrency(unittest.TestCase):
    def tearDown(self):
        prolog_engine.reset_for_tests()

    def test_no_provenance_leaks_between_sessions(self):
        a, _ = decide({"age": 24, "correction_history": history("age", (23, 24))},
                      session="s-a")
        b, _ = decide({"age": 30}, session="s-b")
        self.assertEqual(a.profile_correction_slot, "age")
        self.assertEqual(b.contradictions, ())
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_no_facts_leak_after_a_decision(self):
        decide({"age": 24, "correction_history": history("age", (23, 24))})
        self.assertEqual(prolog_engine._fact_count_all(), 0)

    def test_concurrent_correction_reasoning_stays_correct(self):
        from concurrent.futures import ThreadPoolExecutor

        errors = []

        def worker(index):
            profile = ({"age": 24, "correction_history": history("age", (23, 24))}
                       if index % 2 == 0 else {"age": 30})
            expected = "age" if index % 2 == 0 else None
            try:
                for _ in range(15):
                    decision, _ = decide(profile, session=f"s-t{index}")
                    if not decision.available or decision.profile_correction_slot != expected:
                        errors.append(f"{index}: {decision.profile_correction_slot}")
                        return
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{type(exc).__name__}: {exc}")

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(worker, range(8)))

        self.assertEqual(errors, [])
        self.assertEqual(prolog_engine._fact_count_all(), 0)


# ===========================================================================
# 7. Rule file separation
# ===========================================================================

class TestRuleFileSeparation(unittest.TestCase):
    def _body(self, name):
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "reasoning_engine", "rules", name)
        with open(path, encoding="utf-8") as fh:
            return "\n".join(l for l in fh if not l.strip().startswith("%"))

    def test_contradictions_pl_owns_no_urgency_or_red_flags(self):
        body = self._body("contradictions.pl")
        for forbidden in ("urgency", "red_flag", "urgency_rank", "final_urgency"):
            self.assertNotIn(forbidden, body, forbidden)

    def test_contradictions_pl_owns_no_question_selection(self):
        body = self._body("contradictions.pl")
        for forbidden in ("next_question", "relevant_question", "question_priority",
                          "interview_complete"):
            self.assertNotIn(forbidden, body, forbidden)

    def test_contradictions_pl_contains_no_natural_language(self):
        body = self._body("contradictions.pl")
        self.assertNotIn('"', body)
        for arabic_marker in ("ال", "من", "في"):
            self.assertNotIn(arabic_marker, body)

    def test_safety_pl_owns_no_contradiction_rules(self):
        body = self._body("safety.pl")
        for forbidden in ("contradiction", "single_valued", "stated("):
            self.assertNotIn(forbidden, body, forbidden)

    def test_interview_pl_owns_no_contradiction_rules(self):
        body = self._body("interview.pl")
        for forbidden in ("contradiction", "single_valued", "vd_stated"):
            self.assertNotIn(forbidden, body, forbidden)


if __name__ == "__main__":
    unittest.main()
