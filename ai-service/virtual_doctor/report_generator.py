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
import os
import subprocess
import sys
import uuid
from html import escape as html_escape
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from db import get_pool

logger = logging.getLogger(__name__)

# NOTE: weasyprint is deliberately NOT imported here. It is loaded only inside
# pdf_worker.py, which runs as a child process — see PDF_ISOLATION below.

_MODULE_DIR = Path(__file__).resolve().parent
_ASSETS_DIR = _MODULE_DIR / "assets"
_REPORTS_DIR = _MODULE_DIR / "generated" / "reports"
_REPORTS_DIR.mkdir(parents=True, exist_ok=True)
(_REPORTS_DIR.parent / ".gitignore").write_text("*\n!.gitignore\n", encoding="utf-8")

_URGENCY_COLOR = {"emergency": "#b3261e", "urgent": "#b7791f", "routine": "#2f6d43"}
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
    },
}

# Identity fields belong in the patient-information block, not the symptoms
# table. Without "name" here the patient's name was listed as a symptom, and
# "age" was silently dropped altogether because it is an int, not a str.
_EXCLUDED_PROFILE_KEYS = {
    "chief_complaint_description",
    "associated_symptoms_detected",
    "name",
    "age",
}


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
        "urgency_level": session["urgency_level"] or "routine",
        "recommended_specialty_name_en": specialty_row["name_en"] if specialty_row else None,
        "recommended_specialty_name_ar": specialty_row["name_ar"] if specialty_row else None,
        "recommended_next_step": differential.get("next_step"),
        "ai_confidence": differential.get("confidence"),
    }


def _build_history_narrative(report: Dict[str, Any], lang: str) -> str:
    labels = _SLOT_LABELS[lang]
    parts = [report.get("chief_complaint_description") or ""]
    for key, value in report["symptoms_summary"].items():
        label = labels.get(key, key)
        parts.append(f"{label}: {value}.")
    return " ".join(p for p in parts if p)


def _render_html(report: Dict[str, Any]) -> str:
    lang = report["language"]
    labels = _LABELS[lang]
    slot_labels = _SLOT_LABELS[lang]
    direction = "rtl" if lang == "ar" else "ltr"
    align = "right" if lang == "ar" else "left"

    urgency = report["urgency_level"]
    urgency_color = _URGENCY_COLOR.get(urgency, "#555555")
    urgency_label = _URGENCY_LABEL[lang].get(urgency, urgency)

    specialty_name = report["recommended_specialty_name_ar" if lang == "ar" else "recommended_specialty_name_en"]

    # Every value below is ultimately transcribed patient speech or LLM output
    # going into an HTML template. Escaping keeps a stray "&" or "<" from
    # producing malformed markup (and silently mangling the report).
    def esc(value: Any) -> str:
        return html_escape(str(value), quote=False) if value is not None else ""

    info = report["patient_info"]
    patient_fields = [
        (labels["patient_name"], esc(info.get("name")) or labels["no_data"]),
        (labels["patient_age"],
         f"{esc(info['age'])} {labels['years']}" if info.get("age") is not None else labels["no_data"]),
        (labels["interview_date"],
         esc((info.get("interview_date") or "")[:19].replace("T", " ")) or labels["no_data"]),
        (labels["session_reference"], esc(info.get("session_reference"))),
    ]
    patient_rows = "".join(
        f"<tr><th>{label}</th><td>{value}</td></tr>" for label, value in patient_fields
    )

    symptoms_rows = "".join(
        f"<tr><th>{esc(slot_labels.get(k, k))}</th><td>{esc(v)}</td></tr>"
        for k, v in report["symptoms_summary"].items()
    ) or f"<tr><td colspan='2' class='muted'>{labels['no_data']}</td></tr>"

    differential_items = "".join(
        f"<li><span class='cond'>{esc(c.get('condition', ''))}</span>"
        f"<span class='likelihood'>{esc(_LIKELIHOOD_LABEL[lang].get(c.get('likelihood'), c.get('likelihood', '')))}</span></li>"
        for c in report["differential"]
    ) or f"<li class='muted'>{labels['no_data']}</li>"

    confidence = report.get("ai_confidence")
    confidence_display = f"{round(confidence * 100)}%" if isinstance(confidence, (int, float)) else "—"

    history_text = _build_history_narrative(report, lang)
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
@page {{ size: A4; margin: 2cm; }}
body {{
  font-family: 'Cairo', sans-serif;
  direction: {direction};
  text-align: {align};
  color: #1c1c1c;
  font-size: 12pt;
  line-height: 1.6;
}}
h1 {{ font-size: 18pt; margin: 0 0 4pt; }}
h2 {{
  font-size: 13pt; margin: 18pt 0 6pt;
  border-{'right' if direction == 'rtl' else 'left'}: 4pt solid #2f4b8c;
  padding-{'right' if direction == 'rtl' else 'left'}: 8pt;
}}
.meta {{ color: #555; font-size: 9.5pt; margin-bottom: 14pt; }}
.disclaimer {{
  border: 1pt solid #b7791f;
  background: #fdf3e0;
  padding: 10pt 12pt;
  border-radius: 4pt;
  font-size: 10pt;
  margin-top: 20pt;
}}
.disclaimer .label {{ font-weight: 700; color: #8a5a10; margin-bottom: 4pt; }}
table {{ width: 100%; border-collapse: collapse; margin-top: 4pt; }}
th, td {{ text-align: {align}; padding: 5pt 8pt; border-bottom: 0.5pt solid #ddd; font-size: 10.5pt; }}
th {{ width: 35%; color: #444; font-weight: 700; }}
.muted {{ color: #888; font-style: italic; }}
.urgency-badge {{
  display: inline-block;
  padding: 3pt 12pt;
  border-radius: 12pt;
  color: white;
  font-weight: 700;
  background: {urgency_color};
}}
ul.differential {{ list-style: none; margin: 4pt 0; padding: 0; }}
ul.differential li {{
  display: flex;
  justify-content: space-between;
  padding: 4pt 0;
  border-bottom: 0.5pt solid #eee;
}}
.likelihood {{ color: #666; font-size: 9.5pt; }}
</style>
</head>
<body>
  <h1>{labels['title']}</h1>
  <div class="meta">
    {labels['generated_on']}: {generated_at} &nbsp;·&nbsp;
    {labels['session_reference']}: {report['patient_info']['session_reference']}
  </div>

  <h2>{labels['patient_info']}</h2>
  <table>{patient_rows}</table>

  <h2>{labels['chief_complaint']}</h2>
  <p>{esc(report.get('chief_complaint')) or labels['no_data']}</p>

  <h2>{labels['history']}</h2>
  <p>{esc(history_text) or labels['no_data']}</p>

  <h2>{labels['symptoms_summary']}</h2>
  <table>{symptoms_rows}</table>

  <h2>{labels['urgency']}</h2>
  <p><span class="urgency-badge">{urgency_label}</span></p>

  <h2>{labels['specialty']}</h2>
  <p>{esc(specialty_name) or labels['no_data']}</p>

  <h2>{labels['differential']}</h2>
  <ul class="differential">{differential_items}</ul>

  <h2>{labels['next_step']}</h2>
  <p>{esc(report.get('recommended_next_step')) or labels['no_data']}</p>

  <h2>{labels['confidence']}</h2>
  <p>{confidence_display}</p>

  <div class="disclaimer">
    <div class="label">{labels['disclaimer_title']}</div>
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
        # A native abort exits with an NTSTATUS code rather than raising, so
        # name the one we already know about instead of leaving a bare number.
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


async def generate_report(session_id: str) -> Optional[Dict[str, Any]]:
    """
    Build the report data, render it to PDF, and persist it to
    virtual_doctor_reports. Returns the report metadata (including
    report_id and pdf_path) or None if the session doesn't exist.

    Raises PdfGenerationUnavailable if the report data was built but the PDF
    could not be rendered.
    """
    report = await build_report_data(session_id)
    if not report:
        return None

    html_string = _render_html(report)
    pdf_path = _REPORTS_DIR / f"{report['report_id']}.pdf"
    # subprocess.run blocks; keep it off the event loop.
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


async def get_report_pdf_path(report_id: str) -> Optional[str]:
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT pdf_path FROM virtual_doctor_reports WHERE id = $1", uuid.UUID(report_id)
    )
    return row["pdf_path"] if row else None
