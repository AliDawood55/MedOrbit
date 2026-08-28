import logging
import os
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response

from identity_boundary import require_internal_identity

from . import interview_engine as engine
from . import reasoning_engine, report_generator
from .schemas import (
    MessageRequest,
    MessageResponse,
    ReasoningHealthResponse,
    ReportResponse,
    SessionResponse,
    SpeakRequest,
    SttStatusResponse,
    StartRequest,
    StartResponse,
    TranscriptionResponse,
    TtsStatusResponse,
)
from .voice import stt, tts

logger = logging.getLogger(__name__)


async def internal_identity(
    x_medorbit_internal_token: Optional[str] = Header(None),
    x_medorbit_user_id: Optional[str] = Header(None),
) -> str:
    """The authenticated user, as vouched for by the MedOrbit backend.

    Returns a user id only when the caller presented the shared internal
    credential; otherwise raises 403. Declared as a router-level dependency
    below as well as an argument here, so a future endpoint added to this
    router is protected even if its author forgets to ask for the identity.
    """
    return require_internal_identity(None, x_medorbit_internal_token, x_medorbit_user_id)


router = APIRouter(
    prefix="/virtual-doctor",
    tags=["virtual-doctor"],
    dependencies=[Depends(internal_identity)],
)


@router.post("/start", response_model=StartResponse)
async def start(req: StartRequest, user_id: str = Depends(internal_identity)):
    if req.user_id:
        raise HTTPException(status_code=403, detail="Client-supplied identity is not accepted")
    result = await engine.start_session(req.language, user_id)
    return StartResponse(**result)


@router.post("/message", response_model=MessageResponse)
async def message(req: MessageRequest, user_id: str = Depends(internal_identity)):
    try:
        result = await engine.handle_message(req.session_id, req.message, owner_user_id=user_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Session not found")
    return MessageResponse(**result)


@router.get("/session/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str, user_id: str = Depends(internal_identity)):
    state = await engine.get_session_state(session_id, owner_user_id=user_id)
    if not state:
        raise HTTPException(status_code=404, detail="Session not found")
    return SessionResponse(**state)


@router.get("/reasoning/health", response_model=ReasoningHealthResponse)
async def reasoning_health():
    """Whether the symbolic reasoning layer is enabled and its rules loaded.

    Boots the Prolog engine on first call if the runtime is present, so this
    doubles as a warm-up. Never raises: a missing SWI-Prolog reports
    loaded=false with the error rather than failing the request, because in
    Phase 1 that state is entirely survivable — the consultation path does not
    depend on this layer at all.
    """
    return ReasoningHealthResponse(**reasoning_engine.status())


@router.get("/speak/status", response_model=TtsStatusResponse)
async def speak_status():
    return TtsStatusResponse(**tts.get_status())


@router.post("/speak/warmup", response_model=TtsStatusResponse)
async def speak_warmup():
    """Load the Piper voices before the first reply needs them."""
    return TtsStatusResponse(**await tts.warmup())


@router.post("/speak")
async def speak(req: SpeakRequest):
    """Render a doctor reply to speech.

    Returns audio/wav. A failure here must never block the consultation, so
    the client is expected to carry on showing text on any non-200.
    """
    try:
        result = await tts.synthesize(req.text, req.language)
    except tts.TtsError as exc:
        raise HTTPException(status_code=503, detail=f"tts_unavailable: {exc}")
    except Exception as exc:  # noqa: BLE001
        logger.exception("TTS failed")
        raise HTTPException(status_code=503, detail=f"tts_unavailable: {exc}")

    return Response(
        content=result["audio"],
        media_type="audio/wav",
        headers={
            "X-TTS-Voice": result["voice"],
            "X-TTS-Language": result["language"],
            "X-TTS-Cached": "1" if result["cached"] else "0",
            "X-TTS-Synthesis-Seconds": str(result["synthesis_seconds"]),
            "Cache-Control": "public, max-age=86400",
        },
    )


@router.post("/report/{session_id}", response_model=ReportResponse)
async def create_report(session_id: str, user_id: str = Depends(internal_identity)):
    try:
        report = await report_generator.generate_report(session_id, owner_user_id=user_id)
    except report_generator.PdfGenerationUnavailable as exc:
        raise HTTPException(status_code=503, detail=f"pdf_unavailable: {exc}")
    if not report:
        raise HTTPException(status_code=404, detail="Session not found")
    return ReportResponse(
        report_id=report["report_id"],
        session_id=report["session_id"],
        urgency_level=report["urgency_level"],
        recommended_specialty_name_en=report["recommended_specialty_name_en"],
        recommended_specialty_name_ar=report["recommended_specialty_name_ar"],
        download_url=f"/virtual-doctor/report/{report['report_id']}/download",
    )


@router.get("/transcribe/status", response_model=SttStatusResponse)
async def transcribe_status():
    """Whether the Whisper model is already resident.

    Lets the UI warn that the first recording will be slow (model download +
    load) instead of looking frozen.
    """
    return SttStatusResponse(**stt.get_status())


@router.post("/transcribe/warmup", response_model=SttStatusResponse)
async def transcribe_warmup(language: Optional[str] = None):
    """Load the Whisper model now instead of during the patient's first answer.

    Cold-loading costs ~9s, which otherwise lands entirely on turn one of a
    consultation. The client fires this when the session starts so the load
    overlaps the greeting.

    `language` picks which model to warm — Arabic and English use different
    sizes on CPU, so warming the wrong one still leaves a cold load on turn one.
    """
    try:
        return SttStatusResponse(**await stt.warmup(language))
    except Exception as exc:  # noqa: BLE001 - warmup is best-effort
        logger.exception("STT warmup failed")
        raise HTTPException(status_code=503, detail=f"warmup failed: {exc}")


@router.post("/transcribe", response_model=TranscriptionResponse)
async def transcribe(
    audio: UploadFile = File(...),
    language: Optional[str] = Form(None),
):
    """Transcribe a recorded audio blob (WebM/Opus, MP4/AAC, WAV, OGG…).

    `language` is an optional "ar"/"en" hint; omit it to auto-detect.
    """
    data = await audio.read()
    try:
        return TranscriptionResponse(**await stt.transcribe(data, language))
    except stt.TranscriptionTimeout as exc:
        logger.warning("Transcription timed out: %s", exc)
        return TranscriptionResponse(
            text="",
            detected_language=language or "",
            timed_out=True,
        )
    except stt.AudioTooLongError as exc:
        raise HTTPException(status_code=413, detail=str(exc))
    except stt.AudioDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Could not decode audio: {exc}")
    except Exception as exc:  # noqa: BLE001 - model load / runtime failures
        logger.exception("Transcription failed")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}")


@router.get("/report/{report_id}/download")
async def download_report(report_id: str, user_id: str = Depends(internal_identity)):
    pdf_path = await report_generator.get_report_pdf_path(report_id, owner_user_id=user_id)
    if not pdf_path or not os.path.exists(pdf_path):
        raise HTTPException(status_code=404, detail="Report not found")
    return FileResponse(pdf_path, media_type="application/pdf", filename=f"{report_id}.pdf")
