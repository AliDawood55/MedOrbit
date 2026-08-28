"""
Phase 6.5 — deterministic guards on the benchmark and the production prompt.

NO MODEL CALLS. The benchmark itself is not a unit test — it takes minutes and
its results depend on which weights are installed. What IS testable, and worth
testing, is the property that made the benchmark trustworthy:

    NO HELD-OUT SENTENCE MAY APPEAR IN THE PRODUCTION PROMPT.

Phase 6.5 measured a prompt variant (v3) that scored better than the shipped
prompt on the dev split — uncertainty recall 0.33 -> 1.00 — and WORSE on
held-out — F1 0.682 -> 0.637, uncertainty still 0.00. It was rejected on that
evidence. The held-out split is only capable of catching that as long as its
sentences stay out of the prompt, so the separation is asserted here rather
than left to whoever edits the prompt next.

The rest of this file keeps the corpus honest: ground truth may only use
canonical vocabulary, so the benchmark cannot quietly start scoring against
terms the validator would reject.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "benchmarks"))

from virtual_doctor import understanding
from virtual_doctor.reasoning_engine import vocabulary

try:
    from understanding_corpus import CATEGORIES, CORPUS, DEV, HELD_OUT, SAFETY_ATOMS
    _HAVE_CORPUS = True
except ImportError:  # pragma: no cover - only in a stripped runtime image
    CATEGORIES = CORPUS = DEV = HELD_OUT = SAFETY_ATOMS = ()
    _HAVE_CORPUS = False

_needs_corpus = unittest.skipUnless(_HAVE_CORPUS, "benchmarks/ not present")


@_needs_corpus
class TestNoHeldOutLeakage(unittest.TestCase):
    """The anti-overfit guarantee, asserted rather than trusted."""

    def _production_prompts(self):
        return [understanding.build_prompt("PLACEHOLDER", lang) for lang in ("ar", "en")]

    def test_no_held_out_sentence_appears_in_the_production_prompt(self):
        for prompt in self._production_prompts():
            for case in HELD_OUT:
                text = case["text"].strip()
                self.assertNotIn(text, prompt,
                                 f"held-out sentence {case['id']} leaked into the prompt")

    def test_the_splits_are_disjoint_and_complete(self):
        dev_ids = {c["id"] for c in DEV}
        held_ids = {c["id"] for c in HELD_OUT}
        self.assertEqual(set(), dev_ids & held_ids)
        self.assertEqual(len(CORPUS), len(dev_ids) + len(held_ids))

    def test_case_ids_are_unique(self):
        ids = [c["id"] for c in CORPUS]
        self.assertEqual(len(ids), len(set(ids)))


@_needs_corpus
class TestCorpusGroundTruthIsCanonical(unittest.TestCase):
    """Ground truth may only name things the validator would accept, or the
    benchmark would score a model down for being right."""

    def test_every_expected_symptom_is_canonical_vocabulary(self):
        for case in CORPUS:
            for polarity in ("present", "absent", "uncertain"):
                for symptom in case["expected"][polarity]:
                    self.assertIn(symptom, vocabulary.SYMPTOMS,
                                  f"{case['id']}: {symptom} is not vocabulary")

    def test_every_expected_finding_is_a_clinical_slot(self):
        for case in CORPUS:
            for slot in case["expected_findings"]:
                self.assertIn(slot, vocabulary.CLINICAL_SLOTS, f"{case['id']}: {slot}")

    def test_every_expected_correction_field_is_correctable(self):
        for case in CORPUS:
            for field in case["expected_corrections"]:
                self.assertIn(field, understanding.ALLOWED_CORRECTION_FIELDS,
                              f"{case['id']}: {field}")

    def test_no_expectation_names_a_condition_or_urgency(self):
        """The benchmark scores extraction, never diagnosis. If a condition
        ever appears in ground truth, Phase 5 has leaked back in."""
        for case in CORPUS:
            self.assertNotIn("condition", case)
            self.assertNotIn("diagnosis", case)
            self.assertNotIn("urgency", case)

    def test_safety_atoms_are_a_subset_of_the_present_expectation(self):
        for case in CORPUS:
            self.assertTrue(set(case["safety_atoms"]) <= set(case["expected"]["present"]),
                            case["id"])

    def test_the_corpus_safety_atoms_match_the_production_list(self):
        self.assertEqual(set(SAFETY_ATOMS), set(understanding.LATENT_SAFETY_ATOMS))


@_needs_corpus
class TestCorpusCoverage(unittest.TestCase):
    """A benchmark with a silently empty category measures nothing about it."""

    def test_every_declared_category_has_at_least_one_case(self):
        covered = {cat for case in CORPUS for cat in case["categories"]}
        self.assertEqual(set(), set(CATEGORIES) - covered)

    def test_every_category_has_at_least_one_held_out_case(self):
        """Otherwise a prompt could be tuned on a whole category with no way to
        detect that it memorised rather than generalised."""
        covered = {cat for case in HELD_OUT for cat in case["categories"]}
        self.assertEqual(set(), set(CATEGORIES) - covered,
                         "category has no held-out case")

    def test_both_languages_are_well_represented(self):
        arabic = [c for c in CORPUS if c["lang"] == "ar"]
        english = [c for c in CORPUS if c["lang"] == "en"]
        self.assertGreaterEqual(len(arabic), 20)
        self.assertGreaterEqual(len(english), 20)

    def test_every_case_declares_at_least_one_category(self):
        for case in CORPUS:
            self.assertTrue(case["categories"], case["id"])

    def test_all_four_latent_safety_atoms_are_exercised(self):
        exercised = {a for case in CORPUS for a in case["safety_atoms"]}
        self.assertEqual(set(SAFETY_ATOMS), exercised)


@_needs_corpus
class TestPhase8CorpusExpansion(unittest.TestCase):
    """Phase 8 grew the corpus with realistic phrasing and, more importantly,
    with negative controls. These guard the properties that make those cases
    meaningful — a negative control that accidentally expects a symptom would
    silently stop being a control."""

    def test_the_corpus_meets_the_phase_8_size_target(self):
        self.assertGreaterEqual(len(CORPUS), 100)

    def test_arabic_coverage_is_strong(self):
        arabic = [c for c in CORPUS if c["lang"] == "ar"]
        self.assertGreaterEqual(len(arabic), 60)
        self.assertGreater(len(arabic), len([c for c in CORPUS if c["lang"] == "en"]))

    def test_every_realistic_language_slice_is_populated(self):
        for category, minimum in (("colloquial", 15), ("code_switch", 4),
                                  ("asr_like", 5), ("negative_control", 12)):
            found = [c for c in CORPUS if category in c["categories"]]
            self.assertGreaterEqual(len(found), minimum, category)

    def test_a_negative_control_never_expects_a_present_symptom(self):
        """This is what makes it a control. Any atom the model emits on these
        cases is invented outright."""
        for case in CORPUS:
            if "negative_control" not in case["categories"]:
                continue
            self.assertEqual([], case["expected"]["present"], case["id"])
            self.assertEqual([], case["safety_atoms"], case["id"])

    def test_third_party_cases_expect_nothing_at_all(self):
        """Someone else's seizure is not the patient's seizure. If a model
        extracts it, the consultation escalates on the wrong person."""
        for case in CORPUS:
            if "third_party" not in case["categories"]:
                continue
            for polarity in ("present", "absent", "uncertain"):
                self.assertEqual([], case["expected"][polarity], case["id"])

    def test_a_question_about_a_symptom_is_not_a_report_of_it(self):
        for case in CORPUS:
            if "question_not_report" not in case["categories"]:
                continue
            self.assertEqual([], case["expected"]["present"], case["id"])

    def test_uncertainty_has_many_independent_phrasings(self):
        """The Phase 6.5 weak spot. One phrasing cannot distinguish a model
        that understands hedging from one that memorised an example."""
        cases = [c for c in CORPUS if "uncertainty" in c["categories"]]
        self.assertGreaterEqual(len(cases), 12)
        held = [c for c in cases if c["split"] == "held_out"]
        self.assertGreaterEqual(len(held), 8)
        self.assertEqual(len({c["text"] for c in cases}), len(cases))

    def test_all_case_texts_are_unique(self):
        texts = [c["text"] for c in CORPUS]
        self.assertEqual(len(texts), len(set(texts)))

    def test_no_case_text_looks_like_an_identifier(self):
        """Cheap PHI smoke test: the corpus is synthetic by construction, so
        nothing in it should resemble a phone number, email or long digit run."""
        import re
        for case in CORPUS:
            self.assertIsNone(re.search(r"\d{6,}", case["text"]), case["id"])
            self.assertNotIn("@", case["text"], case["id"])
            self.assertIsNone(re.search(r"\+\d{3,}", case["text"]), case["id"])

    def test_correction_cases_declare_a_correction(self):
        """A "not X, Y" case that expects no correction field is a case whose
        point has been lost."""
        for case in CORPUS:
            if not {"name_correction", "age_correction"} & set(case["categories"]):
                continue
            self.assertTrue(case["expected_corrections"], case["id"])


class TestProductionUnchangedByPhase65(unittest.TestCase):
    """Phase 6.5 made no production change. These pin the things a change
    would have touched, so the report and the code cannot disagree."""

    def test_the_default_model_is_still_the_phase_6_model(self):
        self.assertEqual("qwen2.5:3b",
                         os.environ.get("VD_UNDERSTANDING_MODEL", "qwen2.5:3b"))

    def test_structured_understanding_still_defaults_off(self):
        saved = os.environ.pop("VD_STRUCTURED_UNDERSTANDING", None)
        try:
            self.assertEqual("off", understanding.mode())
        finally:
            if saved is not None:
                os.environ["VD_STRUCTURED_UNDERSTANDING"] = saved

    def test_the_production_prompt_is_still_v1(self):
        """v2/v3 added worked examples. The shipped prompt has none — if this
        fails, a variant was promoted and the held-out evidence should be
        re-read first."""
        prompt = understanding.build_prompt("PLACEHOLDER", "en")
        self.assertNotIn("EXAMPLES", prompt)
        self.assertIn("NEVER output a disease, condition, or diagnosis", prompt)


if __name__ == "__main__":
    unittest.main()
