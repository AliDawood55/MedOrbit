"""
T-051: LLM Report Summarizer (Bilingual)

Takes extracted text (from PDF/OCR or medical records),
generates bilingual summaries via the existing LLM service (Ollama/qwen2:7b),
and persists results to `report_summarizations` table.
"""

import os
import time
import logging
import requests
from typing import Dict, Any, Optional
from uuid import UUID

from db import get_pool

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
MODEL_NAME = os.environ.get("OLLAMA_MODEL", "qwen2:7b")

logger = logging.getLogger("medorbit-ai.summarizer")


class ReportSummarizerLLM:
    """
    LLM-powered medical report summarizer.
    Generates Arabic AND English summaries, saves to report_summarizations.
    """

    async def summarize_and_save(
        self,
        extracted_text: str,
        user_id: Optional[str] = None,
        record_id: Optional[str] = None,
        source_file_name: Optional[str] = None,
        source_file_type: Optional[str] = "text",
    ) -> Dict[str, Any]:
        """
        Full pipeline: extract → LLM summarize (AR + EN) → persist.

        Returns:
            {
                "id": str,
                "summary_ar": str,
                "summary_en": str,
                "processing_time_ms": int,
                "model_used": str,
            }
        """
        start = time.time()

        if not extracted_text or not extracted_text.strip():
            raise ValueError("No text to summarize")

        truncated = self._truncate(extracted_text, max_chars=6000)

        summary_ar = self._generate_summary(truncated, lang="ar")
        summary_en = self._generate_summary(truncated, lang="en")

        processing_ms = int((time.time() - start) * 1000)

        pool = await get_pool()
        row = await pool.fetchrow(
            """
            INSERT INTO report_summarizations
                (record_id, user_id, source_file_name, source_file_type,
                 extracted_text, summary_ar, summary_en,
                 processing_time_ms, model_used)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING id
            """,
            UUID(record_id) if record_id else None,
            UUID(user_id) if user_id else None,
            source_file_name,
            source_file_type,
            truncated,
            summary_ar,
            summary_en,
            processing_ms,
            MODEL_NAME,
        )

        logger.info(
            "Report summarized: id=%s, %dms, %d chars in → %d AR + %d EN out",
            row["id"], processing_ms,
            len(truncated), len(summary_ar), len(summary_en),
        )

        return {
            "id": str(row["id"]),
            "summary_ar": summary_ar,
            "summary_en": summary_en,
            "processing_time_ms": processing_ms,
            "model_used": MODEL_NAME,
        }

    def _generate_summary(self, text: str, lang: str = "ar") -> str:
        """Call Ollama LLM to generate a medical report summary."""

        if lang == "ar":
            system = (
                "أنت مساعد طبي متخصص في تلخيص التقارير الطبية.\n"
                "القواعد:\n"
                "1. لخص التقرير بشكل مختصر ومفيد\n"
                "2. رتب الملخص: التشخيص، الأعراض، العلاج، التوصيات\n"
                "3. استخدم لغة طبية واضحة ومبسطة\n"
                "4. أضف تحذير: 'هذا الملخص للاسترشاد فقط'\n"
                "5. لا تضف معلومات ليست في النص الأصلي\n"
                "6. استخدم العناوين والنقاط لتنظيم الملخص\n"
            )
            fallback = "تعذر إنشاء الملخص. يرجى المحاولة مرة أخرى."
        else:
            system = (
                "You are a medical assistant specialized in summarizing medical reports.\n"
                "Rules:\n"
                "1. Summarize concisely and usefully\n"
                "2. Organize: Diagnosis, Symptoms, Treatment, Recommendations\n"
                "3. Use clear, simplified medical language\n"
                "4. Add disclaimer: 'This summary is for guidance only'\n"
                "5. Do not add information not in the original text\n"
                "6. Use headings and bullet points for organization\n"
            )
            fallback = "Could not generate summary. Please try again."

        prompt = f"""{system}

---
Medical Report Text:
{text}

---
Provide a structured summary in {"Arabic" if lang == "ar" else "English"}.
Include: Key Findings, Diagnosis (if mentioned), Symptoms, Treatment Plan, Recommendations.
"""

        try:
            response = requests.post(
                OLLAMA_URL,
                json={
                    "model": MODEL_NAME,
                    "prompt": prompt,
                    "stream": False,
                },
                timeout=90,
            )
            data = response.json()
            result = data.get("response", "").strip()
            return result if result else fallback
        except requests.exceptions.Timeout:
            logger.error("LLM timeout during summarization (lang=%s)", lang)
            return fallback
        except Exception as e:
            logger.error("LLM error during summarization: %s", e)
            return fallback

    @staticmethod
    def _truncate(text: str, max_chars: int = 6000) -> str:
        """Truncate text to max_chars at a sentence boundary."""
        if len(text) <= max_chars:
            return text
        truncated = text[:max_chars]
        for sep in [".\n", ". ", "。", "\n"]:
            last = truncated.rfind(sep)
            if last > max_chars * 0.7:
                return truncated[: last + len(sep)]
        return truncated
