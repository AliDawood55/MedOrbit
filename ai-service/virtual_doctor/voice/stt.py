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
    """Put the pip-installed CUDA runtime libraries where the loader can find them.

    `pip install nvidia-cublas-cu12 nvidia-cudnn-cu12` drops its libraries
    inside site-packages, which is not on the loader's search path — without
    this, CTranslate2 fails at inference with "Library cublas64_12.dll is not
    found" even though a CUDA device is visible. Windows wheels use bin/,
    Linux wheels use lib/.

    The two platforms need genuinely different treatment:

      * Windows resolves DLL dependencies through PATH + add_dll_directory,
        so registering the directory is enough.
      * Linux resolves .so files through the dynamic loader, which reads
        LD_LIBRARY_PATH once at process start. Mutating os.environ afterwards
        has NO effect on the running process — the directory-registration
        approach is a silent no-op there. The libraries must instead be opened
        explicitly with RTLD_GLOBAL so their symbols are already resident when
        CTranslate2 later dlopen()s its own extension against them.

    Returns True only if the CUDA runtime is actually usable, so callers can
    tell "no GPU support installed" apart from "GPU support present".
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
            if os.name == "posix":
                _preload_shared_objects(path)
    return found


def _preload_shared_objects(directory: str) -> None:
    """dlopen every .so in `directory` with RTLD_GLOBAL.

    Best-effort by design: these libraries have load-order dependencies
    (cuDNN needs cuBLAS), and rather than hardcode a fragile order this makes
    two passes and lets the second pick up whatever the first could not
    satisfy. A library that still fails is left to CTranslate2 to complain
    about with a far more specific message than anything raised here.
    """
    import ctypes
    import glob

    pending = sorted(glob.glob(os.path.join(directory, "*.so*")))
    for _ in range(2):
        if not pending:
            return
        retry = []
        for lib in pending:
            try:
                ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
            except OSError:
                retry.append(lib)
        if len(retry) == len(pending):
            break  # no progress; the rest are genuinely unloadable
        pending = retry


_CUDA_LIBS_REGISTERED = _register_cuda_libraries()

# --- Configuration (env-overridable so model size can be tuned per machine) ---
#
# MODEL SIZE IS CHOSEN PER DEVICE, because the right answer genuinely differs.
#
# 'medium' is the accuracy choice: Arabic is the accuracy bottleneck, not
# English — measured on real FLEURS ar_eg speech, 'small' scored 21.4% WER
# against 'medium' at 7.1%. That rationale still stands and is why CUDA keeps
# 'medium'.
#
# But on CPU 'medium' is not affordable. Measured on this container (20 cores,
# int8, language hint supplied, real bilingual speech):
#
#     medium   en 2.99s   ar 3.10s      <- blows a 2s conversational budget
#     small    en 1.10s   ar 1.15s
#     base     en 0.45s   ar 0.47s
#
# On GPU 'medium' costs ~0.6s, so there is no trade to make there. On CPU there
# is, and a 3s pause after every answer is not a consultation. So: CUDA gets
# 'medium' (fast AND accurate), CPU falls back to 'small' (the smallest step
# down that still meets the latency budget — 'base' is faster still but visibly
# drops words, e.g. "ما اسمك" -> "ماسم").
#
# This also self-heals: fix the CUDA driver and the accurate model comes back
# automatically, with no config change.
#
# VD_STT_MODEL still forces one size on every device (back-compatible);
# VD_STT_MODEL_CPU / VD_STT_MODEL_CUDA tune a single path.
# SIZE IS ALSO LANGUAGE-AWARE ON CPU, because the accuracy cliff is not
# symmetric. 'small' is fine for English but genuinely fails on Arabic — real
# users reported it not understanding a spoken name, which matches the FLEURS
# ar_eg numbers above (21.4% vs 7.1% WER). English keeps 'small' and stays
# ~1.1s; Arabic pays ~3.3s for a transcript that is actually usable. A wrong
# transcript is not faster, it is just wrong: it silently corrupts the symptom
# text feeding triage, retrieval and the differential.
MODEL_SIZE_OVERRIDE = os.getenv("VD_STT_MODEL")
MODEL_SIZE_CUDA = os.getenv("VD_STT_MODEL_CUDA", "medium")
MODEL_SIZE_CPU_AR = os.getenv("VD_STT_MODEL_CPU_AR", "medium")
MODEL_SIZE_CPU_EN = os.getenv("VD_STT_MODEL_CPU_EN", "small")


def _model_size_for(device: str, language: Optional[str] = None) -> str:
    """Which Whisper size to load for `device`/`language`. Override wins.

    On CUDA there is no trade — 'medium' is ~0.6s — so both languages get it.
    Auto-detect (language=None) has to assume the harder language, since
    picking 'small' and discovering the speaker was Arabic is unrecoverable.
    """
    if MODEL_SIZE_OVERRIDE:
        return MODEL_SIZE_OVERRIDE
    if device == "cuda":
        return MODEL_SIZE_CUDA
    return MODEL_SIZE_CPU_EN if language == "en" else MODEL_SIZE_CPU_AR
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

# A hard ceiling on decoding one utterance. Whisper can occasionally get stuck
# emitting repetitive segments on a short/noisy clip; without a ceiling that
# wedges the single worker thread below and every later turn queues behind it
# forever, which is exactly the "stuck on 'transcribing'" report. The deadline
# is checked between segments, so the worker always returns and the queue
# always drains. It deliberately does NOT cover model loading — a first-run
# weight download legitimately takes minutes and must not be killed.
TRANSCRIBE_TIMEOUT = float(os.getenv("VD_STT_TIMEOUT", "10"))

# One entry per loaded size; ar and en can resolve to different models.
_models: Dict[str, Any] = {}
_model_lock = threading.Lock()
_load_error: Optional[str] = None
# Resolved once the first model loads — "auto" is not an answer.
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


class TranscriptionTimeout(SttError):
    """Decoding blew through TRANSCRIBE_TIMEOUT without producing usable text."""


def _build_model(size: str, device: str, compute_type: str):
    """Construct a model AND prove it can actually run.

    Constructing a CUDA model succeeds even when the CUDA runtime libraries are
    missing — the failure only surfaces on the first encoder pass. So the smoke
    test below is the real check, not the constructor.
    """
    import numpy as np
    from faster_whisper import WhisperModel

    model = WhisperModel(
        size, device=device, compute_type=compute_type, cpu_threads=CPU_THREADS,
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


def _get_model(language: Optional[str] = None):
    """Load (and on the very first call, download) the model for `language`.

    Arabic and English can map to different sizes, so this keeps one entry per
    size rather than a single global model. The device/compute runtime is
    resolved once, on the first successful load, and reused for every size.
    """
    global _load_error, _active_device, _active_compute, _device_fallback_reason

    # Fast path: runtime already known and this size already resident.
    if _active_device is not None:
        cached = _models.get(_model_size_for(_active_device, language))
        if cached is not None:
            return cached

    with _model_lock:
        if _active_device is not None:
            device, compute = _active_device, _active_compute
        else:
            device, compute = _resolve_device()

        size = _model_size_for(device, language)
        if size in _models:
            return _models[size]

        started = time.time()
        logger.info(
            "Loading Whisper model '%s' for language=%s (device=%s, compute=%s) "
            "— first run downloads weights",
            size, language or "auto", device, compute,
        )
        try:
            model = _build_model(size, device, compute)
        except Exception as exc:  # noqa: BLE001
            if DEVICE != "auto" or device == "cpu":
                _load_error = f"{type(exc).__name__}: {exc}"
                logger.exception("Whisper model failed to load")
                raise
            # auto mode: CUDA is unusable on this machine, fall back to CPU.
            # The size can change with the device, so recompute it.
            _device_fallback_reason = f"{type(exc).__name__}: {exc}"
            device, compute = "cpu", ("int8" if COMPUTE_TYPE == "auto" else COMPUTE_TYPE)
            size = _model_size_for(device, language)
            logger.warning(
                "CUDA unusable (%s) — falling back to CPU with model '%s' for "
                "language=%s. Fix the CUDA runtime to get '%s' everywhere.",
                _device_fallback_reason, size, language or "auto", MODEL_SIZE_CUDA,
            )
            if size in _models:
                _active_device, _active_compute = device, compute
                return _models[size]
            try:
                model = _build_model(size, device, compute)
            except Exception as cpu_exc:  # noqa: BLE001
                _load_error = f"{type(cpu_exc).__name__}: {cpu_exc}"
                logger.exception("Whisper model failed to load on CPU too")
                raise

        _models[size] = model
        _active_device, _active_compute = device, compute
        _load_error = None
        logger.info(
            "Whisper model '%s' ready on %s/%s in %.1fs",
            size, device, compute, time.time() - started,
        )
        return model


def get_status() -> Dict[str, Any]:
    """Cheap, non-blocking status — lets the UI warn about a slow first call."""
    # "auto" optimistically resolves to CUDA, but reporting a CUDA model on a
    # box with no CUDA libraries present would just be wrong.
    device = _active_device or (
        "cpu" if (DEVICE == "auto" and not _CUDA_LIBS_REGISTERED) else _resolve_device()[0]
    )
    by_language = {lang: _model_size_for(device, lang) for lang in SUPPORTED_LANGUAGES}
    return {
        # Kept a plain string for backwards compatibility: the size used when
        # no language hint is given (the conservative choice). Per-language
        # detail is in model_by_language.
        "model": _model_size_for(device, None),
        "model_by_language": by_language,
        "models_loaded": sorted(_models),
        "device": device,
        "compute_type": _active_compute or COMPUTE_TYPE,
        "loaded": bool(_models),
        "load_error": _load_error,
        "device_fallback_reason": _device_fallback_reason,
        "cuda_libraries_found": _CUDA_LIBS_REGISTERED,
        "supported_languages": list(SUPPORTED_LANGUAGES),
        "timeout_seconds": TRANSCRIBE_TIMEOUT,
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

    # Loading happens before the clock starts: a first-run weight download can
    # take minutes and must not count against the decode deadline.
    model = _get_model(language)

    common = dict(
        beam_size=BEAM_SIZE,
        vad_filter=True,               # trims the silence around a click-to-record clip
        condition_on_previous_text=False,  # short utterances; avoids repeat-loop hallucinations
    )

    started = time.time()
    deadline = started + TRANSCRIBE_TIMEOUT
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

    # Consume the lazy generator with the deadline checked between segments.
    # This is real, cooperative cancellation inside the worker: abandoning the
    # future from the caller would leave this thread spinning and, with a
    # single-worker executor, block every subsequent turn indefinitely.
    parts = []
    timed_out = False
    for segment in segments:
        parts.append(segment.text)
        if time.time() > deadline:
            timed_out = True
            logger.warning(
                "Transcription exceeded %.0fs on %.1fs of audio (lang=%s) — "
                "returning what was decoded so far.",
                TRANSCRIBE_TIMEOUT, duration, detected_language,
            )
            break

    text = "".join(parts).strip()

    # Nothing usable AND over budget is a failure the caller must surface, not
    # an empty string to silently swallow.
    if timed_out and not text:
        raise TranscriptionTimeout(
            f"no speech decoded within {TRANSCRIBE_TIMEOUT:.0f}s"
        )

    return {
        "text": text,
        "timed_out": timed_out,
        "detected_language": detected_language,
        "language_probability": round(float(info.language_probability or 1.0), 4),
        "language_was_forced": language is not None,
        "language_was_snapped": language_snapped,
        "audio_seconds": round(duration, 2),
        "processing_seconds": round(time.time() - started, 2),
        # The size that actually served this request — with per-language
        # selection this differs between turns of the same consultation.
        "model": _model_size_for(_active_device or "cpu", language),
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


async def warmup(language: Optional[str] = None) -> Dict[str, Any]:
    """Force the model to load now rather than during a user's first recording.

    Takes the session language so the *right* model is resident: with
    per-language sizes, warming English and then speaking Arabic would
    otherwise pay a full medium-model load mid-consultation — long enough to
    look like a hang.
    """
    hint = language if language in SUPPORTED_LANGUAGES else None
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(_executor, _get_model, hint)
    return get_status()
