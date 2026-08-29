from typing import Dict, List, Optional


class EntityLinker:
    """
    Entity Linking System.
    Resolves extracted entity names to database IDs whenever possible.
    Maintains a local cache of known entities for fast resolution.
    """

    def __init__(self):
        self._specialty_cache = {}
        self._doctor_cache = {}
        self._clinic_cache = {}
        self._medication_cache = {}

    def link_specialty(self, specialty_name: str, specialties_list: Optional[List[Dict]] = None) -> Optional[Dict]:
        """
        Link a specialty name to its database record.
        Uses fuzzy matching if exact match fails.
        """
        if not specialty_name:
            return None

        name_lower = specialty_name.lower().strip()

        if name_lower in self._specialty_cache:
            return self._specialty_cache[name_lower]

        if specialties_list:
            for spec in specialties_list:
                spec_name_en = (spec.get("name_en") or "").lower()
                spec_name_ar = (spec.get("name_ar") or "").lower()

                if name_lower in spec_name_en or name_lower in spec_name_ar:
                    result = {
                        "id": spec.get("id"),
                        "name_ar": spec.get("name_ar"),
                        "name_en": spec.get("name_en"),
                        "confidence": 0.95
                    }
                    self._specialty_cache[name_lower] = result
                    return result

        return {
            "id": None,
            "name": specialty_name,
            "confidence": 0.5,
            "unmatched": True
        }

    def link_doctor(self, doctor_name: str, doctors_list: Optional[List[Dict]] = None) -> Optional[Dict]:
        """
        Link a doctor name to its database record.
        """
        if not doctor_name:
            return None

        name_lower = doctor_name.lower().strip()

        if name_lower in self._doctor_cache:
            return self._doctor_cache[name_lower]

        if doctors_list:
            for doc in doctors_list:
                first_en = (doc.get("first_name_en") or "").lower()
                last_en = (doc.get("last_name_en") or "").lower()
                first_ar = (doc.get("first_name_ar") or "").lower()
                last_ar = (doc.get("last_name_ar") or "").lower()

                full_en = f"{first_en} {last_en}".strip()
                full_ar = f"{first_ar} {last_ar}".strip()

                if name_lower in full_en or name_lower in full_ar:
                    result = {
                        "id": doc.get("id"),
                        "name_ar": f"{doc.get('first_name_ar', '')} {doc.get('last_name_ar', '')}",
                        "name_en": f"{doc.get('first_name_en', '')} {doc.get('last_name_en', '')}",
                        "specialty": doc.get("specialty_ar") or doc.get("specialty_en"),
                        "confidence": 0.9
                    }
                    self._doctor_cache[name_lower] = result
                    return result

        return {
            "id": None,
            "name": doctor_name,
            "confidence": 0.4,
            "unmatched": True
        }

    def link_clinic(self, clinic_name: str, clinics_list: Optional[List[Dict]] = None) -> Optional[Dict]:
        """
        Link a clinic name to its database record.
        """
        if not clinic_name:
            return None

        name_lower = clinic_name.lower().strip()

        if name_lower in self._clinic_cache:
            return self._clinic_cache[name_lower]

        if clinics_list:
            for clinic in clinics_list:
                name_en = (clinic.get("name_en") or "").lower()
                name_ar = (clinic.get("name_ar") or "").lower()

                if name_lower in name_en or name_lower in name_ar:
                    result = {
                        "id": clinic.get("id"),
                        "name_ar": clinic.get("name_ar"),
                        "name_en": clinic.get("name_en"),
                        "type": clinic.get("type"),
                        "latitude": clinic.get("latitude"),
                        "longitude": clinic.get("longitude"),
                        "confidence": 0.9
                    }
                    self._clinic_cache[name_lower] = result
                    return result

        return {
            "id": None,
            "name": clinic_name,
            "confidence": 0.4,
            "unmatched": True
        }

    def link_medication(self, medication_name: str, medications_list: Optional[List[Dict]] = None) -> Optional[Dict]:
        """
        Link a medication name to its database record.
        """
        if not medication_name:
            return None

        name_lower = medication_name.lower().strip()

        if name_lower in self._medication_cache:
            return self._medication_cache[name_lower]

        if medications_list:
            for med in medications_list:
                name_en = (med.get("name_en") or "").lower()
                name_ar = (med.get("name_ar") or "").lower()
                generic = (med.get("generic_name") or "").lower()

                if name_lower in name_en or name_lower in name_ar or name_lower in generic:
                    result = {
                        "id": med.get("id"),
                        "name_ar": med.get("name_ar"),
                        "name_en": med.get("name_en"),
                        "generic_name": med.get("generic_name"),
                        "drug_class": med.get("drug_class"),
                        "confidence": 0.9
                    }
                    self._medication_cache[name_lower] = result
                    return result

        return {
            "id": None,
            "name": medication_name,
            "confidence": 0.4,
            "unmatched": True
        }

    def link_entities(self, entities: Dict, available_data: Optional[Dict] = None) -> Dict:
        """
        Link all extractable entities in a dict to database records.
        Returns enriched entities with linked IDs.
        """
        linked = dict(entities)

        specialty = entities.get("specialty")
        if specialty:
            specialties_list = (available_data or {}).get("specialties")
            linked_specialty = self.link_specialty(specialty, specialties_list)
            if linked_specialty:
                linked["specialty_id"] = linked_specialty.get("id")
                linked["specialty_linked"] = linked_specialty

        medications = entities.get("medications", [])
        if medications:
            meds_list = (available_data or {}).get("medications")
            linked_meds = []
            for med in medications:
                linked_med = self.link_medication(med, meds_list)
                if linked_med:
                    linked_meds.append(linked_med)
            if linked_meds:
                linked["medications_linked"] = linked_meds

        return linked

    def update_cache_from_backend(self, data_type: str, items: List[Dict]):
        """
        Update the local cache with data from backend responses.
        Called when the backend returns search results.
        """
        if data_type == "specialties":
            for item in items:
                for name_key in ["name_en", "name_ar"]:
                    name = (item.get(name_key) or "").lower().strip()
                    if name:
                        self._specialty_cache[name] = {
                            "id": item.get("id"),
                            "name_ar": item.get("name_ar"),
                            "name_en": item.get("name_en"),
                            "confidence": 1.0
                        }

        elif data_type == "doctors":
            for item in items:
                first_en = (item.get("first_name_en") or "").lower()
                last_en = (item.get("last_name_en") or "").lower()
                full_en = f"{first_en} {last_en}".strip()
                if full_en:
                    self._doctor_cache[full_en] = {
                        "id": item.get("id"),
                        "name_ar": f"{item.get('first_name_ar', '')} {item.get('last_name_ar', '')}",
                        "name_en": f"{item.get('first_name_en', '')} {item.get('last_name_en', '')}",
                        "confidence": 1.0
                    }

        elif data_type == "clinics":
            for item in items:
                for name_key in ["name_en", "name_ar"]:
                    name = (item.get(name_key) or "").lower().strip()
                    if name:
                        self._clinic_cache[name] = {
                            "id": item.get("id"),
                            "name_ar": item.get("name_ar"),
                            "name_en": item.get("name_en"),
                            "confidence": 1.0
                        }

    def clear_cache(self):
        """Clear all cached entity links."""
        self._specialty_cache.clear()
        self._doctor_cache.clear()
        self._clinic_cache.clear()
        self._medication_cache.clear()
