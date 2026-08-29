"""
T-046: Symptom-Specialty Mapping Engine (Rule-Based)

Matches normalized symptom text against symptom_specialty_mappings table.
Uses weighted scoring to rank specialties by relevance.

Usage:
    engine = SymptomSpecialtyEngine()
    results = await engine.match(["chest pain", "shortness of breath"])
"""

import re
import logging
from collections import defaultdict
from typing import List, Dict, Any, Optional
from uuid import UUID

from db import get_pool

logger = logging.getLogger("medorbit-ai.triage")


class SymptomSpecialtyEngine:
    """
    Rule-based engine that maps symptom keywords to medical specialties
    using the `symptom_specialty_mappings` DB table.
    
    Scoring: Each mapping has a `weight` (0.01-5.00). For a list of input
    symptoms, we sum weights per specialty. The top-scoring specialty wins.
    """

    EMERGENCY_KEYWORDS_EN = {
        "severe chest pain", "difficulty breathing", "unconscious",
        "severe bleeding", "choking", "poisoning", "suicide",
    }
    EMERGENCY_KEYWORDS_AR = {
        "ألم صدري حاد", "صعوبة التنفس", "فقدان الوعي",
        "نزيف حاد", "اختناق", "تسمم", "انتحار",
    }

    async def match(
        self,
        symptoms: List[str],
        user_id: Optional[UUID] = None,
    ) -> Dict[str, Any]:
        """
        Given a list of symptom strings, return triage result.

        Returns:
            {
                "symptoms": [...],
                "triage_level": "emergency" | "urgent" | "routine",
                "recommended_specialty_id": UUID | None,
                "recommended_specialty_name_en": str | None,
                "recommended_specialty_name_ar": str | None,
                "confidence_score": float,
                "specialty_scores": {name_en: float, ...},
                "matched_keywords": [str, ...],
                "recommendations": str,
                "follow_up_action": str,
            }
        """
        pool = await get_pool()

        normalized = [self._normalize(s) for s in symptoms if s.strip()]
        text_bag = " ".join(normalized).lower()

        is_emergency = False
        for kw in self.EMERGENCY_KEYWORDS_EN:
            if kw in text_bag:
                is_emergency = True
                break
        if not is_emergency:
            for kw in self.EMERGENCY_KEYWORDS_AR:
                if kw in text_bag:
                    is_emergency = True
                    break

        rows = await pool.fetch(
            """
            SELECT ssm.symptom_keyword, ssm.symptom_keyword_ar,
                   ssm.weight, sp.id AS specialty_id,
                   sp.name_en, sp.name_ar
            FROM symptom_specialty_mappings ssm
            JOIN specialties sp ON sp.id = ssm.specialty_id
            WHERE ssm.is_active = true AND sp.is_active = true
            """
        )

        scores: Dict[UUID, float] = defaultdict(float)
        specialty_names: Dict[UUID, Dict[str, str]] = {}
        matched_keywords: List[str] = []

        for row in rows:
            kw_en = (row["symptom_keyword"] or "").lower()
            kw_ar = row["symptom_keyword_ar"] or ""

            for sym in normalized:
                sym_lower = sym.lower()
                if kw_en and kw_en in sym_lower:
                    sid = row["specialty_id"]
                    scores[sid] += float(row["weight"])
                    specialty_names[sid] = {
                        "en": row["name_en"],
                        "ar": row["name_ar"],
                    }
                    if kw_en not in matched_keywords:
                        matched_keywords.append(kw_en)
                if kw_ar and kw_ar in sym:
                    sid = row["specialty_id"]
                    scores[sid] += float(row["weight"])
                    specialty_names[sid] = {
                        "en": row["name_en"],
                        "ar": row["name_ar"],
                    }
                    if kw_ar not in matched_keywords:
                        matched_keywords.append(kw_ar)

        if not scores:
            gp_row = await pool.fetchrow(
                "SELECT id, name_en, name_ar FROM specialties WHERE name_en = 'General Practice' LIMIT 1"
            )
            return {
                "symptoms": symptoms,
                "triage_level": "routine",
                "recommended_specialty_id": str(gp_row["id"]) if gp_row else None,
                "recommended_specialty_name_en": gp_row["name_en"] if gp_row else "General Practice",
                "recommended_specialty_name_ar": gp_row["name_ar"] if gp_row else "طب عام",
                "confidence_score": 0.1,
                "specialty_scores": {},
                "matched_keywords": [],
                "recommendations": "No specific match found. Consult a general practitioner.",
                "follow_up_action": "visit_general_practitioner",
            }

        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        top_specialty_id, top_score = ranked[0]

        if len(ranked) > 1:
            second_score = ranked[1][1]
            gap_ratio = (top_score - second_score) / top_score if top_score > 0 else 0
            confidence = round(min(0.5 + gap_ratio * 0.5, 1.0), 4)
        else:
            confidence = round(min(top_score / 10.0, 1.0), 4)

        if is_emergency:
            triage_level = "emergency"
            follow_up = "visit_emergency_immediately"
            recommendations = "Emergency symptoms detected. Please go to the nearest emergency room immediately."
        elif top_score >= 7.0 or confidence >= 0.8:
            triage_level = "urgent"
            follow_up = "book_urgent_appointment"
            recommendations = (
                f"Based on your symptoms, we recommend seeing a "
                f"{specialty_names[top_specialty_id]['en']} specialist soon. "
                f"Please book an appointment within 24-48 hours."
            )
        else:
            triage_level = "routine"
            follow_up = "book_appointment"
            recommendations = (
                f"Your symptoms suggest a {specialty_names[top_specialty_id]['en']} consultation "
                f"may be helpful. You can book a routine appointment at your convenience."
            )

        specialty_scores_display = {
            specialty_names[sid]["en"]: round(score, 2)
            for sid, score in ranked[:5]
        }

        return {
            "symptoms": symptoms,
            "triage_level": triage_level,
            "recommended_specialty_id": str(top_specialty_id),
            "recommended_specialty_name_en": specialty_names[top_specialty_id]["en"],
            "recommended_specialty_name_ar": specialty_names[top_specialty_id]["ar"],
            "confidence_score": confidence,
            "specialty_scores": specialty_scores_display,
            "matched_keywords": matched_keywords,
            "recommendations": recommendations,
            "follow_up_action": follow_up,
        }

    def _normalize(self, text: str) -> str:
        """Lowercase, strip diacritics, collapse whitespace."""
        text = text.lower().strip()
        text = re.sub(r"[\u0610-\u061A\u064B-\u065F\u0670]", "", text)
        text = re.sub(r"\s+", " ", text)
        return text
