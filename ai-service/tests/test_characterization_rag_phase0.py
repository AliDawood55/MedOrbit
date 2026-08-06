"""
Characterization tests — RAG Phase 0.

Pin down CURRENT behavior of virtual_doctor/{retrieval,memory,planner,
reasoning,interview_engine}.py before the RAG/performance roadmap changes:
  1. moving blocking requests.post calls off the event loop (planner/reasoning)
  2. parallelizing memory.load_recent() + retrieval.retrieve_for_turn()
  3. parallelizing symptom_engine.match() + retrieval.retrieve_for_profile()

These tests intentionally pin existing behavior, including quirks that are
not necessarily ideal (e.g. _build_turn_context() currently discarding an
already-successful branch when the other branch raises), so a later
refactor can be verified as behavior-preserving. No real network or
database connections are made anywhere in this file.
"""

import asyncio
import os
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import retrieval
from virtual_doctor import memory
from virtual_doctor import planner
from virtual_doctor import reasoning
from virtual_doctor import interview_engine
from virtual_doctor.planner import LLMPlanner, PlannerError, PlannerInput


# ===========================================================================
# A. virtual_doctor/retrieval.py
# ===========================================================================

class TestRetrievalQueryConstruction(unittest.TestCase):
    """Pure functions: query building, citation, context formatting."""

    def test_build_turn_query_english_complaint(self):
        query = retrieval.build_turn_query("I have chest pain for 3 hours", "chest_pain")
        self.assertEqual(query, "chest pain. chest pain. duration. I have chest pain for 3 hours")

    def test_build_turn_query_arabic_complaint(self):
        query = retrieval.build_turn_query("عندي ألم في الصدر", "chest_pain")
        self.assertEqual(query, "chest pain. chest pain. عندي ألم في الصدر")

    def test_build_turn_query_palestinian_dialect_phrase(self):
        # "بطني بتوجعني كتير" (dialect: "my stomach really hurts") has no
        # canonical complaint yet (None), so only infer_topics() anchors it —
        # "بطن" substring-matches TOPIC_LEXICON's abdominal-pain entry.
        query = retrieval.build_turn_query("بطني بتوجعني كتير", None)
        self.assertEqual(query, "abdominal pain. بطني بتوجعني كتير")
        self.assertEqual(retrieval.infer_topics("بطني بتوجعني كتير"), ["abdominal pain"])

    def test_build_profile_query_with_realistic_profile(self):
        query = retrieval.build_profile_query(
            "chest_pain",
            {"duration": "3 hours", "radiation": "left arm", "empty_field": ""},
        )
        # Empty-string fields are dropped; only non-empty string values are appended.
        self.assertEqual(query, "chest pain. duration: 3 hours. radiation: left arm")

    def test_build_profile_query_unknown_complaint_falls_back_to_complaint_name(self):
        query = retrieval.build_profile_query("generic", {})
        self.assertEqual(query, "generic")

    def test_cite_single_page(self):
        self.assertEqual(retrieval.cite({"page_start": 59, "page_end": 59}), "p. 59")

    def test_cite_page_range(self):
        self.assertEqual(retrieval.cite({"page_start": 114, "page_end": 115}), "pp. 114-115")

    def test_cite_no_pages(self):
        self.assertEqual(retrieval.cite({"page_start": None, "page_end": None}), "n.p.")

    def test_format_context_empty_chunks_returns_empty_string(self):
        self.assertEqual(retrieval.format_context([]), "")

    def test_format_context_renders_labelled_passages_with_citation(self):
        chunks = [{
            "text": "Chest pain assessment guideline text here.",
            "source": "Macleods", "page_start": 59, "page_end": 59, "score": 0.71,
        }]
        result = retrieval.format_context(chunks)
        self.assertEqual(
            result,
            "MEDICAL CONTEXT — verbatim passages retrieved from Macleods. "
            "Treat these as your primary evidence:\n\n"
            "[1] (p. 59) Chest pain assessment guideline text here.\n",
        )

    def test_turn_cache_key_is_deterministic(self):
        key1 = retrieval.turn_cache_key("hello", "headache", "en")
        key2 = retrieval.turn_cache_key("hello", "headache", "en")
        self.assertEqual(key1, key2)
        self.assertNotEqual(key1, retrieval.turn_cache_key("hello", "chest_pain", "en"))


class TestRetrievalFailSoft(unittest.IsolatedAsyncioTestCase):
    """retrieve_for_turn() must never raise, regardless of what fails."""

    def setUp(self):
        retrieval.reset_stats_for_tests()

    def tearDown(self):
        retrieval.reset_stats_for_tests()

    async def test_retrieve_for_turn_returns_empty_list_when_embedding_fails(self):
        with patch.object(
            retrieval.requests, "post",
            side_effect=requests.exceptions.ConnectionError("ollama unreachable"),
        ) as mock_post, patch.object(
            retrieval, "get_pool", new=AsyncMock(side_effect=AssertionError("DB must not be touched"))
        ):
            chunks = await retrieval.retrieve_for_turn("I have a headache", "headache", "en")

        self.assertEqual(chunks, [])
        mock_post.assert_called_once()  # only the embed call, DB never reached

    async def test_retrieve_for_turn_returns_empty_list_when_db_search_fails(self):
        fake_embed_response = MagicMock()
        fake_embed_response.status_code = 200
        fake_embed_response.raise_for_status = MagicMock()
        fake_embed_response.json.return_value = {"embeddings": [[0.1, 0.2, 0.3]]}

        fake_pool = AsyncMock()
        fake_pool.fetch = AsyncMock(side_effect=Exception("relation does not exist"))

        with patch.object(retrieval.requests, "post", return_value=fake_embed_response), \
             patch.object(retrieval, "get_pool", new=AsyncMock(return_value=fake_pool)):
            chunks = await retrieval.retrieve_for_turn("I have a headache", "headache", "en")

        self.assertEqual(chunks, [])
        fake_pool.fetch.assert_awaited_once()

    async def test_retrieve_returns_empty_list_for_blank_query(self):
        chunks = await retrieval.retrieve("   ")
        self.assertEqual(chunks, [])

    async def test_search_filters_out_scores_below_threshold(self):
        fake_pool = AsyncMock()
        fake_pool.fetch = AsyncMock(return_value=[
            {"chunk_text": "high relevance", "source": "book", "page_start": 1, "page_end": 1,
             "score": retrieval.RAG_MIN_SCORE + 0.05},
            {"chunk_text": "below floor", "source": "book", "page_start": 2, "page_end": 2,
             "score": retrieval.RAG_MIN_SCORE - 0.05},
        ])
        with patch.object(retrieval, "get_pool", new=AsyncMock(return_value=fake_pool)):
            chunks = await retrieval._search([0.1, 0.2, 0.3])

        self.assertEqual(len(chunks), 1)
        self.assertEqual(chunks[0]["text"], "high relevance")


# ===========================================================================
# B. virtual_doctor/memory.py
# ===========================================================================

class TestMemoryLoadRecent(unittest.IsolatedAsyncioTestCase):

    async def test_load_recent_success_returns_oldest_first(self):
        fake_pool = AsyncMock()
        # DB returns DESC (newest first); load_recent reverses to oldest-first.
        fake_pool.fetch = AsyncMock(return_value=[
            {"role": "doctor", "message_text": "second"},
            {"role": "patient", "message_text": "first"},
        ])
        with patch.object(memory, "get_pool", new=AsyncMock(return_value=fake_pool)):
            history = await memory.load_recent("session-row-id")

        self.assertEqual(history, [
            {"role": "patient", "text": "first"},
            {"role": "doctor", "text": "second"},
        ])

    async def test_load_recent_empty_result(self):
        fake_pool = AsyncMock()
        fake_pool.fetch = AsyncMock(return_value=[])
        with patch.object(memory, "get_pool", new=AsyncMock(return_value=fake_pool)):
            history = await memory.load_recent("session-row-id")

        self.assertEqual(history, [])

    async def test_load_recent_database_failure_degrades_to_empty_list(self):
        with patch.object(
            memory, "get_pool", new=AsyncMock(side_effect=Exception("connection refused"))
        ):
            history = await memory.load_recent("session-row-id")

        self.assertEqual(history, [])  # never raises

    async def test_load_recent_truncates_long_messages(self):
        long_text = "x" * (memory.MAX_MESSAGE_CHARS + 50)
        fake_pool = AsyncMock()
        fake_pool.fetch = AsyncMock(return_value=[{"role": "patient", "message_text": long_text}])
        with patch.object(memory, "get_pool", new=AsyncMock(return_value=fake_pool)):
            history = await memory.load_recent("session-row-id")

        self.assertEqual(len(history[0]["text"]), memory.MAX_MESSAGE_CHARS)

    async def test_doctor_turns_database_failure_degrades_to_empty_list(self):
        with patch.object(
            memory, "get_pool", new=AsyncMock(side_effect=Exception("db down"))
        ):
            turns = await memory.doctor_turns("session-row-id")
        self.assertEqual(turns, [])

    def test_format_history_empty_messages_returns_empty_string(self):
        self.assertEqual(memory.format_history([]), "")

    def test_format_history_localizes_role_labels(self):
        messages = [{"role": "patient", "text": "hello"}, {"role": "doctor", "text": "hi"}]
        self.assertEqual(memory.format_history(messages, "en"), "Patient: hello\nDoctor: hi")
        self.assertEqual(memory.format_history(messages, "ar"), "المريض: hello\nالطبيب: hi")


# ===========================================================================
# C. virtual_doctor/planner.py
# ===========================================================================

def _fake_ollama_chat_response(content: str) -> MagicMock:
    response = MagicMock()
    response.raise_for_status = MagicMock()
    response.json.return_value = {"message": {"content": content}}
    return response


def _planner_ctx(**overrides) -> PlannerInput:
    defaults = dict(
        message="I have a headache",
        lang="en",
        phase="interviewing",
        chief_complaint="headache",
        profile={"duration": "2 days"},
        entities={},
        history=[],
        chunks=[],
        context_block="",
        turn_index=2,
        asked_questions=[],
    )
    defaults.update(overrides)
    return PlannerInput(**defaults)


class TestLLMPlannerCharacterization(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        self.llm_planner = LLMPlanner(
            texts={},
            # Only reached if ctx.phase == "intake"; every ctx here uses
            # phase="interviewing", but Python still evaluates these dict
            # lookups as call arguments, so real callables must be present.
            helpers={"extract_name": lambda m: m, "extract_age": lambda m: None},
            validators={
                "text_matches_language": reasoning._text_matches_language,
                "looks_coherent": reasoning._looks_coherent,
            },
        )

    async def test_successful_response_is_parsed_into_planner_result(self):
        content = (
            '{"chief_complaint": "headache", '
            '"findings": {"duration": "2 days"}, '
            '"next_question": "Where exactly is the pain located?"}'
        )
        with patch.object(planner.requests, "post", return_value=_fake_ollama_chat_response(content)):
            result = await self.llm_planner.plan(_planner_ctx())

        self.assertEqual(result.reply, "Where exactly is the pain located?")
        self.assertEqual(result.chief_complaint, "headache")
        self.assertEqual(result.phase, "interviewing")
        self.assertEqual(result.source, "llm")
        self.assertFalse(result.ready_for_diagnosis)

    async def test_timeout_raises_planner_error(self):
        with patch.object(
            planner.requests, "post", side_effect=requests.exceptions.Timeout("timed out")
        ):
            with self.assertRaises(PlannerError):
                await self.llm_planner.plan(_planner_ctx())

    async def test_connection_error_raises_planner_error(self):
        with patch.object(
            planner.requests, "post", side_effect=requests.exceptions.ConnectionError("unreachable")
        ):
            with self.assertRaises(PlannerError):
                await self.llm_planner.plan(_planner_ctx())

    async def test_unparseable_json_content_raises_planner_error(self):
        with patch.object(
            planner.requests, "post", return_value=_fake_ollama_chat_response("not json at all {{{")
        ):
            with self.assertRaises(PlannerError):
                await self.llm_planner.plan(_planner_ctx())

    async def test_malformed_http_response_raises_planner_error(self):
        bad_response = MagicMock()
        bad_response.raise_for_status.side_effect = requests.exceptions.HTTPError("500 Server Error")
        with patch.object(planner.requests, "post", return_value=bad_response):
            with self.assertRaises(PlannerError):
                await self.llm_planner.plan(_planner_ctx())

    async def test_empty_next_question_raises_planner_error(self):
        content = '{"chief_complaint": "headache", "findings": {}, "next_question": ""}'
        with patch.object(planner.requests, "post", return_value=_fake_ollama_chat_response(content)):
            with self.assertRaises(PlannerError):
                await self.llm_planner.plan(_planner_ctx())

    async def test_turn_cap_forces_diagnosis_without_calling_the_provider(self):
        ctx = _planner_ctx(turn_index=planner.MAX_INTERVIEW_TURNS)
        with patch.object(planner.requests, "post") as mock_post:
            result = await self.llm_planner.plan(ctx)

        mock_post.assert_not_called()
        self.assertTrue(result.ready_for_diagnosis)
        self.assertIsNone(result.reply)
        self.assertEqual(result.source, "llm:turn-cap")


class TestPlannerFallbackToStatic(unittest.IsolatedAsyncioTestCase):
    """interview_engine._run_planner falls back to the static flow on failure."""

    async def test_run_planner_falls_back_to_static_on_planner_error(self):
        fake_primary = MagicMock()
        fake_primary.name = "llm"
        fake_primary.plan = AsyncMock(side_effect=PlannerError("boom"))

        ctx = _planner_ctx()
        with patch.object(interview_engine, "_planner", fake_primary):
            result = await interview_engine._run_planner(ctx)

        self.assertTrue(result.source.endswith("->static"))
        self.assertEqual(result.phase, "interviewing")

    async def test_run_planner_falls_back_to_static_on_unexpected_exception(self):
        fake_primary = MagicMock()
        fake_primary.name = "llm"
        fake_primary.plan = AsyncMock(side_effect=RuntimeError("unexpected"))

        ctx = _planner_ctx()
        with patch.object(interview_engine, "_planner", fake_primary):
            result = await interview_engine._run_planner(ctx)

        self.assertTrue(result.source.endswith("->static"))


# ===========================================================================
# D. virtual_doctor/reasoning.py
# ===========================================================================

class TestMoreUrgentEscalateOnly(unittest.TestCase):
    """The single safety-critical merge point: LLM can escalate, never downgrade."""

    def test_llm_cannot_downgrade_rule_engine_emergency(self):
        self.assertEqual(reasoning._more_urgent("emergency", "routine"), "emergency")

    def test_llm_cannot_downgrade_rule_engine_urgent(self):
        self.assertEqual(reasoning._more_urgent("urgent", "routine"), "urgent")

    def test_llm_can_escalate_rule_engine_routine_to_urgent(self):
        self.assertEqual(reasoning._more_urgent("routine", "urgent"), "urgent")

    def test_llm_can_escalate_rule_engine_routine_to_emergency(self):
        self.assertEqual(reasoning._more_urgent("routine", "emergency"), "emergency")

    def test_equal_urgency_levels(self):
        self.assertEqual(reasoning._more_urgent("routine", "routine"), "routine")
        self.assertEqual(reasoning._more_urgent("emergency", "emergency"), "emergency")

    def test_unrecognized_value_ranks_lowest(self):
        self.assertEqual(reasoning._more_urgent("bogus", "routine"), "routine")
        self.assertEqual(reasoning._more_urgent("routine", "bogus"), "routine")


class TestLanguageCoherenceGuards(unittest.TestCase):

    def test_text_matches_language_plain_english(self):
        self.assertTrue(reasoning._text_matches_language("Rest and drink fluids.", "en"))

    def test_text_matches_language_plain_arabic(self):
        self.assertTrue(reasoning._text_matches_language("الرجاء الراحة وشرب السوائل", "ar"))

    def test_text_matches_language_rejects_latin_mixed_into_arabic(self):
        self.assertFalse(reasoning._text_matches_language("خذ x-ray الآن", "ar"))

    def test_text_matches_language_rejects_cjk_regardless_of_requested_language(self):
        self.assertFalse(reasoning._text_matches_language("你好世界", "en"))
        self.assertFalse(reasoning._text_matches_language("你好世界", "ar"))

    def test_looks_coherent_short_text_not_penalized(self):
        self.assertTrue(reasoning._looks_coherent("ok", "en"))

    def test_looks_coherent_real_sentence_contains_common_word(self):
        self.assertTrue(reasoning._looks_coherent("the pain is sharp", "en"))

    def test_looks_coherent_letter_salad_rejected(self):
        self.assertFalse(reasoning._looks_coherent("xkq zzz plq", "en"))


class TestNormalizeLlmOutput(unittest.TestCase):

    def test_none_parsed_returns_fallback(self):
        result = reasoning._normalize_llm_output(None, "en")
        self.assertEqual(result, reasoning._fallback_llm_output("en"))

    def test_invalid_urgency_defaults_to_routine(self):
        result = reasoning._normalize_llm_output(
            {"urgency": "catastrophic", "differential": [], "recommended_next_step": "See a doctor.",
             "confidence": 0.5},
            "en",
        )
        self.assertEqual(result["urgency"], "routine")

    def test_non_list_differential_becomes_empty_list(self):
        result = reasoning._normalize_llm_output(
            {"urgency": "routine", "differential": "not a list", "recommended_next_step": "x",
             "confidence": 0.5},
            "en",
        )
        self.assertEqual(result["differential"], [])

    def test_confidence_clamped_to_valid_range(self):
        high = reasoning._normalize_llm_output(
            {"urgency": "routine", "differential": [], "recommended_next_step": "x", "confidence": 5},
            "en",
        )
        low = reasoning._normalize_llm_output(
            {"urgency": "routine", "differential": [], "recommended_next_step": "x", "confidence": -1},
            "en",
        )
        self.assertEqual(high["confidence"], 1.0)
        self.assertEqual(low["confidence"], 0.0)

    def test_non_numeric_confidence_defaults_to_half(self):
        result = reasoning._normalize_llm_output(
            {"urgency": "routine", "differential": [], "recommended_next_step": "x",
             "confidence": "not a number"},
            "en",
        )
        self.assertEqual(result["confidence"], 0.5)


class TestCallLlmFailSoftAndGrounding(unittest.IsolatedAsyncioTestCase):

    async def _call_llm_off_loop(self, *args, **kwargs):
        # _call_llm is a coroutine function (RAG Performance Batch R1 moved
        # its blocking requests.post off the event loop internally via
        # asyncio.to_thread), so it's awaited directly.
        return await reasoning._call_llm(*args, **kwargs)

    async def test_llm_call_failure_falls_back_to_templated_reply(self):
        with patch.object(
            reasoning.requests, "post", side_effect=requests.exceptions.ConnectionError("down")
        ):
            result = await self._call_llm_off_loop("headache", {"duration": "2 days"}, "en")

        self.assertEqual(result, reasoning._fallback_llm_output("en"))
        self.assertEqual(result["recommended_next_step"], reasoning._FALLBACK_NEXT_STEP["en"])

    async def test_ungrounded_prompt_used_when_context_block_is_empty(self):
        content = (
            '{"differential": [], "urgency": "routine", '
            '"recommended_next_step": "You should rest and drink fluids.", "confidence": 0.5}'
        )
        with patch.object(
            reasoning.requests, "post", return_value=_fake_ollama_chat_response(content)
        ) as mock_post:
            await self._call_llm_off_loop("headache", {"duration": "2 days"}, "en", context_block="")

        sent_system_message = mock_post.call_args.kwargs["json"]["messages"][0]["content"]
        self.assertEqual(sent_system_message, reasoning._SYSTEM_PROMPTS["en"])

    async def test_grounded_prompt_used_when_context_block_is_present(self):
        content = (
            '{"differential": [], "urgency": "routine", '
            '"recommended_next_step": "You should rest and drink fluids.", "confidence": 0.5}'
        )
        context_block = retrieval.format_context([{
            "text": "Some textbook passage.", "source": "Macleods",
            "page_start": 10, "page_end": 10, "score": 0.7,
        }])
        with patch.object(
            reasoning.requests, "post", return_value=_fake_ollama_chat_response(content)
        ) as mock_post:
            await self._call_llm_off_loop(
                "headache", {"duration": "2 days"}, "en", context_block=context_block
            )

        sent_system_message = mock_post.call_args.kwargs["json"]["messages"][0]["content"]
        self.assertEqual(sent_system_message, reasoning._RAG_SYSTEM_PROMPTS["en"])

    async def test_empty_retrieval_chunks_format_to_empty_context_block(self):
        # Characterizes the "retrieval returned nothing" path end-to-end at the
        # formatting boundary: an empty chunk list must produce an empty
        # context_block, which is what routes _call_llm to the ungrounded
        # system prompt (see test_ungrounded_prompt_used_when_context_block_is_empty).
        self.assertEqual(reasoning._format_medical_context([]), "")


# ===========================================================================
# E. virtual_doctor/interview_engine.py
# ===========================================================================

class TestBuildTurnContext(unittest.IsolatedAsyncioTestCase):

    async def test_includes_both_memory_history_and_retrieval_chunks(self):
        fake_history = [{"role": "patient", "text": "hi"}]
        fake_chunks = [{
            "text": "chunk", "source": "book", "page_start": 1, "page_end": 1, "score": 0.7,
        }]
        with patch.object(interview_engine.memory, "load_recent", new=AsyncMock(return_value=fake_history)), \
             patch.object(interview_engine.retrieval, "retrieve_for_turn", new=AsyncMock(return_value=fake_chunks)):
            result = await interview_engine._build_turn_context(
                {"id": "session-row-id"}, "hello", "headache", "en"
            )

        self.assertEqual(result["history"], fake_history)
        self.assertEqual(result["chunks"], fake_chunks)
        self.assertEqual(result["context_block"], retrieval.format_context(fake_chunks))
        self.assertIn("memory_ms", result)
        self.assertIn("rag_ms", result)

    async def test_memory_failure_keeps_retrieval_chunks_independent_per_branch_degradation(self):
        """RAG Performance Batch R3 (approved behavior improvement): memory and
        retrieval now run concurrently via asyncio.gather(return_exceptions=True)
        and degrade INDEPENDENTLY. A memory failure must no longer discard an
        already-successful retrieval result."""
        fake_chunks = [{"text": "chunk", "source": "book", "page_start": 1, "page_end": 1, "score": 0.7}]
        with patch.object(
            interview_engine.memory, "load_recent", new=AsyncMock(side_effect=Exception("db down"))
        ), patch.object(
            interview_engine.retrieval, "retrieve_for_turn", new=AsyncMock(return_value=fake_chunks)
        ):
            result = await interview_engine._build_turn_context(
                {"id": "session-row-id"}, "hello", "headache", "en"
            )

        self.assertEqual(result["history"], [])
        self.assertEqual(result["chunks"], fake_chunks)
        self.assertEqual(result["context_block"], retrieval.format_context(fake_chunks))
        self.assertIsInstance(result["memory_ms"], float)
        self.assertIsInstance(result["rag_ms"], float)

    async def test_retrieval_failure_keeps_memory_history_independent_per_branch_degradation(self):
        """RAG Performance Batch R3 (approved behavior improvement): a
        retrieval failure must no longer discard an already-successful
        memory history result."""
        fake_history = [{"role": "patient", "text": "hi"}]
        with patch.object(
            interview_engine.memory, "load_recent", new=AsyncMock(return_value=fake_history),
        ), patch.object(
            interview_engine.retrieval, "retrieve_for_turn",
            new=AsyncMock(side_effect=Exception("ollama down")),
        ):
            result = await interview_engine._build_turn_context(
                {"id": "session-row-id"}, "hello", "headache", "en"
            )

        self.assertEqual(result["history"], fake_history)
        self.assertEqual(result["chunks"], [])
        self.assertEqual(result["context_block"], "")
        self.assertIsInstance(result["memory_ms"], float)
        self.assertIsInstance(result["rag_ms"], float)

    async def test_both_memory_and_retrieval_failing_yields_fully_empty_context(self):
        with patch.object(
            interview_engine.memory, "load_recent", new=AsyncMock(side_effect=Exception("db down"))
        ), patch.object(
            interview_engine.retrieval, "retrieve_for_turn",
            new=AsyncMock(side_effect=Exception("ollama down")),
        ):
            result = await interview_engine._build_turn_context(
                {"id": "session-row-id"}, "hello", "headache", "en"
            )

        self.assertEqual(result["history"], [])
        self.assertEqual(result["chunks"], [])
        self.assertEqual(result["context_block"], "")


class TestEmergencyShortCircuit(unittest.IsolatedAsyncioTestCase):
    """Confirms the safety check runs, and short-circuits, before the planner
    or per-turn RAG retrieval are ever reached."""

    async def test_emergency_message_never_reaches_planner_or_retrieval(self):
        fake_session = {
            "id": "row-id", "session_id": "public-id", "language": "en",
            "phase": "interviewing", "chief_complaint": "headache",
            "patient_profile": "{}", "urgency_level": None,
            "recommended_specialty_id": None, "differential": None,
        }
        fake_pool = AsyncMock()
        fake_pool.fetchrow = AsyncMock(return_value=fake_session)
        fake_pool.execute = AsyncMock()

        build_context_mock = AsyncMock()
        run_planner_mock = AsyncMock()

        with patch.object(interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)), \
             patch.object(interview_engine, "_build_turn_context", new=build_context_mock), \
             patch.object(interview_engine, "_run_planner", new=run_planner_mock):
            result = await interview_engine.handle_message("public-id", "emergency")

        self.assertEqual(result["phase"], "complete")
        self.assertEqual(result["urgency_level"], "emergency")
        build_context_mock.assert_not_called()
        run_planner_mock.assert_not_called()

    def test_check_safety_severity_matches_known_trigger_words(self):
        self.assertEqual(interview_engine._check_safety("emergency", "en")["severity"], "emergency")
        self.assertEqual(interview_engine._check_safety("طوارئ", "ar")["severity"], "emergency")
        self.assertEqual(
            interview_engine._check_safety("I need a doctor appointment", "en")["severity"], "normal"
        )


if __name__ == "__main__":
    unittest.main()
