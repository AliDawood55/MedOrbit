"""
Virtual Doctor Report Uncertainty — behavior tests.

The STT Confirmation + Clinical Correction Layer (interview_engine.py) can
leave three markers in patient_profile: pending_confirmation,
confirmed_fields, and uncertain_fields (see
interview_engine._apply_confirmation_layer, _mark_confirmed). This file
pins the FIXED report_generator.py behavior, after the Virtual Doctor
Report Uncertainty Implementation Batch: build_report_data() now passes
those three markers through into the report dict, and _render_html() /
_build_history_narrative() use them (via _field_status/
_format_uncertainty_label) to visibly mark a present-but-not-yet-verified
fact instead of rendering it identically to a confirmed one.

This file was originally written (same name, mostly the same test classes)
to pin the PRE-fix limitation — see git history for that version. It is
updated here to assert the corrected, desired behavior, using the same
"characterize -> fix -> verify" discipline as every other test file in this
session.

Two layers are tested, matching the two testable units report_generator.py
actually exposes:
  - build_report_data(session_id): async, needs the DB pool (mocked here,
    the same way every other virtual_doctor test in this repo mocks it —
    no real DB, Ollama, or network access anywhere in this file).
  - _render_html(report) / _build_history_narrative(report, lang, ...):
    pure, synchronous functions that take an already-built report dict —
    called directly with hand-built dicts, so no PDF is ever rendered and
    WeasyPrint/pdf_worker.py are never invoked.
"""

import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import report_generator


def _fake_session(profile, chief_complaint=None, urgency_level=None,
                  session_id="public-id", language="ar"):
    return {
        "id": "row-id", "session_id": session_id, "language": language,
        "chief_complaint": chief_complaint,
        "patient_profile": json.dumps(profile),
        "urgency_level": urgency_level,
        "recommended_specialty_id": None,
        "differential": None,
        "created_at": None,
    }


async def _build(profile, **session_kwargs):
    """Runs build_report_data() against a mocked pool holding `profile` as
    the session's patient_profile, with no real DB access."""
    fake_session = _fake_session(profile, **session_kwargs)
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=fake_session)

    with patch.object(report_generator, "get_pool", new=AsyncMock(return_value=fake_pool)):
        return await report_generator.build_report_data(fake_session["session_id"])


def _base_report(**overrides):
    report = {
        "report_id": "11111111-1111-1111-1111-111111111111",
        "session_id": "public-id",
        "generated_at": "2026-01-01T00:00:00+00:00",
        "language": "ar",
        "patient_info": {
            "session_reference": "public-i",
            "interview_date": None,
            "language": "ar",
            "name": None,
            "age": None,
        },
        "chief_complaint": None,
        "chief_complaint_description": None,
        "symptoms_summary": {},
        "detected_symptoms": [],
        "differential": [],
        "urgency_level": "routine",
        "recommended_specialty_name_en": None,
        "recommended_specialty_name_ar": None,
        "recommended_next_step": None,
        "ai_confidence": None,
        "sources": [],
        "confirmed_fields": {},
        "uncertain_fields": {},
        "pending_confirmation": None,
    }
    report.update(overrides)
    return report



class TestUnconfirmedNameVisiblyMarked(unittest.IsolatedAsyncioTestCase):
    async def test_build_report_data_passes_confirmed_fields_through(self):
        profile = {"name": "درج", "confirmed_fields": {"name": False}, "uncertain_fields": {"name": "درج"}}
        report = await _build(profile)

        self.assertEqual(report["patient_info"]["name"], "درج")
        self.assertEqual(report["confirmed_fields"], {"name": False})
        self.assertEqual(report["uncertain_fields"], {"name": "درج"})

    def test_render_html_marks_uncertain_name_with_arabic_label(self):
        report = _base_report(
            patient_info={**_base_report()["patient_info"], "name": "درج"},
            confirmed_fields={"name": False},
            uncertain_fields={"name": "درج"},
        )
        html = report_generator._render_html(report)

        self.assertIn("<td>درج (غير مؤكد)</td>", html)

    def test_render_html_marks_uncertain_name_with_english_label(self):
        report = _base_report(
            language="en",
            patient_info={**_base_report()["patient_info"], "name": "Draj"},
            confirmed_fields={"name": False},
            uncertain_fields={"name": "Draj"},
        )
        html = report_generator._render_html(report)

        self.assertIn("<td>Draj (unconfirmed)</td>", html)



class TestUncertainChiefComplaintVisiblyMarked(unittest.IsolatedAsyncioTestCase):
    async def test_build_report_data_passes_uncertain_chief_complaint_through(self):
        profile = {
            "chief_complaint_description": "عندي صدق شديد فجأة",
            "uncertain_fields": {"chief_complaint": "عندي صدق شديد فجأة"},
        }
        report = await _build(profile)

        self.assertEqual(report["chief_complaint_description"], "عندي صدق شديد فجأة")
        self.assertEqual(report["uncertain_fields"], {"chief_complaint": "عندي صدق شديد فجأة"})

    def test_render_html_marks_uncertain_chief_complaint(self):
        report = _base_report(
            chief_complaint_description="عندي صدق شديد فجأة",
            uncertain_fields={"chief_complaint": "عندي صدق شديد فجأة"},
        )
        html = report_generator._render_html(report)

        self.assertIn("عندي صدق شديد فجأة (غير مؤكد)", html)



class TestPendingConfirmationVisible(unittest.IsolatedAsyncioTestCase):
    def test_pending_name_shows_heard_value_marked_pending(self):
        """No confirmed name is stored yet (see interview_engine
        ._apply_confirmation_layer — a suspicious name is never written to
        profile["name"] until resolved), so the only candidate to show is
        the pending confirmation's "heard" text."""
        report = _base_report(
            pending_confirmation={
                "field": "name", "heard": "درج", "suggested": None,
                "question": "هل سمعت اسمك بشكل صحيح: درج؟", "attempts": 0,
            },
        )
        html = report_generator._render_html(report)

        self.assertIn("<td>درج (بانتظار التأكيد)</td>", html)

    def test_pending_chief_complaint_shows_suggested_value_marked_pending(self):
        report = _base_report(
            chief_complaint_description=None,
            pending_confirmation={
                "field": "chief_complaint", "heard": "عندي صدق شديد فجأة",
                "suggested": "صداع شديد بدأ فجأة",
                "question": "هل تقصد صداع شديد بدأ فجأة؟", "attempts": 0,
            },
        )
        html = report_generator._render_html(report)

        self.assertIn("صداع شديد بدأ فجأة (بانتظار التأكيد)", html)



class TestConfirmedFieldsRenderNormally(unittest.IsolatedAsyncioTestCase):
    def test_confirmed_name_has_no_uncertainty_suffix(self):
        report = _base_report(
            patient_info={**_base_report()["patient_info"], "name": "علي"},
            confirmed_fields={"name": True},
        )
        html = report_generator._render_html(report)

        self.assertIn("<td>علي</td>", html)
        self.assertNotIn("غير مؤكد", html)
        self.assertNotIn("بانتظار التأكيد", html)

    def test_field_never_touched_by_confirmation_layer_also_renders_normally(self):
        """A field that simply never appears in confirmed_fields/
        uncertain_fields at all (e.g. today, "age" — the confirmation layer
        added in the prior batch never touches it) must render exactly as
        before this batch: plain, no suffix."""
        report = _base_report(
            patient_info={**_base_report()["patient_info"], "age": 34},
        )
        html = report_generator._render_html(report)

        self.assertIn("34 <span class='unit'>سنة</span></td>", html)
        self.assertNotIn("غير مؤكد", html)
        self.assertNotIn("بانتظار التأكيد", html)



class TestMissingFieldsStillRenderAsMissing(unittest.IsolatedAsyncioTestCase):
    def test_absent_name_shows_not_collected_note_not_a_blank_or_pending_label(self):
        report = _base_report()
        html = report_generator._render_html(report)

        self.assertIn(
            "<td><span class='muted'>لم يتم جمعها خلال هذه المقابلة.</span></td>", html,
        )
        self.assertNotIn("بانتظار التأكيد", html)

    def test_absent_chief_complaint_still_shows_not_collected(self):
        report = _base_report()
        html = report_generator._render_html(report)

        self.assertIn(
            "<div class=\"lead\"><span class='muted'>لم يتم جمعها خلال هذه المقابلة.</span></div>", html,
        )



class TestConfirmationMetadataNotRenderedAsSymptoms(unittest.IsolatedAsyncioTestCase):
    async def test_build_report_data_excludes_confirmation_keys_from_symptoms_summary(self):
        profile = {
            "duration": "3 days",
            "confirmed_fields": {"duration": True},
            "uncertain_fields": {"name": "درج"},
            "pending_confirmation": {"field": "chief_complaint", "heard": "x", "suggested": None,
                                     "question": "q", "attempts": 0},
        }
        report = await _build(profile)

        self.assertEqual(report["symptoms_summary"], {"duration": "3 days"})
        self.assertNotIn("confirmed_fields", report["symptoms_summary"])
        self.assertNotIn("uncertain_fields", report["symptoms_summary"])
        self.assertNotIn("pending_confirmation", report["symptoms_summary"])

    def test_uncertain_symptom_row_is_marked_not_dropped(self):
        """A symptoms_summary key that DOES appear in uncertain_fields (not
        exercised by today's interview_engine, which only ever flags name/
        chief_complaint, but the mechanism is generic) is marked, not
        silently rendered as fact and not silently removed."""
        report = _base_report(
            symptoms_summary={"duration": "يومين"},
            uncertain_fields={"duration": "يومين"},
        )
        html = report_generator._render_html(report)

        self.assertIn("يومين (غير مؤكد)", html)

    def test_confirmed_symptom_row_unmarked(self):
        report = _base_report(
            symptoms_summary={"duration": "يومين"},
            confirmed_fields={"duration": True},
        )
        html = report_generator._render_html(report)

        self.assertIn("<td>يومين</td>", html)



class TestHistoryNarrativeReflectsUncertainty(unittest.IsolatedAsyncioTestCase):
    def test_uncertain_chief_complaint_marked_in_narrative(self):
        report = _base_report(
            chief_complaint_description="عندي صدق شديد فجأة",
            symptoms_summary={"duration": "منذ ساعة"},
            uncertain_fields={"chief_complaint": "عندي صدق شديد فجأة"},
        )
        narrative = report_generator._build_history_narrative(
            report, "ar", report["confirmed_fields"], report["uncertain_fields"],
            report["pending_confirmation"],
        )

        self.assertIn("عندي صدق شديد فجأة (غير مؤكد)", narrative)

    def test_confirmed_chief_complaint_unmarked_in_narrative(self):
        report = _base_report(
            chief_complaint_description="صداع شديد بدأ فجأة",
            confirmed_fields={"chief_complaint": True},
        )
        narrative = report_generator._build_history_narrative(
            report, "ar", report["confirmed_fields"], report["uncertain_fields"],
            report["pending_confirmation"],
        )

        self.assertIn("صداع شديد بدأ فجأة", narrative)
        self.assertNotIn("غير مؤكد", narrative)

    def test_default_arguments_keep_old_two_arg_call_backward_compatible(self):
        """A caller that still invokes _build_history_narrative(report, lang)
        with no uncertainty args (as this file's pre-fix version did) keeps
        working exactly as before — every field resolves to "normal" status."""
        report = _base_report(
            chief_complaint_description="صداع شديد بدأ فجأة",
            uncertain_fields={"chief_complaint": "..."},
        )
        narrative = report_generator._build_history_narrative(report, "ar")

        self.assertEqual(narrative, "صداع شديد بدأ فجأة")


if __name__ == "__main__":
    unittest.main()
