"""
Symbolic reasoning layer, Phase 1 — fact construction from session state.

fact_builder turns the authoritative Python/PostgreSQL state into validated
facts. Prolog is never the memory: everything it knows this turn was rebuilt
from the session row, so a restart, a second worker or a replayed consultation
all reconstruct the same picture.

The properties pinned here:

  * Arabic and English surface forms collapse to the SAME canonical English
    atom, because rules are written once, not once per language.
  * Free text becomes unknown_value rather than an atom — the slot counts as
    answered, but no rule can read meaning into patient prose.
  * Malformed, empty and duplicate input degrade to fewer facts, never to an
    exception. This runs on a live consultation path.
  * The deterministic MedicalSafetyLayer verdict is mirrored in as a FACT,
    with a rule id that maps back to the exact pattern that fired. Invariant
    S1: the Python floor keeps running on raw text and Prolog only reads it.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, retrieval
from virtual_doctor.reasoning_engine import fact_builder, vocabulary


def _pairs(result, predicate):
    return {(f.subject, f.value) for f in result.facts if f.predicate == predicate}


def _subjects(result, predicate):
    return {f.subject for f in result.facts if f.predicate == predicate}



class TestVocabularyDoesNotDriftFromTheService(unittest.TestCase):
    """vocabulary.py restates two sets that already exist elsewhere, to keep it
    import-cheap (importing planner would drag in retrieval -> db). These tests
    are what stop the copies diverging."""

    def test_clinical_slots_match_the_planners_finding_keys(self):
        self.assertEqual(vocabulary.CLINICAL_SLOTS, planner.KNOWN_FINDING_KEYS)

    def test_complaints_match_the_retrieval_anchors(self):
        self.assertEqual(vocabulary.COMPLAINTS, set(retrieval.COMPLAINT_ANCHORS))

    def test_urgency_lattice_has_exactly_three_levels_in_order(self):
        self.assertEqual(vocabulary.URGENCY_LEVELS, ("routine", "urgent", "emergency"))
        self.assertEqual(vocabulary.URGENCY_RANK,
                         {"routine": 1, "urgent": 2, "emergency": 3})



class TestArabicAndEnglishNormalization(unittest.TestCase):
    def test_arabic_surface_forms_map_to_canonical_english_atoms(self):
        cases = [
            ("صداع", "headache"),
            ("وجع راس", "headache"),
            ("ألم صدر", "chest_pain"),
            ("ضيق تنفس", "shortness_of_breath"),
            ("وجع بطن", "stomach_pain"),
            ("حرارة", "fever"),
            ("غثيان", "nausea"),
            ("طفح جلدي", "skin_rash"),
            ("دم في البول", "hematuria"),
            ("الخاصرة", "flank_pain"),
        ]
        for arabic, expected in cases:
            with self.subTest(arabic=arabic):
                self.assertEqual(vocabulary.canonical_symptom(arabic), expected)

    def test_english_surface_forms_map_to_the_same_atoms(self):
        for english, expected in [("headache", "headache"), ("migraine", "headache"),
                                  ("chest pain", "chest_pain"),
                                  ("shortness of breath", "shortness_of_breath"),
                                  ("abdominal pain", "stomach_pain")]:
            with self.subTest(english=english):
                self.assertEqual(vocabulary.canonical_symptom(english), expected)

    def test_hamza_and_ta_marbuta_variants_fold_together(self):
        """Reuses the project's own normalizer, so الم/ألم and حكة/حكه agree
        exactly the way the safety layer already treats them as equal."""
        self.assertEqual(vocabulary.canonical_symptom("ألم صدر"),
                         vocabulary.canonical_symptom("الم صدر"))
        self.assertEqual(vocabulary.canonical_symptom("حكة"),
                         vocabulary.canonical_symptom("حكه"))

    def test_extractor_symptom_keys_are_all_in_the_vocabulary(self):
        """Whatever EntityExtractor can emit, the symbolic layer must accept —
        otherwise every consultation logs rejections for ordinary symptoms."""
        for key in interview_engine._extractor.entities.get("symptoms", {}):
            with self.subTest(key=key):
                self.assertEqual(vocabulary.canonical_symptom(key), key)

    def test_arabic_severity_values_map_to_canonical_values(self):
        self.assertEqual(vocabulary.canonical_slot_value("شديد"), "severe")
        self.assertEqual(vocabulary.canonical_slot_value("خفيف"), "mild")
        self.assertEqual(vocabulary.canonical_slot_value("متوسط"), "moderate")
        self.assertEqual(vocabulary.canonical_slot_value("severe"), "severe")

    def test_unrecognised_symptom_returns_none(self):
        self.assertIsNone(vocabulary.canonical_symptom("درج"))
        self.assertIsNone(vocabulary.canonical_symptom("quantum entanglement"))



class TestSymptomFacts(unittest.TestCase):
    def test_entity_symptoms_become_present_facts(self):
        result = fact_builder.build_facts(
            "s1", entities={"symptoms": ["chest_pain", "nausea"]})
        self.assertEqual(_pairs(result, "symptom"),
                         {("chest_pain", "present"), ("nausea", "present")})

    def test_negated_symptoms_become_absent_facts(self):
        result = fact_builder.build_facts(
            "s1", entities={"symptoms": ["chest_pain"]}, denied_symptoms=["fever", "cough"])
        self.assertEqual(_pairs(result, "symptom"), {
            ("chest_pain", "present"), ("fever", "absent"), ("cough", "absent"),
        })

    def test_uncertain_symptoms_become_uncertain_facts(self):
        result = fact_builder.build_facts("s1", uncertain_symptoms=["flank_pain"])
        self.assertEqual(_pairs(result, "symptom"), {("flank_pain", "uncertain")})

    def test_uncertain_clinical_terms_in_the_profile_are_picked_up(self):
        """interview_engine records STT-ambiguous clinical terms under
        uncertain_fields.clinical_terms; those that name a real symptom become
        uncertain facts rather than being lost."""
        result = fact_builder.build_facts(
            "s1", profile={"uncertain_fields": {"clinical_terms": ["flank_pain"]}})
        self.assertEqual(_pairs(result, "symptom"), {("flank_pain", "uncertain")})

    def test_a_reported_symptom_outranks_a_denial_of_the_same_symptom(self):
        """Conservative direction for a safety-critical system: a contradiction
        within one turn resolves toward the symptom being present. Detecting
        the contradiction itself is Phase 4's job, not this layer's."""
        result = fact_builder.build_facts(
            "s1", entities={"symptoms": ["chest_pain"]}, denied_symptoms=["chest_pain"])
        self.assertEqual(_pairs(result, "symptom"), {("chest_pain", "present")})

    def test_duplicate_symptoms_collapse_to_one_fact(self):
        result = fact_builder.build_facts(
            "s1",
            entities={"symptoms": ["chest_pain", "chest_pain", "ألم صدر", "chest pain"]},
            profile={"associated_symptoms_detected": ["chest_pain"]},
        )
        self.assertEqual(len(result.facts) - len(vocabulary.CLINICAL_SLOTS), 1)
        self.assertEqual(_pairs(result, "symptom"), {("chest_pain", "present")})

    def test_out_of_vocabulary_symptoms_are_rejected_with_a_reason(self):
        result = fact_builder.build_facts("s1", entities={"symptoms": ["درج", "unicorn"]})
        self.assertEqual(_subjects(result, "symptom"), set())
        self.assertEqual(len(result.rejected), 2)
        self.assertTrue(all("vocabulary" in r.reason for r in result.rejected))



class TestSlotFacts(unittest.TestCase):
    def test_recognised_slot_values_keep_their_meaning(self):
        result = fact_builder.build_facts("s1", profile={"severity": "شديد"})
        self.assertEqual(_pairs(result, "slot"), {("severity", "severe")})

    def test_free_text_slot_answers_become_unknown_value_but_count_as_answered(self):
        result = fact_builder.build_facts("s1", profile={"duration": "من يومين تقريبا"})
        self.assertEqual(_pairs(result, "slot"), {("duration", vocabulary.UNKNOWN_VALUE)})
        self.assertEqual(_pairs(result, "answered"), {("duration", "true")})

    def test_every_clinical_slot_is_declared_expected_each_turn(self):
        result = fact_builder.build_facts("s1")
        self.assertEqual(_subjects(result, "expected_slot"), set(vocabulary.CLINICAL_SLOTS))

    def test_off_vocabulary_findings_under_other_are_walked_too(self):
        result = fact_builder.build_facts(
            "s1", profile={"other": {"radiation": "للذراع", "made_up": "x"}})
        self.assertEqual(_pairs(result, "slot"),
                         {("radiation", vocabulary.UNKNOWN_VALUE)})
        self.assertIn("made_up", {r.raw for r in result.rejected})

    def test_dialogue_bookkeeping_keys_are_skipped_without_noisy_rejections(self):
        """These appear in every profile; reporting them as rejections each
        turn would bury the rejections that actually mean something."""
        result = fact_builder.build_facts("s1", profile={
            "name": "سارة", "pending_confirmation": {"field": "name"},
            "confirmed_fields": {"name": True}, "correction_history": [],
            "safety_warning_shown_for": "urgent", "safety_flags_detected": ["x"],
            "chief_complaint_description": "بوجعني بطني", "name_repeat_attempts": 1,
            "symbolic_asked_topics": ["duration", "character"],
        })
        self.assertEqual(result.rejected, ())
        self.assertEqual(_subjects(result, "slot"), set())

    def test_symbolic_asked_topics_is_internal_bookkeeping_not_a_clinical_slot(self):
        """Phase 9.2 follow-up 2: SymbolicPlanner.ASKED_TOPICS_KEY is its own
        bookkeeping, not a patient finding. Silently skipped like the other
        dialogue-bookkeeping keys above — and unlike them, its value is a
        LIST of canonical topic names, which would otherwise be walked as an
        off-vocabulary `slot` value (or worse, rejected every single turn)."""
        from virtual_doctor.planner import ASKED_TOPICS_KEY
        self.assertEqual("symbolic_asked_topics", ASKED_TOPICS_KEY)
        result = fact_builder.build_facts(
            "s1", profile={ASKED_TOPICS_KEY: ["duration", "radiation"]})
        self.assertEqual(result.rejected, ())
        self.assertEqual(_subjects(result, "slot"), set())

    def test_the_vocabulary_allow_list_stays_strict_alongside_the_new_exclusion(self):
        """Excluding symbolic_asked_topics must not loosen the allow-list for
        anything else: a genuinely unrecognised key next to it is still
        rejected exactly as before."""
        result = fact_builder.build_facts("s1", profile={
            "symbolic_asked_topics": ["duration"], "made_up_field": "x",
        })
        self.assertIn("made_up_field", {r.raw for r in result.rejected})

    def test_empty_and_missing_state_produce_only_the_static_slot_vocabulary(self):
        for profile in ({}, None):
            with self.subTest(profile=profile):
                result = fact_builder.build_facts("s1", profile=profile)
                self.assertEqual(_subjects(result, "symptom"), set())
                self.assertEqual(_subjects(result, "slot"), set())
                self.assertEqual(_subjects(result, "expected_slot"),
                                 set(vocabulary.CLINICAL_SLOTS))


class TestPatientAttributes(unittest.TestCase):
    def test_plausible_age_becomes_an_integer_fact(self):
        result = fact_builder.build_facts("s1", profile={"age": 41})
        self.assertEqual(_pairs(result, "patient_attr"), {("age", 41)})

    def test_implausible_or_non_numeric_age_is_rejected(self):
        for bad in (0, 200, -5, "abc", True):
            with self.subTest(bad=bad):
                result = fact_builder.build_facts("s1", profile={"age": bad})
                self.assertEqual(_subjects(result, "patient_attr"), set())
                self.assertTrue(result.rejected)

    def test_absent_age_is_neither_a_fact_nor_a_rejection(self):
        result = fact_builder.build_facts("s1", profile={"age": None})
        self.assertEqual(_subjects(result, "patient_attr"), set())
        self.assertEqual(result.rejected, ())



class TestMalformedInputDegradesInsteadOfRaising(unittest.TestCase):
    def test_wrong_types_everywhere_still_return_a_factset(self):
        result = fact_builder.build_facts(
            "s1",
            profile=["not", "a", "mapping"],          # type: ignore[arg-type]
            entities="also not a mapping",            # type: ignore[arg-type]
            chief_complaint=12345,                    # type: ignore[arg-type]
            safety_result={"severity": None, "matched_patterns": "nope"},
        )
        self.assertIsInstance(result.facts, tuple)

    def test_symptoms_that_are_not_a_list_are_ignored(self):
        for bad in ("chest_pain", 42, None, {"a": 1}):
            with self.subTest(bad=bad):
                result = fact_builder.build_facts("s1", entities={"symptoms": bad})
                self.assertEqual(_subjects(result, "symptom"), set())

    def test_empty_call_is_valid_and_produces_no_clinical_facts(self):
        result = fact_builder.build_facts("s1")
        self.assertEqual(_subjects(result, "symptom"), set())
        self.assertEqual(_subjects(result, "deterministic_urgency"), set())
        self.assertEqual(result.rejected, ())



class TestDeterministicSafetyIsMirroredAsFact(unittest.TestCase):
    def _facts_for(self, text, lang="ar"):
        safety = interview_engine._check_safety(text, lang)
        return safety, fact_builder.build_facts("s1", safety_result=safety)

    def test_arabic_thunderclap_headache_carries_its_urgent_verdict(self):
        safety, result = self._facts_for("عندي صداع شديد فجأة")
        self.assertEqual(safety["severity"], "urgent")
        self.assertEqual({v for _, v in _pairs(result, "deterministic_urgency")}, {"urgent"})

    def test_arabic_hematuria_carries_its_urgent_verdict(self):
        safety, result = self._facts_for("في دم في البول")
        self.assertEqual(safety["severity"], "urgent")
        self.assertEqual({v for _, v in _pairs(result, "deterministic_urgency")}, {"urgent"})

    def test_emergency_text_carries_an_emergency_verdict(self):
        safety, result = self._facts_for("عندي ضيق تنفس")
        self.assertEqual(safety["severity"], "emergency")
        self.assertEqual({v for _, v in _pairs(result, "deterministic_urgency")}, {"emergency"})

    def test_rule_ids_identify_the_pattern_that_actually_fired(self):
        """Not a bare label: the id maps back to a specific line of the safety
        layer, which is what makes a verdict auditable."""
        _, result = self._facts_for("عندي صداع شديد فجأة")
        rules = _subjects(result, "deterministic_urgency")
        self.assertTrue(all(r.startswith("safety_urgent_") for r in rules), rules)
        self.assertTrue(all(vocabulary.is_safe_atom(r) for r in rules))

    def test_normal_severity_produces_no_urgency_fact(self):
        safety, result = self._facts_for("I have a mild headache", "en")
        self.assertEqual(safety["severity"], "normal")
        self.assertEqual(_subjects(result, "deterministic_urgency"), set())

    def test_legacy_normal_maps_to_routine_only_at_the_boundary(self):
        """MedicalSafetyLayer says "normal"; the symbolic lattice says
        "routine". That translation happens once, here, and nowhere else."""
        self.assertEqual(vocabulary.canonical_urgency("normal"), "routine")
        self.assertEqual(vocabulary.canonical_urgency("routine"), "routine")
        self.assertEqual(vocabulary.canonical_urgency("urgent"), "urgent")
        self.assertEqual(vocabulary.canonical_urgency("emergency"), "emergency")
        self.assertIsNone(vocabulary.canonical_urgency("catastrophic"))

    def test_unattributed_match_still_records_the_level(self):
        """A verdict must never be dropped just because its provenance is
        unusual — an entity-based match has no regex to name."""
        result = fact_builder.build_facts("s1", safety_result={
            "severity": "emergency",
            "matched_patterns": [{"type": "entity_based", "symptoms": ["chest_pain"]}],
        })
        self.assertEqual({v for _, v in _pairs(result, "deterministic_urgency")},
                         {"emergency"})



class TestSessionKeys(unittest.TestCase):
    def test_a_uuid_becomes_a_safe_atom(self):
        key = vocabulary.slug_session_key("3f2b1c4d-9e8a-4b7c-8d6e-1a2b3c4d5e6f")
        self.assertTrue(vocabulary.is_safe_atom(key))
        self.assertTrue(key.startswith("s_"))

    def test_different_sessions_get_different_keys(self):
        self.assertNotEqual(vocabulary.slug_session_key("abc"),
                            vocabulary.slug_session_key("def"))

    def test_the_same_session_always_gets_the_same_key(self):
        self.assertEqual(vocabulary.slug_session_key("abc-123"),
                         vocabulary.slug_session_key("abc-123"))

    def test_facts_carry_the_slugged_session_key(self):
        result = fact_builder.build_facts(
            "abc-123", entities={"symptoms": ["headache"]})
        expected = vocabulary.slug_session_key("abc-123")
        self.assertTrue(all(f.session == expected for f in result.facts))


if __name__ == "__main__":
    unittest.main()
