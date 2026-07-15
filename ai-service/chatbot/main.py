from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, Dict, Any
import time
import logging

# Core NLP
from chatbot.intent.classifier import IntentClassifier
from chatbot.entities.extractor import EntityExtractor

# Medical AI
from chatbot.medical.drug_checker import DrugChecker
from chatbot.medical.report_summarizer import ReportSummarizer

# NLU Pipeline
from chatbot.nlu.pipeline import NLUPipeline
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.nlu.slots import SlotFiller
from chatbot.nlu.provider_resolver import ProviderResolver

# LLM + RAG
from rag.retriever import retrieve_context
from llm.llm_service import generate_response

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s'
)
logger = logging.getLogger("medorbit-ai")

# Initialize services
classifier = IntentClassifier()
extractor = EntityExtractor()
drug_checker = DrugChecker()
report_summarizer = ReportSummarizer()

# NLU modules
nlu_pipeline = NLUPipeline()
safety_layer = MedicalSafetyLayer()
slot_filler = SlotFiller()
provider_resolver = ProviderResolver()

# FastAPI app
app = FastAPI(
    title="MedOrbit AI Service",
    version="2.0.0",
    docs=None
)

# CORS (allow backend to call this)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# =========================
# Request Schema
# =========================
class ChatRequest(BaseModel):
    message: Optional[str] = None
    context: Optional[Dict[str, Any]] = None
    type: Optional[str] = None
    medications: Optional[list] = None
    record: Optional[Dict[str, Any]] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None


# =========================
# Response Schema
# =========================
class ChatResponse(BaseModel):
    reply: str
    intent: Optional[str] = None
    confidence: Optional[float] = None
    entities: Optional[Dict[str, Any]] = None


# =========================
# Health Check
# =========================
@app.get("/health")
async def health():
    return {"status": "healthy", "service": "medorbit-ai", "version": "2.0.0"}


# =========================
# Main Endpoint
# =========================
@app.post("/chat")
async def chat(req: ChatRequest):
    pipeline_start = time.time()
    pipeline_log = []

    try:

        # ============================================
        # SPECIAL FLOWS (unchanged, backward compatible)
        # ============================================

        if req.type == "drug_check":
            medications = req.medications or []
            interactions = drug_checker.check_interaction(medications)
            logger.info(f"Drug check: {len(medications)} medications, {len(interactions)} interactions")

            if not interactions:
                return ChatResponse(
                    reply="No known serious interactions between these medications.",
                    intent="drug_interaction",
                    confidence=1.0,
                    entities={}
                )

            return ChatResponse(
                reply=f"Potential interaction found: {interactions}",
                    intent="drug_interaction",
                    confidence=1.0,
                    entities={}
            )

        if req.type == "report_summary":
            if not req.record:
                return ChatResponse(
                    reply="No medical record provided for analysis.",
                    intent="report_summary",
                    confidence=0.5,
                    entities={}
                )

            summary = report_summarizer.summarize(req.record)
            logger.info(f"Report summary generated: {len(summary)} chars")

            return ChatResponse(
                reply=summary,
                intent="report_summary",
                confidence=1.0,
                entities={}
            )

        # ============================================
        # NORMAL CHAT — Full NLU Pipeline
        # ============================================

        if not req.message:
            return ChatResponse(
                reply="Please enter a message.",
                intent="unknown",
                confidence=0.0,
                entities={}
            )

        message = req.message
        logger.info(f"=== NEW MESSAGE === | {message[:100]}")

        # ============================================
        # Step 1: Extract conversation context
        # ============================================
        conv_context = None
        if req.context:
            conv_context = {
                "lastIntent": req.context.get("lastIntent"),
                "currentTopic": req.context.get("currentTopic"),
                "entities": req.context.get("entities", {})
            }
        pipeline_log.append({"step": "context_extraction", "has_context": conv_context is not None})

        # ============================================
        # Step 2: Medical Safety Check (highest priority)
        # ============================================
        safety_result = safety_layer.check(message)
        pipeline_log.append({
            "step": "safety_check",
            "severity": safety_result["severity"],
            "is_emergency": safety_result["is_emergency"]
        })
        logger.info(f"Safety check: {safety_result['severity']}")

        if safety_result["bypass_intent_routing"]:
            logger.warning(f"EMERGENCY DETECTED: {message[:80]}")
            return ChatResponse(
                reply=safety_result["response"],
                intent="emergency",
                confidence=1.0,
                entities={"is_emergency": True, "matched_patterns": safety_result["matched_patterns"]}
            )

        # ============================================
        # Step 3: Intent Classification (with NLU pipeline)
        # ============================================
        intent_start = time.time()
        intent_result = classifier.classify(message, context=conv_context)
        intent_time = round((time.time() - intent_start) * 1000, 2)
        pipeline_log.append({
            "step": "intent_classification",
            "intent": intent_result["intent"],
            "confidence": intent_result["confidence"],
            "processing_ms": intent_time,
            "is_fallback": intent_result.get("is_fallback", False)
        })
        logger.info(f"Intent: {intent_result['intent']} | Confidence: {intent_result['confidence']:.4f} | {intent_time}ms")

        # ============================================
        # Step 4: Entity Extraction (with NLU pipeline)
        # ============================================
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
            "is_follow_up": entities.get("is_follow_up", False),
            "was_corrected": entities.get("was_corrected", False),
            "was_dialect": entities.get("was_dialect", False),
            "processing_ms": extract_time
        })
        logger.info(f"Entities: specialty={entities.get('specialty')} type={entities.get('type')} "
                    f"symptoms={entities.get('symptoms')} location={entities.get('location')} "
                    f"corrected={entities.get('was_corrected')} dialect={entities.get('was_dialect')} | {extract_time}ms")

        # Add intent info to entities for RAG
        entities["intent"] = intent_result["intent"]

        # Add location to entities for RAG
        if req.latitude and req.longitude:
            entities["latitude"] = req.latitude
            entities["longitude"] = req.longitude
            pipeline_log.append({"step": "location_added", "lat": req.latitude, "lng": req.longitude})

        # ============================================
        # Step 5: Slot Filling
        # ============================================
        slot_info = None
        if intent_result["intent"] != "unknown" and not intent_result.get("is_fallback"):
            slot_filler.update_state(
                str(hash(message)),  # Use message hash as conversation ID for stateless tracking
                intent_result["intent"],
                entities
            )
            slot_state = slot_filler.get_state_summary(str(hash(message)))
            if slot_state.get("active") and not slot_state.get("completed"):
                next_question = slot_filler.get_next_question(
                    str(hash(message)),
                    "ar" if any('\u0600' <= c <= '\u06FF' for c in message) else "en"
                )
                slot_info = {
                    "state": slot_state,
                    "next_question": next_question
                }
                pipeline_log.append({
                    "step": "slot_filling",
                    "missing_slots": slot_state["missing_slots"],
                    "has_next_question": next_question is not None
                })
                if next_question:
                    logger.info(f"Slot filling: missing={slot_state['missing_slots']} next_q={next_question['question'][:60]}")

        # ============================================
        # Step 6: Build RAG Context
        # ============================================
        context = retrieve_context(message, entities)
        pipeline_log.append({"step": "rag_retrieval", "context_type": entities.get("intent", "unknown")})

        # ============================================
        # Step 7: Determine Response Source
        # ============================================
        response_source = "LLM"
        reply = None

        # If confidence is high and we have structured data, use rule-based response
        if intent_result["confidence"] >= 0.7 and not intent_result.get("is_fallback"):
            if intent_result["intent"] in ("find_nearest", "find_doctor", "find_pharmacy", "find_hospital"):
                response_source = "RAG"
                # The backend will handle the actual data retrieval
                # We just generate a contextual response
                reply = None  # Let LLM handle it with RAG context
            elif intent_result["intent"] in ("small_talk", "thanks", "bye", "how_are_you", "yes_confirmation", "no_negation"):
                response_source = "RULE"
                reply = _get_rule_response(intent_result["intent"], message)
                logger.info(f"Rule-based response: {intent_result['intent']}")

        # ============================================
        # Step 8: Generate LLM Response (if needed)
        # ============================================
        if reply is None:
            llm_start = time.time()
            lang = "ar" if any('\u0600' <= c <= '\u06FF' for c in message) else "en"
            reply = generate_response(message, context, lang=lang, entities=entities)
            llm_time = round((time.time() - llm_start) * 1000, 2)
            pipeline_log.append({"step": "llm_generation", "processing_ms": llm_time})
            logger.info(f"LLM response: {llm_time}ms | Source: {response_source}")

        # ============================================
        # Step 9: Build Final Response
        # ============================================
        total_time = round((time.time() - pipeline_start) * 1000, 2)
        pipeline_log.append({"step": "complete", "total_ms": total_time, "response_source": response_source})
        logger.info(f"=== COMPLETE === | {total_time}ms | Source: {response_source} | Intent: {intent_result['intent']}")

        return ChatResponse(
            reply=reply,
            intent=intent_result["intent"],
            confidence=intent_result["confidence"],
            entities={
                **entities,
                "_pipeline": pipeline_log,
                "_total_ms": total_time,
                "_response_source": response_source,
                "_slot_filling": slot_info
            }
        )

    except Exception as e:
        import traceback
        traceback.print_exc()
        logger.error(f"Pipeline error: {str(e)}")

        return ChatResponse(
            reply="An error occurred. Please try again.",
            intent="error",
            confidence=0.0,
            entities={}
        )


def _get_rule_response(intent: str, message: str) -> str:
    """Get rule-based response for simple intents (no LLM needed)."""
    lang = "ar" if any('\u0600' <= c <= '\u06FF' for c in message) else "en"

    responses = {
        "small_talk": {
            "ar": "أهلاً بك في MedOrbit! كيف يمكنني مساعدتك صحياً اليوم؟ 🩺",
            "en": "Welcome to MedOrbit! How can I help you with your health today? 🩺"
        },
        "thanks": {
            "ar": "العفو! دائماً في خدمتك. هل هناك شيء آخر يمكنني مساعدتك به؟ 😊",
            "en": "You're welcome! Always happy to help. Is there anything else? 😊"
        },
        "bye": {
            "ar": "مع السلامة! نتمنى لك دوام الصحة والعافية. 👋",
            "en": "Goodbye! Wishing you health and wellness. 👋"
        },
        "how_are_you": {
            "ar": "أنا بخير، شكراً لسؤالك! كيف يمكنني مساعدتك اليوم؟ 😊",
            "en": "I'm doing well, thank you! How can I help you today? 😊"
        },
        "yes_confirmation": {
            "ar": "تمام! كيف يمكنني مساعدتك؟",
            "en": "Great! How can I help you?"
        },
        "no_negation": {
            "ar": "حسناً. إذا احتجت أي مساعدة، أنا هنا.",
            "en": "Okay. If you need any help, I'm here."
        }
    }

    intent_responses = responses.get(intent, {})
    return intent_responses.get(lang, intent_responses.get("en", "How can I help you?"))