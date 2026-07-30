"""
Virtual Doctor — reasoning phase (Track A, Phase 2).

Runs once the interview's required slots are filled. Combines:
  - An LLM (qwen2 via Ollama) pass for a differential, a suggested next step,
    and a confidence score.
  - The existing rule-based chatbot.medical.symptom_engine.SymptomSpecialtyEngine
    (imported, unmodified) for a DB-grounded urgency level and recommended
    specialty.

CRITICAL safety rule: the LLM's urgency is only ever allowed to escalate the
final urgency, never to downgrade it. final_urgency = the MORE severe of
(rule_engine urgency, LLM urgency) on the emergency > urgent > routine scale.
See `_more_urgent`.

A dedicated JSON-mode Ollama call is used here rather than
llm_service.generate_response(): that function's prompt templates are built
for free-text chat replies (fixed instructions like "use emojis", "ask
follow-up questions"), not for the structured, parseable output this phase
needs. The env var conventions (OLLAMA_URL / OLLAMA_MODEL) match
llm/llm_service.py for consistency, and it is left unmodified.

Language-drift guard: qwen2 is a Chinese-origin model and will occasionally
answer patient-facing text (differential condition names, recommended_next_step)
in Chinese despite explicit instructions to use Arabic/English. _call_llm()
pins the language in an actual system-role message (via /api/chat, not the
role-less /api/generate), validates the output script post-generation, retries
once with a stricter prompt on failure, and falls back to a safe templated
sentence rather than ever surfacing wrong-language text to the patient.
"""

import json
import logging
import os
import re
from typing import Any, Dict, List, Optional

import requests

from chatbot.medical.symptom_engine import SymptomSpecialtyEngine

logger = logging.getLogger("medorbit-ai.virtual_doctor.reasoning")

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
MODEL_NAME = os.environ.get("OLLAMA_MODEL", "qwen2:7b")

# The generate-only endpoint has no role separation, so a language directive
# can only ever live in the user prompt. /api/chat supports a real system
# role, which is where a language instruction belongs and is far less likely
# to get diluted by the rest of the prompt. Derived from OLLAMA_URL rather
# than a second required env var — same host, same model.
OLLAMA_CHAT_URL = os.environ.get("OLLAMA_CHAT_URL", OLLAMA_URL.replace("/api/generate", "/api/chat"))

# emergency > urgent > routine — used to decide which of the two urgency
# opinions (rule engine vs LLM) wins. Higher number always wins.
_URGENCY_RANK = {"emergency": 3, "urgent": 2, "routine": 1}
_VALID_URGENCY = set(_URGENCY_RANK)

_symptom_engine = SymptomSpecialtyEngine()

# Seed phrases fed to the rule engine's substring matcher, in the exact
# wording used by symptom_specialty_mappings (db/07_triage_tables.sql), so
# the DB-backed lookup fires even when the patient's free-text answers are
# terse (e.g. a one-word severity answer).
_CHIEF_COMPLAINT_PHRASES: Dict[str, List[str]] = {
    "headache": ["headache"],
    "chest_pain": ["chest pain"],
    "abdominal_pain": ["abdominal pain", "stomach pain"],
    "rash": ["skin rash"],
    "fever_cough": ["fever", "cough"],
    "generic": [],
}

_FALLBACK_NEXT_STEP = {
    "en": "Please book an appointment with the recommended specialty to review these symptoms in person.",
    "ar": "يرجى حجز موعد مع التخصص الموصى به لمراجعة هذه الأعراض شخصياً.",
}

_URGENCY_LABEL_AR = {"emergency": "طارئة", "urgent": "عاجلة", "routine": "روتينية"}

# CJK ranges (Han + common extensions, Hiragana/Katakana, Hangul, CJK
# compatibility ideographs). Any of these in patient-facing text is an
# automatic reject, regardless of which language was requested.
_CJK_RE = re.compile(
    "["
    "㐀-䶿"  # CJK Unified Ideographs Extension A
    "一-鿿"  # CJK Unified Ideographs
    "぀-ヿ"  # Hiragana + Katakana
    "가-힣"  # Hangul Syllables
    "豈-﫿"  # CJK Compatibility Ideographs
    "]"
)
_ARABIC_RE = re.compile("[؀-ۿݐ-ݿ]")
_LATIN_RE = re.compile("[A-Za-z]")

# Common function words. A real sentence of 2+ words almost always contains
# at least one of these; letter-salad essentially never does by chance. This
# catches the case script-membership checks alone miss: text that is
# correctly Arabic (or English) *script* but not actually coherent language.
_COMMON_WORDS = {
    "ar": {"و", "في", "من", "إلى", "على", "مع", "أو", "لا", "أن", "هذا", "هذه", "ثم", "بعد", "قبل", "قد", "يجب", "مع"},
    "en": {"the", "a", "an", "to", "and", "or", "of", "in", "on", "with", "for", "is", "are", "your", "you"},
}
_WORD_STRIP = ".,!?،؛:؟\"'"

_SYSTEM_PROMPTS = {
    "ar": (
        "أنت نظام مساعد للفرز الطبي داخل تطبيق طبي. "
        "يجب أن تكتب كل نص تولّده باللغة العربية فقط وبالحروف العربية فقط. "
        "ممنوع منعاً باتاً استخدام أي حروف صينية أو يابانية أو كورية أو أي لغة أخرى غير العربية في أي حقل نصي. "
        "أعد فقط كائن JSON صالح، بدون أي نص خارج الـ JSON وبدون علامات markdown."
    ),
    "en": (
        "You are a medical triage assistant system inside a medical app. "
        "You must write all generated text in English only, using Latin script only. "
        "Do not use any Chinese, Japanese, Korean, Arabic, or any other script in any text field, under any circumstances. "
        "Return only a valid JSON object, with no text outside the JSON and no markdown."
    ),
}

_STRICT_SYSTEM_PROMPTS = {
    # Deliberately short and single-directive: an earlier, longer, multi-
    # warning version of this prompt (stacked on top of the JSON-schema
    # instructions) measurably degraded qwen2:7b's output on retry — it still
    # obeyed the script constraint, but produced incoherent letter strings
    # instead of real words. A shorter, calmer instruction plus a lower
    # temperature (see _call_llm_once) fixed that.
    "ar": "أعد المحاولة. اكتب ردك بالكامل بلغة عربية فصحى صحيحة وواضحة ومفهومة. ممنوع أي حرف من لغة أخرى.",
    "en": "Try again. Write your entire response in clear, correct, natural English. Do not use any other language.",
}


def _more_urgent(a: str, b: str) -> str:
    """Return whichever of two urgency levels ranks higher. This is the one
    place that decides final urgency — the LLM can only push it up, never down."""
    return a if _URGENCY_RANK.get(a, 0) >= _URGENCY_RANK.get(b, 0) else b


def _build_symptom_list(chief_complaint: str, profile: Dict[str, Any]) -> List[str]:
    symptoms = list(_CHIEF_COMPLAINT_PHRASES.get(chief_complaint, []))
    for value in profile.values():
        if isinstance(value, str) and value.strip():
            symptoms.append(value)
    return symptoms


def _extract_json(text: str) -> Optional[dict]:
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        pass
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            return None
    return None


def _text_matches_language(text: Any, lang: str) -> bool:
    """Reject CJK script outright, and reject any mixing of the *other*
    requested language's opposite script too — a stray Latin word like "X-ray"
    or "tummy" inside an Arabic sentence is a milder version of the same
    language-drift problem and must not silently pass."""
    if not isinstance(text, str) or not text.strip():
        return False
    if _CJK_RE.search(text):
        return False
    if lang == "ar":
        return bool(_ARABIC_RE.search(text)) and not _LATIN_RE.search(text)
    if lang == "en":
        return not _ARABIC_RE.search(text)
    return True


def _looks_coherent(text: str, lang: str) -> bool:
    """Script-membership alone doesn't prove the text is real language —
    correctly-scripted letter-salad passes it too. A 2+ word sentence in a
    known language almost always contains at least one common function word;
    require that here rather than trusting script checks alone."""
    words = [w.strip(_WORD_STRIP) for w in text.split()]
    words = [w for w in words if w]
    if len(words) < 2:
        return True  # too short to judge either way — don't penalize it
    common = _COMMON_WORDS.get(lang)
    if not common:
        return True
    return any(w.lower() in common for w in words)


def _output_language_ok(normalized: dict, lang: str) -> bool:
    next_step = normalized["recommended_next_step"]
    if not _text_matches_language(next_step, lang):
        return False
    if not _looks_coherent(next_step, lang):
        return False
    for item in normalized["differential"]:
        condition = item.get("condition") if isinstance(item, dict) else None
        if condition and not _text_matches_language(condition, lang):
            return False
    return True


def _fallback_llm_output(lang: str) -> dict:
    return {
        "differential": [],
        "urgency": "routine",
        "recommended_next_step": _FALLBACK_NEXT_STEP[lang],
        "confidence": 0.3,
    }


def _normalize_llm_output(parsed: Optional[dict], lang: str) -> dict:
    if not parsed:
        return _fallback_llm_output(lang)

    urgency = parsed.get("urgency")
    if urgency not in _VALID_URGENCY:
        urgency = "routine"

    differential = parsed.get("differential")
    if not isinstance(differential, list):
        differential = []

    try:
        confidence = max(0.0, min(1.0, float(parsed.get("confidence", 0.5))))
    except (TypeError, ValueError):
        confidence = 0.5

    next_step = parsed.get("recommended_next_step")
    if not isinstance(next_step, str) or not next_step.strip():
        next_step = _FALLBACK_NEXT_STEP[lang]

    return {
        "differential": differential,
        "urgency": urgency,
        "recommended_next_step": next_step,
        "confidence": confidence,
    }


def _build_user_prompt(chief_complaint: str, profile: Dict[str, Any], lang: str, strict: bool) -> str:
    profile_lines = "\n".join(f"- {key}: {value}" for key, value in profile.items() if value)
    language_name = "Arabic" if lang == "ar" else "English"
    extra_warning = (
        f"\nFINAL REMINDER: write ONLY in {language_name} script. Any other script will be rejected.\n"
        if strict
        else ""
    )

    return f"""Respond with ONLY a JSON object (no markdown, no extra text) with exactly these fields:
{{
  "differential": [{{"condition": "<name>", "likelihood": "high|medium|low"}}],
  "urgency": "emergency|urgent|routine",
  "recommended_next_step": "<one short sentence>",
  "confidence": <float between 0.0 and 1.0>
}}

Rules:
- List 2 to 4 plausible differential conditions, most likely first. This is decision support, never a certain diagnosis.
- "urgency": "emergency" = needs immediate emergency care now; "urgent" = needs care within 24-48 hours; "routine" = can be scheduled normally.
- Write "condition" and "recommended_next_step" in {language_name} ONLY. Keep the JSON field names in English exactly as shown above.
{extra_warning}
Chief complaint: {chief_complaint}
Patient details:
{profile_lines}

Reminder: "condition" and "recommended_next_step" must be written entirely in {language_name}.
"""


def _call_llm_once(chief_complaint: str, profile: Dict[str, Any], lang: str, strict: bool) -> Optional[dict]:
    system_prompts = _STRICT_SYSTEM_PROMPTS if strict else _SYSTEM_PROMPTS
    system_prompt = system_prompts[lang]
    user_prompt = _build_user_prompt(chief_complaint, profile, lang, strict)

    # Lower temperature on the retry: a longer, more constrained retry prompt
    # combined with the model's default sampling temperature was observed to
    # produce incoherent, letter-salad output that still technically passed
    # a script-only check. A more deterministic, focused generation is far
    # less likely to wander off into gibberish while still following the
    # (now much shorter) strict instruction.
    temperature = 0.2 if strict else 0.4

    try:
        response = requests.post(
            OLLAMA_CHAT_URL,
            json={
                "model": MODEL_NAME,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "stream": False,
                "format": "json",
                "options": {"temperature": temperature},
            },
            timeout=60,
        )
        data = response.json()
        content = data.get("message", {}).get("content", "")
        return _extract_json(content)
    except Exception as exc:  # LLM unavailable/timeout — never break reasoning
        logger.warning("Reasoning LLM call failed (strict=%s): %s", strict, exc)
        return None


def _call_llm(chief_complaint: str, profile: Dict[str, Any], lang: str) -> dict:
    parsed = _call_llm_once(chief_complaint, profile, lang, strict=False)
    normalized = _normalize_llm_output(parsed, lang)
    if _output_language_ok(normalized, lang):
        return normalized

    logger.warning(
        "Reasoning LLM output failed language check (lang=%s) — retrying with a stricter prompt", lang
    )
    parsed_retry = _call_llm_once(chief_complaint, profile, lang, strict=True)
    normalized_retry = _normalize_llm_output(parsed_retry, lang)
    if _output_language_ok(normalized_retry, lang):
        return normalized_retry

    logger.warning(
        "Reasoning LLM output failed language check again after retry (lang=%s) — falling back to templated text",
        lang,
    )
    return _fallback_llm_output(lang)


async def run_reasoning(chief_complaint: str, profile: Dict[str, Any], lang: str) -> dict:
    """
    Synthesize urgency / differential / recommended specialty / next step /
    confidence for a completed interview. Returns a dict ready to persist
    and to send back to the patient.
    """
    symptom_list = _build_symptom_list(chief_complaint, profile)
    rule_result = await _symptom_engine.match(symptoms=symptom_list or [chief_complaint])
    llm_result = _call_llm(chief_complaint, profile, lang)

    final_urgency = _more_urgent(rule_result["triage_level"], llm_result["urgency"])

    reasoning_payload = {
        "conditions": llm_result["differential"],
        "confidence": llm_result["confidence"],
        "next_step": llm_result["recommended_next_step"],
        "urgency_source": {
            "rule_engine": rule_result["triage_level"],
            "llm": llm_result["urgency"],
            "final": final_urgency,
            "note": "final urgency is always the more severe of the two — the LLM can escalate but never downgrade",
        },
        "rule_confidence": rule_result["confidence_score"],
        "specialty_scores": rule_result["specialty_scores"],
    }

    if lang == "ar":
        reply = (
            f"بناءً على ما أخبرتني به، أقترح مراجعة تخصص {rule_result['recommended_specialty_name_ar']}. "
            f"درجة الأولوية: {_URGENCY_LABEL_AR[final_urgency]}. {llm_result['recommended_next_step']}"
        )
    else:
        reply = (
            f"Based on what you've told me, I'd suggest seeing a {rule_result['recommended_specialty_name_en']} "
            f"specialist. Urgency: {final_urgency}. {llm_result['recommended_next_step']}"
        )

    return {
        "reply": reply,
        "urgency_level": final_urgency,
        "recommended_specialty_id": rule_result["recommended_specialty_id"],
        "recommended_specialty_name_en": rule_result["recommended_specialty_name_en"],
        "recommended_specialty_name_ar": rule_result["recommended_specialty_name_ar"],
        "differential": reasoning_payload,
        "confidence": llm_result["confidence"],
    }
