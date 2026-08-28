"""
Characterization — what the legacy extraction path actually does today.

Written BEFORE the Phase 6 understanding layer and pinned here so that layer
can be measured against something real rather than something assumed. Two
things it records, both load-bearing:

  1. THE EXTRACTOR CANNOT REPRESENT POLARITY. "I have a fever", "I do not have
     a fever", "I am not sure if I have a fever" and "I had a fever last week"
     all produce ['fever']. Four clinically different statements, one fact.

  2. FOUR SAFETY RULES ARE UNREACHABLE. rules/safety.pl has clauses for
     hematuria, seizure, unconscious and severe_bleeding. The extractor has no
     key for any of them — medical_entities.json declares 15 symptoms and none
     of the four is among them — so those clauses have never fired from
     extraction in production.

MedicalSafetyLayer is checked alongside on every case, because the point of (2)
is NOT that these cases are unprotected. They are: the raw-text safety layer
catches them. The gap is that the SYMBOLIC layer never sees them as facts, so
it cannot combine them with anything else.

These are assertions about current behaviour, not statements about what is
correct. Where a case looks wrong (English hematuria reaching only `normal`),
it is pinned as-is and called out, because a characterization test that
quietly "fixes" what it measures is worthless.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.entities.extractor import EntityExtractor
from chatbot.nlu.safety import MedicalSafetyLayer
from virtual_doctor.reasoning_engine import vocabulary

_extractor = EntityExtractor()
_safety = MedicalSafetyLayer()


def canonical(text):
    """What the legacy path contributes to the symbolic layer, canonicalised."""
    found = {
        c for raw in (_extractor.extract(text).get("symptoms") or [])
        if (c := vocabulary.canonical_symptom(raw)) is not None
    }
    return sorted(found)


def severity(text):
    return _safety.check(text).get("severity")


LATENT_SAFETY_ATOMS = ("hematuria", "seizure", "unconscious", "severe_bleeding")


class TestPolarityIsLost(unittest.TestCase):
    """The gap Phase 6 exists to close, in the plainest possible form."""

    def test_a_report_a_denial_a_hedge_and_a_memory_are_indistinguishable(self):
        variants = {
            "report":     "I have a fever",
            "denial":     "I do not have a fever",
            "hedge":      "I am not sure if I have a fever",
            "historical": "I had a fever last week",
        }
        results = {name: canonical(text) for name, text in variants.items()}
        for name, result in results.items():
            self.assertEqual(["fever"], result,
                             f"{name}: extractor no longer reports plain ['fever']")
        self.assertEqual(1, len({tuple(r) for r in results.values()}),
                         "the extractor has gained polarity — Phase 6's premise has changed")

    def test_arabic_denial_is_also_read_as_present(self):
        self.assertEqual(["fever"], canonical("عندي حرارة"))
        self.assertEqual(["fever"], canonical("ما عندي حرارة"))

    def test_a_correction_yields_both_the_old_and_the_new_symptom(self):
        self.assertEqual(["chest_pain", "headache"],
                         canonical("لا، مش صداع، ألم في الصدر"))


class TestLatentSafetyRulesAreUnreachable(unittest.TestCase):
    """Each of the four is in the vocabulary and in safety.pl, and the
    extractor still cannot produce it."""

    def test_all_four_are_already_application_vocabulary(self):
        for atom in LATENT_SAFETY_ATOMS:
            self.assertIn(atom, vocabulary.SYMPTOMS,
                          f"{atom} is not in vocabulary.SYMPTOMS")

    def test_extractor_declares_only_fifteen_symptoms_and_none_of_the_four(self):
        declared = set(_extractor.entities.get("symptoms", {}))
        self.assertEqual(15, len(declared))
        for atom in LATENT_SAFETY_ATOMS:
            self.assertNotIn(atom, declared)

    def test_extraction_finds_nothing_for_any_of_the_four(self):
        cases = [
            "في دم في البول", "there is blood in my urine",
            "صار عندي تشنج", "I had a seizure",
            "فقدان الوعي", "I passed out",
            "عندي نزيف شديد", "I have severe bleeding",
        ]
        for text in cases:
            self.assertEqual([], canonical(text),
                             f"extractor now reports something for {text!r}")

    def test_but_the_deterministic_safety_layer_does_catch_them(self):
        """The gap is symbolic reachability, not patient safety."""
        self.assertEqual("urgent", severity("في دم في البول"))
        self.assertEqual("urgent", severity("صار عندي تشنج"))
        self.assertEqual("urgent", severity("I had a seizure"))
        self.assertEqual("emergency", severity("فقدان الوعي"))
        self.assertEqual("emergency", severity("I passed out"))
        self.assertEqual("emergency", severity("عندي نزيف شديد"))
        self.assertEqual("emergency", severity("I have severe bleeding"))

    def test_english_hematuria_reaches_neither_layer(self):
        """Pinned as an observed gap, not endorsed.

        URGENT_PATTERNS_AR[12] is `blood\\s+in\\s+(vomit|stool|urine)`, which
        the natural phrasing "blood in my urine" does not match — the
        possessive breaks the adjacency. The Arabic equivalent DOES match. So
        this one phrasing is currently invisible to both the extractor and the
        safety layer, which makes it the clearest demonstration of what
        structured understanding adds. chatbot/** is not modified to fix it:
        Phase 6's scope is explicit about that, and the structured path
        escalates it through safety.pl instead.
        """
        self.assertEqual([], canonical("there is blood in my urine"))
        self.assertEqual("normal", severity("there is blood in my urine"))
        self.assertEqual("urgent", severity("في دم في البول"))


class TestWhatExtractionDoesReach(unittest.TestCase):
    """The cases Phase 6 must not disturb."""

    def test_single_and_combined_symptoms(self):
        self.assertEqual(["headache"], canonical("عندي صداع"))
        self.assertEqual(["headache"], canonical("I have a headache"))
        self.assertEqual(["headache", "nausea"], canonical("عندي صداع وغثيان"))
        self.assertEqual(["headache", "nausea"], canonical("I have a headache and nausea"))
        self.assertEqual(["chest_pain"], canonical("عندي ألم في الصدر"))
        self.assertEqual(["chest_pain"], canonical("I have chest pain"))
        self.assertEqual(["shortness_of_breath"], canonical("I have shortness of breath"))
        self.assertEqual(["chest_pain", "shortness_of_breath"],
                         canonical("chest pain and shortness of breath"))

    def test_attribute_answers_produce_no_symptoms(self):
        """Duration, location, radiation and severity answers are slot values,
        not symptoms. The extractor correctly finds nothing in them — which is
        why the understanding layer reports them under `findings`, separately."""
        for text in ("من ثلاث أيام", "for three days", "في الجانب الأيمن",
                     "on the right side", "ينتشر إلى ذراعي", "it spreads to my arm",
                     "the pain is severe"):
            self.assertEqual([], canonical(text), f"unexpected symptom in {text!r}")


class TestSafetyBaselineForPinnedRoutineCases(unittest.TestCase):
    """Cases this system deliberately rates routine, pinned so no Phase 6
    change can escalate them by accident."""

    def test_headache_cases_stay_normal(self):
        for text in ("عندي صداع", "I have a headache", "عندي صداع وغثيان",
                     "I have a headache and nausea"):
            self.assertEqual("normal", severity(text), f"{text!r} escalated")

    def test_plain_chest_pain_english_stays_normal(self):
        self.assertEqual("normal", severity("I have chest pain"))


if __name__ == "__main__":
    unittest.main()
