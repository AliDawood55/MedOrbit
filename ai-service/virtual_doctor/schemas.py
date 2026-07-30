from typing import Any, Dict, List, Optional

from pydantic import BaseModel


class StartRequest(BaseModel):
    language: Optional[str] = "en"
    user_id: Optional[str] = None


class StartResponse(BaseModel):
    session_id: str
    reply: str
    phase: str
    # Echoed back so the client can pin STT to this language for every turn
    # instead of auto-detecting — detection is unreliable on short answers.
    language: str = "en"


class MessageRequest(BaseModel):
    session_id: str
    message: str


class MessageResponse(BaseModel):
    session_id: str
    reply: str
    phase: str
    chief_complaint: Optional[str] = None
    urgency_level: Optional[str] = None
    profile_snapshot: Dict[str, Any] = {}
    recommended_specialty_id: Optional[str] = None
    recommended_specialty_name_en: Optional[str] = None
    recommended_specialty_name_ar: Optional[str] = None
    confidence: Optional[float] = None
    differential: Optional[Dict[str, Any]] = None


class SessionMessage(BaseModel):
    role: str
    text: str


class ReportResponse(BaseModel):
    report_id: str
    session_id: str
    urgency_level: Optional[str] = None
    recommended_specialty_name_en: Optional[str] = None
    recommended_specialty_name_ar: Optional[str] = None
    download_url: str


class TranscriptionResponse(BaseModel):
    text: str
    detected_language: str
    language_probability: float = 1.0
    language_was_forced: bool = False
    language_was_snapped: bool = False
    audio_seconds: float = 0.0
    processing_seconds: float = 0.0
    model: str = ""


class SttStatusResponse(BaseModel):
    model: str
    device: str
    compute_type: str
    loaded: bool
    load_error: Optional[str] = None
    device_fallback_reason: Optional[str] = None
    cuda_libraries_found: bool = False
    supported_languages: List[str] = []


class SpeakRequest(BaseModel):
    text: str
    language: Optional[str] = None


class TtsStatusResponse(BaseModel):
    engine: str
    voices: Dict[str, str] = {}
    loaded: List[str] = []
    load_errors: Dict[str, str] = {}
    cache_entries: int = 0
    stats: Dict[str, int] = {}


class SessionResponse(BaseModel):
    session_id: str
    language: str
    chief_complaint: Optional[str] = None
    phase: str
    patient_profile: Dict[str, Any] = {}
    urgency_level: Optional[str] = None
    recommended_specialty_id: Optional[str] = None
    differential: Optional[Dict[str, Any]] = None
    messages: List[SessionMessage] = []
