"""
Virtual Doctor — Formal Arabic Voice Quality Upgrade — behavior tests.

Real user feedback drove TWO opposite-direction Arabic style passes on this
codebase: first toward natural Palestinian/Levantine dialect (the dialect
wording itself then drew the same "not real" complaint it was meant to
fix), then this explicit reversal back to simplified formal Modern Standard
Arabic (فصحى مبسطة) — clear and calm, but formal, never slang. This file
pins THAT reversal: the exact wording of the templates the task named
explicitly, a forbidden-dialect-word regression guard across every "ar"
template (word-bounded, not naive substring — see _contains_forbidden_word's
docstring for why that distinction matters), and the two per-turn LLM
prompt constraints (planner.py's arabic_style_rule, reasoning.py's final
reply) that carry the same policy outside the static templates.

No production medical/diagnosis/safety-detection logic is touched by this
batch, and none of these tests exercise it — wording only. No real DB,
Ollama, STT, TTS, or network access anywhere in this file.
"""

import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, reasoning

# The dialect words the task explicitly forbids. Checked with word
# boundaries (see _contains_forbidden_word) so "لأ" (colloquial "no") does
# not false-positive on "الأعراض"/"الأسئلة"/"الألم"/"الأول" — a definite
# article "ال" immediately followed by a hamza-initial word is a substring
# coincidence, not the dialect word, as verified during this batch's own
# manual audit.
_FORBIDDEN_DIALECT_WORDS = (
    "شو", "بتشعر", "احكيلي", "تمام", "مش", "خليني",
    "حكيتلي", "بدك", "لأ", "عيدلي",
)


def _contains_forbidden_word(text: str) -> list:
    """Returns which forbidden dialect words appear in `text` as whole
    words. Uses \\b word boundaries rather than plain substring matching —
    Python's `re` module treats Arabic letters as \\w under Unicode (the
    default for str patterns), so \\bلأ\\b correctly does NOT match inside
    "الأعراض" (no boundary exists between "ا" and "ل" there), while it DOES
    match a standalone "لأ". A naive `word in text` check was tried during
    this batch's manual audit and produced exactly that false positive.
    """
    return [w for w in _FORBIDDEN_DIALECT_WORDS if re.search(rf"\b{re.escape(w)}\b", text)]


# Every top-level static Arabic template touched by this batch, plus the
# pre-existing ones this batch deliberately left unchanged because they were
# already formal-compliant (CORRECTION_APPLIED_NAME/AGE/GENERIC).
_ALL_AR_TEMPLATES = {
    "GREETING": interview_engine.GREETING["ar"],
    "ASK_AGE": interview_engine.ASK_AGE["ar"],
    "ASK_AGE_RETRY": interview_engine.ASK_AGE_RETRY["ar"],
    "ASK_COMPLAINT": interview_engine.ASK_COMPLAINT["ar"],
    "WRAP_UP": interview_engine.WRAP_UP["ar"],
    "SAFETY_URGENT_WARNING": interview_engine.SAFETY_URGENT_WARNING["ar"],
    "SAFETY_URGENT_REMINDER": interview_engine.SAFETY_URGENT_REMINDER["ar"],
    "SAFETY_EMERGENCY_CONTINUATION": interview_engine.SAFETY_EMERGENCY_CONTINUATION["ar"],
    "SAFETY_EMERGENCY_REMINDER": interview_engine.SAFETY_EMERGENCY_REMINDER["ar"],
    "NAME_CONFIRM_QUESTION": interview_engine.NAME_CONFIRM_QUESTION["ar"],
    "NAME_CONFIRM_RETRY": interview_engine.NAME_CONFIRM_RETRY["ar"],
    "CHIEF_COMPLAINT_CONFIRM_RETRY": interview_engine.CHIEF_COMPLAINT_CONFIRM_RETRY["ar"],
    "FOCUSED_FLANK_URINARY_QUESTION": interview_engine.FOCUSED_FLANK_URINARY_QUESTION["ar"],
    "NAME_UNCLEAR_REPEAT": interview_engine.NAME_UNCLEAR_REPEAT["ar"],
    "CORRECTION_ASK_NAME": interview_engine.CORRECTION_ASK_NAME["ar"],
    "CORRECTION_ASK_AGE": interview_engine.CORRECTION_ASK_AGE["ar"],
    "CORRECTION_ASK_FIELD": interview_engine.CORRECTION_ASK_FIELD["ar"],
    "CORRECTION_APPLIED_NAME": interview_engine.CORRECTION_APPLIED_NAME["ar"],
    "CORRECTION_APPLIED_AGE": interview_engine.CORRECTION_APPLIED_AGE["ar"],
    "CORRECTION_APPLIED_GENERIC": interview_engine.CORRECTION_APPLIED_GENERIC["ar"],
    "CORRECTION_APPLIED_COMPLAINT": interview_engine.CORRECTION_APPLIED_COMPLAINT["ar"],
}


# ===========================================================================
# 1. No forbidden dialect word survives in any static Arabic template
# ===========================================================================

class TestNoForbiddenDialectWordsInTemplates(unittest.TestCase):
    def test_word_boundary_helper_avoids_the_laa_false_positive(self):
        """Regression guard for this batch's own audit finding: "لأ" must
        not be flagged inside "الأعراض" (definite article + hamza-initial
        noun), only as an actual standalone word."""
        self.assertEqual(_contains_forbidden_word("ما الأعراض التي تشعر بها اليوم؟"), [])
        # List order follows _FORBIDDEN_DIALECT_WORDS iteration order, not
        # the order the words appear in the text.
        self.assertEqual(_contains_forbidden_word("لأ، مش هيك"), ["مش", "لأ"])

    def test_static_templates_are_free_of_dialect_words(self):
        for name, text in _ALL_AR_TEMPLATES.items():
            with self.subTest(template=name):
                self.assertEqual(_contains_forbidden_word(text), [],
                                  f"{name!r} = {text!r} contains a forbidden dialect word")

    def test_flow_json_questions_are_free_of_dialect_words(self):
        for flow in interview_engine.FLOWS.values():
            for slot in flow.get("slots", []):
                question = slot.get("question_ar", "")
                with self.subTest(question=question):
                    self.assertEqual(_contains_forbidden_word(question), [])


# ===========================================================================
# 2. Exact wording pins for the templates the task named explicitly
# ===========================================================================

class TestExplicitlyRequestedTemplatesMatchExactWording(unittest.TestCase):
    def test_greeting_is_formal(self):
        self.assertEqual(
            interview_engine.GREETING["ar"],
            "مرحبًا، أنا المساعد الطبي في MedOrbit. قبل أن نبدأ، ما اسمك؟",
        )

    def test_ask_age_is_formal(self):
        self.assertEqual(interview_engine.ASK_AGE["ar"], "شكرًا يا {name}. كم عمرك؟")

    def test_ask_complaint_is_formal(self):
        self.assertEqual(
            interview_engine.ASK_COMPLAINT["ar"], "ما الأعراض التي تشعر بها اليوم؟",
        )

    def test_name_unclear_repeat_matches_task_exact_text(self):
        self.assertEqual(
            interview_engine.NAME_UNCLEAR_REPEAT["ar"],
            "لست متأكدًا من أنني سمعت الاسم بشكل صحيح. من فضلك، أخبرني باسمك الأول فقط.",
        )

    def test_chief_complaint_confirm_retry_matches_task_exact_text(self):
        self.assertEqual(
            interview_engine.CHIEF_COMPLAINT_CONFIRM_RETRY["ar"],
            "من فضلك، وضّح لي ما تشعر به بالتحديد.",
        )


# ===========================================================================
# 3. LLMPlanner's per-turn Arabic style rule requires formal MSA
# ===========================================================================

class TestPlannerPromptRequiresFormalArabic(unittest.TestCase):
    def test_arabic_style_rule_mandates_msa_and_forbids_dialect(self):
        from virtual_doctor.planner import LLMPlanner, PlannerInput
        import asyncio
        from unittest.mock import MagicMock, patch

        captured = {}

        def fake_post(url, json=None, timeout=None):  # noqa: A002
            captured["payload"] = json
            response = MagicMock()
            response.raise_for_status = MagicMock()
            response.json.return_value = {
                "message": {"content": "{\"next_question\": \"ok\", \"findings\": {}}"},
            }
            return response

        ctx = PlannerInput(
            message="عندي صداع", lang="ar", phase="interviewing",
            chief_complaint="headache", profile={}, entities={},
            history=[], chunks=[], context_block="", turn_index=2,
            asked_questions=[],
        )
        llm_planner = LLMPlanner(
            texts={},
            helpers={"extract_name": lambda m: m, "extract_age": lambda m: None},
            validators={
                "text_matches_language": reasoning._text_matches_language,
                "looks_coherent": reasoning._looks_coherent,
            },
        )
        with patch("virtual_doctor.planner.requests.post", side_effect=fake_post):
            asyncio.run(llm_planner._ask(ctx))
        prompt = captured["payload"]["messages"][1]["content"]

        self.assertIn("Modern Standard Arabic", prompt)
        self.assertIn("NOT Levantine/Palestinian dialect", prompt)


# ===========================================================================
# 4. reasoning.py's final Arabic recommendation reply is formal
# ===========================================================================

class TestReasoningFinalReplyIsFormal(unittest.TestCase):
    def test_final_reply_template_has_no_dialect_words(self):
        import inspect

        source = inspect.getsource(reasoning)
        # Anchored on the f-string's own opening text and read FORWARD only
        # (not backward) — the comment directly above this f-string
        # deliberately quotes the old dialect wording it superseded
        # ("حسب اللي حكيتلي إياه...") as historical documentation, which
        # would false-positive a backward/window-based scan.
        anchor = 'f"بحسب المعلومات التي ذكرتها'
        self.assertIn(anchor, source)
        start = source.index(anchor)
        segment = source[start:source.index(")", start) + 1]
        self.assertEqual(_contains_forbidden_word(segment), [])


if __name__ == "__main__":
    unittest.main()
