"""
MedOrbit AI Service — main.py (Updated)

New endpoints added:
  POST /triage              — T-047: Symptom triage + persistence
  POST /drug-interactions   — T-048: Drug interaction checker (DB-backed)
  POST /prescription-check  — T-049: Auto-check on Rx creation
  POST /summarize           — T-050 + T-051: PDF/OCR + LLM bilingual summary + persist
  GET  /health              — Existing
  POST /chat                — Existing (enhanced: uses new DrugInteractionMatcher for drug_check)
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, Form, File, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
import time
import logging
import json
import uuid

# Core NLP (existing)
from chatbot.intent.classifier import IntentClassifier
from chatbot.entities.extractor import EntityExtractor
from chatbot.medical.drug_checker import DrugChecker  # legacy in-memory checker
from chatbot.medical.report_summarizer import ReportSummarizer  # legacy template-based

# NLU Pipeline (existing)
from chatbot.nlu.pipeline import NLUPipeline
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.nlu.slots import SlotFiller
from chatbot.nlu.provider_resolver import ProviderResolver

# LLM + RAG (existing)
from rag.retriever import retrieve_context
from llm.llm_service import generate_response

# === NEW MODULES (Phase 2 + Phase 3) ===
from db import get_pool, close_pool
from chatbot.medical.symptom_engine import SymptomSpecialtyEngine
from chatbot.medical.drug_interaction_matcher import DrugInteractionMatcher
from chatbot.medical.document_extractor import DocumentExtractor
from chatbot.medical.report_summarizer_llm import ReportSummarizerLLM
from identity_boundary import resolve_internal_identity

# === Virtual Doctor (new, additive, isolated module) ===
from virtual_doctor.router import router as virtual_doctor_router

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("medorbit-ai")

# Initialize existing services
classifier = IntentClassifier()
extractor = EntityExtractor()
drug_checker = DrugChecker()          # kept for backward compat
report_summarizer = ReportSummarizer()  # kept for backward compat
nlu_pipeline = NLUPipeline()
safety_layer = MedicalSafetyLayer()
slot_filler = SlotFiller()
provider_resolver = ProviderResolver()

# Initialize new services
symptom_engine = SymptomSpecialtyEngine()
drug_matcher = DrugInteractionMatcher()
doc_extractor = DocumentExtractor()
llm_summarizer = ReportSummarizerLLM()


# =========================
# Lifespan (DB pool)
# =========================
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: warm the DB pool
    await get_pool()
    logger.info("AI service started")
    yield
    # Shutdown
    await close_pool()
    logger.info("AI service stopped")


# FastAPI app
app = FastAPI(
    title="MedOrbit AI Service",
    version="3.0.0",
    docs=None,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(virtual_doctor_router)


# =========================================================
# REQUEST / RESPONSE SCHEMAS
# =========================================================

class ChatRequest(BaseModel):
    message: Optional[str] = None
    context: Optional[Dict[str, Any]] = None
    type: Optional[str] = None
    medications: Optional[list] = None
    record: Optional[Dict[str, Any]] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    conversation_id: Optional[str] = None


class ChatResponse(BaseModel):
    reply: str
    intent: Optional[str] = None
    confidence: Optional[float] = None
    entities: Optional[Dict[str, Any]] = None


# --- T-047: Triage ---
class TriageRequest(BaseModel):
    symptoms: List[str] = Field(..., min_length=1, description="List of symptom strings")
    user_id: Optional[str] = None
    session_id: Optional[str] = None


class TriageResponse(BaseModel):
    id: str
    symptoms: List[str]
    triage_level: str
    recommended_specialty_id: Optional[str]
    recommended_specialty_name_en: Optional[str]
    recommended_specialty_name_ar: Optional[str]
    confidence_score: float
    specialty_scores: Dict[str, float]
    matched_keywords: List[str]
    recommendations: str
    follow_up_action: str


# --- T-048: Drug Interactions ---
class DrugCheckRequest(BaseModel):
    medication_ids: Optional[List[str]] = None
    medication_names: Optional[List[str]] = None


class DrugCheckResponse(BaseModel):
    has_interactions: bool
    interaction_count: int
    interactions: List[Dict[str, Any]]
    severity_summary: Dict[str, int]  # {"severe": 1, "moderate": 2, ...}


# --- T-049: Prescription Auto-Check ---
class PrescriptionCheckRequest(BaseModel):
    prescription_items: List[Dict[str, Any]] = Field(
        ...,
        description="List of prescription item dicts, each with 'medication_name_en'"
    )


class PrescriptionCheckResponse(BaseModel):
    prescription_safe: bool
    interactions: List[Dict[str, Any]]
    warnings: List[str]


# --- T-050/051: Summarize ---
class SummarizeRequest(BaseModel):
    text: Optional[str] = None
    user_id: Optional[str] = None
    record_id: Optional[str] = None
    source_file_name: Optional[str] = None


class SummarizeResponse(BaseModel):
    id: str
    summary_ar: str
    summary_en: str
    extracted_text: Optional[str] = None
    processing_time_ms: int
    model_used: str
    source_file_type: Optional[str] = None


# =========================================================
# HEALTH CHECK
# =========================================================
@app.get("/health")
async def health():
    return {"status": "healthy", "service": "medorbit-ai", "version": "3.0.0"}


# =========================================================
# T-047: TRIAGE ENDPOINT
# =========================================================
@app.post("/triage", response_model=TriageResponse)
async def triage(
    req: TriageRequest,
    x_medorbit_internal_token: Optional[str] = Header(None),
    x_medorbit_user_id: Optional[str] = Header(None),
):
    """
    Symptom triage: maps symptoms → specialty using rule-based engine.
    Persists session to symptom_triage_sessions table.
    """
    try:
        resolved_user_id, _ = resolve_internal_identity(
            req.user_id, None, x_medorbit_internal_token, x_medorbit_user_id, None
        )

        # 1) Run the mapping engine
        result = await symptom_engine.match(
            symptoms=req.symptoms,
            user_id=uuid.UUID(resolved_user_id) if resolved_user_id else None,
        )

        # 2) Persist to DB
        pool = await get_pool()
        row = await pool.fetchrow(
            """
            INSERT INTO symptom_triage_sessions
                (user_id, session_id, reported_symptoms, triage_level,
                 recommended_specialty_id, recommended_specialty_name_ar,
                 recommended_specialty_name_en, confidence_score,
                 recommendations, follow_up_action)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            RETURNING id
            """,
            uuid.UUID(resolved_user_id) if resolved_user_id else None,
            req.session_id or str(uuid.uuid4()),
            json.dumps({"symptoms": req.symptoms, "matched_keywords": result["matched_keywords"]}),
            result["triage_level"],
            uuid.UUID(result["recommended_specialty_id"]) if result["recommended_specialty_id"] else None,
            result["recommended_specialty_name_ar"],
            result["recommended_specialty_name_en"],
            result["confidence_score"],
            result["recommendations"],
            result["follow_up_action"],
        )

        logger.info(
            "Triage: level=%s, specialty=%s, confidence=%.2f, session=%s",
            result["triage_level"],
            result["recommended_specialty_name_en"],
            result["confidence_score"],
            row["id"],
        )

        return TriageResponse(
            id=str(row["id"]),
            symptoms=req.symptoms,
            triage_level=result["triage_level"],
            recommended_specialty_id=result["recommended_specialty_id"],
            recommended_specialty_name_en=result["recommended_specialty_name_en"],
            recommended_specialty_name_ar=result["recommended_specialty_name_ar"],
            confidence_score=result["confidence_score"],
            specialty_scores=result["specialty_scores"],
            matched_keywords=result["matched_keywords"],
            recommendations=result["recommendations"],
            follow_up_action=result["follow_up_action"],
        )

    except Exception as e:
        logger.error("Triage error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="Triage failed")


# =========================================================
# T-048: DRUG INTERACTIONS ENDPOINT
# =========================================================
@app.post("/drug-interactions", response_model=DrugCheckResponse)
async def drug_interactions(req: DrugCheckRequest):
    """
    Check drug interactions using DB medications.known_interactions JSONB.
    Accepts medication IDs or names.
    """
    try:
        interactions = await drug_matcher.check(
            medication_ids=req.medication_ids,
            medication_names=req.medication_names,
        )

        severity_summary: Dict[str, int] = {}
        for ix in interactions:
            sev = ix["severity"]
            severity_summary[sev] = severity_summary.get(sev, 0) + 1

        return DrugCheckResponse(
            has_interactions=len(interactions) > 0,
            interaction_count=len(interactions),
            interactions=interactions,
            severity_summary=severity_summary,
        )

    except Exception as e:
        logger.error("Drug interaction check error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Drug check failed: {str(e)}")


# =========================================================
# T-049: PRESCRIPTION AUTO-CHECK ENDPOINT
# =========================================================
@app.post("/prescription-check", response_model=PrescriptionCheckResponse)
async def prescription_check(req: PrescriptionCheckRequest):
    """
    Auto-check drug interactions when creating a prescription.
    Takes prescription_items (each with medication_name_en),
    queries DB for known_interactions, returns warnings.
    """
    try:
        med_names = [
            item.get("medication_name_en", "")
            for item in req.prescription_items
            if item.get("medication_name_en")
        ]

        if not med_names:
            return PrescriptionCheckResponse(
                prescription_safe=True,
                interactions=[],
                warnings=["No medications provided for checking."],
            )

        interactions = await drug_matcher.check_prescription_items(med_names)
        warnings: List[str] = []

        for ix in interactions:
            sev_label = ix["severity"].upper()
            warnings.append(
                f"[{sev_label}] {ix['drug_1']['name_en']} + {ix['drug_2']['name_en']}: "
                f"{ix['description']}"
            )

        has_severe = any(ix["severity"] == "severe" for ix in interactions)

        return PrescriptionCheckResponse(
            prescription_safe=not has_severe,
            interactions=interactions,
            warnings=warnings,
        )

    except Exception as e:
        logger.error("Prescription check error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Prescription check failed: {str(e)}")


# =========================================================
# T-050 + T-051: SUMMARIZE ENDPOINT (file upload)
# =========================================================
@app.post("/summarize", response_model=SummarizeResponse)
async def summarize(
    file: Optional[UploadFile] = File(None),
    text: Optional[str] = Form(None),
    user_id: Optional[str] = Form(None),
    record_id: Optional[str] = Form(None),
    x_medorbit_internal_token: Optional[str] = Header(None),
    x_medorbit_user_id: Optional[str] = Header(None),
    x_medorbit_record_id: Optional[str] = Header(None),
):
    """
    Medical report summarization pipeline.
    Accepts either:
      - A file upload (PDF/image) → OCR extraction → LLM bilingual summary
      - Raw text → direct LLM bilingual summary
    Saves to report_summarizations table.
    """
    try:
        resolved_user_id, resolved_record_id = resolve_internal_identity(
            user_id,
            record_id,
            x_medorbit_internal_token,
            x_medorbit_user_id,
            x_medorbit_record_id,
        )

        extracted_text = ""
        source_file_name = None
        source_file_type = None

        if file:
            file_bytes = await file.read()
            source_file_name = file.filename

            ext = (file.filename or "").rsplit(".", 1)[-1].lower() if file.filename else "unknown"
            source_file_type = "pdf" if ext == "pdf" else "image" if ext in {"png", "jpg", "jpeg", "tiff", "bmp"} else "text"

            if not file_bytes:
                raise HTTPException(status_code=400, detail="Empty file uploaded")

            result = doc_extractor.extract_from_bytes(file_bytes, file.filename or "unknown")
            extracted_text = result["text"]
            source_file_type = result["method"]

            if result.get("error") and not extracted_text:
                logger.warning("Extraction issue: %s", result["error"])

        elif text:
            extracted_text = text
            source_file_type = "text"
        else:
            raise HTTPException(status_code=400, detail="Provide either a file or text field")

        if not extracted_text.strip():
            raise HTTPException(
                status_code=422,
                detail="No text could be extracted from the input. "
                       "For images/PDFs, ensure OCR dependencies are installed "
                       "(pdfplumber, pytesseract, pdf2image, tesseract-ocr).",
            )

        # Run LLM summarization + persist
        summary_result = await llm_summarizer.summarize_and_save(
            extracted_text=extracted_text,
            user_id=resolved_user_id,
            record_id=resolved_record_id,
            source_file_name=source_file_name,
            source_file_type=source_file_type,
        )

        return SummarizeResponse(
            id=summary_result["id"],
            summary_ar=summary_result["summary_ar"],
            summary_en=summary_result["summary_en"],
            extracted_text=extracted_text[:2000],  # preview only
            processing_time_ms=summary_result["processing_time_ms"],
            model_used=summary_result["model_used"],
            source_file_type=source_file_type,
        )

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.error("Summarize error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="Summarization failed")


# =========================================================
# CHAT ENDPOINT (existing, enhanced)
# =========================================================
@app.post("/chat")
async def chat(req: ChatRequest):
    pipeline_start = time.time()
    pipeline_log = []

    try:

        # ============================================
        # SPECIAL FLOWS
        # ============================================

        if req.type == "drug_check":
            # Enhanced: try DB-backed checker first
            med_names = []
            med_ids = []
            for m in (req.medications or []):
                if isinstance(m, dict):
                    if m.get("id"):
                        med_ids.append(m["id"])
                    elif m.get("name_en"):
                        med_names.append(m["name_en"])
                    elif m.get("name"):
                        med_names.append(m["name"])

            if med_ids or med_names:
                try:
                    interactions = await drug_matcher.check(
                        medication_ids=med_ids,
                        medication_names=med_names,
                    )
                    if interactions:
                        lines = []
                        for ix in interactions:
                            lines.append(
                                f"  - {ix['drug_1']['name_en']} + {ix['drug_2']['name_en']}: "
                                f"[{ix['severity'].upper()}] {ix['description']}"
                            )
                        reply = "Potential drug interactions found:\n" + "\n".join(lines)
                        return ChatResponse(
                            reply=reply,
                            intent="drug_interaction",
                            confidence=1.0,
                            entities={"interactions": interactions},
                        )
                except Exception as e:
                    logger.warning("DB drug check failed, falling back to in-memory: %s", e)

            # Fallback to legacy in-memory checker
            medications = req.medications or []
            interactions = drug_checker.check_interaction(medications)
            logger.info("Drug check (legacy): %d medications, %d interactions", len(medications), len(interactions))

            if not interactions:
                return ChatResponse(
                    reply="No known serious interactions between these medications.",
                    intent="drug_interaction",
                    confidence=1.0,
                    entities={},
                )

            return ChatResponse(
                reply=f"Potential interaction found: {interactions}",
                intent="drug_interaction",
                confidence=1.0,
                entities={},
            )

        if req.type == "report_summary":
            if not req.record:
                return ChatResponse(
                    reply="No medical record provided for analysis.",
                    intent="report_summary",
                    confidence=0.5,
                    entities={},
                )

            summary = report_summarizer.summarize(req.record)
            logger.info("Report summary generated (legacy): %d chars", len(summary))

            return ChatResponse(
                reply=summary,
                intent="report_summary",
                confidence=1.0,
                entities={},
            )

        # ============================================
        # NORMAL CHAT — Full NLU Pipeline
        # ============================================

        if not req.message:
            return ChatResponse(
                reply="Please enter a message.",
                intent="unknown",
                confidence=0.0,
                entities={},
            )

        message = req.message
        logger.info("=== NEW MESSAGE === | chars=%d", len(message))

        # Step 1: Extract conversation context
        conv_context = None
        if req.context:
            conv_context = {
                "lastIntent": req.context.get("lastIntent"),
                "currentTopic": req.context.get("currentTopic"),
                "entities": req.context.get("entities", {}),
            }
        pipeline_log.append({"step": "context_extraction", "has_context": conv_context is not None})

        # Step 2: Medical Safety Check
        safety_result = safety_layer.check(message)
        pipeline_log.append({
            "step": "safety_check",
            "severity": safety_result["severity"],
            "is_emergency": safety_result["is_emergency"],
        })
        logger.info("Safety check: %s", safety_result["severity"])

        if safety_result["bypass_intent_routing"]:
            logger.warning("EMERGENCY DETECTED: %s", message[:80])
            return ChatResponse(
                reply=safety_result["response"],
                intent="emergency",
                confidence=1.0,
                entities={"is_emergency": True, "matched_patterns": safety_result["matched_patterns"]},
            )

        # Step 3: Intent Classification
        intent_start = time.time()
        intent_result = classifier.classify(message, context=conv_context)
        intent_time = round((time.time() - intent_start) * 1000, 2)
        pipeline_log.append({
            "step": "intent_classification",
            "intent": intent_result["intent"],
            "confidence": intent_result["confidence"],
            "processing_ms": intent_time,
            "is_fallback": intent_result.get("is_fallback", False),
        })

        # Step 4: Entity Extraction
        extract_start = time.time()
        entities = extractor.extract(message, context=conv_context)
        extract_time = round((time.time() - extract_start) * 1000, 2)
        pipeline_log.append({
            "step": "entity_extraction",
            "specialty": entities.get("specialty"),
            "type": entities.get("type"),
            "symptoms": entities.get("symptoms"),
            "location": entities.get("location"),
            "medications": entities.get("medications"),
        })

        entities["intent"] = intent_result["intent"]

        if req.latitude and req.longitude:
            entities["latitude"] = req.latitude
            entities["longitude"] = req.longitude

        # Step 5: Slot Filling
        # NOTE: conversation_id is optional on ChatRequest. When the caller
        # doesn't supply one, we fall back to a per-request UUID rather than
        # hash(message) -- this avoids cross-user state collisions on
        # identical message text, but (unlike a real conversation_id) it
        # does NOT provide multi-turn continuity across requests. True
        # continuity requires the backend/frontend to send a stable
        # conversation_id, which is a separate follow-up.
        slot_info = None
        slot_conversation_id = req.conversation_id or str(uuid.uuid4())
        if intent_result["intent"] != "unknown" and not intent_result.get("is_fallback"):
            slot_filler.update_state(
                slot_conversation_id,
                intent_result["intent"],
                entities,
            )
            slot_state = slot_filler.get_state_summary(slot_conversation_id)
            if slot_state.get("active") and not slot_state.get("completed"):
                next_question = slot_filler.get_next_question(
                    slot_conversation_id,
                    "ar" if any("\u0600" <= c <= "\u06FF" for c in message) else "en",
                )
                slot_info = {"state": slot_state, "next_question": next_question}
                if next_question:
                    logger.info("Slot filling: missing=%s", slot_state["missing_slots"])

        # Step 6: Build RAG Context
        context = retrieve_context(message, entities)

        # Step 7: Determine Response Source
        response_source = "LLM"
        reply = None

        if intent_result["confidence"] >= 0.7 and not intent_result.get("is_fallback"):
            if intent_result["intent"] in ("find_nearest", "find_doctor", "find_pharmacy", "find_hospital"):
                response_source = "RAG"
            elif intent_result["intent"] in ("small_talk", "thanks", "bye", "how_are_you", "yes_confirmation", "no_negation"):
                response_source = "RULE"
                reply = _get_rule_response(intent_result["intent"], message)

        # Step 8: Generate LLM Response
        if reply is None:
            llm_start = time.time()
            lang = "ar" if any("\u0600" <= c <= "\u06FF" for c in message) else "en"
            reply = generate_response(message, context, lang=lang, entities=entities)
            llm_time = round((time.time() - llm_start) * 1000, 2)
            pipeline_log.append({"step": "llm_generation", "processing_ms": llm_time})

        # Step 9: Build Final Response
        total_time = round((time.time() - pipeline_start) * 1000, 2)

        return ChatResponse(
            reply=reply,
            intent=intent_result["intent"],
            confidence=intent_result["confidence"],
            entities={
                **entities,
                "_pipeline": pipeline_log,
                "_total_ms": total_time,
                "_response_source": response_source,
                "_slot_filling": slot_info,
            },
        )

    except Exception as e:
        import traceback
        traceback.print_exc()
        logger.error("Pipeline error: %s", e)
        return ChatResponse(
            reply="An error occurred. Please try again.",
            intent="error",
            confidence=0.0,
            entities={},
        )


def _get_rule_response(intent: str, message: str) -> str:
    """Get rule-based response for simple intents (no LLM needed)."""
    lang = "ar" if any("\u0600" <= c <= "\u06FF" for c in message) else "en"

    responses = {
        "small_talk": {
            "ar": "أهلاً بك في MedOrbit! كيف يمكنني مساعدتك صحياً اليوم؟",
            "en": "Welcome to MedOrbit! How can I help you with your health today?",
        },
        "thanks": {
            "ar": "العفو! دائماً في خدمتك. هل هناك شيء آخر يمكنني مساعدتك به؟",
            "en": "You're welcome! Always happy to help. Is there anything else?",
        },
        "bye": {
            "ar": "مع السلامة! نتمنى لك دوام الصحة والعافية.",
            "en": "Goodbye! Wishing you health and wellness.",
        },
        "how_are_you": {
            "ar": "أنا بخير، شكراً لسؤالك! كيف يمكنني مساعدتك اليوم؟",
            "en": "I'm doing well, thank you! How can I help you today?",
        },
        "yes_confirmation": {
            "ar": "تمام! كيف يمكنني مساعدتك؟",
            "en": "Great! How can I help you?",
        },
        "no_negation": {
            "ar": "حسناً. إذا احتجت أي مساعدة، أنا هنا.",
            "en": "Okay. If you need any help, I'm here.",
        },
    }

    intent_responses = responses.get(intent, {})
    return intent_responses.get(lang, intent_responses.get("en", "How can I help you?"))
