"""Text-to-speech for the AI Virtual Doctor, wrapping Piper.

Piper (rhasspy/piper) is fully open source, runs on CPU through the
onnxruntime that faster-whisper already pulls in, and ships both an Arabic and
an English voice — so nothing new has to be compiled and no cloud service is
involved. Measured on this project's hardware it synthesises at roughly 10x
real time, i.e. a five-second reply takes about half a second to produce.

Voices are downloaded on first use into assets/tts_voices/ (~60 MB each) and
cached there, mirroring how the Whisper weights are handled.

LICENSE NOTE: piper-tts is GPL-3.0 from 1.3.0 onwards (it links espeak-ng).
That is open source as required, but it is a stronger copyleft than the rest
of this repo — worth knowing before MedOrbit is ever distributed as a binary.
"""

from __future__ import annotations

import asyncio
import hashlib
import io
import logging
import os
import re
import threading
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

_MODULE_DIR = Path(__file__).resolve().parent.parent
_VOICE_DIR = Path(os.getenv("VD_TTS_VOICE_DIR", str(_MODULE_DIR / "assets" / "tts_voices")))
_CACHE_DIR = _MODULE_DIR / "generated" / "tts"

# Piper's only medium-quality Arabic voice is male (kareem); the English one
# chosen here is female (amy). They therefore do not match in gender — Piper
# simply has no female Arabic voice. Override either with the env vars below.
VOICES = {
    "ar": os.getenv("VD_TTS_VOICE_AR", "ar_JO-kareem-medium"),
    "en": os.getenv("VD_TTS_VOICE_EN", "en_US-amy-medium"),
}
DEFAULT_LANGUAGE = "en"

MAX_TEXT_CHARS = 800
_MEMORY_CACHE_ENTRIES = 128

_voices: Dict[str, Any] = {}
_voice_lock = threading.Lock()
_load_errors: Dict[str, str] = {}

# Piper is CPU-bound; a single worker keeps it off the event loop without
# letting several syntheses fight over the same cores. It is deliberately a
# different executor from the STT one so speech generation and transcription
# can overlap (STT runs on the GPU).
_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="vd-tts")

_memory_cache: Dict[str, bytes] = {}
_memory_order: list[str] = []
_cache_lock = threading.Lock()

_stats = {"requests": 0, "memory_hits": 0, "disk_hits": 0, "synthesized": 0}


class TtsError(Exception):
    """Speech could not be produced. Callers should fall back to text."""


# Latin words are read letter-salad by the Arabic voice — "MedOrbit" comes out
# as "مذابه". Only a tiny fixed vocabulary appears in the doctor's script, so
# transliterating those explicitly is both sufficient and predictable.
_AR_TRANSLITERATIONS = {
    "medorbit": "ميد أوربِت",
    "med orbit": "ميد أوربِت",
    "ai": "الذكاء الاصطناعي",
    "pdf": "بي دي إف",
}
_LATIN_RUN = re.compile(r"[A-Za-z][A-Za-z0-9'’\-]*(?:\s+[A-Za-z][A-Za-z0-9'’\-]*)*")


def _prepare_text(text: str, language: str) -> str:
    text = (text or "").strip()
    if not text:
        return text
    if language == "ar":
        def replace(match: re.Match) -> str:
            token = match.group(0)
            return _AR_TRANSLITERATIONS.get(token.strip().lower(), token)
        text = _LATIN_RUN.sub(replace, text)
    return text


def resolve_language(language: Optional[str]) -> str:
    return language if language in VOICES else DEFAULT_LANGUAGE


def _voice_path(name: str) -> Path:
    return _VOICE_DIR / f"{name}.onnx"


def _get_voice(language: str):
    """Load (and on first use, download) the Piper voice for this language."""
    name = VOICES[language]
    voice = _voices.get(language)
    if voice is not None:
        return voice

    with _voice_lock:
        if language in _voices:
            return _voices[language]

        from piper import PiperVoice

        _VOICE_DIR.mkdir(parents=True, exist_ok=True)
        onnx = _voice_path(name)
        if not onnx.exists():
            from piper.download_voices import download_voice

            logger.info("Downloading Piper voice '%s' (~60MB, first run only)", name)
            download_voice(name, _VOICE_DIR)

        started = time.time()
        try:
            voice = PiperVoice.load(onnx)
        except Exception as exc:  # noqa: BLE001 - reported through /speak/status
            _load_errors[language] = f"{type(exc).__name__}: {exc}"
            logger.exception("Piper voice '%s' failed to load", name)
            raise TtsError(str(exc)) from exc

        _load_errors.pop(language, None)
        _voices[language] = voice
        logger.info("Piper voice '%s' ready in %.2fs", name, time.time() - started)
        return voice


def _cache_key(language: str, text: str) -> str:
    raw = f"{VOICES[language]}|{text}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _cache_get(key: str) -> Optional[bytes]:
    with _cache_lock:
        hit = _memory_cache.get(key)
    if hit is not None:
        _stats["memory_hits"] += 1
        return hit

    path = _CACHE_DIR / f"{key}.wav"
    if path.exists():
        data = path.read_bytes()
        _cache_put_memory(key, data)
        _stats["disk_hits"] += 1
        return data
    return None


def _cache_put_memory(key: str, data: bytes) -> None:
    with _cache_lock:
        if key in _memory_cache:
            return
        _memory_cache[key] = data
        _memory_order.append(key)
        while len(_memory_order) > _MEMORY_CACHE_ENTRIES:
            _memory_cache.pop(_memory_order.pop(0), None)


def _cache_put(key: str, data: bytes) -> None:
    _cache_put_memory(key, data)
    try:
        _CACHE_DIR.mkdir(parents=True, exist_ok=True)
        # Write-then-rename so a crash mid-write cannot leave a truncated wav
        # that would be served as a cache hit forever.
        tmp = _CACHE_DIR / f".{key}.part"
        tmp.write_bytes(data)
        tmp.replace(_CACHE_DIR / f"{key}.wav")
    except OSError as exc:
        logger.warning("Could not persist TTS cache entry: %s", exc)


def _synthesize_sync(text: str, language: str) -> Dict[str, Any]:
    key = _cache_key(language, text)
    cached = _cache_get(key)
    if cached is not None:
        return {"audio": cached, "cached": True, "voice": VOICES[language],
                "language": language, "synthesis_seconds": 0.0}

    voice = _get_voice(language)
    prepared = _prepare_text(text, language)

    started = time.time()
    buffer = io.BytesIO()
    try:
        with wave.open(buffer, "wb") as wav_file:
            voice.synthesize_wav(prepared, wav_file)
    except Exception as exc:  # noqa: BLE001 - any Piper failure is a TTS failure
        logger.exception("Piper synthesis failed")
        raise TtsError(str(exc)) from exc

    data = buffer.getvalue()
    if len(data) <= 44:  # header only, no samples
        raise TtsError("synthesis produced no audio")

    _cache_put(key, data)
    _stats["synthesized"] += 1
    return {"audio": data, "cached": False, "voice": VOICES[language],
            "language": language, "synthesis_seconds": round(time.time() - started, 3)}


async def synthesize(text: str, language: Optional[str] = None) -> Dict[str, Any]:
    """Render `text` to WAV bytes using the voice for `language`."""
    text = (text or "").strip()
    if not text:
        raise TtsError("empty text")
    if len(text) > MAX_TEXT_CHARS:
        raise TtsError(f"text exceeds {MAX_TEXT_CHARS} characters")

    lang = resolve_language(language)
    _stats["requests"] += 1
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_executor, _synthesize_sync, text, lang)


async def warmup(language: Optional[str] = None) -> Dict[str, Any]:
    """Load voices up front so the first reply is not delayed by a model load."""
    langs = [resolve_language(language)] if language else list(VOICES)
    loop = asyncio.get_running_loop()
    for lang in langs:
        try:
            await loop.run_in_executor(_executor, _get_voice, lang)
        except TtsError:
            pass   # recorded in _load_errors and surfaced by get_status()
    return get_status()


def get_status() -> Dict[str, Any]:
    return {
        "engine": "piper",
        "voices": dict(VOICES),
        "loaded": sorted(_voices.keys()),
        "load_errors": dict(_load_errors),
        "cache_entries": len(list(_CACHE_DIR.glob("*.wav"))) if _CACHE_DIR.exists() else 0,
        "stats": dict(_stats),
    }
