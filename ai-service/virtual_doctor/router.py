import logging
import os
from typing import Optional

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response

from . import interview_engine as engine
from . import report_generator
from .schemas import (
    MessageRequest,
    MessageResponse,
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

router = APIRouter(prefix="/virtual-doctor", tags=["virtual-doctor"])


@router.post("/start", response_model=StartResponse)
async def start(req: StartRequest):
    result = await engine.start_session(req.language, req.user_id)
    return StartResponse(**result)


@router.post("/message", response_model=MessageResponse)
async def message(req: MessageRequest):
    try:
        result = await engine.handle_message(req.session_id, req.message)
    except ValueError:
        raise HTTPException(status_code=404, detail="Session not found")
    return MessageResponse(**result)


@router.get("/session/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str):
    state = await engine.get_session_state(session_id)
    if not state:
        raise HTTPException(status_code=404, detail="Session not found")
    return SessionResponse(**state)


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
async def create_report(session_id: str):
    try:
        report = await report_generator.generate_report(session_id)
    except report_generator.PdfGenerationUnavailable as exc:
        # The consultation and its data are fine — only the PDF renderer is
        # broken on this machine (see pdf_worker.py). 503 so the client can
        # say "temporarily unavailable" rather than "your report failed".
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
async def transcribe_warmup():
    """Load the Whisper model now instead of during the patient's first answer.

    Cold-loading costs ~9s, which otherwise lands entirely on turn one of a
    consultation. The client fires this when the session starts so the load
    overlaps the greeting.
    """
    try:
        return SttStatusResponse(**await stt.warmup())
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
    except stt.AudioTooLongError as exc:
        raise HTTPException(status_code=413, detail=str(exc))
    except stt.AudioDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Could not decode audio: {exc}")
    except Exception as exc:  # noqa: BLE001 - model load / runtime failures
        logger.exception("Transcription failed")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}")


@router.get("/report/{report_id}/download")
async def download_report(report_id: str):
    pdf_path = await report_generator.get_report_pdf_path(report_id)
    if not pdf_path or not os.path.exists(pdf_path):
        raise HTTPException(status_code=404, detail="Report not found")
    return FileResponse(pdf_path, media_type="application/pdf", filename=f"{report_id}.pdf")
