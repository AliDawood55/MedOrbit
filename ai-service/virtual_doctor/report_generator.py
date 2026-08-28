"""
Virtual Doctor — consultation report (Track A, Phase 3).

Assembles a structured report from a completed interview session and
renders it to a bilingual, RTL-aware PDF via WeasyPrint. The report is
generated in whichever language the session was conducted in (this module
does not produce one combined AR+EN document — "bilingual" here means the
renderer correctly supports either language, not that a single PDF contains
both).

WeasyPrint needs a working GTK/Pango stack to import at all (see
first_steps.html upstream docs) — that is a system-level dependency outside
this module's control, not something pip alone can provide on Windows.
"""

import asyncio
import json
import logging
import subprocess
import sys
import uuid
from html import escape as html_escape
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from db import get_pool

logger = logging.getLogger(__name__)


_MODULE_DIR = Path(__file__).resolve().parent
_ASSETS_DIR = _MODULE_DIR / "assets"
_REPORTS_DIR = _MODULE_DIR / "generated" / "reports"


def _ensure_report_output_dirs() -> None:
    """Create the generated-reports directory (and its .gitignore) on first use.

    Deferred from import time: importing this module must not write to disk —
    only actually rendering a report should. Idempotent, so it is safe to call
    on every report generation.
    """
    _REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    (_REPORTS_DIR.parent / ".gitignore").write_text("*\n!.gitignore\n", encoding="utf-8")

_URGENCY_STYLE = {
    "routine": {"fg": "#1c6b45", "bg": "#e8f4ed", "border": "#a8d5bd"},
    "urgent": {"fg": "#9a6206", "bg": "#fdf4e3", "border": "#e6c98a"},
    "emergency": {"fg": "#b3261e", "bg": "#fceded", "border": "#eab3ae"},
}
_URGENCY_NEUTRAL = {"fg": "#55666f", "bg": "#f1f4f6", "border": "#d5dee3"}
_URGENCY_ORDER = ("routine", "urgent", "emergency")

_LIKELIHOOD_COLOR = {
    "high": {"fg": "#b3261e", "bg": "#fceded"},
    "medium": {"fg": "#9a6206", "bg": "#fdf4e3"},
    "low": {"fg": "#55666f", "bg": "#f1f4f6"},
}

_URGENCY_LABEL = {
    "en": {"emergency": "Emergency", "urgent": "Urgent", "routine": "Routine"},
    "ar": {"emergency": "طارئة", "urgent": "عاجلة", "routine": "روتينية"},
}

_LIKELIHOOD_LABEL = {
    "en": {"high": "High", "medium": "Medium", "low": "Low"},
    "ar": {"high": "عالية", "medium": "متوسطة", "low": "منخفضة"},
}

_SLOT_LABELS = {
    "en": {
        "duration": "Duration",
        "severity": "Severity",
        "location": "Location",
        "location_character": "Location & character",
        "character": "Character",
        "radiation": "Radiation",
        "triggers": "Triggers",
        "appearance": "Appearance",
        "exposure": "Exposure / contact history",
        "associated_symptoms": "Associated symptoms",
    },
    "ar": {
        "duration": "المدة",
        "severity": "الشدة",
        "location": "المكان",
        "location_character": "المكان والطبيعة",
        "character": "طبيعة الألم",
        "radiation": "الانتشار",
        "triggers": "المحفزات",
        "appearance": "المظهر",
        "exposure": "التعرض / مخالطة",
        "associated_symptoms": "أعراض مرافقة",
    },
}

_LABELS = {
    "en": {
        "title": "AI Virtual Doctor — Consultation Report",
        "generated_on": "Generated on",
        "session_reference": "Session reference",
        "patient_info": "Patient information",
        "patient_name": "Name",
        "patient_age": "Age",
        "interview_date": "Interview date",
        "years": "years",
        "chief_complaint": "Chief complaint",
        "history": "History of present illness",
        "symptoms_summary": "Symptoms summary",
        "detected_symptoms": "Symptoms detected by the system",
        "differential": "Differential (AI-generated, decision support only)",
        "urgency": "Urgency level",
        "specialty": "Recommended specialty",
        "next_step": "Recommended next step",
        "confidence": "AI confidence",
        "disclaimer_title": "Disclaimer",
        "disclaimer_body": (
            "This report was produced by an AI-based preliminary assessment tool. "
            "It is not a medical diagnosis and does not replace evaluation by a licensed "
            "physician. If you are experiencing a medical emergency, seek immediate "
            "in-person care rather than relying on this report."
        ),
        "no_data": "Not collected in this interview.",
        "platform": "MedOrbit",
        "platform_tagline": "Smart Health Platform",
        "doc_kind": "Consultation Report",
        "doc_kind_sub": "AI-assisted preliminary assessment",
        "report_id": "Report ID",
        "patient_gender": "Gender",
        "sec_symptoms": "Presenting symptoms",
        "sec_differential": "AI differential diagnosis",
        "sec_urgency": "Urgency level",
        "sec_next_steps": "Recommended next steps",
        "differential_caveat": "AI-generated — decision support only, not a diagnosis.",
        "col_condition": "Possible condition",
        "col_likelihood": "Likelihood",
        "page_label": "Page",
        "page_of": "of",
        "confidential": "Confidential medical document — for the named patient and their treating clinician.",
        "references": "Reference sources",
        "references_note": "Passages from the medical reference below were retrieved and given to the AI as evidence for the differential above.",
        "page_one": "p.",
        "page_many": "pp.",
    },
    "ar": {
        "title": "الطبيب الافتراضي بالذكاء الاصطناعي — تقرير الاستشارة",
        "generated_on": "تاريخ الإصدار",
        "session_reference": "مرجع الجلسة",
        "patient_info": "معلومات المريض",
        "patient_name": "الاسم",
        "patient_age": "العمر",
        "interview_date": "تاريخ المقابلة",
        "years": "سنة",
        "chief_complaint": "الشكوى الرئيسية",
        "history": "تاريخ المرض الحالي",
        "symptoms_summary": "ملخص الأعراض",
        "detected_symptoms": "أعراض رصدها النظام",
        "differential": "التشخيص التفريقي (من الذكاء الاصطناعي، لأغراض الدعم فقط)",
        "urgency": "درجة الأولوية",
        "specialty": "التخصص الموصى به",
        "next_step": "الخطوة التالية الموصى بها",
        "confidence": "درجة ثقة الذكاء الاصطناعي",
        "disclaimer_title": "إخلاء المسؤولية",
        "disclaimer_body": (
            "تم إنشاء هذا التقرير بواسطة أداة تقييم أولي تعتمد على الذكاء الاصطناعي. "
            "وهو لا يمثل تشخيصاً طبياً ولا يغني عن تقييم طبيب مرخّص. في حال وجود حالة "
            "طارئة، يرجى طلب الرعاية الطبية الفورية شخصياً بدلاً من الاعتماد على هذا التقرير."
        ),
        "no_data": "لم يتم جمعها خلال هذه المقابلة.",
        "platform": "MedOrbit",
        "platform_tagline": "منصة طبية ذكية",
        "doc_kind": "تقرير استشارة",
        "doc_kind_sub": "تقييم أولي بمساعدة الذكاء الاصطناعي",
        "report_id": "رقم التقرير",
        "patient_gender": "الجنس",
        "sec_symptoms": "الأعراض المعروضة",
        "sec_differential": "التشخيص التفريقي بالذكاء الاصطناعي",
        "sec_urgency": "درجة الأولوية",
        "sec_next_steps": "الخطوات التالية الموصى بها",
        "differential_caveat": "مُولَّد بالذكاء الاصطناعي — لدعم القرار فقط، وليس تشخيصاً.",
        "col_condition": "حالة محتملة",
        "col_likelihood": "الاحتمالية",
        "page_label": "صفحة",
        "page_of": "من",
        "confidential": "وثيقة طبية سرية — للمريض المذكور وللطبيب المعالج فقط.",
        "references": "المصادر المرجعية",
        "references_note": "تم استرجاع المقاطع التالية من المرجع الطبي وتزويد الذكاء الاصطناعي بها كأساس للتشخيص التفريقي أعلاه.",
        "page_one": "ص.",
        "page_many": "ص.",
    },
}

_EXCLUDED_PROFILE_KEYS = {
    "chief_complaint_description",
    "associated_symptoms_detected",
    "name",
    "age",
    "pending_confirmation",
    "confirmed_fields",
    "uncertain_fields",
}

_UNCERTAIN_LABEL = {"ar": "غير مؤكد", "en": "unconfirmed"}
_PENDING_LABEL = {"ar": "بانتظار التأكيد", "en": "pending confirmation"}


def _is_field_confirmed(field: str, confirmed_fields: Dict[str, Any]) -> bool:
    return confirmed_fields.get(field) is True


def _is_field_uncertain(field: str, uncertain_fields: Dict[str, Any]) -> bool:
    return field in uncertain_fields


def _format_uncertainty_label(value: str, status: str, lang: str) -> str:
    """Appends a short, visible qualifier to an already-prepared (escaped /
    HTML-safe) `value`. status "confirmed" and "normal" return `value`
    completely unchanged — a confirmed fact, or one the confirmation layer
    never touched at all, must keep rendering exactly as it always has."""
    if status == "uncertain":
        return f"{value} ({_UNCERTAIN_LABEL[lang]})"
    if status == "pending":
        return f"{value} ({_PENDING_LABEL[lang]})"
    return value


def _field_status(
    field: str,
    confirmed_fields: Dict[str, Any],
    uncertain_fields: Dict[str, Any],
    pending_confirmation: Optional[Dict[str, Any]],
) -> str:
    """One of "pending" | "uncertain" | "confirmed" | "normal", checked in
    that priority order: a still-open confirmation for this exact field
    outranks a stale uncertain_fields entry that could be about an earlier,
    already-resolved round for the same field name."""
    if pending_confirmation and pending_confirmation.get("field") == field:
        return "pending"
    if _is_field_uncertain(field, uncertain_fields):
        return "uncertain"
    if _is_field_confirmed(field, confirmed_fields):
        return "confirmed"
    return "normal"


async def build_report_data(session_id: str) -> Optional[Dict[str, Any]]:
    """Assemble the structured report JSON for a completed session."""
    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1", session_id
    )
    if not session:
        return None

    def _load(value):
        if isinstance(value, str):
            return json.loads(value) if value else {}
        return value or {}

    lang = session["language"] if session["language"] in ("ar", "en") else "en"
    profile = _load(session["patient_profile"])
    differential = _load(session["differential"]) if session["differential"] else {}

    symptoms_summary = {
        key: value
        for key, value in profile.items()
        if key not in _EXCLUDED_PROFILE_KEYS and isinstance(value, str) and value.strip()
    }

    specialty_row = None
    if session["recommended_specialty_id"]:
        specialty_row = await pool.fetchrow(
            "SELECT name_en, name_ar FROM specialties WHERE id = $1",
            session["recommended_specialty_id"],
        )

    return {
        "report_id": str(uuid.uuid4()),
        "session_id": session_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "language": lang,
        "patient_info": {
            "session_reference": session_id[:8],
            "interview_date": session["created_at"].isoformat() if session["created_at"] else None,
            "language": lang,
            "name": profile.get("name"),
            "age": profile.get("age"),
        },
        "chief_complaint": session["chief_complaint"],
        "chief_complaint_description": profile.get("chief_complaint_description"),
        "symptoms_summary": symptoms_summary,
        "detected_symptoms": profile.get("associated_symptoms_detected", []),
        "differential": differential.get("conditions", []),
        "confirmed_fields": profile.get("confirmed_fields", {}),
        "uncertain_fields": profile.get("uncertain_fields", {}),
        "pending_confirmation": profile.get("pending_confirmation"),
        "urgency_level": session["urgency_level"] or "routine",
        "recommended_specialty_name_en": specialty_row["name_en"] if specialty_row else None,
        "recommended_specialty_name_ar": specialty_row["name_ar"] if specialty_row else None,
        "recommended_next_step": differential.get("next_step"),
        "ai_confidence": differential.get("confidence"),
        "sources": differential.get("sources", []),
    }


def _build_history_narrative(
    report: Dict[str, Any],
    lang: str,
    confirmed_fields: Optional[Dict[str, Any]] = None,
    uncertain_fields: Optional[Dict[str, Any]] = None,
    pending_confirmation: Optional[Dict[str, Any]] = None,
) -> str:
    """Plain text (the whole return value is HTML-escaped once, as a block,
    by the caller) — so uncertainty qualifiers are appended as plain text
    here too, not pre-escaped HTML. The three uncertainty args default to
    None/empty so any existing caller passing only (report, lang) keeps
    working exactly as before (every field then resolves to "normal" status,
    i.e. unchanged output)."""
    labels = _SLOT_LABELS[lang]
    confirmed_fields = confirmed_fields or {}
    uncertain_fields = uncertain_fields or {}

    complaint_text = report.get("chief_complaint_description") or ""
    if complaint_text:
        complaint_status = _field_status(
            "chief_complaint", confirmed_fields, uncertain_fields, pending_confirmation,
        )
        complaint_text = _format_uncertainty_label(complaint_text, complaint_status, lang)

    parts = [complaint_text]
    for key, value in report["symptoms_summary"].items():
        label = labels.get(key, key)
        status = _field_status(key, confirmed_fields, uncertain_fields, pending_confirmation)
        value = _format_uncertainty_label(value, status, lang)
        parts.append(f"{label}: {value}.")
    return " ".join(p for p in parts if p)


def _render_html(report: Dict[str, Any]) -> str:
    lang = report["language"]
    labels = _LABELS[lang]
    slot_labels = _SLOT_LABELS[lang]
    direction = "rtl" if lang == "ar" else "ltr"
    start = "right" if lang == "ar" else "left"
    end = "left" if lang == "ar" else "right"
    tracking = "0.3pt" if lang == "en" else "0"

    urgency = report["urgency_level"]
    urgency_style = _URGENCY_STYLE.get(urgency, _URGENCY_NEUTRAL)
    urgency_label = _URGENCY_LABEL[lang].get(urgency, urgency)

    specialty_name = report["recommended_specialty_name_ar" if lang == "ar" else "recommended_specialty_name_en"]

    def esc(value: Any) -> str:
        return html_escape(str(value), quote=False) if value is not None else ""

    info = report["patient_info"]
    confirmed_fields = report.get("confirmed_fields") or {}
    uncertain_fields = report.get("uncertain_fields") or {}
    pending_confirmation = report.get("pending_confirmation")

    def or_missing(value: str) -> str:
        """Render a value, degrading to a muted 'not collected' note."""
        return value if value else f"<span class='muted'>{labels['no_data']}</span>"

    def labeled(field: str, raw_value: Optional[str]) -> str:
        """Escaped display text for one patient_info-style field, marked
        (غير مؤكد)/(بانتظار التأكيد) when the STT confirmation layer flagged
        it. Falls back to the still-open pending confirmation's
        suggested/heard text when there is no stored value yet, so a pending
        fact stays visible (marked pending) instead of collapsing to "not
        collected". Returns "" when there is truly nothing to show, letting
        or_missing() apply exactly as before."""
        status = _field_status(field, confirmed_fields, uncertain_fields, pending_confirmation)
        value = raw_value
        if not value and status == "pending" and pending_confirmation:
            value = pending_confirmation.get("suggested") or pending_confirmation.get("heard")
        if not value:
            return ""
        return _format_uncertainty_label(esc(value), status, lang)

    age_status = _field_status("age", confirmed_fields, uncertain_fields, pending_confirmation)
    age_display = (
        _format_uncertainty_label(
            f"{esc(info['age'])} <span class='unit'>{labels['years']}</span>", age_status, lang,
        )
        if info.get("age") is not None else ""
    )
    gender_display = labeled("gender", info.get("gender"))
    interview_raw = esc((info.get("interview_date") or "")[:19].replace("T", " "))
    interview_display = f"<span class='ltr'>{interview_raw}</span>" if interview_raw else ""

    symptoms_rows = "".join(
        f"<tr><th>{esc(slot_labels.get(k, k))}</th><td>"
        f"{_format_uncertainty_label(esc(v), _field_status(k, confirmed_fields, uncertain_fields, pending_confirmation), lang)}"
        f"</td></tr>"
        for k, v in report["symptoms_summary"].items()
    ) or f"<tr><td colspan='2' class='muted pad'>{labels['no_data']}</td></tr>"

    detected = [s for s in (report.get("detected_symptoms") or []) if str(s).strip()]
    detected_block = ""
    if detected:
        chips = "".join(f"<span class='chip'>{esc(s)}</span>" for s in detected)
        detected_block = (
            f"<div class='field'>"
            f"<div class='field-label'>{labels['detected_symptoms']}</div>"
            f"<div>{chips}</div></div>"
        )

    differential_rows = ""
    for rank, cond in enumerate(report["differential"], start=1):
        likelihood = cond.get("likelihood")
        chip = _LIKELIHOOD_COLOR.get(likelihood, _LIKELIHOOD_COLOR["low"])
        likelihood_text = _LIKELIHOOD_LABEL[lang].get(likelihood, likelihood or "")
        differential_rows += (
            f"<tr><td class='rank'>{rank}</td>"
            f"<td class='cond'>{esc(cond.get('condition', ''))}</td>"
            f"<td class='lk'><span class='chip-lk' "
            f"style=\"color:{chip['fg']};background:{chip['bg']}\">"
            f"{esc(likelihood_text)}</span></td></tr>"
        )
    if not differential_rows:
        differential_rows = f"<tr><td colspan='3' class='muted pad'>{labels['no_data']}</td></tr>"

    confidence = report.get("ai_confidence")
    confidence_block = ""
    if isinstance(confidence, (int, float)):
        pct = max(0, min(100, round(confidence * 100)))
        confidence_block = (
            f"<div class='conf'><table class='conf-row'><tr>"
            f"<td>{labels['confidence']}</td><td class='conf-val'>{pct}%</td></tr></table>"
            f"<div class='meter'><div class='meter-fill' style='width:{pct}%'></div></div></div>"
        )

    sources = [s for s in (report.get("sources") or []) if isinstance(s, dict)]
    references_block = ""
    if sources:
        items = ""
        for ref in sources:
            first_page, last_page = ref.get("page_start"), ref.get("page_end")
            if first_page and last_page and last_page != first_page:
                page_label, page_value = labels["page_many"], f"{first_page}-{last_page}"
            elif first_page:
                page_label, page_value = labels["page_one"], str(first_page)
            else:
                page_label = page_value = ""
            pages = (
                f"{page_label} <span class='ltr'>{page_value}</span>" if page_value else ""
            )
            items += (
                f"<li><span class='ref-title'>{esc(ref.get('source'))}</span>"
                f"<span class='ref-pages'>{pages}</span></li>"
            )
        references_block = (
            f"<div class='refs'>"
            f"<div class='refs-head'>{labels['references']}</div>"
            f"<div class='refs-note'>{labels['references_note']}</div>"
            f"<ul class='ref-list'>{items}</ul></div>"
        )

    urgency_steps = ""
    for level in _URGENCY_ORDER:
        step = _URGENCY_STYLE[level]
        step_label = _URGENCY_LABEL[lang].get(level, level)
        if level == urgency:
            urgency_steps += (
                f"<td class='ustep uactive' style=\"background:{step['bg']};"
                f"border-color:{step['fg']};color:{step['fg']}\">"
                f"<span class='udot' style=\"background:{step['fg']}\"></span>"
                f"{step_label}</td>"
            )
        else:
            urgency_steps += f"<td class='ustep'>{step_label}</td>"

    history_text = _build_history_narrative(
        report, lang, confirmed_fields, uncertain_fields, pending_confirmation,
    )
    generated_at = report["generated_at"][:19].replace("T", " ")

    fonts_uri = (_ASSETS_DIR / "fonts").as_uri()

    return f"""<!doctype html>
<html lang="{lang}" dir="{direction}">
<head>
<meta charset="utf-8">
<title>{labels['title']}</title>
<style>
@font-face {{
  font-family: 'Cairo';
  font-weight: 400;
  src: url('{fonts_uri}/Cairo-Regular.woff') format('woff');
}}
@font-face {{
  font-family: 'Cairo';
  font-weight: 700;
  src: url('{fonts_uri}/Cairo-Bold.woff') format('woff');
}}

/* ---------- page ---------- */
@page {{
  size: A4;
  margin: 15mm 15mm 18mm;
  direction: {direction};
  @bottom-{start} {{
    content: "{labels['confidential']}";
    font-family: 'Cairo', sans-serif; font-size: 7pt; color: #93a4ae;
  }}
  @bottom-{end} {{
    content: "{labels['page_label']} " counter(page) " {labels['page_of']} " counter(pages);
    font-family: 'Cairo', sans-serif; font-size: 7pt; color: #93a4ae;
  }}
}}
body {{
  font-family: 'Cairo', sans-serif;
  direction: {direction};
  text-align: {start};
  color: #16232b;
  font-size: 10pt;
  line-height: 1.55;
  margin: 0;
}}
p {{ margin: 0; }}
.muted {{ color: #8a99a3; font-style: italic; font-weight: 400; }}
.pad {{ padding: 7pt 9pt; }}
.unit {{ font-weight: 400; color: #6b7f8a; font-size: 8.5pt; }}
/* Timestamps and IDs are Latin/neutral runs: isolate them so RTL bidi does
   not reorder "date time" into "time date". */
.ltr {{ direction: ltr; unicode-bidi: embed; display: inline-block; }}

/* ---------- masthead ---------- */
.masthead {{
  border-bottom: 2.5pt solid #0e7c86;
  padding-bottom: 7pt;
  margin-bottom: 9pt;
}}
.masthead table {{ width: 100%; border-collapse: collapse; }}
.masthead td {{ border: 0; padding: 0; vertical-align: middle; }}
.mark {{
  display: inline-block; width: 25pt; height: 25pt; line-height: 25pt;
  background: #123b5c; color: #ffffff;
  text-align: center; font-weight: 700; font-size: 13pt;
}}
.brand {{ padding-{start}: 8pt !important; }}
.brand-name {{ font-size: 14pt; font-weight: 700; color: #123b5c; }}
.brand-tag {{ font-size: 7.5pt; color: #6b7f8a; }}
.doc-kind-cell {{ text-align: {end}; }}
.doc-kind {{ font-size: 11.5pt; font-weight: 700; color: #0e7c86; }}
.doc-kind-sub {{ font-size: 7.5pt; color: #6b7f8a; }}

/* ---------- meta bar ---------- */
.metabar {{
  width: 100%; border-collapse: collapse;
  background: #f4f8fa; border: 0.5pt solid #dbe6ec;
  margin-bottom: 12pt;
}}
.metabar td {{
  padding: 5pt 9pt; vertical-align: top;
  border-{end}: 0.5pt solid #e3ecf1;
}}
.metabar td.last {{ border-{end}: 0; }}
.metabar .k {{
  display: block; color: #6b7f8a; font-size: 7pt;
  text-transform: uppercase; letter-spacing: {tracking};
}}
.metabar .v {{ font-weight: 700; color: #123b5c; font-size: 9pt; }}
.metabar .v.id {{ font-size: 7.5pt; letter-spacing: 0; }}

/* ---------- patient panel ---------- */
.panel {{ border: 0.75pt solid #cfdde5; margin-bottom: 13pt; }}
.panel-head {{
  background: #123b5c; color: #ffffff;
  font-size: 8.5pt; font-weight: 700;
  padding: 5pt 10pt;
  text-transform: uppercase; letter-spacing: {tracking};
}}
.kv {{ width: 100%; border-collapse: collapse; }}
.kv th, .kv td {{
  padding: 6pt 10pt; text-align: {start}; vertical-align: top;
  border-top: 0.5pt solid #e6eef3;
}}
.kv tr:first-child th, .kv tr:first-child td {{ border-top: 0; }}
.kv th {{ color: #6b7f8a; font-weight: 400; font-size: 8pt; width: 16%; }}
.kv td {{ font-weight: 700; font-size: 9.5pt; width: 34%; }}

/* ---------- sections ---------- */
.sec {{ margin-bottom: 12pt; break-inside: avoid; }}
.sec-head {{
  border-{start}: 3pt solid #0e7c86;
  padding-{start}: 8pt;
  margin-bottom: 6pt;
}}
.sec-num {{
  display: inline-block; width: 13pt; height: 13pt; line-height: 13pt;
  background: #0e7c86; color: #ffffff;
  text-align: center; font-size: 7.5pt; font-weight: 700;
  margin-{end}: 5pt;
}}
.sec-title {{ font-size: 11pt; font-weight: 700; color: #123b5c; }}
.sec-note {{ font-size: 7.5pt; color: #6b7f8a; }}

/* ---------- fields ---------- */
.field {{ margin-bottom: 7pt; }}
.field-label {{
  font-size: 7.5pt; color: #6b7f8a;
  text-transform: uppercase; letter-spacing: {tracking};
}}
.lead {{
  font-size: 11pt; font-weight: 700; color: #16232b;
  background: #f4f8fa; border-{start}: 2.5pt solid #0e7c86;
  padding: 6pt 10pt;
}}

/* ---------- data tables ---------- */
.dtable {{
  width: 100%; border-collapse: collapse;
  border: 0.5pt solid #dbe6ec; margin-top: 3pt;
}}
.dtable th, .dtable td {{
  text-align: {start}; padding: 5pt 9pt; font-size: 9.5pt;
  border-bottom: 0.5pt solid #e6eef3; vertical-align: top;
}}
.dtable tr:last-child th, .dtable tr:last-child td {{ border-bottom: 0; }}
.dtable thead th {{
  background: #eef5f8; color: #4a6270;
  font-size: 7.5pt; font-weight: 700;
  text-transform: uppercase; letter-spacing: {tracking};
  border-bottom: 0.5pt solid #cfdde5;
}}
.dtable tbody th {{
  width: 34%; color: #4a6270; font-weight: 400; background: #fafcfd;
}}
.chip {{
  display: inline-block; background: #eef5f8;
  border: 0.5pt solid #cfdde5; color: #2c4551;
  font-size: 8.5pt; padding: 1.5pt 7pt;
  margin-{end}: 4pt; margin-bottom: 3pt;
}}

/* ---------- differential ---------- */
.rank {{ width: 7%; color: #8a99a3; font-weight: 700; }}
.cond {{ font-weight: 700; }}
.lk {{ width: 22%; text-align: {end} !important; }}
.chip-lk {{
  display: inline-block; font-size: 8.5pt; font-weight: 700;
  padding: 1.5pt 8pt;
}}
.conf {{ margin-top: 7pt; }}
.conf-row {{ width: 100%; border-collapse: collapse; }}
.conf-row td {{ border: 0; padding: 0 0 3pt; font-size: 8.5pt; color: #4a6270; }}
.conf-val {{ text-align: {end}; font-weight: 700; color: #123b5c; }}
.meter {{ height: 5pt; background: #e6eef3; }}
.meter-fill {{ height: 5pt; background: #0e7c86; }}

/* ---------- reference sources (RAG citations) ---------- */
.refs {{
  margin-top: 8pt; padding: 7pt 10pt;
  background: #fafcfd; border: 0.5pt solid #e6eef3;
  border-{start}: 2pt solid #cfdde5;
}}
.refs-head {{
  font-size: 7.5pt; font-weight: 700; color: #4a6270;
  text-transform: uppercase; letter-spacing: {tracking};
}}
.refs-note {{ font-size: 7.5pt; color: #8a99a3; margin-bottom: 3pt; }}
.ref-list {{ list-style: none; margin: 0; padding: 0; }}
.ref-list li {{ font-size: 8.5pt; padding: 1.5pt 0; }}
.ref-title {{ color: #16232b; }}
.ref-pages {{
  color: #0e7c86; font-weight: 700; margin-{start}: 6pt;
}}

/* ---------- urgency ---------- */
.uband {{
  border: 0.75pt solid; border-{start}-width: 4pt;
  padding: 7pt 11pt; margin-bottom: 6pt;
}}
.uband-value {{ font-size: 13pt; font-weight: 700; }}
.uscale {{
  width: 100%; border-collapse: separate; border-spacing: 4pt 0;
  table-layout: fixed;
}}
.ustep {{
  border: 0.75pt solid #dbe6ec; background: #f7fafb; color: #8a99a3;
  font-size: 8.5pt; text-align: center; padding: 4pt 2pt;
}}
.uactive {{ font-weight: 700; }}
.udot {{
  display: inline-block; width: 5pt; height: 5pt;
  margin-{end}: 4pt;
}}

/* ---------- disclaimer ---------- */
.disclaimer {{
  border: 0.75pt solid #e6c98a; border-{start}-width: 3pt;
  background: #fdf8ee; color: #5c4a22;
  padding: 9pt 12pt; margin-top: 13pt; font-size: 8.5pt;
  break-inside: avoid;
}}
.disclaimer-title {{
  font-weight: 700; color: #8a5a10; font-size: 9pt; margin-bottom: 2pt;
}}
</style>
</head>
<body>

  <div class="masthead">
    <table>
      <tr>
        <td style="width:25pt"><span class="mark">M</span></td>
        <td class="brand">
          <div class="brand-name">{labels['platform']}</div>
          <div class="brand-tag">{labels['platform_tagline']}</div>
        </td>
        <td class="doc-kind-cell">
          <div class="doc-kind">{labels['doc_kind']}</div>
          <div class="doc-kind-sub">{labels['doc_kind_sub']}</div>
        </td>
      </tr>
    </table>
  </div>

  <table class="metabar">
    <tr>
      <td>
        <span class="k">{labels['report_id']}</span>
        <span class="v id ltr">{esc(report['report_id'])}</span>
      </td>
      <td>
        <span class="k">{labels['generated_on']}</span>
        <span class="v ltr">{generated_at}</span>
      </td>
      <td class="last">
        <span class="k">{labels['session_reference']}</span>
        <span class="v ltr">{esc(info.get('session_reference'))}</span>
      </td>
    </tr>
  </table>

  <div class="panel">
    <div class="panel-head">{labels['patient_info']}</div>
    <table class="kv">
      <tr>
        <th>{labels['patient_name']}</th><td>{or_missing(labeled('name', info.get('name')))}</td>
        <th>{labels['patient_age']}</th><td>{or_missing(age_display)}</td>
      </tr>
      <tr>
        <th>{labels['patient_gender']}</th><td>{or_missing(gender_display)}</td>
        <th>{labels['interview_date']}</th><td>{or_missing(interview_display)}</td>
      </tr>
    </table>
  </div>

  <div class="sec">
    <div class="sec-head">
      <span class="sec-num">1</span><span class="sec-title">{labels['sec_symptoms']}</span>
    </div>
    <div class="field">
      <div class="field-label">{labels['chief_complaint']}</div>
      <div class="lead">{or_missing(labeled('chief_complaint', report.get('chief_complaint_description')))}</div>
    </div>
    <div class="field">
      <div class="field-label">{labels['history']}</div>
      <p>{or_missing(esc(history_text))}</p>
    </div>
    <div class="field">
      <div class="field-label">{labels['symptoms_summary']}</div>
      <table class="dtable">{symptoms_rows}</table>
    </div>
    {detected_block}
  </div>

  <div class="sec">
    <div class="sec-head">
      <span class="sec-num">2</span><span class="sec-title">{labels['sec_differential']}</span>
      <div class="sec-note">{labels['differential_caveat']}</div>
    </div>
    <table class="dtable">
      <thead>
        <tr>
          <th class="rank">#</th>
          <th>{labels['col_condition']}</th>
          <th class="lk">{labels['col_likelihood']}</th>
        </tr>
      </thead>
      <tbody>{differential_rows}</tbody>
    </table>
    {confidence_block}
    {references_block}
  </div>

  <div class="sec">
    <div class="sec-head">
      <span class="sec-num">3</span><span class="sec-title">{labels['sec_urgency']}</span>
    </div>
    <div class="uband" style="background:{urgency_style['bg']};border-color:{urgency_style['border']};color:{urgency_style['fg']}">
      <div class="uband-value">{urgency_label}</div>
    </div>
    <table class="uscale"><tr>{urgency_steps}</tr></table>
  </div>

  <div class="sec">
    <div class="sec-head">
      <span class="sec-num">4</span><span class="sec-title">{labels['sec_next_steps']}</span>
    </div>
    <table class="dtable">
      <tr>
        <th>{labels['specialty']}</th>
        <td>{or_missing(esc(specialty_name))}</td>
      </tr>
      <tr>
        <th>{labels['next_step']}</th>
        <td>{or_missing(esc(report.get('recommended_next_step')))}</td>
      </tr>
    </table>
  </div>

  <div class="disclaimer">
    <div class="disclaimer-title">{labels['disclaimer_title']}</div>
    {labels['disclaimer_body']}
  </div>

</body>
</html>
"""


class PdfGenerationUnavailable(Exception):
    """PDF rendering failed or crashed. The report data itself is still valid."""


_PDF_WORKER = _MODULE_DIR / "pdf_worker.py"
_PDF_TIMEOUT_SECONDS = 90


def _render_pdf_isolated(html_string: str, pdf_path: Path) -> None:
    """Render the PDF in a child process so a native crash cannot kill us.

    PDF_ISOLATION: WeasyPrint currently aborts with 0xC0000374 (heap
    corruption) on this environment. In-process that took ai-service down
    entirely; here the worst case is a failed child and a 503.
    """
    _ensure_report_output_dirs()
    payload = json.dumps({
        "html": html_string,
        "base_url": str(_MODULE_DIR),
        "out_path": str(pdf_path),
    })

    try:
        proc = subprocess.run(
            [sys.executable, str(_PDF_WORKER)],
            input=payload,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=_PDF_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        raise PdfGenerationUnavailable(
            f"PDF worker timed out after {_PDF_TIMEOUT_SECONDS}s"
        )

    if proc.returncode != 0:
        detail = (proc.stderr or "").strip().splitlines()
        detail = detail[-1] if detail else f"exit code {proc.returncode}"
        native = {
            3221226356: "0xC0000374 STATUS_HEAP_CORRUPTION in the WeasyPrint/Pango "
                        "native stack — known environment issue, tracked separately",
            3221225477: "0xC0000005 ACCESS_VIOLATION in the WeasyPrint native stack",
        }.get(proc.returncode)
        if native:
            detail = native
        logger.error(
            "PDF worker failed (exit %s): %s — the consultation and its report "
            "data are intact; only the PDF could not be rendered.",
            proc.returncode, detail,
        )
        raise PdfGenerationUnavailable(detail)

    if not pdf_path.exists():
        raise PdfGenerationUnavailable("PDF worker reported success but wrote no file")


async def generate_report(
    session_id: str, owner_user_id: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """
    Build the report data, render it to PDF, and persist it to
    virtual_doctor_reports. Returns the report metadata (including
    report_id and pdf_path) or None if the session doesn't exist.

    Raises PdfGenerationUnavailable if the report data was built but the PDF
    could not be rendered.

    owner_user_id scopes the session lookup to the account that owns the
    consultation. It is checked BEFORE any report is built, so a caller
    supplying someone else's session id does not cause their medical data to
    be read, rendered, or written to disk. Optional only for direct in-process
    callers; every HTTP path supplies it.
    """
    if owner_user_id:
        pool = await get_pool()
        owned = await pool.fetchrow(
            "SELECT id FROM virtual_doctor_sessions WHERE session_id = $1 AND user_id = $2",
            session_id,
            uuid.UUID(owner_user_id),
        )
        if not owned:
            return None

    report = await build_report_data(session_id)
    if not report:
        return None

    html_string = _render_html(report)
    pdf_path = _REPORTS_DIR / f"{report['report_id']}.pdf"
    await asyncio.to_thread(_render_pdf_isolated, html_string, pdf_path)

    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT id FROM virtual_doctor_sessions WHERE session_id = $1", session_id
    )
    await pool.execute(
        """
        INSERT INTO virtual_doctor_reports (id, session_id, pdf_path, report_json)
        VALUES ($1, $2, $3, $4::jsonb)
        """,
        uuid.UUID(report["report_id"]),
        session["id"],
        str(pdf_path),
        json.dumps(report, ensure_ascii=False),
    )

    report["pdf_path"] = str(pdf_path)
    return report


async def get_report_pdf_path(
    report_id: str, owner_user_id: Optional[str] = None
) -> Optional[str]:
    """Path to a rendered report PDF, scoped to the account that owns it.

    A report id is a bearer token for a medical document if it is looked up on
    its own, so the owning session is joined in rather than trusted.
    """
    pool = await get_pool()
    if owner_user_id:
        row = await pool.fetchrow(
            """
            SELECT r.pdf_path
            FROM virtual_doctor_reports r
            JOIN virtual_doctor_sessions s ON s.id = r.session_id
            WHERE r.id = $1 AND s.user_id = $2
            """,
            uuid.UUID(report_id),
            uuid.UUID(owner_user_id),
        )
    else:
        row = await pool.fetchrow(
            "SELECT pdf_path FROM virtual_doctor_reports WHERE id = $1", uuid.UUID(report_id)
        )
    return row["pdf_path"] if row else None
