"""
Characterization tests and tracing — Cluster A (Phase 0).

Cluster A bug: IntentClassifier produces wrong or "unknown" intents due to
several distinct, confirmed mechanisms living in chatbot/intent/classifier.py,
chatbot/intent/intents.json, and chatbot/nlu/ranker.py:

  (a) SUBSTRING MATCH — classifier.py Step 6 checks `keyword_norm in
      match_text` with no word-boundary check, so a keyword embedded inside
      an unrelated longer word (Arabic's attached "ال"/plural forms, or an
      English keyword like "er" inside "there") falsely fires.

  (b) GENERIC KEYWORD — some keywords are too short/broad to be specific to
      one intent ("how" for platform_support, "er" for emergency, "دكتور"
      for both find_doctor and doctor_by_name, "عيادة" for find_doctor AND
      clinic_info AND show_route inputs that merely mention a clinic).

  (c) NGRAM FALLBACK — the `keyword_norm in ' '.join(ngrams)` half of the
      Step 6 check matches against ngrams built from the PRE-synonym-
      resolution tokens, so a keyword can match even when the synonym-
      resolved text no longer contains it (e.g. "ضغط" still matches
      lab_result_query even after "الضغط" was resolved to "blood_pressure").

  (d) TIE / THRESHOLD — chatbot/nlu/ranker.py normalizes calibrated scores to
      sum to 1.0. When N intents score identically, each gets confidence
      ~1/N. If 1/N falls below the WINNING intent's own
      `confidence_threshold` (0.3-0.4 in intents.json), classifier.py's
      final threshold check discards the ranked winner and falls back to
      "unknown" — even though the ranker itself (threshold 0.15) considered
      the match valid.

  (e) KEYWORD OVERLAP — the same keyword is listed under multiple intents'
      keyword lists (e.g. "أطباء" under both find_doctor and clinic_doctors;
      "عيادة" under find_doctor and matched via ngram fallback for
      clinic_info), so any input matching one plausibly matches both.

  (f) RANKER BEHAVIOR — IntentRanker.rank()'s negation-word check
      (`n in text_lower`, itself a Cluster-A-shaped substring check) applies
      uniformly to ALL intents when any negation word appears anywhere in
      the text; its cross-category penalty silently no-ops for any intent
      not listed in INTENT_CATEGORIES (most intents, including clinic_hours,
      clinic_doctors, doctor_fee, medication_interaction, are unmapped); and
      its keyword-count boost (x1.2 at 2+ matched keywords, x1.3 more at 4+)
      rewards intents with more (possibly redundant) keyword hits regardless
      of specificity.

This phase does NOT fix anything. It pins the CURRENT wrong output for every
confirmed example (via the public `classify()` API only — matched_keywords
and alternative_intents are both already part of its public return value, so
no production code was changed or specially instrumented to observe them),
and encodes the INTENDED correct output as `@unittest.expectedFailure` tests
for future regression tracking once a Cluster A fix is approved.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.intent.classifier import IntentClassifier


class TestClusterACurrentWrongOutputs(unittest.TestCase):
    """Pins the CURRENT (wrong) classify() output for every confirmed
    Cluster A example, plus the mechanism responsible (see module docstring
    for the (a)-(f) key). All values below were captured directly from
    classify()'s own public return value — matched_keywords and
    alternative_intents are already part of its documented output shape.
    """

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    def test_how_do_i_get_there_misclassified_as_emergency(self):
        # Mechanism: (a) substring match + (b) generic keyword. intents.json's
        # "emergency" keywords_en list includes the bare 2-letter word "er",
        # which substring-matches inside "there". Score >= 1.0 fires
        # classifier.py's Step 9 emergency override before ranking even runs
        # (is_fallback is None here, not False, confirming the early-return
        # path rather than the ranked path).
        result = self.classifier.classify("How do I get there")
        self.assertEqual(result["intent"], "emergency")
        self.assertEqual(result["confidence"], 1.0)
        self.assertEqual(result["matched_keywords"], ["er"])

    def test_kaifak_how_are_you_misclassified_as_platform_support(self):
        # Mechanism: (b) generic keyword + (d) tie/threshold + (f) ranker
        # keyword-count boost. Three intents tie at confidence 0.3333 each
        # (platform_support via "how"; small_talk and how_are_you both via
        # the phrase "how are you", since "كيفك" normalizes to "how are you"
        # per the Cluster B fix). platform_support wins the 3-way tie purely
        # by dict/iteration order, not by relevance.
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "platform_support")
        self.assertAlmostEqual(result["confidence"], 0.3333, places=3)
        self.assertEqual(result["matched_keywords"], ["how"])
        alt_intents = {a["intent"] for a in result["alternative_intents"]}
        self.assertEqual(alt_intents, {"small_talk", "how_are_you"})

    def test_travel_time_phrase_misclassified_as_platform_support(self):
        # Mechanism: (a) substring match + (b) generic keyword. "كم" (a
        # legitimate standalone dialect word, not a Cluster B corruption)
        # normalizes to "how_much", whose literal substring "how" matches
        # platform_support's own generic keyword at a full 1.0 (primary,
        # single clean match — no tie here, platform_support simply wins
        # outright with nothing else scoring).
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertEqual(result["intent"], "platform_support")
        self.assertEqual(result["confidence"], 1.0)
        self.assertEqual(result["matched_keywords"], ["how"])

    def test_doctor_fee_phrase_falls_back_to_unknown(self):
        # Mechanism: (c) ngram fallback + (e) keyword overlap + (d) tie/
        # threshold. Raw trace (chatbot/intent/classifier.py Step 6 logic):
        #   find_doctor        1.0  via "دكتور" (generic, shared keyword)
        #   doctor_by_name     1.0  via "دكتور" (same generic keyword)
        #   book_appointment   1.0  via "كشف" (generic, shared keyword)
        #   doctor_fee         0.6  via "price" (its own keyword, but only
        #                            reachable at SECONDARY weight, and only
        #                            because synonym resolution canonicalized
        #                            both "سعر" and "كشف" to "price" —
        #                            destroying doctor_fee's own primary
        #                            Arabic phrase keywords "سعر الكشف"/
        #                            "كم سعر" in the process)
        # doctor_fee's own real signal is weaker than three unrelated,
        # generic 1.0 matches, and even a 1.0 raw score would fall well
        # below 0.4 after 1.0/(sum of ~4.6) normalization — the classifier's
        # own confidence_threshold (0.3-0.4) is never reached by anything,
        # so the whole result collapses to "unknown".
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertEqual(result["intent"], "unknown")
        self.assertEqual(result["confidence"], 0.0)

    def test_clinic_doctors_phrase_misclassified_as_find_doctor(self):
        # Mechanism: (e) keyword overlap. find_doctor's own keyword list
        # independently contains BOTH "أطباء" and "عيادة" (2 matches, and
        # ranker.py's x1.2 boost at len(keywords)>=2 applies), while
        # clinic_doctors only lists "أطباء" (1 match, no boost) — so
        # find_doctor wins even though clinic_doctors is the more specific,
        # intended match.
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertEqual(result["intent"], "find_doctor")
        self.assertAlmostEqual(result["confidence"], 0.3529, places=3)
        self.assertEqual(sorted(result["matched_keywords"]), ["أطباء", "عيادة"])
        alt_intents = {a["intent"] for a in result["alternative_intents"]}
        self.assertEqual(alt_intents, {"clinic_doctors"})

    def test_clinic_hours_phrase_falls_back_to_unknown(self):
        # Mechanism: (d) tie/threshold, the clearest case of it. Raw trace:
        #   find_doctor          1.0  via "عيادة" (generic, shared keyword)
        #   doctor_availability  1.0  via "دوام" (shared with clinic_hours)
        #   clinic_info          1.0  via "عيادة" (generic, shared keyword)
        #   clinic_hours         1.0  via "دوام" (its own real keyword)
        # A clean 4-way tie normalizes to confidence 0.25 each. Every one of
        # these four intents has its own confidence_threshold of 0.3 or 0.4
        # in intents.json — 0.25 clears none of them, so classifier.py
        # discards the ranked winner and falls back to "unknown" even though
        # clinic_hours (the correct answer) was one of the tied candidates.
        result = self.classifier.classify("ساعات دوام العيادة")
        self.assertEqual(result["intent"], "unknown")
        self.assertEqual(result["confidence"], 0.0)

    def test_medication_interaction_phrase_falls_back_to_unknown(self):
        # Mechanism: (c) ngram fallback + (d) tie/threshold. Raw trace:
        #   medication_info         1.0  via "بانادول"
        #   medication_interaction  1.0  via "هل يتعارض" (its own real
        #                                 keyword — matches cleanly)
        #   lab_result_query        1.0  via "ضغط" — reachable ONLY through
        #                                 the ngram-fallback path, since the
        #                                 synonym engine already resolved
        #                                 "الضغط" to "blood_pressure" in the
        #                                 text actually used for the
        #                                 substring check, but the ngrams
        #                                 (built pre-resolution) still
        #                                 contain the raw token "ضغط".
        # A 3-way tie normalizes to confidence 0.3333 each, below
        # medication_interaction's own 0.4 threshold (and medication_info's
        # 0.3 threshold, only barely, but the tie's exact value keeps both
        # under their respective bars in practice) — falls back to unknown.
        result = self.classifier.classify("هل يتعارض بانادول مع الضغط")
        self.assertEqual(result["intent"], "unknown")
        self.assertEqual(result["confidence"], 0.0)

    def test_arabic_show_route_phrase_misclassified_as_find_doctor(self):
        # Mechanism: (a) substring match + (e) keyword overlap. "عيادة"
        # (clinic) is embedded inside "للعيادة" ("to the clinic") with no
        # word-boundary check, matching find_doctor's own "عيادة" keyword —
        # while show_route's own correct multi-word keyword "كيف اوصل" also
        # matches, but find_doctor's keyword-count boost (2 matches: "عيادة"
        # here plus the ngram-fallback "how" contamination it also picks up)
        # out-ranks it.
        result = self.classifier.classify("كيف اوصل للعيادة")
        self.assertEqual(result["intent"], "find_doctor")
        self.assertAlmostEqual(result["confidence"], 0.3846, places=3)
        self.assertEqual(result["matched_keywords"], ["عيادة"])
        alt_intents = {a["intent"] for a in result["alternative_intents"]}
        self.assertIn("clinic_info", alt_intents)


class TestClusterAIntendedBehavior(unittest.TestCase):
    """Encodes the INTENDED, correct classification for the same inputs.

    All marked @unittest.expectedFailure — Cluster A is not fixed yet. Once a
    Cluster A batch is approved and implemented, each of these will report
    "unexpected success"; at that point remove the decorator and this class
    becomes the real regression test for the fix.
    """

    @classmethod
    def setUpClass(cls):
        cls.classifier = IntentClassifier()

    @unittest.expectedFailure
    def test_how_do_i_get_there_should_classify_as_show_route(self):
        result = self.classifier.classify("How do I get there")
        self.assertEqual(result["intent"], "show_route")

    @unittest.expectedFailure
    def test_kaifak_should_classify_as_how_are_you(self):
        result = self.classifier.classify("كيفك")
        self.assertEqual(result["intent"], "how_are_you")

    @unittest.expectedFailure
    def test_travel_time_phrase_should_classify_correctly(self):
        result = self.classifier.classify("كم يستغرق الوصول")
        self.assertIn(result["intent"], ["travel_time", "show_route"])

    @unittest.expectedFailure
    def test_doctor_fee_phrase_should_classify_correctly(self):
        result = self.classifier.classify("كم سعر كشف الدكتور")
        self.assertIn(result["intent"], ["doctor_fee", "find_doctor"])

    @unittest.expectedFailure
    def test_clinic_doctors_phrase_should_classify_correctly(self):
        result = self.classifier.classify("من هم الأطباء في العيادة")
        self.assertIn(result["intent"], ["clinic_doctors", "clinic_info"])

    @unittest.expectedFailure
    def test_clinic_hours_phrase_should_classify_correctly(self):
        result = self.classifier.classify("ساعات دوام العيادة")
        self.assertIn(result["intent"], ["clinic_hours", "clinic_info"])

    @unittest.expectedFailure
    def test_medication_interaction_phrase_should_classify_correctly(self):
        result = self.classifier.classify("هل يتعارض بانادول مع الضغط")
        self.assertIn(result["intent"], ["medication_interaction", "medication_info"])

    @unittest.expectedFailure
    def test_arabic_show_route_phrase_should_classify_correctly(self):
        result = self.classifier.classify("كيف اوصل للعيادة")
        self.assertEqual(result["intent"], "show_route")


if __name__ == "__main__":
    unittest.main()
