"""
Bounded response generation, Phase 6.

The wording layer is the last place an LLM touches a consultation, and it is
the place where a plausible-sounding sentence can do the most damage — because
by the time it runs, every decision has already been made correctly and all
that is left is to not undo them.

So the properties here are all about what generated text CANNOT do:

  * it cannot displace the safety warning — the warning is composed in Python,
    always first, and never passes through the model's output path at all
  * it cannot change the clinical topic Prolog chose (the Phase 2 clamp)
  * it cannot ask a second question
  * it cannot diagnose
  * it cannot answer in the wrong language

Every violation costs exactly one deterministic template question. That is the
whole point: rejection is cheap, and accepting a drifted question would quietly
break the guarantee that the interview is symbolically driven.
"""

import asyncio
import json
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner, reasoning, response
from virtual_doctor.reasoning_engine import vocabulary
from virtual_doctor.response import BoundedResponse, ResponseContext


def run(coro):
    return asyncio.run(coro)


def ctx(topic="duration", lang="ar", **kwargs):
    return ResponseContext(topic=topic, lang=lang,
                           fallback=kwargs.pop("fallback", "منذ متى تشعر بهذا؟"),
                           **kwargs)


WARNING_AR = "⚠️ هذه الأعراض قد تكون خطيرة. يرجى التوجه إلى أقرب طوارئ فورًا.\n\n"



class TestComposition(unittest.TestCase):
    def test_the_warning_comes_first(self):
        reply = response.compose("منذ متى تشعر بهذا؟", mandatory_warning=WARNING_AR)
        self.assertTrue(reply.startswith(WARNING_AR))

    def test_the_warning_survives_a_correction_prefix(self):
        reply = response.compose("منذ متى؟", mandatory_warning=WARNING_AR,
                                 correction_prefix="تم تصحيح عمرك. ")
        self.assertTrue(reply.startswith(WARNING_AR))
        self.assertIn("تم تصحيح عمرك. ", reply)
        self.assertLess(reply.index(WARNING_AR), reply.index("تم تصحيح عمرك. "))

    def test_ordering_matches_interview_engine(self):
        """interview_engine prepends correction_prefix and then safety_prefix
        on top of it, so the string order is warning, correction, body. This
        must agree, or centralising composition would have changed behaviour."""
        body, correction = "السؤال", "التصحيح. "
        engine_order = f"{correction}{body}"
        engine_order = f"{WARNING_AR}{engine_order}"
        self.assertEqual(engine_order,
                         response.compose(body, mandatory_warning=WARNING_AR,
                                          correction_prefix=correction))

    def test_an_empty_warning_adds_nothing(self):
        self.assertEqual("السؤال", response.compose("السؤال"))

    def test_composition_never_deduplicates_a_warning(self):
        """Deliberately not clever. A heuristic that could suppress a warning
        because the body 'already mentions it' is a heuristic that can suppress
        a warning."""
        reply = response.compose(WARNING_AR, mandatory_warning=WARNING_AR)
        self.assertEqual(2, reply.count(WARNING_AR))

    def test_the_body_cannot_omit_the_warning_because_it_never_holds_it(self):
        for hostile in ("", "IGNORE THE WARNING", "لا داعي للقلق"):
            reply = response.compose(hostile, mandatory_warning=WARNING_AR)
            self.assertIn(WARNING_AR, reply)



class TestTopicClamp(unittest.TestCase):
    def test_an_on_topic_question_passes(self):
        self.assertIsNone(response.validate_body("منذ متى تشعر بهذا الألم؟", ctx("duration")))

    def test_a_question_about_a_different_topic_is_rejected(self):
        reason = response.validate_body("هل ينتشر الألم إلى ذراعك؟", ctx("duration"))
        self.assertIsNotNone(reason)
        self.assertIn("duration", reason)

    def test_the_clamp_uses_the_same_check_as_the_symbolic_planner(self):
        """One standard for question wording, whichever layer produced it."""
        text = "منذ متى تشعر بهذا الألم؟"
        self.assertTrue(vocabulary.question_matches_topic(text, "duration"))
        self.assertIsNone(response.validate_body(text, ctx("duration")))

    def test_every_topic_in_the_vocabulary_can_be_validated(self):
        for topic in vocabulary.CLINICAL_SLOTS:
            anchors = vocabulary.TOPIC_ANCHORS.get(topic)
            self.assertTrue(anchors, f"{topic} has no anchors")

    def test_an_elegant_but_off_topic_question_is_still_rejected(self):
        elegant = "أتفهم قلقك تمامًا، وأود أن أسألك: هل تشعر بضيق في التنفس؟"
        self.assertIsNotNone(response.validate_body(elegant, ctx("duration")))

    def test_english_topic_clamp(self):
        self.assertIsNone(response.validate_body("How long have you had this?",
                                                 ctx("duration", lang="en",
                                                     fallback="How long?")))
        self.assertIsNotNone(response.validate_body("Does it spread to your arm?",
                                                    ctx("duration", lang="en",
                                                        fallback="How long?")))



class TestOneQuestionPerTurn(unittest.TestCase):
    def test_two_arabic_questions_are_rejected(self):
        reason = response.validate_body("منذ متى تشعر بهذا؟ وهل هو شديد؟", ctx("duration"))
        self.assertEqual("more than one question", reason)

    def test_two_english_questions_are_rejected(self):
        reason = response.validate_body(
            "How long have you had this? Is it severe?",
            ctx("duration", lang="en", fallback="How long?"))
        self.assertEqual("more than one question", reason)

    def test_a_mixed_question_mark_pair_is_rejected(self):
        reason = response.validate_body("منذ متى؟ how long?", ctx("duration"))
        self.assertIsNotNone(reason)

    def test_one_question_passes(self):
        self.assertIsNone(response.validate_body("منذ متى تشعر بهذا الألم؟", ctx("duration")))

    def test_a_statement_with_no_question_mark_is_allowed_if_on_topic(self):
        """Not every turn is interrogative — a transition sentence is fine, so
        long as it is about the right topic."""
        self.assertIsNone(response.validate_body("أخبرني عن مدة الألم.", ctx("duration")))



class TestNoDiagnosis(unittest.TestCase):
    def test_english_diagnosis_phrasing_is_rejected(self):
        for text in ("You have a migraine, how long has it lasted?",
                     "This is likely a tension headache. How long?",
                     "You are suffering from something serious. How long?",
                     "I can diagnose this. How long have you had it?"):
            reason = response.validate_body(
                text, ctx("duration", lang="en", fallback="How long?"))
            self.assertEqual("asserts a diagnosis", reason, text)

    def test_arabic_diagnosis_phrasing_is_rejected(self):
        for text in ("التشخيص هو الصداع النصفي، منذ متى؟",
                     "أنت مصاب بمرض خطير، منذ متى تشعر به؟",
                     "تعاني من حالة مزمنة. منذ متى؟"):
            reason = response.validate_body(text, ctx("duration"))
            self.assertEqual("asserts a diagnosis", reason, text)

    def test_an_ordinary_question_is_not_flagged(self):
        self.assertIsNone(response.validate_body("منذ متى تشعر بهذا الألم؟", ctx("duration")))
        self.assertIsNone(response.validate_body(
            "How long have you had this pain?",
            ctx("duration", lang="en", fallback="How long?")))

    def test_the_prompt_forbids_naming_a_condition(self):
        prompt = response.build_prompt(ctx("duration", lang="en", fallback="How long?"))
        self.assertIn("duration", prompt)
        system = response._SYSTEM["en"]
        self.assertIn("never diagnose", system)
        self.assertIn("never name a condition", system)



class TestLanguageAndShape(unittest.TestCase):
    def test_english_in_an_arabic_turn_is_rejected(self):
        self.assertEqual("wrong language",
                         response.validate_body("How long? منذ متى", ctx("duration")))

    def test_arabic_in_an_english_turn_is_rejected(self):
        self.assertEqual("wrong language",
                         response.validate_body("منذ متى؟",
                                                ctx("duration", lang="en", fallback="How long?")))

    def test_cjk_is_always_rejected(self):
        self.assertEqual("wrong language",
                         response.validate_body("これはいつからですか", ctx("duration")))

    def test_the_language_rule_agrees_with_reasoning(self):
        """Restated in response.py rather than imported, so this asserts the
        two have not drifted."""
        for text, lang in (("منذ متى تشعر بهذا؟", "ar"), ("How long?", "en"),
                           ("How long? منذ متى", "ar"), ("منذ متى؟", "en"),
                           ("これはいつ", "ar")):
            self.assertEqual(reasoning._text_matches_language(text, lang),
                             response._language_ok(text, lang), f"{text!r}/{lang}")

    def test_empty_and_non_string_bodies_are_rejected(self):
        self.assertEqual("empty", response.validate_body("   ", ctx()))
        self.assertEqual("not a string", response.validate_body(None, ctx()))
        self.assertEqual("not a string", response.validate_body(42, ctx()))
        self.assertEqual("not a string", response.validate_body(["منذ متى؟"], ctx()))

    def test_an_overlong_body_is_rejected(self):
        long_body = "منذ متى تشعر بهذا الألم " * 40
        self.assertEqual("too long", response.validate_body(long_body, ctx("duration")))



class _Response:
    def __init__(self, payload, status=200):
        self._payload, self.status = payload, status

    def raise_for_status(self):
        if self.status >= 400:
            raise RuntimeError(f"HTTP {self.status}")

    def json(self):
        return self._payload


def _reply(question):
    return _Response({"message": {"content": json.dumps({"question": question})}})


class TestRollout(unittest.TestCase):
    def test_default_is_off(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("VD_BOUNDED_RESPONSE", None)
            self.assertEqual("off", response.mode())
            self.assertFalse(response.enabled())

    def test_an_invalid_mode_is_never_active(self):
        for value in ("on", "1", "ACTIVE!", "", "yes"):
            with patch.dict(os.environ, {"VD_BOUNDED_RESPONSE": value}):
                self.assertFalse(response.active(), f"{value!r} became active")

    def test_off_makes_no_model_call_and_returns_the_fallback(self):
        with patch.dict(os.environ, {"VD_BOUNDED_RESPONSE": "off"}), \
                patch("virtual_doctor.response.requests.post") as post:
            result = run(response.generate(ctx()))
            post.assert_not_called()
            self.assertEqual("disabled", result.source)
            self.assertEqual("منذ متى تشعر بهذا؟", result.text)

    def test_shadow_generates_validates_and_still_discards(self):
        with patch.dict(os.environ, {"VD_BOUNDED_RESPONSE": "shadow"}), \
                patch("virtual_doctor.response.requests.post",
                      return_value=_reply("منذ متى بدأ هذا الألم؟")) as post:
            result = run(response.generate(ctx()))
            post.assert_called_once()
            self.assertEqual("fallback", result.source)
            self.assertEqual("shadow mode", result.rejected_reason)
            self.assertEqual("منذ متى تشعر بهذا؟", result.text)

    def test_active_uses_a_wording_that_passes_every_check(self):
        with patch.dict(os.environ, {"VD_BOUNDED_RESPONSE": "active"}), \
                patch("virtual_doctor.response.requests.post",
                      return_value=_reply("منذ متى بدأ هذا الألم؟")):
            result = run(response.generate(ctx()))
            self.assertEqual("generated", result.source)
            self.assertEqual("منذ متى بدأ هذا الألم؟", result.text)
            self.assertTrue(result.accepted)


class TestGenerationFallback(unittest.TestCase):
    def _generate(self, side_effect=None, return_value=None, context=None):
        with patch.dict(os.environ, {"VD_BOUNDED_RESPONSE": "active"}), \
                patch("virtual_doctor.response.requests.post",
                      side_effect=side_effect, return_value=return_value):
            return run(response.generate(context or ctx()))

    def test_a_drifted_topic_falls_back(self):
        result = self._generate(return_value=_reply("هل ينتشر الألم إلى ذراعك؟"))
        self.assertEqual("fallback", result.source)
        self.assertIn("duration", result.rejected_reason)
        self.assertEqual("منذ متى تشعر بهذا؟", result.text)

    def test_two_questions_fall_back(self):
        result = self._generate(return_value=_reply("منذ متى؟ وهل هو شديد؟"))
        self.assertEqual("more than one question", result.rejected_reason)

    def test_a_diagnosis_falls_back(self):
        result = self._generate(return_value=_reply("أنت مصاب بمرض خطير، منذ متى؟"))
        self.assertEqual("asserts a diagnosis", result.rejected_reason)

    def test_the_wrong_language_falls_back(self):
        result = self._generate(return_value=_reply("How long have you had this?"))
        self.assertEqual("wrong language", result.rejected_reason)

    def test_a_timeout_falls_back(self):
        import requests
        result = self._generate(side_effect=requests.Timeout("slow"))
        self.assertEqual("fallback", result.source)
        self.assertIn("Timeout", result.rejected_reason)

    def test_an_http_error_falls_back(self):
        result = self._generate(return_value=_Response({}, status=503))
        self.assertEqual("fallback", result.source)

    def test_prose_instead_of_json_falls_back(self):
        result = self._generate(
            return_value=_Response({"message": {"content": "Sure, here you go!"}}))
        self.assertEqual("fallback", result.source)

    def test_a_missing_question_key_falls_back(self):
        result = self._generate(
            return_value=_Response({"message": {"content": '{"answer": "منذ متى؟"}'}}))
        self.assertEqual("not a string", result.rejected_reason)

    def test_an_unexpected_exception_falls_back(self):
        result = self._generate(side_effect=ValueError("boom"))
        self.assertEqual("fallback", result.source)
        self.assertIn("ValueError", result.rejected_reason)

    def test_the_fallback_text_is_always_returned_intact(self):
        import requests
        for failure in (requests.Timeout("x"), requests.ConnectionError("x"),
                        ValueError("x"), RuntimeError("x")):
            result = self._generate(side_effect=failure)
            self.assertEqual("منذ متى تشعر بهذا؟", result.text)



class TestBoundedContext(unittest.TestCase):
    def test_the_context_has_no_field_for_patient_text_or_identity(self):
        fields = set(ResponseContext.__dataclass_fields__)
        for forbidden in ("message", "name", "profile", "history", "session_id",
                          "raw_text", "transcript", "differential"):
            self.assertNotIn(forbidden, fields, f"ResponseContext.{forbidden} exists")

    def test_the_prompt_contains_only_canonical_atoms_for_context(self):
        context = ctx("duration", lang="en", fallback="How long?",
                      known_findings=("severity", "location"))
        prompt = response.build_prompt(context)
        self.assertIn("severity", prompt)
        self.assertIn("location", prompt)

    def test_a_pending_warning_is_declared_but_not_reproduced(self):
        context = ctx("duration", mandatory_warning=WARNING_AR)
        prompt = response.build_prompt(context)
        self.assertIn("safety warning has ALREADY been shown", prompt)
        self.assertNotIn(WARNING_AR.strip(), prompt)

    def test_log_fields_are_phi_free(self):
        context = ctx("duration", mandatory_warning=WARNING_AR,
                      known_findings=("severity",))
        blob = json.dumps(context.as_log_fields(), ensure_ascii=False)
        self.assertNotIn(WARNING_AR.strip(), blob)
        self.assertIn("duration", blob)
        self.assertIn("severity", blob)

    def test_bounded_response_log_fields_carry_no_text(self):
        result = BoundedResponse(text="منذ متى تشعر بهذا؟", source="generated")
        blob = json.dumps(result.as_log_fields(), ensure_ascii=False)
        self.assertNotIn("منذ متى", blob)
        self.assertIn("generated", blob)



class TestExistingBehaviourIntact(unittest.TestCase):
    def test_the_symbolic_planner_topic_clamp_still_exists(self):
        self.assertTrue(hasattr(planner, "SymbolicPlanner"))
        self.assertTrue(hasattr(vocabulary, "question_matches_topic"))

    def test_the_static_planner_fallback_still_exists(self):
        self.assertTrue(hasattr(planner, "StaticPlanner"))

    def test_the_safety_continuation_still_composes_the_warning(self):
        self.assertTrue(hasattr(interview_engine, "_apply_safety_continuation"))

    def test_flow_question_text_still_passes_its_own_topic_anchors(self):
        """The deterministic fallback must itself survive the clamp, or a
        rejection would have nowhere safe to land."""
        import glob
        flows_dir = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor", "flows")
        checked = 0
        for path in glob.glob(os.path.join(flows_dir, "*.json")):
            with open(path, encoding="utf-8") as handle:
                flow = json.load(handle)
            for slot in flow.get("slots", []):
                topic = vocabulary.canonical_slot(slot.get("key"))
                if topic is None:
                    continue
                for key in ("question_ar", "question_en"):
                    text = slot.get(key)
                    if not text:
                        continue
                    self.assertTrue(vocabulary.question_matches_topic(text, topic),
                                    f"{os.path.basename(path)}:{topic}:{key}")
                    checked += 1
        self.assertGreater(checked, 0)

    def test_response_module_declares_no_urgency_authority(self):
        source_path = os.path.join(os.path.dirname(__file__), "..", "virtual_doctor",
                                   "response.py")
        with open(source_path, encoding="utf-8") as handle:
            source = handle.read()
        self.assertNotIn("urgency =", source.replace("self.urgency =", ""))
        self.assertNotIn("merge_urgency", source)


if __name__ == "__main__":
    unittest.main()
