import json


def retrieve_context(message: str, entities: dict) -> str:
    """
    Build structured RAG context as JSON string.
    
    The backend will use this context to query PostgreSQL and enrich
    the response. This function prepares the context that tells the
    LLM what type of data to expect and what the user is looking for.
    
    Returns a JSON string that the LLM can parse and use to generate
    a structured response.
    """
    context = {
        "type": "general_medical",
        "user_intent": entities.get("intent", "unknown"),
        "entities_found": {},
        "search_parameters": {},
        "available_data": []
    }

    # ============================================
    # Location context
    # ============================================
    if entities.get("latitude") and entities.get("longitude"):
        context["search_parameters"]["user_location"] = {
            "latitude": entities["latitude"],
            "longitude": entities["longitude"]
        }
        context["entities_found"]["has_location"] = True

    if entities.get("location"):
        context["entities_found"]["region"] = entities["location"]

    # ============================================
    # Facility type context
    # ============================================
    entity_type = entities.get("type")
    if entity_type:
        type_map = {
            "clinic": "clinics",
            "hospital": "hospitals",
            "pharmacy": "pharmacies", 
            "laboratory": "laboratories",
            "radiology": "radiology_centers",
            "dental": "dental_clinics",
            "emergency": "emergency_departments",
            "optical": "optical_centers",
            "vaccination": "vaccination_centers"
        }
        context["type"] = "place_search"
        context["search_parameters"]["facility_type"] = entity_type
        context["search_parameters"]["data_source"] = type_map.get(entity_type, "clinics")
        context["available_data"].append({
            "type": entity_type,
            "fields": ["name", "address", "phone", "latitude", "longitude", 
                       "distance", "rating", "services", "operating_hours", "insurance"]
        })

    # ============================================
    # Medical specialty context
    # ============================================
    if entities.get("specialty"):
        context["type"] = "doctor_search"
        context["search_parameters"]["specialty"] = entities["specialty"]
        if entities.get("specialties"):
            context["search_parameters"]["specialties"] = entities["specialties"]
        context["available_data"].append({
            "type": "doctors",
            "filter": {"specialty": entities["specialty"]},
            "fields": ["name", "specialty", "rating", "fee", "experience", "clinic"]
        })

    # ============================================
    # Symptom context
    # ============================================
    if entities.get("symptoms") and len(entities["symptoms"]) > 0:
        context["type"] = "symptom_analysis"
        context["entities_found"]["symptoms"] = entities["symptoms"]
        context["available_data"].append({
            "type": "medical_guidance",
            "symptoms": entities["symptoms"],
            "note": "Provide general guidance only. Never diagnose."
        })

    # ============================================
    # Medication context
    # ============================================
    if entities.get("medications") and len(entities["medications"]) > 0:
        context["type"] = "medication_info"
        context["entities_found"]["medications"] = entities["medications"]
        context["available_data"].append({
            "type": "medication",
            "names": entities["medications"],
            "note": "Provide general information only. Recommend consulting a pharmacist."
        })

    # ============================================
    # Navigation context
    # ============================================
    if entities.get("intent") == "show_route":
        context["type"] = "navigation"
        context["available_data"].append({
            "type": "route",
            "note": "User wants directions to a previously found location."
        })

    # ============================================
    # Default fallback
    # ============================================
    if not context["available_data"]:
        context["available_data"].append({
            "type": "general",
            "note": "General medical question"
        })

    return json.dumps(context, ensure_ascii=False)