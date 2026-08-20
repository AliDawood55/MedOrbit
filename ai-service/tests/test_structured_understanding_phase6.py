"""
Structured clinical understanding, Phase 6.

The properties this file defends, in order of how much damage their loss would
do:

  1. NO MODEL OUTPUT BECOMES PROLOG SYNTAX. Every hostile payload from the
     Phase 0 audit — unbound-variable atoms, goal fragments, control operators,
     bidi controls, NULs, oversized values — is replayed through the real
     validator and, where the engine is present, all the way into a live
     Prolog session. The allow-list is not widened by a single term.

  2. THE MODEL NEVER DIAGNOSES. `condition`, `diagnosis` and `differential`
     keys are refused structurally, not by prompt alone. Phase 5 was deferred
     for lack of a grounded condition source; a model-authored condition would
     route around that.

  3. THE MODEL NEVER TOUCHES URGENCY. Structured facts can make a latent
     safety rule reachable — that is the point — but the merge is a maximum
     and the deterministic floor enters separately, so nothing here can lower
     a verdict. Asserted directly, including for a payload that tries.

  4. OFF AND SHADOW CHANGE NOTHING. The fact set built in either mode is
     identical to the one Phase 5 built.

Tests that need a live engine are skipped without one; everything about the
trust boundary itself runs everywhere, because the boundary is pure Python and
must be verifiable on any machine.
"""

import asyncio
import json
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, understanding
from virtual_doctor.reasoning_engine import fact_builder, prolog_engine, vocabulary
from virtual_doctor.understanding import (
    ClinicalUnderstanding,
    CorrectionCandidate,
    SlotFinding,
    SymptomObservation,
    parse_understanding,
)

from test_characterization_understanding import LATENT_SAFETY_ATOMS

_needs_engine = unittest.skipUnless(
    prolog_engine.available(), "SWI-Prolog/pyswip not installed on this machine"
)

SESSION = "sess-understanding"
RULES_DIR = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                         "reasoning_engine", "rules")


def run(coro):
    return asyncio.run(coro)


def facts_for(result, **kwargs):
    """Build a fact set the way interview_engine does in active mode."""
    return fact_builder.build_facts(
        SESSION,
        present_symptoms=result.present_symptoms,
        denied_symptoms=result.denied_symptoms,
        uncertain_symptoms=result.uncertain_symptoms,
        **kwargs,
    )


# ===========================================================================
# 1. Schema and parsing
# ===========================================================================

class TestSchema(unittest.TestCase):
    def test_observation_rejects_a_symptom_outside_the_vocabulary(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            SymptomObservation(symptom="brain_tumor", status="present")

    def test_observation_rejects_an_invented_status(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            SymptomObservation(symptom="fever", status="probably")

    def test_finding_rejects_a_slot_outside_the_vocabulary(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            SlotFinding(slot="mood", value="mild", canonical=True)

    def test_finding_rejects_a_value_that_is_not_an_atom(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            SlotFinding(slot="severity", value="very bad; halt.", canonical=False)

    def test_correction_rejects_an_uncorrectable_field(self):
        with self.assertRaises(vocabulary.OutOfVocabulary):
            CorrectionCandidate(field="diagnosis", new_value="x")

    def test_unavailable_is_not_the_same_as_empty(self):
        empty = parse_understanding({"symptoms": []})
        missing = ClinicalUnderstanding.unavailable("timeout")
        self.assertTrue(empty.available)
        self.assertFalse(missing.available)
        self.assertEqual((), empty.present_symptoms)
        self.assertEqual((), missing.present_symptoms)

    def test_correction_fields_agree_with_fact_builder_provenance(self):
        for slot in fact_builder.PROVENANCE_IDENTITY_SLOTS:
            self.assertIn(slot, understanding.ALLOWED_CORRECTION_FIELDS)


class TestJsonHandling(unittest.TestCase):
    def test_valid_json_object(self):
        parsed = understanding._extract_json('{"symptoms": ["fever"]}')
        self.assertEqual({"symptoms": ["fever"]}, parsed)

    def test_prose_wrapped_json_is_recovered(self):
        """Deliberate design choice, not an accident: a small model that says
        "Sure! {...} Hope that helps" has still done the work, and discarding
        it would waste the call. Prose INSTEAD of JSON is a different case and
        is rejected below."""
        parsed = understanding._extract_json('Sure! {"symptoms": ["fever"]} Hope that helps.')
        self.assertEqual({"symptoms": ["fever"]}, parsed)

    def test_prose_without_json_is_rejected(self):
        self.assertIsNone(understanding._extract_json("I think the patient has a fever."))

    def test_malformed_json_is_rejected(self):
        self.assertIsNone(understanding._extract_json('{"symptoms": ["fever"'))

    def test_a_json_array_is_not_an_understanding(self):
        self.assertIsNone(understanding._extract_json('["fever"]'))

    def test_non_object_payload_is_unavailable_not_empty(self):
        result = parse_understanding(["fever"])
        self.assertFalse(result.available)
        self.assertTrue(result.malformed)

    def test_oversized_text_is_truncated_before_parsing(self):
        self.assertIsNone(understanding._extract_json("x" * (understanding.MAX_PAYLOAD_CHARS + 10)))


# ===========================================================================
# 2. Negation, uncertainty and the difference between them
# ===========================================================================

class TestPolarity(unittest.TestCase):
    def test_present(self):
        r = parse_understanding({"symptoms": [{"symptom": "fever", "status": "present"}]})
        self.assertEqual(("fever",), r.present_symptoms)
        self.assertEqual((), r.denied_symptoms)

    def test_absent(self):
        r = parse_understanding({"symptoms": [{"symptom": "fever", "status": "absent"}]})
        self.assertEqual((), r.present_symptoms)
        self.assertEqual(("fever",), r.denied_symptoms)

    def test_uncertain(self):
        r = parse_understanding({"symptoms": [{"symptom": "fever", "status": "uncertain"}]})
        self.assertEqual((), r.present_symptoms)
        self.assertEqual((), r.denied_symptoms)
        self.assertEqual(("fever",), r.uncertain_symptoms)

    def test_the_three_states_are_mutually_exclusive(self):
        for status, expected in (("present", "present_symptoms"),
                                 ("absent", "denied_symptoms"),
                                 ("uncertain", "uncertain_symptoms")):
            r = parse_understanding({"symptoms": [{"symptom": "cough", "status": status}]})
            for attr in ("present_symptoms", "denied_symptoms", "uncertain_symptoms"):
                if attr == expected:
                    self.assertEqual(("cough",), getattr(r, attr))
                else:
                    self.assertEqual((), getattr(r, attr))

    def test_denied_is_not_unknown(self):
        """A denial is a positive statement and must survive into the facts.
        An unmentioned symptom produces nothing at all."""
        denied = parse_understanding({"symptoms": [{"symptom": "fever", "status": "absent"}]})
        silent = parse_understanding({"symptoms": []})
        self.assertEqual(("fever",), denied.denied_symptoms)
        self.assertEqual((), silent.denied_symptoms)

    def test_a_bare_string_means_present(self):
        r = parse_understanding({"symptoms": ["fever"]})
        self.assertEqual(("fever",), r.present_symptoms)

    def test_status_synonyms_map_to_the_three_canonical_states(self):
        for surface, expected in (("yes", "present"), ("no", "absent"),
                                  ("negative", "absent"), ("denied", "absent"),
                                  ("maybe", "uncertain"), ("unsure", "uncertain")):
            r = parse_understanding({"symptoms": [{"symptom": "cough", "status": surface}]})
            self.assertEqual((r.symptoms[0].status), expected, f"{surface!r}")

    def test_an_unrecognised_status_falls_back_to_present_not_to_silence(self):
        """Conservative by design: an unreadable status on a symptom the
        patient did mention must not become a denial."""
        r = parse_understanding({"symptoms": [{"symptom": "fever", "status": "wobbly"}]})
        self.assertEqual(("fever",), r.present_symptoms)

    def test_historical_mentions_are_dropped_not_downgraded(self):
        r = parse_understanding({"symptoms": [
            {"symptom": "fever", "status": "present", "historical": True}]})
        self.assertEqual((), r.present_symptoms)
        self.assertEqual((), r.uncertain_symptoms)
        self.assertEqual((), r.denied_symptoms)
        self.assertIn("historical", r.rejected[0].reason)

    def test_timing_past_is_also_treated_as_historical(self):
        r = parse_understanding({"symptoms": [
            {"symptom": "fever", "status": "present", "timing": "resolved"}]})
        self.assertEqual((), r.present_symptoms)


class TestContradictoryOutput(unittest.TestCase):
    def test_present_and_absent_for_one_symptom_resolves_upward_and_is_recorded(self):
        """A model that says both has contradicted itself. The resolution can
        only ever escalate — never suppress — and the conflict is reported."""
        r = parse_understanding({"symptoms": [
            {"symptom": "chest_pain", "status": "absent"},
            {"symptom": "chest_pain", "status": "present"},
        ]})
        self.assertEqual(("chest_pain",), r.present_symptoms)
        self.assertEqual((), r.denied_symptoms)
        self.assertEqual(("chest_pain",), r.conflicts)

    def test_resolution_does_not_depend_on_the_order_the_model_listed_them(self):
        forward = parse_understanding({"symptoms": [
            {"symptom": "fever", "status": "present"},
            {"symptom": "fever", "status": "absent"}]})
        reverse = parse_understanding({"symptoms": [
            {"symptom": "fever", "status": "absent"},
            {"symptom": "fever", "status": "present"}]})
        self.assertEqual(forward.present_symptoms, reverse.present_symptoms)
        self.assertEqual(forward.conflicts, reverse.conflicts)

    def test_uncertain_loses_to_present_and_beats_absent(self):
        r = parse_understanding({"symptoms": [
            {"symptom": "fever", "status": "absent"},
            {"symptom": "fever", "status": "uncertain"}]})
        self.assertEqual(("fever",), r.uncertain_symptoms)

    def test_duplicates_collapse_to_one_observation(self):
        r = parse_understanding({"symptoms": ["fever", "fever", "fever"]})
        self.assertEqual(1, len(r.symptoms))
        self.assertEqual(("fever",), r.present_symptoms)

    def test_no_symptom_appears_in_two_states_at_once(self):
        r = parse_understanding({"symptoms": [
            {"symptom": "fever", "status": "present"},
            {"symptom": "fever", "status": "absent"},
            {"symptom": "cough", "status": "uncertain"},
        ]})
        states = [set(r.present_symptoms), set(r.denied_symptoms), set(r.uncertain_symptoms)]
        for i, first in enumerate(states):
            for second in states[i + 1:]:
                self.assertEqual(set(), first & second)


# ===========================================================================
# 3. The vocabulary is never extended
# ===========================================================================

class TestVocabularyIsClosed(unittest.TestCase):
    def test_an_unknown_symptom_is_rejected(self):
        r = parse_understanding({"symptoms": ["pneumonia"]})
        self.assertEqual((), r.present_symptoms)
        self.assertEqual("not in vocabulary", r.rejected[0].reason)

    def test_rejecting_a_term_does_not_add_it_to_the_vocabulary(self):
        before = set(vocabulary.SYMPTOMS)
        parse_understanding({"symptoms": ["pneumonia", "appendicitis", "gastritis"]})
        self.assertEqual(before, set(vocabulary.SYMPTOMS))

    def test_the_allow_list_handed_to_the_model_is_exactly_the_vocabulary(self):
        self.assertEqual(set(vocabulary.SYMPTOMS), set(understanding.ALLOWED_SYMPTOMS))
        self.assertEqual(set(vocabulary.CLINICAL_SLOTS), set(understanding.ALLOWED_SLOTS))

    def test_a_migraine_is_normalised_to_headache_not_treated_as_a_condition(self):
        """medical_synonyms.json lists migraine as a SURFACE FORM of headache.
        Phase 5 established that reading that table as clinical knowledge would
        be a misreading; here it is used only for what it is — normalisation."""
        r = parse_understanding({"symptoms": ["migraine"]})
        self.assertEqual(("headache",), r.present_symptoms)

    def test_good_and_bad_symptoms_in_one_payload_keep_the_good_ones(self):
        r = parse_understanding({"symptoms": ["fever", "pneumonia", "cough"]})
        self.assertEqual(("cough", "fever"), r.present_symptoms)
        self.assertEqual(1, len(r.rejected))

    def test_an_unknown_finding_key_is_rejected(self):
        r = parse_understanding({"findings": {"mood": "sad"}})
        self.assertEqual((), r.findings)
        self.assertEqual("slot not in vocabulary", r.rejected[0].reason)

    def test_an_unknown_finding_value_becomes_unknown_value_not_a_rejection(self):
        """The slot really was answered; only the meaning is unavailable. Same
        treatment fact_builder gives a free-text profile value."""
        r = parse_understanding({"findings": {"duration": "since Tuesday afternoon"}})
        self.assertEqual(1, len(r.findings))
        self.assertEqual(vocabulary.UNKNOWN_VALUE, r.findings[0].value)
        self.assertFalse(r.findings[0].canonical)

    def test_a_recognised_finding_value_is_canonical(self):
        r = parse_understanding({"findings": {"severity": "severe"}})
        self.assertEqual("severe", r.findings[0].value)
        self.assertTrue(r.findings[0].canonical)

    def test_symptom_and_finding_counts_are_capped(self):
        r = parse_understanding({"symptoms": ["fever"] * 500})
        self.assertLessEqual(len(r.symptoms), understanding.MAX_SYMPTOMS)


# ===========================================================================
# 4. Diagnosis is refused structurally
# ===========================================================================

class TestNoDiagnosis(unittest.TestCase):
    def test_a_condition_key_is_never_read(self):
        r = parse_understanding({"condition": "brain_tumor", "symptoms": ["chest_pain"]})
        self.assertEqual(("condition",), r.forbidden_keys)
        self.assertEqual(("chest_pain",), r.present_symptoms)
        self.assertNotIn("brain_tumor", str(r.symptoms))

    def test_every_diagnosis_shaped_key_is_forbidden(self):
        for key in ("condition", "conditions", "diagnosis", "differential", "assessment"):
            r = parse_understanding({key: "anything"})
            self.assertIn(key, r.forbidden_keys, f"{key} was not refused")

    def test_a_rule_or_predicate_key_is_forbidden(self):
        r = parse_understanding({"symptoms": ["chest_pain"], "rule": "urgency(S,emergency)"})
        self.assertIn("rule", r.forbidden_keys)
        r = parse_understanding({"predicate": "red_flag"})
        self.assertIn("predicate", r.forbidden_keys)

    def test_an_urgency_key_is_forbidden(self):
        r = parse_understanding({"urgency": "emergency", "symptoms": ["headache"]})
        self.assertIn("urgency", r.forbidden_keys)
        # And it changes nothing about what was understood.
        self.assertEqual(("headache",), r.present_symptoms)

    def test_understanding_exposes_no_urgency_field_at_all(self):
        """The strongest form of "the LLM is not the safety authority": there
        is nowhere for an urgency to live on this object."""
        r = parse_understanding({"symptoms": ["headache"]})
        for forbidden in ("urgency", "severity", "condition", "diagnosis", "differential"):
            self.assertFalse(hasattr(r, forbidden), f"ClinicalUnderstanding.{forbidden} exists")

    def test_unknown_keys_are_ignored_and_counted_rather_than_fatal(self):
        r = parse_understanding({"symptoms": ["fever"], "confidence": 0.9, "notes": "hi"})
        self.assertTrue(r.available)
        self.assertEqual(("confidence", "notes"), r.unknown_keys)
        self.assertEqual(("fever",), r.present_symptoms)

    def test_the_prompt_states_the_allow_list_and_forbids_diagnosis(self):
        prompt = understanding.build_prompt("I have a headache", "en")
        for symptom in understanding.ALLOWED_SYMPTOMS:
            self.assertIn(symptom, prompt)
        self.assertIn("NEVER output a disease, condition, or diagnosis", prompt)
        self.assertIn("NEVER invent a symptom", prompt)


# ===========================================================================
# 5. Security red team
# ===========================================================================

HOSTILE_SYMPTOMS = [
    "X",                                   # an unbound Prolog variable
    "Evil",
    "_Anything",
    "x). halt. (",                         # a goal fragment
    "chest_pain), halt, f(p,symptom,x",    # the Phase 0 audit payload
    "fever'), assert(urgency(s,emergency)), f('",
    "urgency(S,emergency)",
    "red_flag(s, emergency, x, [])",
    ":- initialization(halt).",
    "fever, halt",
    "fever.\nhalt.",
    "fever\x00",
    "fever‮",                         # bidi override
    "fever‏",
    "a" * 5000,
    "",
    "   ",
    "../../etc/passwd",
    "fever; DROP TABLE sessions;",
]


class TestRedTeam(unittest.TestCase):
    """Every one of these must be REJECTED, and none may reach a goal."""

    def test_no_hostile_symptom_survives_validation(self):
        for payload in HOSTILE_SYMPTOMS:
            r = parse_understanding({"symptoms": [payload]})
            self.assertEqual((), r.present_symptoms, f"{payload!r} was accepted")

    def test_every_accepted_symptom_is_a_safe_atom(self):
        """The invariant that matters: whatever survives is renderable."""
        r = parse_understanding({"symptoms": HOSTILE_SYMPTOMS + ["fever", "cough"]})
        for obs in r.symptoms:
            self.assertTrue(vocabulary.is_safe_atom(obs.symptom), obs.symptom)

    def test_hostile_finding_values_never_become_atoms(self):
        for payload in HOSTILE_SYMPTOMS:
            r = parse_understanding({"findings": {"duration": payload}})
            for finding in r.findings:
                self.assertTrue(vocabulary.is_safe_atom(finding.value), finding.value)

    def test_hostile_finding_keys_are_rejected(self):
        for payload in HOSTILE_SYMPTOMS:
            r = parse_understanding({"findings": {payload: "mild"}})
            self.assertEqual((), r.findings, f"{payload!r} became a slot")

    def test_nested_objects_where_a_string_belongs(self):
        r = parse_understanding({"symptoms": [{"symptom": {"nested": ["deep"]}}]})
        self.assertEqual((), r.present_symptoms)

    def test_numbers_and_booleans_where_a_symptom_belongs(self):
        r = parse_understanding({"symptoms": [1, 2.5, True, False, None]})
        self.assertEqual((), r.present_symptoms)

    def test_a_huge_array_is_bounded(self):
        r = parse_understanding({"symptoms": ["fever"] * 100000})
        self.assertLessEqual(len(r.symptoms), understanding.MAX_SYMPTOMS)

    def test_wrong_types_for_every_top_level_key(self):
        for payload in ({"symptoms": "fever"}, {"symptoms": 5}, {"findings": ["a"]},
                        {"findings": "x"}, {"corrections": {"field": "age"}},
                        {"corrections": 3}, {"language": 7}):
            result = parse_understanding(payload)
            self.assertTrue(result.available, f"{payload!r} crashed the parser")

    def test_a_correction_value_is_never_required_to_be_an_atom(self):
        """Names are arbitrary free text and stay text here — they are
        tokenised by vocabulary.value_token before Prolog, never atomised."""
        r = parse_understanding({"corrections": [
            {"field": "name", "new_value": "Ahmad Al-Sayed", "explicit": True}]})
        self.assertEqual("Ahmad Al-Sayed", r.corrections[0].new_value)
        self.assertFalse(vocabulary.is_safe_atom(r.corrections[0].new_value))

    def test_a_hostile_correction_value_never_reaches_prolog_unhashed(self):
        for payload in HOSTILE_SYMPTOMS:
            token = vocabulary.value_token(payload)
            if token is None:
                continue
            self.assertTrue(vocabulary.is_safe_atom(str(token)) or isinstance(token, int),
                            f"{payload!r} -> {token!r}")

    def test_log_fields_contain_no_free_text(self):
        r = parse_understanding({
            "symptoms": ["fever", "pneumonia"],
            "corrections": [{"field": "name", "new_value": "Ahmad Al-Sayed"}],
        })
        blob = json.dumps(r.as_log_fields(), ensure_ascii=False)
        self.assertNotIn("Ahmad", blob)
        self.assertNotIn("Al-Sayed", blob)
        self.assertIn("name", blob)  # the FIELD is logged, the value is not


@_needs_engine
class TestRedTeamReachesRealProlog(unittest.TestCase):
    """The end-to-end proof: hostile model output, through the whole pipeline,
    into a live engine, and the engine still behaves."""

    def test_hostile_payload_builds_facts_without_executing_anything(self):
        result = parse_understanding({"symptoms": HOSTILE_SYMPTOMS})
        fact_set = facts_for(result)
        for fact in fact_set.facts:
            self.assertTrue(vocabulary.is_safe_atom(fact.predicate))
            self.assertTrue(vocabulary.is_safe_atom(fact.subject))

    def test_a_hostile_payload_yields_no_symptom_facts_at_all(self):
        result = parse_understanding({"symptoms": HOSTILE_SYMPTOMS})
        fact_set = facts_for(result)
        symptom_facts = [f for f in fact_set.facts if f.predicate == "symptom"]
        self.assertEqual([], symptom_facts)

    def test_an_injected_urgency_does_not_change_the_verdict(self):
        from virtual_doctor import reasoning_engine
        hostile = parse_understanding({
            "symptoms": ["urgency(S,emergency)", "red_flag(s,emergency,x,[])"],
            "urgency": "emergency",
            "rule": "urgency(S, emergency).",
        })
        verdict = reasoning_engine.decide_safety(
            facts_for(hostile), vocabulary.slug_session_key(SESSION))
        self.assertIn(verdict.urgency, (None, "routine"))
        self.assertEqual((), verdict.red_flags)


# ===========================================================================
# 6. Reachability — the four latent safety rules
# ===========================================================================

class TestLatentAtomProvenance(unittest.TestCase):
    """Every newly reachable atom must trace to approved MedOrbit sources.
    Nothing is added because a model happens to know the concept."""

    def test_the_four_atoms_match_the_characterization_file(self):
        self.assertEqual(set(LATENT_SAFETY_ATOMS), set(understanding.LATENT_SAFETY_ATOMS))

    def test_each_atom_is_already_in_the_vocabulary(self):
        for atom in understanding.LATENT_SAFETY_ATOMS:
            self.assertIn(atom, vocabulary.SYMPTOMS)

    def test_each_atom_records_at_least_two_sources(self):
        for atom, sources in understanding.LATENT_SAFETY_ATOMS.items():
            self.assertGreaterEqual(len(sources), 2, f"{atom} is under-sourced")

    def test_each_atom_has_a_rule_in_safety_pl(self):
        with open(os.path.join(RULES_DIR, "safety.pl"), encoding="utf-8") as handle:
            source = handle.read()
        for atom in understanding.LATENT_SAFETY_ATOMS:
            self.assertIn(f"red_flag(S, ", source)
            self.assertIn(f"symptom(S, {atom})", source,
                          f"safety.pl has no rule keyed on {atom}")

    def test_each_atom_is_named_in_the_safety_layer_patterns(self):
        """The Arabic patterns are not asserted textually here — they are
        Arabic — but the English half of each pattern list is, which is enough
        to prove the concept is MedOrbit's rather than the model's."""
        from chatbot.nlu.safety import MedicalSafetyLayer
        joined = " ".join(MedicalSafetyLayer.EMERGENCY_PATTERNS_AR
                          + MedicalSafetyLayer.URGENT_PATTERNS_AR)
        self.assertIn("seizure", joined)
        self.assertIn("unconscious", joined)
        self.assertIn("bleeding", joined)
        self.assertIn("urine", joined)

    def test_the_understanding_layer_can_produce_all_four(self):
        r = parse_understanding({"symptoms": list(understanding.LATENT_SAFETY_ATOMS)})
        self.assertEqual(tuple(sorted(understanding.LATENT_SAFETY_ATOMS)),
                         r.present_symptoms)


@_needs_engine
class TestNewlyReachableSafetyRules(unittest.TestCase):
    """The payoff: rules that could not fire from extraction now fire from
    structured understanding."""

    def _verdict(self, result, safety_result=None):
        from virtual_doctor import reasoning_engine
        return reasoning_engine.decide_safety(
            facts_for(result, safety_result=safety_result),
            vocabulary.slug_session_key(SESSION))

    def test_hematuria_now_escalates_to_urgent(self):
        verdict = self._verdict(parse_understanding({"symptoms": ["hematuria"]}))
        self.assertEqual("urgent", verdict.urgency)
        self.assertIn("hematuria", [f.rule_id for f in verdict.red_flags])

    def test_seizure_now_escalates_to_urgent(self):
        verdict = self._verdict(parse_understanding({"symptoms": ["seizure"]}))
        self.assertEqual("urgent", verdict.urgency)

    def test_unconscious_now_escalates_to_emergency(self):
        verdict = self._verdict(parse_understanding({"symptoms": ["unconscious"]}))
        self.assertEqual("emergency", verdict.urgency)

    def test_severe_bleeding_now_escalates_to_emergency(self):
        verdict = self._verdict(parse_understanding({"symptoms": ["severe_bleeding"]}))
        self.assertEqual("emergency", verdict.urgency)

    def test_the_english_hematuria_gap_is_closed_symbolically(self):
        """Characterization pinned "there is blood in my urine" as invisible to
        both the extractor and the safety layer. Structured understanding of
        the same sentence reaches the rule."""
        verdict = self._verdict(parse_understanding({"symptoms": ["hematuria"]}))
        self.assertEqual("urgent", verdict.urgency)

    def test_a_denial_of_a_red_flag_symptom_fires_nothing(self):
        verdict = self._verdict(parse_understanding({
            "symptoms": [{"symptom": "unconscious", "status": "absent"}]}))
        self.assertEqual((), verdict.red_flags)

    def test_an_uncertain_red_flag_symptom_fires_nothing(self):
        verdict = self._verdict(parse_understanding({
            "symptoms": [{"symptom": "severe_bleeding", "status": "uncertain"}]}))
        self.assertEqual((), verdict.red_flags)


# ===========================================================================
# 7. Safety can only be raised, never lowered
# ===========================================================================

@_needs_engine
class TestUnderstandingCannotLowerSafety(unittest.TestCase):
    def _floor(self, severity):
        return {"severity": severity,
                "matched_patterns": [{"type": severity, "matched": "x", "pattern": "p"}],
                "response": "BODY"}

    def _merged(self, result, floor_severity):
        from virtual_doctor import reasoning_engine
        verdict = reasoning_engine.decide_safety(
            facts_for(result, safety_result=self._floor(floor_severity)),
            vocabulary.slug_session_key(SESSION))
        return verdict

    def test_denying_everything_does_not_lower_an_emergency_floor(self):
        denials = parse_understanding({"symptoms": [
            {"symptom": s, "status": "absent"} for s in sorted(vocabulary.SYMPTOMS)]})
        self.assertEqual("emergency", self._merged(denials, "emergency").urgency)

    def test_an_empty_understanding_does_not_lower_an_urgent_floor(self):
        self.assertEqual("urgent", self._merged(parse_understanding({}), "urgent").urgency)

    def test_an_unavailable_understanding_does_not_lower_a_floor(self):
        missing = ClinicalUnderstanding.unavailable("timeout")
        self.assertEqual("emergency", self._merged(missing, "emergency").urgency)

    def test_structured_facts_can_only_raise(self):
        from virtual_doctor import reasoning_engine
        raised = self._merged(parse_understanding({"symptoms": ["unconscious"]}), "urgent")
        self.assertEqual("emergency", raised.urgency)
        self.assertEqual("emergency",
                         reasoning_engine.merge_urgency("urgent", raised.urgency))

    def test_a_structured_denial_cannot_cancel_an_extracted_symptom(self):
        """The one-directional rule in build_facts: understanding may add what
        the extractor cannot see, never retract what it did see."""
        from virtual_doctor import reasoning_engine
        denial = parse_understanding({
            "symptoms": [{"symptom": "shortness_of_breath", "status": "absent"}]})
        fact_set = fact_builder.build_facts(
            SESSION,
            entities={"symptoms": ["shortness of breath"]},
            denied_symptoms=denial.denied_symptoms,
        )
        verdict = reasoning_engine.decide_safety(
            fact_set, vocabulary.slug_session_key(SESSION))
        self.assertEqual("emergency", verdict.urgency)


# ===========================================================================
# 8. Rollout
# ===========================================================================

class TestRollout(unittest.TestCase):
    def test_default_is_off(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("VD_STRUCTURED_UNDERSTANDING", None)
            self.assertEqual("off", understanding.mode())
            self.assertFalse(understanding.enabled())
            self.assertFalse(understanding.active())

    def test_each_valid_mode_resolves(self):
        for value in ("off", "shadow", "active"):
            with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": value}):
                self.assertEqual(value, understanding.mode())

    def test_an_invalid_mode_is_never_active(self):
        for value in ("on", "1", "ACTIVE!", "yes", "", "  "):
            with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": value}):
                self.assertFalse(understanding.active(), f"{value!r} became active")

    def test_case_and_whitespace_are_tolerated(self):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "  ACTIVE  "}):
            self.assertEqual("active", understanding.mode())

    def test_off_makes_no_model_call(self):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "off"}), \
                patch("virtual_doctor.understanding.requests.post") as post:
            result = run(understanding.understand("I have a fever", "en"))
            post.assert_not_called()
            self.assertFalse(result.available)


class TestModeAffectsFactsCorrectly(unittest.TestCase):
    """Shadow must produce the Phase 5 fact set exactly; active adds to it."""

    def _facts(self, mode_value, structured):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": mode_value}):
            present = denied = uncertain = ()
            if structured.available and understanding.active():
                present = structured.present_symptoms
                denied = structured.denied_symptoms
                uncertain = structured.uncertain_symptoms
            return fact_builder.build_facts(
                SESSION, entities={"symptoms": ["headache"]},
                present_symptoms=present, denied_symptoms=denied,
                uncertain_symptoms=uncertain)

    def test_shadow_facts_are_identical_to_phase_five(self):
        structured = parse_understanding({"symptoms": ["hematuria", "seizure"]})
        baseline = fact_builder.build_facts(SESSION, entities={"symptoms": ["headache"]})
        shadow = self._facts("shadow", structured)
        self.assertEqual(set(baseline.facts), set(shadow.facts))

    def test_active_adds_the_structured_symptoms(self):
        structured = parse_understanding({"symptoms": ["hematuria"]})
        active = self._facts("active", structured)
        subjects = {f.subject for f in active.facts if f.predicate == "symptom"}
        self.assertIn("hematuria", subjects)
        self.assertIn("headache", subjects)

    def test_active_adds_only_validated_facts(self):
        structured = parse_understanding({"symptoms": ["hematuria"] + HOSTILE_SYMPTOMS})
        active = self._facts("active", structured)
        subjects = {f.subject for f in active.facts if f.predicate == "symptom"}
        self.assertEqual({"headache", "hematuria"}, subjects)

    def test_active_never_removes_a_deterministic_safety_fact(self):
        floor = {"severity": "emergency",
                 "matched_patterns": [{"type": "emergency", "matched": "x", "pattern": "p"}]}
        baseline = fact_builder.build_facts(SESSION, safety_result=floor)
        structured = parse_understanding({"symptoms": [
            {"symptom": s, "status": "absent"} for s in sorted(vocabulary.SYMPTOMS)]})
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "active"}):
            enriched = fact_builder.build_facts(
                SESSION, safety_result=floor,
                denied_symptoms=structured.denied_symptoms)
        deterministic = {f for f in baseline.facts if f.predicate == "deterministic_urgency"}
        self.assertTrue(deterministic)
        self.assertTrue(deterministic <= set(enriched.facts))


# ===========================================================================
# 9. Model failure always degrades to legacy extraction
# ===========================================================================

class _Response:
    def __init__(self, payload, status=200):
        self._payload = payload
        self.status = status

    def raise_for_status(self):
        if self.status >= 400:
            raise RuntimeError(f"HTTP {self.status}")

    def json(self):
        return self._payload


def _reply(content):
    return _Response({"message": {"content": content}})


class TestModelFailure(unittest.TestCase):
    def _understand(self, side_effect=None, return_value=None):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "active"}), \
                patch("virtual_doctor.understanding.requests.post",
                      side_effect=side_effect, return_value=return_value):
            return run(understanding.understand("I have a fever", "en"))

    def test_timeout(self):
        import requests
        result = self._understand(side_effect=requests.Timeout("timed out"))
        self.assertFalse(result.available)
        self.assertIn("Timeout", result.reason)

    def test_connection_refused(self):
        import requests
        result = self._understand(side_effect=requests.ConnectionError("refused"))
        self.assertFalse(result.available)

    def test_http_error(self):
        result = self._understand(return_value=_Response({}, status=500))
        self.assertFalse(result.available)

    def test_prose_instead_of_json(self):
        result = self._understand(return_value=_reply("The patient seems unwell."))
        self.assertFalse(result.available)
        self.assertTrue(result.malformed)

    def test_empty_output(self):
        result = self._understand(return_value=_reply(""))
        self.assertFalse(result.available)

    def test_json_of_the_wrong_shape(self):
        result = self._understand(return_value=_reply('["fever"]'))
        self.assertFalse(result.available)

    def test_a_completely_unexpected_exception_still_degrades(self):
        result = self._understand(side_effect=ValueError("boom"))
        self.assertFalse(result.available)
        self.assertIn("ValueError", result.reason)

    def test_a_good_response_is_parsed(self):
        result = self._understand(return_value=_reply(json.dumps({
            "symptoms": [{"symptom": "fever", "status": "absent"}]})))
        self.assertTrue(result.available)
        self.assertEqual(("fever",), result.denied_symptoms)

    def test_an_empty_message_makes_no_call(self):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "active"}), \
                patch("virtual_doctor.understanding.requests.post") as post:
            result = run(understanding.understand("   ", "en"))
            post.assert_not_called()
            self.assertFalse(result.available)


class TestEngineHonoursTheMode(unittest.TestCase):
    """The mode is read at the point facts are built, not at the point the
    model is called — so shadow really does run the model and really does
    discard it."""

    def _captured(self, mode_value):
        captured = {}

        async def fake_decide(session_id, **kwargs):
            captured.update(kwargs)
            from virtual_doctor.reasoning_engine.result_models import SafetyVerdict
            return SafetyVerdict.unavailable("stubbed")

        structured = parse_understanding({"symptoms": [
            "hematuria", {"symptom": "fever", "status": "absent"},
            {"symptom": "cough", "status": "uncertain"}]})
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": mode_value,
                                     "VD_SYMBOLIC": "1", "VD_SYMBOLIC_SAFETY": "shadow"}), \
                patch("virtual_doctor.reasoning_engine.decide_safety_async", fake_decide):
            run(interview_engine._observe_symbolic_safety(
                SESSION, {}, {"symptoms": ["headache"]}, None,
                {"severity": "normal", "matched_patterns": []},
                {"urgency_level": None}, structured=structured))
        return captured

    def test_shadow_contributes_no_structured_facts(self):
        captured = self._captured("shadow")
        self.assertEqual((), captured["present_symptoms"])
        self.assertEqual((), captured["denied_symptoms"])
        self.assertEqual((), captured["uncertain_symptoms"])

    def test_active_contributes_all_three_polarities(self):
        captured = self._captured("active")
        self.assertEqual(("hematuria",), captured["present_symptoms"])
        self.assertEqual(("fever",), captured["denied_symptoms"])
        self.assertEqual(("cough",), captured["uncertain_symptoms"])

    def test_an_unavailable_understanding_contributes_nothing_even_in_active(self):
        captured = {}

        async def fake_decide(session_id, **kwargs):
            captured.update(kwargs)
            from virtual_doctor.reasoning_engine.result_models import SafetyVerdict
            return SafetyVerdict.unavailable("stubbed")

        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "active",
                                     "VD_SYMBOLIC": "1", "VD_SYMBOLIC_SAFETY": "shadow"}), \
                patch("virtual_doctor.reasoning_engine.decide_safety_async", fake_decide):
            run(interview_engine._observe_symbolic_safety(
                SESSION, {}, {"symptoms": ["headache"]}, None,
                {"severity": "normal", "matched_patterns": []},
                {"urgency_level": None},
                structured=ClinicalUnderstanding.unavailable("timeout")))
        self.assertEqual((), captured["present_symptoms"])

    def test_no_structured_argument_at_all_behaves_like_phase_five(self):
        captured = {}

        async def fake_decide(session_id, **kwargs):
            captured.update(kwargs)
            from virtual_doctor.reasoning_engine.result_models import SafetyVerdict
            return SafetyVerdict.unavailable("stubbed")

        with patch.dict(os.environ, {"VD_SYMBOLIC": "1", "VD_SYMBOLIC_SAFETY": "shadow"}), \
                patch("virtual_doctor.reasoning_engine.decide_safety_async", fake_decide):
            run(interview_engine._observe_symbolic_safety(
                SESSION, {}, {"symptoms": ["headache"]}, None,
                {"severity": "normal", "matched_patterns": []},
                {"urgency_level": None}))
        self.assertEqual((), captured["present_symptoms"])
        self.assertEqual((), captured["denied_symptoms"])


class TestEngineObservationDegrades(unittest.TestCase):
    """interview_engine's wrapper must swallow everything understand() somehow
    lets through."""

    def test_an_exception_inside_understand_returns_none(self):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "shadow"}), \
                patch("virtual_doctor.understanding.understand",
                      side_effect=RuntimeError("boom")):
            result = run(interview_engine._observe_structured_understanding(
                "I have a fever", "en", {"symptoms": []}))
            self.assertIsNone(result)

    def test_off_mode_skips_the_observation_entirely(self):
        with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": "off"}), \
                patch("virtual_doctor.understanding.understand") as call:
            result = run(interview_engine._observe_structured_understanding(
                "I have a fever", "en", {"symptoms": []}))
            call.assert_not_called()
            self.assertIsNone(result)


# ===========================================================================
# 10. Divergence logging is PHI-free
# ===========================================================================

class TestDivergenceLogging(unittest.TestCase):
    def test_divergence_reports_set_arithmetic_over_canonical_atoms(self):
        structured = parse_understanding({"symptoms": ["fever", "hematuria"]})
        fields = understanding.divergence(structured, {"symptoms": ["fever", "cough"]})
        self.assertEqual(["fever"], fields["agree"])
        self.assertEqual(["hematuria"], fields["structured_only"])
        self.assertEqual(["cough"], fields["legacy_only"])

    def test_newly_reachable_safety_atoms_are_called_out(self):
        structured = parse_understanding({"symptoms": ["seizure", "fever"]})
        fields = understanding.divergence(structured, {"symptoms": []})
        self.assertEqual(["seizure"], fields["newly_reachable_safety"])

    def test_denials_are_reported_separately_from_set_arithmetic(self):
        """The legacy extractor cannot express a denial, so a denial is not a
        disagreement about a symptom — it is information it cannot hold."""
        structured = parse_understanding({
            "symptoms": [{"symptom": "fever", "status": "absent"}]})
        fields = understanding.divergence(structured, {"symptoms": []})
        self.assertEqual(["fever"], fields["denied"])
        self.assertEqual([], fields["structured_only"])

    def test_no_raw_text_appears_in_the_divergence_fields(self):
        structured = parse_understanding({
            "symptoms": ["pneumonia"],
            "corrections": [{"field": "name", "new_value": "Ahmad Al-Sayed"}],
        })
        blob = json.dumps(understanding.divergence(structured, {"symptoms": []}),
                          ensure_ascii=False)
        self.assertNotIn("Ahmad", blob)
        self.assertNotIn("pneumonia", blob)

    def test_counters_aggregate_without_identifying_anything(self):
        counters = interview_engine._UnderstandingDivergenceCounters()
        structured = parse_understanding({"symptoms": ["hematuria", "fever"]})
        fields = understanding.divergence(structured, {"symptoms": ["fever"]})
        counters.record(structured, fields)
        counters.record(structured, fields)
        snapshot = counters.snapshot()
        self.assertEqual(2, snapshot["turns"])
        self.assertEqual(2, snapshot["available"])
        self.assertEqual({"hematuria": 2}, snapshot["newly_reachable"])
        self.assertNotIn("session", json.dumps(snapshot))

    def test_counters_reset(self):
        counters = interview_engine._UnderstandingDivergenceCounters()
        counters.record(parse_understanding({"symptoms": ["fever"]}),
                        understanding.divergence(parse_understanding({"symptoms": ["fever"]}), {}))
        counters.reset()
        self.assertEqual(0, counters.snapshot()["turns"])

    def test_the_public_counter_accessor_works(self):
        self.assertIn("turns", interview_engine.understanding_divergence_counters())


# ===========================================================================
# 11. Corrections stay Python's job
# ===========================================================================

class TestCorrections(unittest.TestCase):
    def test_an_age_correction_candidate_is_typed(self):
        r = parse_understanding({"corrections": [
            {"field": "age", "old_value": "23", "new_value": "24", "explicit": True}]})
        self.assertEqual(1, len(r.corrections))
        self.assertEqual("age", r.corrections[0].field)
        self.assertEqual("24", r.corrections[0].new_value)
        self.assertTrue(r.corrections[0].explicit)

    def test_a_name_correction_keeps_the_name_out_of_prolog(self):
        r = parse_understanding({"corrections": [
            {"field": "name", "old_value": "محمد", "new_value": "أحمد"}]})
        token = vocabulary.value_token(r.corrections[0].new_value)
        self.assertTrue(vocabulary.is_value_token(token))
        self.assertNotIn("أحمد", str(token))

    def test_an_uncorrectable_field_is_refused(self):
        r = parse_understanding({"corrections": [
            {"field": "diagnosis", "new_value": "pneumonia"}]})
        self.assertEqual((), r.corrections)

    def test_a_correction_without_a_new_value_is_refused(self):
        r = parse_understanding({"corrections": [{"field": "age", "old_value": "23"}]})
        self.assertEqual((), r.corrections)

    def test_explicit_defaults_to_false(self):
        r = parse_understanding({"corrections": [{"field": "age", "new_value": "24"}]})
        self.assertFalse(r.corrections[0].explicit)

    def test_the_deterministic_correction_parser_is_untouched(self):
        """Phase 6 produces candidates; it does not replace the Phase 4 path."""
        for name in ("_apply_correction_layer", "_detect_profile_correction",
                     "_extract_corrected_name", "_extract_corrected_age",
                     "_extract_corrected_chief_complaint"):
            self.assertTrue(hasattr(interview_engine, name), f"{name} was removed")

    def test_understanding_does_not_mutate_a_profile(self):
        profile = {"name": "محمد", "age": 23}
        before = dict(profile)
        parse_understanding({"corrections": [
            {"field": "age", "old_value": "23", "new_value": "24"}]})
        self.assertEqual(before, profile)


# ===========================================================================
# 12. Phase boundary — Phase 5 stays deferred
# ===========================================================================

class TestPhaseBoundary(unittest.TestCase):
    def test_differential_pl_does_not_exist(self):
        self.assertFalse(os.path.exists(os.path.join(RULES_DIR, "differential.pl")),
                         "Phase 5 is deferred — differential.pl must not exist")

    def test_only_the_four_approved_rule_files_are_present(self):
        present = sorted(f for f in os.listdir(RULES_DIR) if f.endswith(".pl"))
        self.assertEqual(["base.pl", "contradictions.pl", "interview.pl", "safety.pl"],
                         present)

    def test_no_condition_vocabulary_was_introduced(self):
        for term in ("migraine", "pneumonia", "appendicitis", "gastritis"):
            self.assertNotIn(term, vocabulary.SYMPTOMS)

    def test_the_understanding_module_names_no_condition(self):
        path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                            "understanding.py")
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        # It may DISCUSS conditions in prose about refusing them; what it must
        # not do is carry a condition list.
        self.assertNotIn("CONDITIONS", source)
        self.assertNotIn("condition(", source)


if __name__ == "__main__":
    unittest.main()
