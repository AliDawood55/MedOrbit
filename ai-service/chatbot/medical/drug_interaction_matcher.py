"""
T-048: Drug Interactions Matcher

Queries the `medications` table for `known_interactions` JSONB
and cross-references a list of medication names/IDs.

known_interactions JSONB format in DB:
{
    "other_medication_name_en": "severity_description",
    ...
}

Enhanced to also query the DB for full medication records
and check interactions bidirectionally.
"""

import json
import logging
from typing import List, Dict, Any, Optional
from uuid import UUID

from db import get_pool

logger = logging.getLogger("medorbit-ai.drug_checker")


class DrugInteractionMatcher:
    """
    Enhanced drug interaction checker that:
    1. Looks up medication records from DB by name/ID
    2. Reads known_interactions JSONB from each
    3. Cross-checks all pairs bidirectionally
    4. Returns structured interaction results
    """

    async def check(
        self,
        medication_ids: Optional[List[str]] = None,
        medication_names: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        """
        Check interactions between medications.

        Args:
            medication_ids: List of medication UUIDs (strings)
            medication_names: List of medication name_en to look up

        Returns:
            List of interaction objects:
            [
                {
                    "drug_1": {"id": str, "name_en": str, "name_ar": str},
                    "drug_2": {"id": str, "name_en": str, "name_ar": str},
                    "severity": str,
                    "source": "drug_1_name | drug_2_name",
                    "description": str,
                },
                ...
            ]
        """
        pool = await get_pool()
        meds: List[Dict[str, Any]] = []

        # 1) Fetch medication records from DB
        if medication_ids:
            ids = [mid for mid in medication_ids if mid]
            if ids:
                placeholders = ",".join(f"${i+1}" for i in range(len(ids)))
                rows = await pool.fetch(
                    f"""
                    SELECT id, name_en, name_ar, generic_name,
                           drug_class, known_interactions, side_effects, contraindications
                    FROM medications
                    WHERE id IN ({placeholders}) AND is_active = true
                    """,
                    *ids
                )
                meds.extend([dict(r) for r in rows])

        if medication_names:
            for name in medication_names:
                if not name:
                    continue
                rows = await pool.fetch(
                    """
                    SELECT id, name_en, name_ar, generic_name,
                           drug_class, known_interactions, side_effects, contraindications
                    FROM medications
                    WHERE (name_en ILIKE $1 OR name_ar ILIKE $1
                           OR generic_name ILIKE $1
                           OR $2 = ANY(brand_names))
                       AND is_active = true
                    LIMIT 1
                    """,
                    f"%{name}%",
                    name,
                )
                if rows:
                    row_dict = dict(rows[0])
                    # Avoid duplicates if already fetched by ID
                    if not any(m["id"] == row_dict["id"] for m in meds):
                        meds.append(row_dict)

        if len(meds) < 2:
            logger.info("Need at least 2 medications to check interactions, got %d", len(meds))
            return []

        # 2) Cross-check all pairs
        interactions: List[Dict[str, Any]] = []
        seen_pairs: set = set()

        for i, drug_a in enumerate(meds):
            interactions_jsonb = self._interaction_map(drug_a.get("known_interactions"))

            # known_interactions can be: {"Aspirin": "Moderate - increases bleeding risk"}
            # or: {"<uuid>": "Severe - ..."}
            for j, drug_b in enumerate(meds):
                if i == j:
                    continue
                pair_key = tuple(sorted([str(drug_a["id"]), str(drug_b["id"])]))
                if pair_key in seen_pairs:
                    continue

                severity = self._find_severity(interactions_jsonb, drug_b)

                if severity:
                    seen_pairs.add(pair_key)
                    interactions.append({
                        "drug_1": {
                            "id": str(drug_a["id"]),
                            "name_en": drug_a["name_en"],
                            "name_ar": drug_a["name_ar"],
                        },
                        "drug_2": {
                            "id": str(drug_b["id"]),
                            "name_en": drug_b["name_en"],
                            "name_ar": drug_b["name_ar"],
                        },
                        "severity": self._classify_severity(severity),
                        "description": severity,
                    })

        # 3) Also check drug_b interactions for drug_a (bidirectional)
        for j, drug_b in enumerate(meds):
            interactions_jsonb = self._interaction_map(drug_b.get("known_interactions"))
            for i, drug_a in enumerate(meds):
                if i == j:
                    continue
                pair_key = tuple(sorted([str(drug_a["id"]), str(drug_b["id"])]))
                if pair_key in seen_pairs:
                    continue

                severity = self._find_severity(interactions_jsonb, drug_a)

                if severity:
                    seen_pairs.add(pair_key)
                    interactions.append({
                        "drug_1": {
                            "id": str(drug_b["id"]),
                            "name_en": drug_b["name_en"],
                            "name_ar": drug_b["name_ar"],
                        },
                        "drug_2": {
                            "id": str(drug_a["id"]),
                            "name_en": drug_a["name_en"],
                            "name_ar": drug_a["name_ar"],
                        },
                        "severity": self._classify_severity(severity),
                        "description": severity,
                    })

        # Sort by severity: severe > moderate > mild
        severity_order = {"severe": 0, "moderate": 1, "mild": 2, "unknown": 3}
        interactions.sort(key=lambda x: severity_order.get(x["severity"], 3))

        logger.info(
            "Drug interaction check: %d medications, %d interactions found",
            len(meds), len(interactions)
        )
        return interactions

    async def check_prescription_items(
        self,
        medication_name_en_list: List[str],
    ) -> List[Dict[str, Any]]:
        """
        Convenience method for T-049: takes prescription item names
        (as they appear in prescription_items.medication_name_en)
        and checks for interactions.
        """
        return await self.check(medication_names=medication_name_en_list)

    def _find_severity(self, interactions_jsonb: dict, other_drug: dict) -> Optional[str]:
        """
        Look up `other_drug` in the interactions JSONB of the current drug.
        JSONB keys can be: drug name_en, generic_name, or UUID string.
        """
        if not interactions_jsonb:
            return None

        # Try by name_en
        val = interactions_jsonb.get(other_drug.get("name_en", ""))
        if val:
            return str(val)

        # Try by generic_name
        val = interactions_jsonb.get(other_drug.get("generic_name", ""))
        if val:
            return str(val)

        # Try by UUID
        val = interactions_jsonb.get(str(other_drug.get("id", "")))
        if val:
            return str(val)

        # Case-insensitive fallback: scan keys
        name_en_lower = (other_drug.get("name_en") or "").lower()
        generic_lower = (other_drug.get("generic_name") or "").lower()
        for key, value in interactions_jsonb.items():
            if key.lower() in (name_en_lower, generic_lower):
                return str(value)

        return None

    @staticmethod
    def _interaction_map(value: Any) -> Dict[str, Any]:
        """Normalize PostgreSQL JSONB returned as either a mapping or text."""
        if isinstance(value, dict):
            return value
        if isinstance(value, str):
            try:
                decoded = json.loads(value)
            except json.JSONDecodeError:
                logger.warning("Ignoring malformed medication known_interactions JSON")
                return {}
            return decoded if isinstance(decoded, dict) else {}
        return {}

    @staticmethod
    def _classify_severity(description: str) -> str:
        """Classify free-text severity into standard levels."""
        desc_lower = description.lower()
        if any(w in desc_lower for w in ["severe", "critical", "life-threatening", "contraindicated", "شديد"]):
            return "severe"
        if any(w in desc_lower for w in ["moderate", "caution", "monitor", "متوسط"]):
            return "moderate"
        if any(w in desc_lower for w in ["mild", "minor", "خفيف"]):
            return "mild"
        return "unknown"
