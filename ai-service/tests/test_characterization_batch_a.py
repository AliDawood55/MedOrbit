"""
Characterization tests — Batch A (Phase 2).

These tests pin down CURRENT behavior of db.py, chatbot/nlu/synonyms.py,
virtual_doctor/report_generator.py, and llm/llm_service.py before any
refactoring touches them. They intentionally assert existing behavior,
including quirks that are not necessarily ideal (e.g. resolve() preserving
unmatched-case text, report_generator's import-time .gitignore write),
so that Batch A refactors can be verified as behavior-preserving.

No real network or database connections are made — external calls are mocked.
"""

import asyncio
import importlib
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


class TestDbPoolCharacterization(unittest.IsolatedAsyncioTestCase):
    """db.py get_pool/close_pool, using a mocked asyncpg (no real database)."""

    def setUp(self):
        import db
        self.db = db
        self.db._pool = None  # ensure a clean singleton for each test

    def tearDown(self):
        self.db._pool = None

    async def test_get_pool_creates_pool_via_asyncpg_with_db_config(self):
        fake_pool = MagicMock()
        fake_pool._closed = False
        with patch.object(
            self.db.asyncpg, "create_pool", new=AsyncMock(return_value=fake_pool)
        ) as mock_create:
            pool = await self.db.get_pool()

        self.assertIs(pool, fake_pool)
        mock_create.assert_awaited_once()
        _, kwargs = mock_create.call_args
        self.assertEqual(kwargs["host"], self.db.DB_CONFIG["host"])
        self.assertEqual(kwargs["port"], self.db.DB_CONFIG["port"])
        self.assertEqual(kwargs["database"], self.db.DB_CONFIG["database"])
        self.assertEqual(kwargs["user"], self.db.DB_CONFIG["user"])
        self.assertEqual(kwargs["min_size"], 2)
        self.assertEqual(kwargs["max_size"], 10)
        self.assertIs(kwargs["setup"], self.db._set_search_path)
        self.assertEqual(kwargs["command_timeout"], self.db.DB_COMMAND_TIMEOUT_SECONDS)
        self.assertEqual(self.db.DB_COMMAND_TIMEOUT_SECONDS, 10)

    async def test_get_pool_returns_same_singleton_on_second_call(self):
        fake_pool = MagicMock()
        fake_pool._closed = False
        with patch.object(
            self.db.asyncpg, "create_pool", new=AsyncMock(return_value=fake_pool)
        ) as mock_create:
            pool1 = await self.db.get_pool()
            pool2 = await self.db.get_pool()

        self.assertIs(pool1, pool2)
        mock_create.assert_awaited_once()  # not re-created on second call

    async def test_get_pool_recreates_pool_if_previous_was_closed(self):
        closed_pool = MagicMock()
        closed_pool._closed = True
        self.db._pool = closed_pool

        fresh_pool = MagicMock()
        fresh_pool._closed = False
        with patch.object(
            self.db.asyncpg, "create_pool", new=AsyncMock(return_value=fresh_pool)
        ) as mock_create:
            pool = await self.db.get_pool()

        self.assertIs(pool, fresh_pool)
        mock_create.assert_awaited_once()

    async def test_close_pool_closes_and_clears_singleton(self):
        fake_pool = MagicMock()
        fake_pool._closed = False
        fake_pool.close = AsyncMock()
        self.db._pool = fake_pool

        await self.db.close_pool()

        fake_pool.close.assert_awaited_once()
        self.assertIsNone(self.db._pool)

    async def test_close_pool_is_a_no_op_when_no_pool_exists(self):
        self.db._pool = None
        await self.db.close_pool()  # must not raise
        self.assertIsNone(self.db._pool)

    async def test_set_search_path_executes_expected_statement(self):
        fake_conn = MagicMock()
        fake_conn.execute = AsyncMock()
        await self.db._set_search_path(fake_conn)
        fake_conn.execute.assert_awaited_once_with("SET search_path TO medorbit, public")


class TestSynonymEngineCharacterization(unittest.TestCase):
    """chatbot/nlu/synonyms.py — exact current resolve()/resolve_text() outputs."""

    @classmethod
    def setUpClass(cls):
        from chatbot.nlu.synonyms import SynonymEngine
        cls.engine = SynonymEngine()

    def test_resolve_arabic_variant_doctor(self):
        self.assertEqual(self.engine.resolve("دكتور"), "doctor")
        self.assertEqual(self.engine.resolve("طبيب"), "doctor")

    def test_resolve_english_canonical_passthrough(self):
        self.assertEqual(self.engine.resolve("doctor"), "doctor")
        self.assertEqual(self.engine.resolve("headache"), "headache")

    def test_resolve_mixed_case_english_word_is_returned_unchanged(self):
        # resolve() lowercases only for the lookup key, not the returned
        # fallback value: "DOCTOR" has no dict entry (only Arabic variants
        # and canonical "doctor" are keys), so it comes back unmodified.
        self.assertEqual(self.engine.resolve("DOCTOR"), "DOCTOR")

    def test_resolve_medical_synonym_case_insensitive_lookup(self):
        self.assertEqual(self.engine.resolve("Migraine"), "migraine")

    def test_resolve_unknown_term_returns_original(self):
        self.assertEqual(self.engine.resolve("unknown_term_xyz"), "unknown_term_xyz")

    def test_resolve_empty_string(self):
        self.assertEqual(self.engine.resolve(""), "")

    def test_resolve_duplicate_words_not_matched_as_a_phrase(self):
        # "دكتور دكتور" is not itself a registered multi-word variant, so
        # resolve() (single-key exact match) leaves it untouched.
        self.assertEqual(self.engine.resolve("دكتور دكتور"), "دكتور دكتور")

    def test_resolve_text_arabic_sentence(self):
        self.assertEqual(self.engine.resolve_text("انا بدي دكتور"), "انا بدي doctor")

    def test_resolve_text_lowercases_and_resolves_english(self):
        self.assertEqual(
            self.engine.resolve_text("I have a headache and migraine"),
            "i have a headache and migraine",
        )
        self.assertEqual(self.engine.resolve_text("DOCTOR please"), "doctor please")

    def test_resolve_text_duplicate_words_all_resolved(self):
        self.assertEqual(
            self.engine.resolve_text("دكتور دكتور طبيب"), "doctor doctor doctor"
        )

    def test_resolve_text_no_known_synonyms_unchanged_except_lowercasing(self):
        self.assertEqual(
            self.engine.resolve_text("random text with no synonyms"),
            "random text with no synonyms",
        )

    def test_resolve_text_empty_string(self):
        self.assertEqual(self.engine.resolve_text(""), "")

    def test_resolve_text_palestinian_dialect_attached_word_not_matched(self):
        # "عالمستشفى" glues the "عال" (to-the) prefix directly onto
        # "مستشفى" with no separating space; the \b word-boundary guard in
        # resolve_text() correctly declines to match here today. Pinning
        # this exact (non-)match so a refactor can't silently start
        # over-matching glued dialect forms.
        self.assertEqual(
            self.engine.resolve_text("بدي اروح عالمستشفى بسرعة"),
            "بدي اروح عالمستشفى بسرعة",
        )

    def test_get_synonyms_doctor_returns_all_arabic_variants(self):
        result = set(self.engine.get_synonyms("doctor"))
        expected = {
            "دكتور", "طبيب", "طبيبة", "دكتر", "دكاترة",
            "أطباء", "استشاري", "استشارية", "اخصائي", "اخصائية",
            "معالج", "حكيم",
        }
        self.assertEqual(result, expected)

    def test_get_all_canonical_forms_count_and_sample(self):
        forms = self.engine.get_all_canonical_forms()
        self.assertEqual(len(forms), 120)
        self.assertEqual(forms[:5], ["address", "allergy", "amoxicillin", "anemia", "anxiety"])
        self.assertEqual(forms, sorted(forms))

    def test_expand_query_appends_up_to_three_synonyms_in_parentheses(self):
        # get_synonyms() builds its result via list(set(...)), so which three
        # synonyms appear is not stable across interpreter runs (string hash
        # randomization) — pin the *shape* of the output, not the exact
        # synonym order, since that's the real current contract.
        result = self.engine.expand_query("doctor")
        self.assertTrue(result.startswith("doctor ("))
        parts = result[len("doctor"):].strip().split(") (")
        self.assertEqual(len(parts), 3)
        all_synonyms = set(self.engine.get_synonyms("doctor"))
        for part in parts:
            self.assertIn(part.strip("()"), all_synonyms)

    def test_find_canonical_by_substring_ranks_by_confidence(self):
        matches = self.engine.find_canonical_by_substring("I need a doctor now")
        self.assertTrue(matches)
        self.assertEqual(matches[0]["canonical"], "ct_scan")
        self.assertEqual(matches[0]["matched_phrase"], "ct")
        self.assertAlmostEqual(matches[0]["confidence"], 0.6053, places=4)


class TestReportGeneratorImportCharacterization(unittest.TestCase):
    """virtual_doctor/report_generator.py — import-time filesystem behavior.

    RAG/Batch A3 (approved behavior improvement): importing this module must
    no longer write to disk. Filesystem setup is deferred to
    _ensure_report_output_dirs(), called only from the actual PDF-rendering
    path. These tests characterize that new contract, not the old
    import-time side effect.
    """

    def test_import_does_not_write_or_modify_any_file(self):
        import virtual_doctor.report_generator as report_generator

        with patch.object(Path, "mkdir") as mock_mkdir, \
             patch.object(Path, "write_text") as mock_write_text:
            importlib.reload(report_generator)

        mock_mkdir.assert_not_called()
        mock_write_text.assert_not_called()

    def test_reports_and_assets_dir_constants(self):
        import virtual_doctor.report_generator as report_generator

        module_dir = Path(report_generator.__file__).resolve().parent
        self.assertEqual(report_generator._ASSETS_DIR, module_dir / "assets")
        self.assertEqual(report_generator._REPORTS_DIR, module_dir / "generated" / "reports")

    def test_ensure_report_output_dirs_creates_directory_and_gitignore_on_demand(self):
        import virtual_doctor.report_generator as report_generator

        with tempfile.TemporaryDirectory() as tmp:
            fake_reports_dir = Path(tmp) / "generated" / "reports"
            with patch.object(report_generator, "_REPORTS_DIR", fake_reports_dir):
                report_generator._ensure_report_output_dirs()

                self.assertTrue(fake_reports_dir.exists())
                gitignore_path = fake_reports_dir.parent / ".gitignore"
                self.assertTrue(gitignore_path.exists())
                self.assertEqual(gitignore_path.read_text(encoding="utf-8"), "*\n!.gitignore\n")

                # Idempotent: calling again must not raise or change the content.
                report_generator._ensure_report_output_dirs()
                self.assertEqual(gitignore_path.read_text(encoding="utf-8"), "*\n!.gitignore\n")

    def test_render_pdf_isolated_calls_ensure_output_dirs_before_writing(self):
        import virtual_doctor.report_generator as report_generator

        with patch.object(report_generator, "_ensure_report_output_dirs") as mock_ensure, \
             patch.object(report_generator.subprocess, "run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            with patch.object(Path, "exists", return_value=True):
                report_generator._render_pdf_isolated("<html></html>", Path("fake.pdf"))

        mock_ensure.assert_called_once()

    def test_public_api_still_available_after_the_change(self):
        import virtual_doctor.report_generator as report_generator

        self.assertTrue(asyncio.iscoroutinefunction(report_generator.generate_report))
        self.assertTrue(asyncio.iscoroutinefunction(report_generator.get_report_pdf_path))
        self.assertTrue(issubclass(report_generator.PdfGenerationUnavailable, Exception))
        self.assertEqual(report_generator._PDF_TIMEOUT_SECONDS, 90)
        self.assertTrue(callable(report_generator._ensure_report_output_dirs))

    def test_pdf_generation_unavailable_exception_exists(self):
        import virtual_doctor.report_generator as report_generator

        self.assertTrue(issubclass(report_generator.PdfGenerationUnavailable, Exception))

    def test_pdf_timeout_seconds_constant_unchanged(self):
        import virtual_doctor.report_generator as report_generator

        self.assertEqual(report_generator._PDF_TIMEOUT_SECONDS, 90)


class TestLlmServiceFallbackCharacterization(unittest.TestCase):
    """llm/llm_service.py — fallback replies on provider failure, no real network."""

    def setUp(self):
        import llm.llm_service as llm_service
        self.llm_service = llm_service

    def test_timeout_falls_back_to_timeout_reply(self):
        import requests

        with patch.object(
            self.llm_service.requests, "post", side_effect=requests.exceptions.Timeout()
        ):
            reply_ar = self.llm_service.generate_response("مرحبا", "{}", lang="ar")
            reply_en = self.llm_service.generate_response("hello", "{}", lang="en")

        self.assertEqual(reply_ar, self.llm_service._get_timeout_reply("ar"))
        self.assertEqual(reply_en, self.llm_service._get_timeout_reply("en"))
        self.assertEqual(reply_en, "The service is taking too long. Please try again.")

    def test_connection_error_falls_back_to_unavailable_reply(self):
        import requests

        with patch.object(
            self.llm_service.requests,
            "post",
            side_effect=requests.exceptions.ConnectionError(),
        ):
            reply = self.llm_service.generate_response("hello", "{}", lang="en")

        self.assertEqual(reply, self.llm_service._get_unavailable_reply("en"))
        self.assertEqual(reply, "AI service is not available right now. Please try again later.")

    def test_generic_exception_falls_back_to_error_reply(self):
        with patch.object(
            self.llm_service.requests, "post", side_effect=ValueError("boom")
        ):
            reply = self.llm_service.generate_response("hello", "{}", lang="en")

        self.assertEqual(reply, self.llm_service._get_error_reply("en"))
        self.assertEqual(reply, "An error occurred. Please try again.")

    def test_empty_llm_response_falls_back_to_fallback_reply(self):
        fake_response = MagicMock()
        fake_response.json.return_value = {"response": "   "}

        with patch.object(self.llm_service.requests, "post", return_value=fake_response):
            reply = self.llm_service.generate_response("hello", "{}", lang="en")

        self.assertEqual(reply, self.llm_service._get_fallback_reply("en"))
        self.assertEqual(reply, "Thank you for your inquiry. How can I help you further?")

    def test_successful_response_is_returned_stripped_and_untouched(self):
        fake_response = MagicMock()
        fake_response.json.return_value = {"response": "  Take rest and drink fluids.  "}

        with patch.object(self.llm_service.requests, "post", return_value=fake_response) as mock_post:
            reply = self.llm_service.generate_response("I have a headache", "{}", lang="en")

        self.assertEqual(reply, "Take rest and drink fluids.")
        mock_post.assert_called_once()
        _, kwargs = mock_post.call_args
        self.assertEqual(kwargs["timeout"], 60)
        self.assertEqual(kwargs["json"]["model"], self.llm_service.MODEL_NAME)
        self.assertEqual(kwargs["json"]["stream"], False)

    def test_no_real_network_request_is_ever_made(self):
        # Guard for the test file itself: OLLAMA_URL must never be hit for real.
        with patch.object(self.llm_service.requests, "post") as mock_post:
            mock_post.return_value.json.return_value = {"response": "ok"}
            self.llm_service.generate_response("hello", "{}", lang="en")
            mock_post.assert_called_once()
            called_url = mock_post.call_args[0][0]
            self.assertEqual(called_url, self.llm_service.OLLAMA_URL)


if __name__ == "__main__":
    unittest.main()
