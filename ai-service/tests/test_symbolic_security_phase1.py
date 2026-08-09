"""
Symbolic reasoning layer, Phase 1 — the Prolog trust boundary.

Patient speech, LLM output and retrieved RAG text are all untrusted. Two
payload classes below are not hypothetical; both were reproduced against
pyswip 0.3.3 during the Phase 0 audit, by interpolating them into a goal:

    "chest_pain), halt, f(p,symptom,x"   parsed as Prolog SOURCE. The goal ran.
    "Evil"                               became an unbound VARIABLE. It unified
                                         with anything and fired a clinical
                                         rule that must not have fired.

The second is why escaping cannot be the defence and why the assertions here
check that the rule did NOT fire, not merely that nothing raised: the payload
contains no metacharacter for an escaper to find, and a silent false-positive
red flag is exactly as dangerous as a silently suppressed one.

So the boundary is a positive allow-list, and these tests attack it from both
sides: junk must never become an atom, and a hand-built Fact must not be able
to smuggle one past fact_builder either.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor.reasoning_engine import fact_builder, prolog_engine, vocabulary
from virtual_doctor.reasoning_engine.result_models import Fact

_ENGINE_PRESENT = prolog_engine.available()
_needs_engine = unittest.skipUnless(
    _ENGINE_PRESENT, "SWI-Prolog/pyswip not installed on this machine"
)

SESSION = "s_sectest"

# Every one of these must be refused. Grouped by what they attack.
HOSTILE_VALUES = [
    # --- goal injection: the audit payload and relatives -------------------
    "chest_pain), halt, f(p,symptom,x",
    "chest_pain), retractall(vd_fact(_,_,_,_)), symptom(s,x",
    "x :- true",
    "a, b",
    "foo(bar)",
    "[1,2,3]",
    # --- unbound variables: no metacharacter, silently catastrophic --------
    "Evil",
    "X",
    "_",
    "_Anything",
    # --- quoting and control characters ------------------------------------
    "it's",
    "'quoted'",
    '"double"',
    "back\\slash",
    "line\nbreak",
    "null\x00byte",
    "tab\there",
    # --- directives and terminators ----------------------------------------
    "x.\n:- halt.",
    ":- halt",
    "end.",
    # --- operators ----------------------------------------------------------
    "a-b", "a+b", "a=b", "a;b", "a->b", "\\+a",
    # --- Unicode: bidi controls, RTL text, homoglyphs ----------------------
    "‮chest_pain",
    "​chest_pain",
    "صداع_شديد",
    "chest pain",
    # --- shape violations ---------------------------------------------------
    "Chest_pain",
    "9lives",
    " leading_space",
    "trailing_space ",
    "two words",
    "",
    "x" * (vocabulary.MAX_ATOM_CHARS + 1),
    # --- wrong types --------------------------------------------------------
    None, 3.5, True, ["chest_pain"], {"a": 1},
]

# An integer is not an atom — require_atom rejects it — but it IS a legitimate
# FACT VALUE (`patient_attr(s, age, 41)`) and so a legitimate goal binding.
# Kept out of HOSTILE_VALUES so the goal-binding test asserts what it means to.
NON_ATOM_BUT_VALID_VALUES = [41, 0, -1]

# Hostile AND meaningless: no canonical mapping exists, so nothing survives the
# allow-list. Used for the end-to-end "no fact was asserted" assertion.
#
# Deliberately excludes payloads that DO normalise to a real symptom — e.g.
# "chest\xa0pain" with a non-breaking space folds to chest_pain. That is the
# allow-list succeeding, not leaking: the output is a canonical atom from a
# fixed set, which is the entire security property. See
# test_obfuscated_but_legitimate_input_normalises_to_a_canonical_atom.
HOSTILE_AND_UNMAPPABLE = [
    v for v in HOSTILE_VALUES
    if not isinstance(v, str) or vocabulary.canonical_symptom(v) is None
]


# ===========================================================================
# 1. The allow-list itself
# ===========================================================================

class TestIsSafeAtomRejectsEverythingHostile(unittest.TestCase):
    def test_every_hostile_value_is_rejected(self):
        for payload in HOSTILE_VALUES:
            with self.subTest(payload=repr(payload)[:60]):
                self.assertFalse(vocabulary.is_safe_atom(payload))

    def test_legitimate_atoms_are_accepted(self):
        for value in ("chest_pain", "headache", "s_abc123", "duration",
                      "safety_urgent_05", "unknown_value", "a"):
            with self.subTest(value=value):
                self.assertTrue(vocabulary.is_safe_atom(value))

    def test_require_atom_raises_out_of_vocabulary(self):
        for payload in HOSTILE_VALUES:
            with self.subTest(payload=repr(payload)[:60]):
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    vocabulary.require_atom(payload, field="probe")

    def test_length_boundary_is_exact(self):
        self.assertTrue(vocabulary.is_safe_atom("a" * vocabulary.MAX_ATOM_CHARS))
        self.assertFalse(vocabulary.is_safe_atom("a" * (vocabulary.MAX_ATOM_CHARS + 1)))


# ===========================================================================
# 2. Facts cannot carry a hostile value
# ===========================================================================

class TestFactConstructionRevalidates(unittest.TestCase):
    def test_hostile_value_cannot_be_placed_in_any_fact_field(self):
        """Fact re-validates in __post_init__, so code that builds a Fact by
        hand — bypassing fact_builder entirely — still cannot reach Prolog."""
        for payload in HOSTILE_VALUES:
            with self.subTest(payload=repr(payload)[:60]):
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    Fact(session=payload, predicate="symptom",
                         subject="chest_pain", value="present")
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    Fact(session=SESSION, predicate=payload,
                         subject="chest_pain", value="present")
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    Fact(session=SESSION, predicate="symptom",
                         subject=payload, value="present")

    def test_integer_values_are_allowed_but_booleans_are_not(self):
        """isinstance(True, int) is True in Python; `age(s, true)` is not a fact."""
        self.assertEqual(
            Fact(session=SESSION, predicate="patient_attr", subject="age", value=41).value, 41
        )
        with self.assertRaises(vocabulary.OutOfVocabulary):
            Fact(session=SESSION, predicate="patient_attr", subject="age", value=True)

    def test_facts_are_frozen(self):
        fact = Fact(session=SESSION, predicate="symptom", subject="headache", value="present")
        with self.assertRaises(Exception):
            fact.subject = "chest_pain"  # type: ignore[misc]


# ===========================================================================
# 3. Goal construction refuses unvalidated bindings
# ===========================================================================

class TestGoalBindingRejectsHostileAtoms(unittest.TestCase):
    def test_bind_rejects_every_hostile_value(self):
        for payload in HOSTILE_VALUES:
            with self.subTest(payload=repr(payload)[:60]):
                with self.assertRaises(vocabulary.OutOfVocabulary):
                    prolog_engine._bind("symptom({s}, X)", {"s": payload})

    def test_bind_accepts_a_validated_atom(self):
        self.assertEqual(
            prolog_engine._bind("symptom({s}, X)", {"s": "s_abc"}), "symptom(s_abc, X)"
        )

    def test_bind_accepts_integers_which_are_values_not_atoms(self):
        for value in NON_ATOM_BUT_VALID_VALUES:
            with self.subTest(value=value):
                self.assertFalse(vocabulary.is_safe_atom(value))
                self.assertEqual(
                    prolog_engine._bind("patient_attr({s}, age, {v})",
                                        {"s": "s_abc", "v": value}),
                    f"patient_attr(s_abc, age, {value})",
                )

    @_needs_engine
    def test_public_query_refuses_a_hostile_binding(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            prolog_engine.query("symptom({s}, X)", s="chest_pain), halt, f(x")

    @_needs_engine
    def test_session_scope_refuses_a_hostile_session_key(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            with prolog_engine.session_scope("Evil", []):
                pass


# ===========================================================================
# 4. End to end: hostile input through fact_builder never reaches a rule
# ===========================================================================

class TestHostileInputIsDroppedByTheFactBuilder(unittest.TestCase):
    def test_injection_payloads_in_symptoms_produce_no_facts(self):
        result = fact_builder.build_facts(
            "sess-1", entities={"symptoms": [
                "chest_pain), halt, f(x", "Evil", "x.\n:- halt.", "'quoted'",
            ]},
        )
        self.assertEqual([f for f in result.facts if f.predicate == "symptom"], [])
        self.assertEqual(len(result.rejected), 4)

    def test_obfuscated_but_legitimate_input_normalises_to_a_canonical_atom(self):
        """The allow-list is a mapping, not a filter, and that is the point.

        "chest\\xa0pain" (non-breaking space) is not a safe atom and can never
        be written into a goal — but it does name a real symptom, so it folds
        to the canonical `chest_pain`. What reaches Prolog is always a member
        of a fixed set, whatever the input looked like.
        """
        payload = "chest\xa0pain"
        self.assertFalse(vocabulary.is_safe_atom(payload))

        result = fact_builder.build_facts("sess-1", entities={"symptoms": [payload]})
        symptoms = [(f.subject, f.value) for f in result.facts if f.predicate == "symptom"]
        self.assertEqual(symptoms, [("chest_pain", "present")])
        self.assertTrue(vocabulary.is_safe_atom(symptoms[0][0]))
        self.assertIn(symptoms[0][0], vocabulary.SYMPTOMS)

    def test_injection_payload_in_a_slot_value_becomes_unknown_not_an_atom(self):
        """A slot value is free text by nature, so it is never an atom — it
        collapses to unknown_value. The slot still counts as answered."""
        result = fact_builder.build_facts(
            "sess-1", profile={"duration": "chest_pain), halt, f(x"},
        )
        slots = {f.subject: f.value for f in result.facts if f.predicate == "slot"}
        self.assertEqual(slots, {"duration": vocabulary.UNKNOWN_VALUE})
        self.assertIn(("answered", "duration"),
                      [(f.predicate, f.subject) for f in result.facts])

    def test_hostile_session_id_is_slugged_never_passed_through(self):
        for hostile in ("Evil", "s), halt, f(x", "'quoted'", "درج", ""):
            with self.subTest(hostile=hostile):
                key = vocabulary.slug_session_key(hostile)
                self.assertTrue(vocabulary.is_safe_atom(key))
                self.assertTrue(key.startswith("s_"))

    @_needs_engine
    def test_the_engine_survives_a_full_hostile_turn_and_asserts_nothing(self):
        """The real assertion: after feeding every hostile payload through the
        whole path, the engine is alive, the store is empty, and no symptom
        was ever asserted — i.e. no rule could have fired on junk."""
        result = fact_builder.build_facts(
            "sess-hostile",
            profile={"duration": "x.\n:- halt.", "Evil": "X", "age": "'; halt"},
            entities={"symptoms": HOSTILE_AND_UNMAPPABLE},
            chief_complaint="chest_pain), halt, f(x",
            safety_result={"severity": "Evil", "matched_patterns": []},
        )
        key = vocabulary.slug_session_key("sess-hostile")

        with prolog_engine.session_scope(key, result.facts) as session:
            self.assertEqual(session.query("symptom({s}, X)"), [])
            self.assertEqual(session.query("final_urgency({s}, U)"), [{"U": "routine"}])

        self.assertEqual(prolog_engine._fact_count_all(), 0)
        self.assertEqual(
            prolog_engine.query("urgency_rank({level}, R)", level="urgent"), [{"R": 2}]
        )

    @_needs_engine
    def test_an_unbound_variable_payload_cannot_make_a_rule_fire(self):
        """The specific audit failure, pinned: `Evil` unified with anything and
        fired a rule. Here it must produce no fact and no match at all."""
        result = fact_builder.build_facts("sess-var", entities={"symptoms": ["Evil"]})
        key = vocabulary.slug_session_key("sess-var")
        with prolog_engine.session_scope(key, result.facts) as session:
            self.assertEqual(session.query("symptom({s}, X)"), [])


if __name__ == "__main__":
    unittest.main()
