"""
Phase 8.1 — deterministic tests for the subject-attribution prototype.

NO MODEL CALLS. The capability measurement needs a live model and stays out of
CI; the FAIL-CLOSED RULE does not, and it is the part that would matter if this
prototype were ever promoted to production:

    subject == "patient"  -> may become a patient fact
    anything else         -> never becomes a patient fact

"Anything else" deliberately includes a MISSING subject, an unrecognised one,
and a bare string with no subject at all. Absence of an explicit claim is not
treated as a claim. That direction is the whole safety argument: dropping a real
symptom costs one escalation that MedicalSafetyLayer still catches from raw
text, whereas keeping someone else's escalates a consultation on a person who
is not in the room.

These tests also pin that the prototype stays OUT of production — it lives in
benchmarks/, `understanding.py` has no subject field, and the shipped prompt
does not mention one.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "benchmarks"))

from virtual_doctor import understanding

try:
    from subject_prototype import (
        PATIENT,
        RECOGNISED_SUBJECTS,
        build_v5,
        filter_by_subject,
    )
    from understanding_corpus import CORPUS, HELD_OUT
    _HAVE = True
except ImportError:  # pragma: no cover - stripped runtime image
    _HAVE = False

_needs_benchmarks = unittest.skipUnless(_HAVE, "benchmarks/ not present")


def _payload(*entries):
    return {"symptoms": list(entries)}


def _obs(subject=None, symptom="seizure", status="present"):
    entry = {"symptom": symptom, "status": status}
    if subject is not None:
        entry["subject"] = subject
    return entry


@_needs_benchmarks
class TestFailsClosed(unittest.TestCase):
    """Only an explicit "patient" survives."""

    def test_patient_is_kept(self):
        narrowed, stats = filter_by_subject(_payload(_obs("patient")))
        self.assertEqual(1, len(narrowed["symptoms"]))
        self.assertEqual(1, stats["patient"])

    def test_other_is_dropped(self):
        narrowed, stats = filter_by_subject(_payload(_obs("other")))
        self.assertEqual([], narrowed["symptoms"])
        self.assertEqual(1, stats["other"])

    def test_unknown_is_dropped(self):
        narrowed, stats = filter_by_subject(_payload(_obs("unknown")))
        self.assertEqual([], narrowed["symptoms"])
        self.assertEqual(1, stats["unknown"])

    def test_a_missing_subject_is_dropped(self):
        """Absence of a claim is not a claim."""
        narrowed, stats = filter_by_subject(_payload(_obs(None)))
        self.assertEqual([], narrowed["symptoms"])
        self.assertEqual(1, stats["missing"])

    def test_a_bare_string_observation_is_dropped(self):
        narrowed, stats = filter_by_subject(_payload("seizure"))
        self.assertEqual([], narrowed["symptoms"])
        self.assertEqual(1, stats["missing"])

    def test_an_unrecognised_subject_is_dropped(self):
        for bad in ("me", "self", "PATIENT_1", "patient's brother", "", "1", "true"):
            narrowed, stats = filter_by_subject(_payload(_obs(bad)))
            self.assertEqual([], narrowed["symptoms"], bad)

    def test_a_non_string_subject_is_dropped(self):
        for bad in (True, 1, None, ["patient"], {"a": 1}):
            narrowed, _ = filter_by_subject(_payload(_obs(bad)))
            self.assertEqual([], narrowed["symptoms"], repr(bad))

    def test_case_and_whitespace_are_tolerated_for_patient(self):
        for good in ("patient", "Patient", "PATIENT", "  patient  ", "\tPatient\n"):
            narrowed, _ = filter_by_subject(_payload(_obs(good)))
            self.assertEqual(1, len(narrowed["symptoms"]), repr(good))

    def test_mixed_subjects_keep_only_the_patient_entries(self):
        narrowed, stats = filter_by_subject(_payload(
            _obs("other", "seizure"),
            _obs("patient", "headache"),
            _obs("unknown", "hematuria"),
            _obs(None, "severe_bleeding"),
        ))
        self.assertEqual(["headache"], [e["symptom"] for e in narrowed["symptoms"]])
        self.assertEqual(4, stats["total"])
        self.assertEqual(1, stats["patient"])

    def test_the_only_surviving_value_is_the_patient_constant(self):
        self.assertEqual("patient", PATIENT)
        self.assertIn(PATIENT, RECOGNISED_SUBJECTS)
        for subject in RECOGNISED_SUBJECTS:
            narrowed, _ = filter_by_subject(_payload(_obs(subject)))
            self.assertEqual(1 if subject == PATIENT else 0, len(narrowed["symptoms"]),
                             subject)


@_needs_benchmarks
class TestFilterIsOnlyNarrowing(unittest.TestCase):
    """A prefilter may remove entries. It may never admit one, and it must never
    be mistaken for the trust boundary."""

    def test_it_never_adds_a_symptom(self):
        narrowed, _ = filter_by_subject(_payload())
        self.assertEqual([], narrowed["symptoms"])

    def test_the_output_is_never_longer_than_the_input(self):
        entries = [_obs("patient"), _obs("other"), _obs("unknown")]
        narrowed, _ = filter_by_subject(_payload(*entries))
        self.assertLessEqual(len(narrowed["symptoms"]), len(entries))

    def test_other_top_level_keys_pass_through_untouched(self):
        payload = {"symptoms": [_obs("patient")], "findings": {"severity": "severe"},
                   "language": "ar", "condition": "should still be refused later"}
        narrowed, _ = filter_by_subject(payload)
        self.assertEqual({"severity": "severe"}, narrowed["findings"])
        self.assertEqual("ar", narrowed["language"])

    def test_a_forbidden_key_is_still_refused_by_the_production_validator(self):
        """The prefilter narrows; understanding.parse_understanding still does
        the actual validation. This proves the ordering holds."""
        payload = {"symptoms": [_obs("patient", "seizure")],
                   "condition": "brain_tumor", "urgency": "emergency"}
        narrowed, _ = filter_by_subject(payload)
        result = understanding.parse_understanding(narrowed)
        self.assertEqual(("seizure",), result.present_symptoms)
        self.assertIn("condition", result.forbidden_keys)
        self.assertIn("urgency", result.forbidden_keys)

    def test_an_out_of_vocabulary_symptom_is_still_rejected_after_filtering(self):
        narrowed, _ = filter_by_subject(_payload(_obs("patient", "brain_tumor")))
        result = understanding.parse_understanding(narrowed)
        self.assertEqual((), result.present_symptoms)

    def test_a_hostile_symptom_claimed_for_the_patient_is_still_rejected(self):
        for hostile in ("X", "x). halt. (", "urgency(S,emergency)", "a" * 5000):
            narrowed, _ = filter_by_subject(_payload(_obs("patient", hostile)))
            result = understanding.parse_understanding(narrowed)
            self.assertEqual((), result.present_symptoms, hostile[:20])

    def test_malformed_payloads_do_not_raise(self):
        for payload in (None, [], "text", 5, {"symptoms": "not a list"},
                        {"symptoms": None}, {}):
            narrowed, stats = filter_by_subject(payload)
            self.assertIsInstance(stats, dict)


@_needs_benchmarks
class TestPromptV5(unittest.TestCase):
    def test_it_asks_for_the_subject_field(self):
        prompt = build_v5("PLACEHOLDER", "en")
        self.assertIn('"subject"', prompt)
        for value in RECOGNISED_SUBJECTS:
            self.assertIn(value, prompt)

    def test_it_is_a_minimal_delta_from_the_shipped_prompt(self):
        """Any measured change must be attributable to the schema, not to the
        accumulated wording of v2/v3/v4."""
        shipped = understanding.build_prompt("PLACEHOLDER", "en")
        self.assertTrue(build_v5("PLACEHOLDER", "en").startswith(shipped))

    def test_no_held_out_sentence_leaks_into_it(self):
        for lang in ("ar", "en"):
            prompt = build_v5("PLACEHOLDER", lang)
            for case in HELD_OUT:
                self.assertNotIn(case["text"].strip(), prompt, case["id"])

    def test_it_contains_no_lexical_attribution_heuristic(self):
        """The prototype tests SEMANTIC attribution. If it started matching
        trigger phrases it would be measuring a phrase list, not the model.

        Only executable string literals are scanned — docstrings are excluded
        deliberately, because the module's own prose quotes "my brother" while
        explaining the failure it measures, and a test that cannot tell an
        example from an implementation is a test that forces bad comments.
        """
        import ast

        path = os.path.join(os.path.dirname(__file__), "..", "benchmarks",
                            "subject_prototype.py")
        with open(path, encoding="utf-8") as handle:
            source = handle.read()

        tree = ast.parse(source)
        docstrings = set()
        for node in ast.walk(tree):
            if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                                 ast.ClassDef)):
                doc = ast.get_docstring(node, clean=False)
                if doc is not None:
                    docstrings.add(doc)

        literals = [
            node.value for node in ast.walk(tree)
            if isinstance(node, ast.Constant) and isinstance(node.value, str)
            and node.value not in docstrings
        ]
        haystack = "\n".join(literals).lower()
        for phrase in ("my brother", "my friend", "my father", "my aunt",
                       "صاحبي", "أخي", "خالتي", "أمي", "ابني"):
            self.assertNotIn(phrase, haystack, phrase)


@_needs_benchmarks
class TestPositiveControlsExist(unittest.TestCase):
    """A model that suppresses false positives by extracting nothing must fail
    somewhere. These are where."""

    def test_positive_controls_are_present_and_first_person(self):
        cases = [c for c in CORPUS if "positive_control" in c["categories"]]
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            self.assertTrue(case["expected"]["present"], case["id"])

    def test_they_cover_every_latent_safety_atom(self):
        covered = {a for c in CORPUS if "positive_control" in c["categories"]
                   for a in c["safety_atoms"]}
        self.assertEqual({"hematuria", "seizure", "unconscious", "severe_bleeding"},
                         covered)

    def test_both_languages_are_represented(self):
        cases = [c for c in CORPUS if "positive_control" in c["categories"]]
        self.assertTrue(any(c["lang"] == "ar" for c in cases))
        self.assertTrue(any(c["lang"] == "en" for c in cases))

    def test_attribution_controls_are_large_enough_to_certify_absence(self):
        """Phase 8 measured third_party at n=4 — enough to detect a failure,
        not enough to claim another model does not have it."""
        third = [c for c in CORPUS if "third_party" in c["categories"]]
        question = [c for c in CORPUS if "question_not_report" in c["categories"]]
        self.assertGreaterEqual(len(third), 10)
        self.assertGreaterEqual(len(question), 6)


class TestPrototypeStaysOutOfProduction(unittest.TestCase):
    """Phase 8.1 is evaluation only."""

    def test_production_understanding_has_no_subject_field(self):
        result = understanding.parse_understanding(
            {"symptoms": [{"symptom": "seizure", "status": "present",
                           "subject": "other"}]})
        # Production ignores `subject` entirely — which is exactly why the
        # third-party failure exists and why this prototype was measured.
        self.assertEqual(("seizure",), result.present_symptoms)

    def test_the_shipped_prompt_does_not_mention_a_subject_field(self):
        self.assertNotIn('"subject"', understanding.build_prompt("X", "en"))

    def test_the_prototype_lives_in_benchmarks_not_in_the_package(self):
        package = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor")
        self.assertFalse(os.path.exists(os.path.join(package, "subject_prototype.py")))

    def test_structured_understanding_is_still_off_by_default(self):
        saved = os.environ.pop("VD_STRUCTURED_UNDERSTANDING", None)
        try:
            self.assertEqual("off", understanding.mode())
        finally:
            if saved is not None:
                os.environ["VD_STRUCTURED_UNDERSTANDING"] = saved


if __name__ == "__main__":
    unittest.main()
