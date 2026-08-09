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
    # True when decoding hit the deadline. The client uses this to tell the
    # patient to repeat instead of silently discarding the turn.
    timed_out: bool = False


class SttStatusResponse(BaseModel):
    model: str
    # Per-language sizes; ar and en can resolve to different models on CPU.
    model_by_language: Dict[str, str] = {}
    models_loaded: List[str] = []
    device: str
    compute_type: str
    loaded: bool
    load_error: Optional[str] = None
    device_fallback_reason: Optional[str] = None
    cuda_libraries_found: bool = False
    supported_languages: List[str] = []
    timeout_seconds: float = 0.0


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


class ReasoningHealthResponse(BaseModel):
    """Symbolic reasoning layer health. Audit/ops only — no patient data.

    `enabled` is the VD_SYMBOLIC flag; `loaded` is whether SWI-Prolog actually
    booted. They are separate on purpose: a machine with the flag on and no
    Prolog runtime is a real deployment state, and it should be visible rather
    than inferred from silence in the logs.
    """
    enabled: bool
    # Phase 2 rollout state: off | shadow | active. Always "off" when the
    # master switch is off, so one field answers "is the interview symbolic?".
    interview_mode: str = "off"
    # Phase 3 rollout state: off | shadow | active. Independent of
    # interview_mode; also forced "off" when the master switch is off.
    safety_mode: str = "off"
    inference_limit: int = 0
    loaded: bool
    load_error: Optional[str] = None
    rule_files: List[str] = []
    init_ms: float = 0.0
    max_results: int = 0
    prolog_version: Optional[str] = None


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
