"""
Characterization tests — Virtual Doctor report uncertainty gap.

The STT Confirmation + Clinical Correction Layer (interview_engine.py) can
now leave three markers in patient_profile: pending_confirmation,
confirmed_fields, and uncertain_fields (see
interview_engine._apply_confirmation_layer, _mark_confirmed). This file pins
CURRENT report_generator.py behavior: it was written before any of that
existed, builds symptoms_summary/patient_info from flat profile values only,
and — confirmed by direct source reading — never references
confirmed_fields, uncertain_fields, or pending_confirmation anywhere
(`grep -n "confirmed_fields\\|uncertain_fields\\|pending_confirmation"
report_generator.py` returns zero matches). Concretely, this means an
unconfirmed name or an uncertain chief complaint renders in the report
identically to a fully confirmed one, with no marking of any kind.

This is a CHARACTERIZATION file: every test here asserts what the code
ACTUALLY does today, not what it should do. No production code is modified.
report_generator.py is read-only in this batch.

Two layers are tested, matching the two testable units report_generator.py
actually exposes:
  - build_report_data(session_id): async, needs the DB pool (mocked here,
    the same way every other virtual_doctor test in this repo mocks it —
    no real DB, Ollama, or network access anywhere in this file).
  - _render_html(report) / _build_history_narrative(report, lang): pure,
    synchronous functions that take an already-built report dict — called
    directly with hand-built dicts, so no PDF is ever rendered and
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


# A minimal, complete report dict — every top-level key _render_html actually
# reads — so tests can override just the field(s) under test without
# reverse-engineering the whole schema from the template.
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
    }
    report.update(overrides)
    return report


# ===========================================================================
# 1. build_report_data(): confirmed_fields is ignored
# ===========================================================================

class TestBuildReportDataIgnoresConfirmedFields(unittest.IsolatedAsyncioTestCase):
    async def test_unconfirmed_name_appears_in_patient_info_same_as_confirmed(self):
        """A name the STT confirmation layer explicitly marked
        confirmed_fields["name"] = False (i.e. the patient never actually
        confirmed it — see interview_engine._mark_confirmed) still renders
        in patient_info.name exactly as if it had been confirmed."""
        profile = {
            "name": "درج",
            "age": 30,
            "confirmed_fields": {"name": False, "chief_complaint": True},
        }
        report = await _build(profile)

        self.assertEqual(report["patient_info"]["name"], "درج")

    async def test_confirmed_fields_key_itself_does_not_survive_into_report_data(self):
        """confirmed_fields is dropped entirely during the profile -> report
        transformation — there is no field anywhere in the returned dict a
        future renderer could even check, confirmed vs not."""
        profile = {"name": "علي", "confirmed_fields": {"name": True}}
        report = await _build(profile)

        self.assertNotIn("confirmed_fields", report)
        self.assertNotIn("confirmed_fields", report["patient_info"])

    async def test_confirmed_fields_dict_never_leaks_into_symptoms_summary(self):
        """confirmed_fields is itself a dict value on the profile; the
        symptoms_summary comprehension's isinstance(value, str) filter
        happens to exclude it, but incidentally — not because the code knows
        what it is."""
        profile = {
            "duration": "3 days",
            "confirmed_fields": {"duration": True},
        }
        report = await _build(profile)

        self.assertEqual(report["symptoms_summary"], {"duration": "3 days"})
        self.assertNotIn("confirmed_fields", report["symptoms_summary"])


# ===========================================================================
# 2. build_report_data(): uncertain_fields is ignored
# ===========================================================================

class TestBuildReportDataIgnoresUncertainFields(unittest.IsolatedAsyncioTestCase):
    async def test_uncertain_chief_complaint_renders_with_no_marking(self):
        """A chief complaint the confirmation layer gave up on (attempts
        exhausted — see interview_engine._resolve_pending_confirmation's
        "gave_up" outcome) stores BOTH the fallback value under
        chief_complaint_description AND a copy under uncertain_fields. The
        report reads only the former; the latter is never consulted."""
        profile = {
            "chief_complaint_description": "عندي صدق شديد فجأة",
            "uncertain_fields": {"chief_complaint": "عندي صدق شديد فجأة"},
        }
        report = await _build(profile)

        self.assertEqual(report["chief_complaint_description"], "عندي صدق شديد فجأة")
        self.assertNotIn("uncertain_fields", report)

    async def test_uncertain_fields_values_do_not_appear_anywhere_in_symptoms_summary(self):
        profile = {
            "duration": "2 hours",
            "uncertain_fields": {"name": "درج", "chief_complaint": "..."},
        }
        report = await _build(profile)

        self.assertEqual(report["symptoms_summary"], {"duration": "2 hours"})


# ===========================================================================
# 3. build_report_data(): pending_confirmation (an edge case — a report
#    generated while a confirmation is still open) is also silently dropped
# ===========================================================================

class TestBuildReportDataIgnoresPendingConfirmation(unittest.IsolatedAsyncioTestCase):
    async def test_open_pending_confirmation_does_not_surface_or_break_report(self):
        profile = {
            "pending_confirmation": {
                "field": "chief_complaint", "heard": "عندي صدق شديد فجأة",
                "suggested": "صداع شديد بدأ فجأة",
                "question": "هل تقصد صداع شديد بدأ فجأة؟", "attempts": 0,
            },
        }
        report = await _build(profile)

        self.assertNotIn("pending_confirmation", report)
        self.assertEqual(report["symptoms_summary"], {})
        # No hint anywhere that a question was ever left unanswered.
        self.assertIsNone(report["chief_complaint_description"])


# ===========================================================================
# 4. _render_html(): an unconfirmed/uncertain fact renders identically to a
#    confirmed one — no badge, no muted styling, no textual marker
# ===========================================================================

class TestRenderHtmlDoesNotDistinguishUncertainty(unittest.IsolatedAsyncioTestCase):
    def test_name_cell_identical_regardless_of_confirmed_fields_presence(self):
        """_render_html() only ever reads report['patient_info']['name'] —
        confirmed_fields is not part of the report dict at all after
        build_report_data() (Section 1), but even if a future caller passed
        it through as an extra, unused key, the rendered <td> for the name is
        byte-for-byte identical either way."""
        confirmed_report = _base_report(
            patient_info={**_base_report()["patient_info"], "name": "درج"},
        )
        unconfirmed_report = _base_report(
            patient_info={**_base_report()["patient_info"], "name": "درج"},
            confirmed_fields={"name": False},  # extra key; _render_html ignores it
        )

        confirmed_html = report_generator._render_html(confirmed_report)
        unconfirmed_html = report_generator._render_html(unconfirmed_report)

        name_cell = "<td>درج</td>"
        self.assertIn(name_cell, confirmed_html)
        self.assertIn(name_cell, unconfirmed_html)
        self.assertEqual(confirmed_html, unconfirmed_html)

    def test_uncertain_name_is_not_flagged_muted_or_annotated(self):
        """The renderer's only "special" treatment of a field is or_missing()
        — a muted "not collected" note when the value is falsy. A present but
        UNCERTAIN name gets none of that: it renders through the normal,
        confident-looking bold <td>, not the muted branch."""
        report = _base_report(
            patient_info={**_base_report()["patient_info"], "name": "درج"},
        )
        html = report_generator._render_html(report)

        self.assertIn("<td>درج</td>", html)
        # The muted/no-data branch (used elsewhere in this same document for
        # genuinely missing fields like age/gender, which this fixture
        # deliberately leaves unset) is not what rendered the name specifically.
        self.assertNotIn("<span class='muted'>درج", html)

    def test_chief_complaint_lead_shows_uncertain_text_unmarked(self):
        report = _base_report(chief_complaint_description="عندي صدق شديد فجأة")
        html = report_generator._render_html(report)

        self.assertIn("عندي صدق شديد فجأة", html)
        # No "(unconfirmed)"/"reported"-style qualifier anywhere near it.
        self.assertNotIn("unconfirmed", html.lower())
        self.assertNotIn("غير مؤكد", html)


# ===========================================================================
# 5. _build_history_narrative(): uncertain chief-complaint text flows into
#    the narrative unmarked too
# ===========================================================================

class TestHistoryNarrativeDoesNotDistinguishUncertainty(unittest.IsolatedAsyncioTestCase):
    def test_uncertain_chief_complaint_text_included_verbatim(self):
        report = _base_report(
            chief_complaint_description="عندي صدق شديد فجأة",
            symptoms_summary={"duration": "منذ ساعة"},
        )
        narrative = report_generator._build_history_narrative(report, "ar")

        self.assertIn("عندي صدق شديد فجأة", narrative)
        self.assertNotIn("غير مؤكد", narrative)
        self.assertNotIn("uncertain", narrative.lower())


if __name__ == "__main__":
    unittest.main()
