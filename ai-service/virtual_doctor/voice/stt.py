"""Speech-to-text for the AI Virtual Doctor, wrapping faster-whisper.

Takes a raw audio blob straight from the browser's MediaRecorder (WebM/Opus in
Chrome and Firefox, MP4/AAC in Safari) and returns transcribed text plus the
detected language.

No ffmpeg binary is required: faster-whisper decodes through PyAV, which ships
prebuilt FFmpeg libraries inside its own wheel, so container/laptop setup stays
`pip install` only.

The Whisper model is loaded lazily on first use (loading it at import would
stall ai-service startup, and the very first load also downloads the weights)
and then cached for the process lifetime.
"""

from __future__ import annotations

import asyncio
import io
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, Optional, Tuple

logger = logging.getLogger(__name__)


def _register_cuda_libraries() -> bool:
    """Put the pip-installed CUDA runtime DLLs where the loader can find them.

    `pip install nvidia-cublas-cu12 nvidia-cudnn-cu12` drops its libraries
    inside site-packages, which is not on PATH — without this, CTranslate2
    fails at inference with "Library cublas64_12.dll is not found" even though
    a CUDA device is visible. Linux wheels use lib/, Windows wheels use bin/.
    """
    try:
        import nvidia
    except ImportError:
        return False

    # Namespace package: __file__ is None, so __path__ is the way in.
    roots = list(getattr(nvidia, "__path__", []))
    if not roots:
        return False

    found = False
    for pkg in ("cublas", "cudnn", "cuda_nvrtc"):
        for sub in ("bin", "lib"):
            path = os.path.join(roots[0], pkg, sub)
            if not os.path.isdir(path):
                continue
            found = True
            if hasattr(os, "add_dll_directory"):   # Windows only
                try:
                    os.add_dll_directory(path)
                except OSError:
                    pass
            os.environ["PATH"] = path + os.pathsep + os.environ.get("PATH", "")
    return found


_CUDA_LIBS_REGISTERED = _register_cuda_libraries()

# --- Configuration (env-overridable so model size can be tuned per machine) ---
#
# 'medium' is the default because Arabic is the accuracy bottleneck, not
# English: measured on real FLEURS ar_eg speech, 'small' scored 21.4% WER
# against 'medium' at 7.1%, while both still transcribe faster than real time
# on CPU. Set VD_STT_MODEL=small for quicker dev iteration, or large-v3 if a
# working CUDA runtime is available.
MODEL_SIZE = os.getenv("VD_STT_MODEL", "medium")
# "auto" prefers CUDA and falls back to CPU; force with "cuda" / "cpu".
#
# This matters far more than it looks: Whisper pads every utterance to a fixed
# 30s encoder window, so a 2-second answer costs almost the same as a 12-second
# one. Measured on this project's hardware, 'medium' on a 2s utterance takes
# ~7.8s on CPU versus ~0.6s on CUDA — the difference between a conversation
# and a form. Hands-free turn-taking is only viable on the GPU path.
DEVICE = os.getenv("VD_STT_DEVICE", "auto")
COMPUTE_TYPE = os.getenv("VD_STT_COMPUTE", "auto")
CPU_THREADS = int(os.getenv("VD_STT_CPU_THREADS", "0"))  # 0 = let CTranslate2 decide
BEAM_SIZE = int(os.getenv("VD_STT_BEAM_SIZE", "5"))

# This module is bilingual by design; Whisper can detect ~99 languages, but a
# short/noisy clip sometimes lands on a neighbour of Arabic (fa/ur) or English
# (cy/nl). Anything outside this set is snapped back to the closest of the two.
SUPPORTED_LANGUAGES = ("ar", "en")

SAMPLE_RATE = 16000
MAX_AUDIO_BYTES = 25 * 1024 * 1024
MAX_AUDIO_SECONDS = 120

_model = None
_model_lock = threading.Lock()
_load_error: Optional[str] = None
# Resolved once the model actually loads — "auto" is not an answer.
_active_device: Optional[str] = None
_active_compute: Optional[str] = None
_device_fallback_reason: Optional[str] = None

# A CTranslate2 model must not run concurrent transcriptions from several
# threads, and on CPU parallel requests would only thrash the same cores, so
# every transcription is serialised through a single worker thread. It still
# runs off the event loop, which is the part that matters for FastAPI.
_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="vd-stt")


class SttError(Exception):
    """Base class for expected, client-reportable STT failures."""


class AudioDecodeError(SttError):
    """The uploaded blob could not be decoded as audio."""


class AudioTooLongError(SttError):
    """The recording exceeds MAX_AUDIO_SECONDS."""


def _build_model(device: str, compute_type: str):
    """Construct a model AND prove it can actually run.

    Constructing a CUDA model succeeds even when the CUDA runtime libraries are
    missing — the failure only surfaces on the first encoder pass. So the smoke
    test below is the real check, not the constructor.
    """
    import numpy as np
    from faster_whisper import WhisperModel

    model = WhisperModel(
        MODEL_SIZE, device=device, compute_type=compute_type, cpu_threads=CPU_THREADS
    )
    silence = np.zeros(SAMPLE_RATE, dtype="float32")
    segments, _ = model.transcribe(silence, language="en", vad_filter=False, beam_size=1)
    list(segments)  # force the generator; this is where cuBLAS/cuDNN would blow up
    return model


def _resolve_device() -> Tuple[str, str]:
    if DEVICE != "auto":
        return DEVICE, ("int8" if COMPUTE_TYPE == "auto" and DEVICE == "cpu"
                        else "float16" if COMPUTE_TYPE == "auto" else COMPUTE_TYPE)
    return "cuda", ("float16" if COMPUTE_TYPE == "auto" else COMPUTE_TYPE)


def _get_model():
    """Load (and on the very first call, download) the Whisper model once."""
    global _model, _load_error, _active_device, _active_compute, _device_fallback_reason
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model

        device, compute = _resolve_device()
        started = time.time()
        logger.info(
            "Loading Whisper model '%s' (device=%s, compute=%s) — first run downloads weights",
            MODEL_SIZE, device, compute,
        )
        try:
            _model = _build_model(device, compute)
        except Exception as exc:  # noqa: BLE001
            if DEVICE != "auto" or device == "cpu":
                _load_error = f"{type(exc).__name__}: {exc}"
                logger.exception("Whisper model failed to load")
                raise
            # auto mode: CUDA is unusable on this machine, fall back to CPU.
            _device_fallback_reason = f"{type(exc).__name__}: {exc}"
            logger.warning(
                "CUDA unusable (%s) — falling back to CPU. Expect ~8s per "
                "utterance instead of ~0.6s; hands-free turn-taking will feel slow.",
                _device_fallback_reason,
            )
            device, compute = "cpu", ("int8" if COMPUTE_TYPE == "auto" else COMPUTE_TYPE)
            try:
                _model = _build_model(device, compute)
            except Exception as cpu_exc:  # noqa: BLE001
                _load_error = f"{type(cpu_exc).__name__}: {cpu_exc}"
                logger.exception("Whisper model failed to load on CPU too")
                raise

        _active_device, _active_compute = device, compute
        _load_error = None
        logger.info(
            "Whisper model '%s' ready on %s/%s in %.1fs",
            MODEL_SIZE, device, compute, time.time() - started,
        )
        return _model


def is_loaded() -> bool:
    return _model is not None


def get_status() -> Dict[str, Any]:
    """Cheap, non-blocking status — lets the UI warn about a slow first call."""
    return {
        "model": MODEL_SIZE,
        "device": _active_device or DEVICE,
        "compute_type": _active_compute or COMPUTE_TYPE,
        "loaded": _model is not None,
        "load_error": _load_error,
        "device_fallback_reason": _device_fallback_reason,
        "cuda_libraries_found": _CUDA_LIBS_REGISTERED,
        "supported_languages": list(SUPPORTED_LANGUAGES),
    }


def _pick_supported_language(info) -> tuple[str, bool]:
    """Map Whisper's detected language onto {ar, en}.

    Returns (language, was_snapped). `all_language_probs` is only populated
    when detection actually ran, so fall back to Arabic-vs-English by whichever
    the detector preferred, and to the raw guess if we have nothing to go on.
    """
    detected = info.language
    if detected in SUPPORTED_LANGUAGES:
        return detected, False

    probs = dict(info.all_language_probs or [])
    if not probs:
        return detected, False
    best = max(SUPPORTED_LANGUAGES, key=lambda code: probs.get(code, 0.0))
    return best, True


def _transcribe_sync(data: bytes, language: Optional[str]) -> Dict[str, Any]:
    from faster_whisper.audio import decode_audio

    # Decode once to a float32 waveform so a language-snap retry does not have
    # to re-demux the container.
    try:
        audio = decode_audio(io.BytesIO(data), sampling_rate=SAMPLE_RATE)
    except Exception as exc:  # noqa: BLE001 - any PyAV failure means "not usable audio"
        raise AudioDecodeError(str(exc)) from exc

    if audio is None or len(audio) == 0:
        raise AudioDecodeError("decoded audio is empty")

    duration = len(audio) / SAMPLE_RATE
    if duration > MAX_AUDIO_SECONDS:
        raise AudioTooLongError(f"{duration:.0f}s exceeds the {MAX_AUDIO_SECONDS}s limit")

    model = _get_model()

    common = dict(
        beam_size=BEAM_SIZE,
        vad_filter=True,               # trims the silence around a click-to-record clip
        condition_on_previous_text=False,  # short utterances; avoids repeat-loop hallucinations
    )

    started = time.time()
    # `transcribe` runs language detection eagerly and returns `info` before
    # any audio is decoded — the returned generator is lazy. Deciding the
    # language *before* consuming it means a snap costs one extra detection
    # pass, not a whole wasted transcription.
    segments, info = model.transcribe(audio, language=language, **common)

    language_snapped = False
    if language is None:
        chosen, language_snapped = _pick_supported_language(info)
        if language_snapped:
            logger.info(
                "Detected '%s' is outside %s — re-running forced to '%s'",
                info.language, SUPPORTED_LANGUAGES, chosen,
            )
            segments, info = model.transcribe(audio, language=chosen, **common)
            detected_language = chosen
        else:
            detected_language = info.language
    else:
        detected_language = language

    text = "".join(segment.text for segment in segments).strip()

    return {
        "text": text,
        "detected_language": detected_language,
        "language_probability": round(float(info.language_probability or 1.0), 4),
        "language_was_forced": language is not None,
        "language_was_snapped": language_snapped,
        "audio_seconds": round(duration, 2),
        "processing_seconds": round(time.time() - started, 2),
        "model": MODEL_SIZE,
    }


async def transcribe(data: bytes, language: Optional[str] = None) -> Dict[str, Any]:
    """Transcribe an audio blob.

    `language` is an optional "ar"/"en" hint; anything else (including None)
    means auto-detect. Runs off the event loop.
    """
    if not data:
        raise AudioDecodeError("empty upload")
    if len(data) > MAX_AUDIO_BYTES:
        raise AudioTooLongError(f"upload exceeds {MAX_AUDIO_BYTES // (1024 * 1024)}MB")

    hint = language if language in SUPPORTED_LANGUAGES else None
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_executor, _transcribe_sync, data, hint)


async def warmup() -> Dict[str, Any]:
    """Force the model to load now rather than during a user's first recording."""
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(_executor, _get_model)
    return get_status()
