"""
Virtual Doctor — bounded response generation (Phase 6).

    structured decision -> bounded wording -> validation -> final reply

THE SPLIT THIS FILE ENFORCES
----------------------------
Phase 2 established that Prolog decides WHAT is asked and the LLM decides only
HOW. This module is where that split stops being a convention and becomes a
check: a generated sentence that drifts to a different clinical topic, asks two
questions, answers in the wrong language, or slips a diagnosis in is REJECTED,
and the deterministic template is used instead.

An elegant sentence about the wrong topic is not a better answer than a plain
sentence about the right one. Rejection is cheap — one templated question —
and acceptance of a drifted question silently breaks the guarantee that the
interview is symbolically driven.

WHAT THE WORDING LAYER MAY NOT DO
---------------------------------
It may not change urgency, remove or soften the safety warning, choose a
different topic, declare the interview finished, or name a condition. None of
those is enforced by asking it nicely. Urgency and the warning never enter its
output path at all — they are composed around it by compose(), in Python —
and topic, question count and diagnosis wording are checked on the way back.

WARNING COMPOSITION
-------------------
compose() puts the mandatory warning FIRST, unconditionally, and it is the
only function that assembles a reply. The generated body cannot omit the
warning because the generated body is never where the warning lives. This
mirrors interview_engine's existing order exactly — safety_prefix is prepended
last there, so it lands first in the string — and a test pins that the two
agree.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
from dataclasses import dataclass, field
from typing import Any, Dict, Mapping, Optional, Sequence, Tuple

import requests

from .reasoning_engine import vocabulary
from .config import env_float

logger = logging.getLogger("medorbit-ai.virtual_doctor.response")

# --- rollout ---------------------------------------------------------------
# Off by default: the existing planner already words questions, and turning
# this on adds a second model call per turn. Same three-state convention as the
# other VD_* layers; an unrecognised value is never `active`.
#
#   off     no model call; compose()/validate() remain available and are what
#           interview_engine uses to assemble the reply       (the default)
#   shadow  a bounded wording is generated and validated, the outcome is
#           logged, and the deterministic text is what the patient sees
#   active  a wording that passes every check is used; anything else falls
#           back to the deterministic text
MODES: Tuple[str, ...] = ("off", "shadow", "active")
MODE_DEFAULT = "off"


def mode() -> str:
    raw = os.environ.get("VD_BOUNDED_RESPONSE", MODE_DEFAULT).strip().lower()
    if raw not in MODES:
        logger.warning("Unknown VD_BOUNDED_RESPONSE=%r — falling back to %r", raw, MODE_DEFAULT)
        return MODE_DEFAULT
    return raw


def enabled() -> bool:
    return mode() != "off"


def active() -> bool:
    return mode() == "active"


MODEL = os.environ.get("VD_RESPONSE_MODEL", "qwen2.5:3b")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
CHAT_URL = os.environ.get("OLLAMA_CHAT_URL", OLLAMA_URL.replace("/api/generate", "/api/chat"))
# exclusive_min=0: passed to requests(timeout=), which rejects <= 0.
TIMEOUT = env_float("VD_RESPONSE_TIMEOUT", 20.0, minimum=0.0,
                    exclusive_min=True)
KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "1h")

# One short sentence. A wording layer that returns a paragraph has started
# doing something other than wording.
MAX_BODY_CHARS = 300

# Both question marks, because an Arabic reply may use either.
_QUESTION_MARKS = ("?", "؟")

_ARABIC_RE = re.compile(r"[؀-ۿ]")
_LATIN_RE = re.compile(r"[A-Za-z]")
_CJK_RE = re.compile(r"[぀-ヿ一-鿿]")

# Wording that asserts a conclusion rather than asking a question. Not a
# medical vocabulary — a small, closed list of the phrases by which a wording
# layer announces it has diagnosed something. Deliberately generic: the point
# is to catch the ACT of diagnosing, which no amount of condition-name
# blocklisting could do, since Phase 5 established MedOrbit has no condition
# vocabulary to blocklist against.
_DIAGNOSIS_MARKERS_EN = (
    "you have ", "you likely have", "you probably have", "this is ",
    "diagnos", "you are suffering from", "it looks like you have",
    "the cause is", "you may have",
)
_DIAGNOSIS_MARKERS_AR = (
    "تشخيص", "لديك مرض", "انت مصاب", "أنت مصاب", "تعاني من", "سبب حالتك",
    "الحاله هي", "الحالة هي",
)


# ---------------------------------------------------------------------------
# The bounded context
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ResponseContext:
    """Everything the wording layer is allowed to see, and nothing else.

    Note what is NOT here: raw patient speech, the patient's name, the full
    profile, the differential, the session id. The wording layer receives a
    topic to ask about, a language to ask it in, and a handful of canonical
    atoms for context. It cannot leak what it was never given.

    `mandatory_warning` is present so the layer knows a warning WILL be shown
    and can pitch its tone accordingly — it is never asked to reproduce it, and
    compose() emits it from Python regardless of what comes back.
    """

    topic: str
    lang: str = "ar"
    fallback: str = ""
    urgency: Optional[str] = None
    mandatory_warning: str = ""
    known_findings: Tuple[str, ...] = ()
    correction_pending: bool = False
    confirmation_pending: bool = False

    def as_log_fields(self) -> Dict[str, Any]:
        """PHI-free: canonical atoms, flags and lengths only."""
        return {
            "topic": self.topic,
            "lang": self.lang,
            "urgency": self.urgency,
            "has_warning": bool(self.mandatory_warning),
            "known": list(self.known_findings),
            "correction_pending": self.correction_pending,
            "confirmation_pending": self.confirmation_pending,
        }


@dataclass(frozen=True)
class BoundedResponse:
    """A wording decision, with the reason when the generated text was refused.

    `source` is one of: generated (the model's wording passed every check),
    fallback (it did not, or the model was unavailable), disabled.
    """

    text: str
    source: str
    rejected_reason: Optional[str] = None
    elapsed_ms: float = 0.0

    @property
    def accepted(self) -> bool:
        return self.source == "generated"

    def as_log_fields(self) -> Dict[str, Any]:
        return {
            "source": self.source,
            "rejected_reason": self.rejected_reason,
            "elapsed_ms": round(self.elapsed_ms, 1),
            "chars": len(self.text),
        }


# ---------------------------------------------------------------------------
# Composition — Python-owned, and the only place a reply is assembled
# ---------------------------------------------------------------------------

def compose(body: str, *, mandatory_warning: str = "", correction_prefix: str = "") -> str:
    """Assemble the final reply. The warning always comes first.

    Order is warning, then correction acknowledgement, then body — identical to
    interview_engine's existing composition, where correction_prefix is
    prepended and then safety_prefix is prepended on top of it. Centralised
    here so there is one place that defines the order, and one place a test has
    to check to know the warning can never be displaced.

    Deliberately not clever: no deduplication, no "the body already mentions
    it" heuristic. A heuristic that suppressed a warning would be a heuristic
    that can suppress a warning.
    """
    parts = [part for part in (mandatory_warning, correction_prefix, body) if part]
    return "".join(parts)


# ---------------------------------------------------------------------------
# Validation — what makes the split real
# ---------------------------------------------------------------------------

def _language_ok(text: str, lang: str) -> bool:
    """Same rule as reasoning._text_matches_language, restated rather than
    imported: reasoning pulls `db` transitively, and this module runs on every
    turn and must stay import-cheap. A test asserts the two agree."""
    if _CJK_RE.search(text):
        return False
    if lang == "ar":
        return bool(_ARABIC_RE.search(text)) and not _LATIN_RE.search(text)
    if lang == "en":
        return not _ARABIC_RE.search(text)
    return True


def _question_count(text: str) -> int:
    return sum(text.count(mark) for mark in _QUESTION_MARKS)


def _mentions_diagnosis(text: str, lang: str) -> bool:
    lowered = text.lower()
    markers = _DIAGNOSIS_MARKERS_AR if lang == "ar" else _DIAGNOSIS_MARKERS_EN
    return any(marker in lowered for marker in markers)


def validate_body(body: Any, ctx: ResponseContext) -> Optional[str]:
    """None if this wording may be used, otherwise the reason it may not.

    The checks, in the order they matter:

      1. it is a usable, bounded string
      2. it is in the language the patient is speaking
      3. it is still about the topic Prolog chose        <- the Phase 2 clamp
      4. it asks at most one question                    <- one question a turn
      5. it does not diagnose

    Check 3 reuses vocabulary.question_matches_topic, the same clamp
    SymbolicPlanner already applies to planner output, so a question wording
    faces exactly one standard no matter which layer produced it.
    """
    if not isinstance(body, str):
        return "not a string"
    text = body.strip()
    if not text:
        return "empty"
    if len(text) > MAX_BODY_CHARS:
        return "too long"
    if not _language_ok(text, ctx.lang):
        return "wrong language"
    if _question_count(text) > 1:
        return "more than one question"
    if _mentions_diagnosis(text, ctx.lang):
        return "asserts a diagnosis"
    if ctx.topic and not vocabulary.question_matches_topic(text, ctx.topic):
        return f"drifted off topic {ctx.topic}"
    return None


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

_SYSTEM = {
    "ar": (
        "أنت طبيب يجري مقابلة طبية أولية. تكتب سؤالاً واحداً قصيراً بالفصحى المبسطة. "
        "لا تشخّص. لا تقترح مرضاً. لا تعطي نصيحة علاجية."
    ),
    "en": (
        "You are a doctor conducting an initial interview. You write one short, "
        "clear question. You never diagnose, never name a condition, and never "
        "give treatment advice."
    ),
}

_TOPIC_INSTRUCTION = {
    "ar": "اسأل المريض سؤالاً واحداً عن: {topic}",
    "en": "Ask the patient exactly one question about: {topic}",
}

_STYLE = {
    # Mirrors planner's approved Arabic style rule: simplified MSA, calm,
    # concise, no dialect and no performed empathy.
    "ar": ("اكتب بالعربية الفصحى المبسطة. جملة واحدة قصيرة. "
           "بدون لهجة عامية وبدون عبارات تعاطف مبالغ فيها."),
    "en": "Write one short sentence in plain English.",
}


def build_prompt(ctx: ResponseContext) -> str:
    """The user-side prompt, split out so a test can assert what is in it —
    that the topic is stated, that diagnosis is forbidden, and that the patient
    context passed in is canonical atoms rather than free text."""
    known = ", ".join(ctx.known_findings) if ctx.known_findings else "nothing yet"
    lang = ctx.lang if ctx.lang in _TOPIC_INSTRUCTION else "en"
    warning_note = ""
    if ctx.mandatory_warning:
        warning_note = (
            "\nA safety warning has ALREADY been shown to this patient. Do not "
            "repeat it, do not contradict it, and do not reassure them that it "
            "does not matter.\n"
        )
    return (
        f"{_TOPIC_INSTRUCTION[lang].format(topic=ctx.topic)}\n"
        f"Already established: {known}\n"
        f"{warning_note}\n"
        f"{_STYLE[lang]}\n"
        "Ask about that topic and nothing else. Exactly one question mark.\n"
        'Return ONLY this JSON object: {"question": "<your question>"}'
    )


def _extract_json(text: Any) -> Optional[dict]:
    if not isinstance(text, str):
        return None
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else None
    except (json.JSONDecodeError, TypeError, ValueError):
        pass
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        parsed = json.loads(match.group())
    except (json.JSONDecodeError, ValueError):
        return None
    return parsed if isinstance(parsed, dict) else None


async def generate(ctx: ResponseContext) -> BoundedResponse:
    """Word the chosen topic, or fall back to the deterministic text.

    Never raises. Every failure — disabled, unreachable model, timeout, bad
    JSON, a wording that fails any check — returns ctx.fallback with the reason
    recorded. The caller always gets usable text.
    """
    if not enabled():
        return BoundedResponse(text=ctx.fallback, source="disabled")

    started = time.perf_counter()
    lang = ctx.lang if ctx.lang in _SYSTEM else "en"
    try:
        response = await asyncio.to_thread(
            requests.post,
            CHAT_URL,
            json={
                "model": MODEL,
                "messages": [
                    {"role": "system", "content": _SYSTEM[lang]},
                    {"role": "user", "content": build_prompt(ctx)},
                ],
                "stream": False,
                "format": "json",
                "keep_alive": KEEP_ALIVE,
                "options": {"temperature": 0.3},
            },
            timeout=TIMEOUT,
        )
        response.raise_for_status()
        content = response.json().get("message", {}).get("content", "")
    except Exception as exc:  # noqa: BLE001 - a wording failure never breaks a turn
        elapsed = (time.perf_counter() - started) * 1000
        logger.info("Bounded response unavailable (%s) — using deterministic text", exc)
        return BoundedResponse(text=ctx.fallback, source="fallback",
                               rejected_reason=f"call failed: {type(exc).__name__}",
                               elapsed_ms=elapsed)

    elapsed = (time.perf_counter() - started) * 1000
    parsed = _extract_json(content)
    body = parsed.get("question") if isinstance(parsed, Mapping) else None

    reason = validate_body(body, ctx)
    if reason is not None:
        logger.info("Bounded response rejected (%s) — using deterministic text", reason)
        return BoundedResponse(text=ctx.fallback, source="fallback",
                               rejected_reason=reason, elapsed_ms=elapsed)

    if not active():
        # Shadow: the wording was generated and passed, and is still discarded.
        return BoundedResponse(text=ctx.fallback, source="fallback",
                               rejected_reason="shadow mode", elapsed_ms=elapsed)

    return BoundedResponse(text=str(body).strip(), source="generated", elapsed_ms=elapsed)
