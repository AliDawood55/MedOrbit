import asyncio
import json
import logging
import os
import re
import threading
import time
import uuid
from typing import Any, Dict, List, Optional, Tuple

from chatbot.entities.extractor import EntityExtractor
from chatbot.nlu.safety import MedicalSafetyLayer
from chatbot.utils.text_normalizer import detect_language, normalize_text
from db import get_pool

from . import memory, planner, reasoning, reasoning_engine, retrieval, understanding
from .planner import PlannerError, PlannerInput


PER_TURN_CONTEXT = os.environ.get("VD_PER_TURN_CONTEXT", "1") not in ("0", "false", "False")

logger = logging.getLogger("medorbit-ai.virtual_doctor.interview")

_FLOWS_DIR = os.path.join(os.path.dirname(__file__), "flows")


GREETING = {
    "en": "Hello, I'm the MedOrbit virtual doctor assistant. Before we begin, what is your name?",
    "ar": "مرحبًا، أنا المساعد الطبي في MedOrbit. قبل أن نبدأ، ما اسمك؟",
}

ASK_AGE = {
    "en": "Nice to meet you, {name}. How old are you?",
    "ar": "شكرًا يا {name}. كم عمرك؟",
}

ASK_AGE_RETRY = {
    "en": "Sorry, I didn't catch a number. How old are you, in years?",
    "ar": "عذرًا، لم أفهم رقمًا واضحًا. كم عمرك بالسنوات؟",
}

ASK_COMPLAINT = {
    "en": "Thank you. Now, what's bothering you today?",
    "ar": "ما الأعراض التي تشعر بها اليوم؟",
}

WRAP_UP = {
    "en": "Thank you, I've noted everything you've told me.",
    "ar": "حسنًا، سجّلت كل ما ذكرته لي.",
}


SAFETY_URGENT_WARNING = {


    "ar": (
        "قد يحتاج هذا العرض تقييمًا طبيًا عاجلًا، لكن سأطرح عليك بعض الأسئلة "
        "السريعة والمهمة لتوثيق حالتك بدقة. إذا اشتدّ الألم كثيرًا، أو شعرت "
        "بإغماء أو ضيق في التنفس أو ضعف مفاجئ، فتوجّه إلى الطوارئ فورًا أو "
        "اتصل بالإسعاف. "
    ),
    "en": (
        "This symptom may need urgent medical evaluation, but I'll ask a few quick, "
        "important questions to document your case more accurately. If the pain is "
        "very severe, or you have fainting, shortness of breath, or sudden weakness, "
        "go to the emergency room immediately or call an ambulance. "
    ),
}

SAFETY_URGENT_REMINDER = {
    "ar": "(تذكير: ما زلت بحاجة إلى تقييم طبي عاجل.) ",
    "en": "(Reminder: this still needs urgent medical evaluation.) ",
}

SAFETY_EMERGENCY_CONTINUATION = {
    "ar": " إذا استطعت، أجب بسرعة عن سؤال واحد فقط: ",
    "en": " If you can, please quickly answer just one question: ",
}

SAFETY_EMERGENCY_REMINDER = {
    "ar": "(تذكير: قد تكون هذه حالة طارئة — توجّه إلى الطوارئ إذا لم تكن قد فعلت ذلك بعد.) ",
    "en": "(Reminder: this may be an emergency — seek emergency care now if you have not already.) ",
}


MAX_CONFIRMATION_ATTEMPTS = 1

NAME_CONFIRM_QUESTION = {


    "ar": "هل هذا اسمك: {heard_name}؟ إذا لم يكن صحيحًا، من فضلك أعد ذكر اسمك.",
    "en": "Did I hear your name correctly: {heard_name}? If not, please say it again.",
}
NAME_CONFIRM_RETRY = {
    "ar": "من فضلك، أعد ذكر اسمك بوضوح أكبر.",
    "en": "Please say your name again, clearly.",
}
CHIEF_COMPLAINT_CONFIRM_RETRY = {
    "ar": "من فضلك، وضّح لي ما تشعر به بالتحديد.",
    "en": "Please clarify: what exactly is bothering you?",
}
FOCUSED_FLANK_URINARY_QUESTION = {
    "ar": "هل الألم في جانبك أو في الخاصرة؟ وهل تشعر بحرقان أو تغيّر في لون البول؟",
    "en": "Is the pain in your side (flank), and do you have burning or a color change in your urine?",
}


NAME_UNCLEAR_REPEAT = {
    "ar": "لست متأكدًا من أنني سمعت الاسم بشكل صحيح. من فضلك، أخبرني باسمك الأول فقط.",
    "en": "I'm not sure I caught your name. Please tell me just your first name.",
}


MAX_CORRECTION_ATTEMPTS = 1

CORRECTION_ASK_NAME = {
    "ar": "بالتأكيد، ما هو الاسم الصحيح؟",
    "en": "Of course — what's the correct name?",
}
CORRECTION_ASK_AGE = {
    "ar": "حسنًا، كم عمرك الصحيح؟",
    "en": "Sure — what's your correct age?",
}
CORRECTION_ASK_FIELD = {
    "ar": "عذرًا، ما المعلومة التي تريد تعديلها؟ الاسم، أم العمر، أم الأعراض؟",
    "en": "Sorry — which detail would you like to fix? Your name, your age, or your symptoms?",
}


CORRECTION_APPLIED_NAME = {
    "ar": "عدّلت الاسم لـ{value}. ",
    "en": "Got it, I've updated the name to {value}. ",
}
CORRECTION_APPLIED_AGE = {
    "ar": "عدّلت العمر لـ{value} سنة. ",
    "en": "Got it, I've updated the age to {value}. ",
}
CORRECTION_APPLIED_COMPLAINT = {


    "ar": "فهمت أنّ الوجع في {value}. ",
    "en": "Understood — the pain is in the {value}. ",
}
CORRECTION_APPLIED_GENERIC = {
    "ar": "عدّلت المعلومة. ",
    "en": "Got it, I've updated that. ",
}


_STRONG_CORRECTION_MARKERS = ("غلط", "خطا", "صحح", "عدل", "قصدي", "اقصد")


_WEAK_CORRECTION_MARKERS = ("مش", "ليس", "مو")


_LEADING_NEGATION_RE = re.compile(r"^\s*(?:لا|لأ)\b")


_NAME_CORRECTION_KEYWORDS = ("اسمي", "الاسم", "اسمى")
_AGE_CORRECTION_KEYWORDS = ("عمري", "العمر", "سني")
_COMPLAINT_CORRECTION_KEYWORDS = (
    "الوجع", "وجع", "الالم", "الم", "الشكوى", "بوجعني", "بتوجعني", "يوجعني",
)


_COMPLAINT_CORRECTION_HINTS = (
    ("بطن", "abdominal_pain", "البطن"),
    ("معده", "abdominal_pain", "المعدة"),
    ("كرش", "abdominal_pain", "البطن"),
    ("صداع", "headache", "الرأس"),
    ("راس", "headache", "الرأس"),
    ("صدر", "chest_pain", "الصدر"),
)


_SUSPICIOUS_NAME_WORDS = {
    normalize_text(w, "ar") for w in (
        "درج", "طاولة", "كرسي", "باب", "شباك", "سيارة", "كمبيوتر", "تلفون",
        "صداع", "الم", "ألم", "وجع", "دكتور", "طبيب", "مريض",
        "لا اعرف", "لا أعرف", "مش عارف", "مش متأكد",
    )
}


MAX_NAME_WORDS = 3
MAX_NAME_CHARS = 40


MAX_NAME_REPEAT_ATTEMPTS = 2


_SUSPICIOUS_NAME_TOKENS = {
    normalize_text(w, "ar") for w in (


        "اسمي", "اسم", "الاسم", "اسمك", "ندخل", "سوف", "راح", "بدي", "بدنا",
        "بدك", "احكي", "حكي", "قلت", "قلتلك", "بقول", "أقول", "اقول", "يعني",
        "هسا",

        "غلط", "خطأ", "خطا", "صحيح", "صح", "صحح",

        "رقم", "عمري", "العمر", "سنة", "سنه", "سنين", "سني",

        "وجع", "ألم", "الم", "صداع", "مريض", "دكتور", "طبيب", "حرارة",
        "غثيان", "تعب", "عندي", "بوجعني", "بتوجعني", "مرض",

        "لا", "نعم", "مش", "اعرف", "أعرف", "عارف", "متأكد", "متاكد",


        "مرحبا", "اهلا", "السلام", "كتب", "كتاب", "كلمة",
    )
}


_HEADACHE_CONTEXT_RE = re.compile(r"شديد|فجأة|مفاجئ")
_SUDDEN_HEADACHE_ASR_RE = re.compile(r"\bصدق\b")


_SILENT_ASR_CORRECTIONS = (
    ("إرهاف", "إرهاق"),
    ("الواخصر", "الخاصرة"),
    ("خواصر", "الخاصرة"),
    ("الزائده", "الزائدة"),
    ("زايدة", "الزائدة"),
)


_UNCERTAIN_CLINICAL_TERMS = {
    "الخاصرة": "flank_pain",
    "خاصرة": "flank_pain",
    "الزائدة": "appendicitis_context",
    "زائدة": "appendicitis_context",
    "جفاف": "dehydration_context",
    "أملاح": "urinary_or_dehydration_context",
    "املاح": "urinary_or_dehydration_context",
}

_CONFIRM_WORDS_AR = {"نعم", "اه", "آه", "ايوه", "أيوه", "ايوة", "صح", "صحيح", "تمام"}
_REJECT_WORDS_AR = {"لا", "لأ", "مش"}
_REJECT_PHRASES_AR = ("لا أقصد", "قصدي", "أقصد", "اقصد", "بحكي")


_CONFUSION_PHRASES_AR = (
    "مش فاهم", "مش فاهمة", "مش عارف", "مش عارفة",
    "لا اعرف", "لا أعرف", "مش متاكد", "مش متأكد",
)


_REJECTION_PREFIX_RE = re.compile(
    r"^\s*(?:لا|لأ|مش)?\s*[,،]?\s*(?:قصدي|أقصد|اقصد|بحكي|يعني)?\s*[:,،]?\s*",
)


_NAME_PREFIXES = re.compile(
    r"^\s*(?:"
    r"my\s+name\s+is|my\s+name'?s|i\s+am|i'm|it'?s|this\s+is|name\s+is|call\s+me|"
    r"اسمي|إسمي|انا|أنا|اسمى|اسمي\s+هو"
    r")\s*[:,]?\s*",
    re.IGNORECASE,
)

_ARABIC_INDIC = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")


_ARABIC_ONES = {
    "واحد": 1, "واحدة": 1,
    "اثنان": 2, "إثنان": 2, "اثنين": 2, "إثنين": 2,
    "ثلاثة": 3, "ثلاث": 3,
    "أربعة": 4, "اربعة": 4, "أربع": 4, "اربع": 4,
    "خمسة": 5, "خمس": 5,
    "ستة": 6, "ست": 6,
    "سبعة": 7, "سبع": 7,
    "ثمانية": 8, "ثمان": 8, "ثمانى": 8,
    "تسعة": 9, "تسع": 9,
}


_SPELLED_AGES = {
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    "seventy": 70, "eighty": 80, "ninety": 90,
    "عشرة": 10, "احدعشر": 11, "اثناعشر": 12,
    "عشرين": 20, "عشرون": 20,
    "ثلاثين": 30, "ثلاثون": 30,
    "اربعين": 40, "أربعين": 40, "اربعون": 40, "أربعون": 40,
    "خمسين": 50, "خمسون": 50,
    "ستين": 60, "ستون": 60,
    "سبعين": 70, "سبعون": 70,
    "ثمانين": 80, "ثمانون": 80,
    "تسعين": 90, "تسعون": 90,
    "مية": 100, "مائة": 100, "ماية": 100,
}


_ARABIC_TENS = {
    word: value for word, value in _SPELLED_AGES.items()
    if value >= 20 and value % 10 == 0 and not word.isascii()
}


_COMPOUND_AGE_RE = re.compile(
    r"\b(" + "|".join(sorted(_ARABIC_ONES, key=len, reverse=True)) + r")"
    r"\s+و\s*"
    r"(" + "|".join(sorted(_ARABIC_TENS, key=len, reverse=True)) + r")\b"
)

MIN_AGE, MAX_AGE = 1, 120


def _extract_name(message: str) -> str:

    cleaned = _NAME_PREFIXES.sub("", message.strip())
    cleaned = cleaned.strip(" .،,!?؟\"'").strip()
    if not cleaned:
        cleaned = message.strip()

    words = cleaned.split()
    return " ".join(words[:4])[:80]


def _extract_age(message: str) -> Optional[int]:
    text = message.translate(_ARABIC_INDIC)


    for match in re.findall(r"\b\d{1,3}\b", text):
        age = int(match)
        if MIN_AGE <= age <= MAX_AGE:
            return age


    compound = _COMPOUND_AGE_RE.search(text)
    if compound:
        age = _ARABIC_ONES[compound.group(1)] + _ARABIC_TENS[compound.group(2)]
        if MIN_AGE <= age <= MAX_AGE:
            return age

    lowered = text.lower()
    for word, value in _SPELLED_AGES.items():
        if word in lowered:
            return value
    return None


def _is_suspicious_name(name: str) -> bool:


    stripped = name.strip()
    if not stripped:
        return True
    if any(ch.isdigit() for ch in stripped):
        return True
    if len(stripped) > MAX_NAME_CHARS:
        return True


    if re.search(r"[؟?!،,.:؛;]", stripped):
        return True
    if normalize_text(stripped, "ar") in _SUSPICIOUS_NAME_WORDS:
        return True
    words = stripped.split()
    if len(words) > MAX_NAME_WORDS:
        return True
    if len(words) == 1 and len(words[0]) <= 1:
        return True
    return any(normalize_text(w, "ar") in _SUSPICIOUS_NAME_TOKENS for w in words)


def _looks_like_garbled_name(heard: str) -> bool:


    stripped = heard.strip()
    if not stripped:
        return True
    if len(stripped) > 20 or len(stripped.split()) > 2:
        return True
    if re.search(r"[؟?!،,.:؛;]", stripped):
        return True
    return any(normalize_text(w, "ar") in _SUSPICIOUS_NAME_TOKENS for w in stripped.split())


def _detect_high_risk_correction(text: str) -> Optional[Dict[str, str]]:


    if _SUDDEN_HEADACHE_ASR_RE.search(text) and _HEADACHE_CONTEXT_RE.search(text):
        suggested = "صداع شديد بدأ فجأة"
        return {"suggested": suggested, "question": f"هل تقصد {suggested}؟"}
    return None


def _apply_silent_asr_corrections(text: str) -> str:


    for heard, replacement in _SILENT_ASR_CORRECTIONS:
        text = text.replace(heard, replacement)
    return text


def _detect_uncertain_clinical_terms(text: str) -> List[str]:

    found: List[str] = []
    for term, tag in _UNCERTAIN_CLINICAL_TERMS.items():
        if term in text and tag not in found:
            found.append(tag)
    return found


def _classify_confirmation_reply(message: str, lang: str) -> str:


    norm = normalize_text(message, lang).strip()
    if not norm:
        return "unclear"

    def _word_present(word: str) -> bool:
        return re.search(rf"(?:^|\s){re.escape(word)}(?:$|\s|[.,!،؟?])", norm) is not None

    if any(phrase in norm for phrase in _CONFUSION_PHRASES_AR):
        return "unclear"
    if any(phrase in norm for phrase in _REJECT_PHRASES_AR) or any(
        _word_present(w) for w in _REJECT_WORDS_AR
    ):
        return "reject"
    if any(_word_present(w) for w in _CONFIRM_WORDS_AR):
        return "confirm"
    return "unclear"


def _extract_correction_text(message: str, lang: str) -> str:


    cleaned = _REJECTION_PREFIX_RE.sub("", message.strip())
    return cleaned.strip(" .،,!?؟\"'").strip()


def _start_pending_confirmation(
    profile: Dict[str, Any], field: str, heard: str, suggested: Optional[str], question: str,
) -> Dict[str, Any]:
    profile = dict(profile)
    profile["pending_confirmation"] = {
        "field": field, "heard": heard, "suggested": suggested,
        "question": question, "attempts": 0,
    }
    return profile


def _mark_confirmed(profile: Dict[str, Any], field: str, confirmed: bool) -> Dict[str, Any]:


    profile = dict(profile)
    confirmed_fields = dict(profile.get("confirmed_fields", {}))
    confirmed_fields[field] = confirmed
    profile["confirmed_fields"] = confirmed_fields
    if not confirmed:
        uncertain = dict(profile.get("uncertain_fields", {}))
        uncertain[field] = profile.get(field)
        profile["uncertain_fields"] = uncertain
    return profile


def _resolve_pending_confirmation(
    pending: Dict[str, Any], message: str, lang: str,
) -> Tuple[str, Optional[Any], Optional[str]]:


    classification = _classify_confirmation_reply(message, lang)

    if classification == "confirm":
        return "confirmed", pending.get("suggested") or pending["heard"], None

    if classification == "reject":
        corrected = _extract_correction_text(message, lang)
        if corrected:
            return "corrected", corrected, None
        classification = "unclear"


    attempts = int(pending.get("attempts", 0)) + 1
    if attempts <= MAX_CONFIRMATION_ATTEMPTS:
        retry_text = (
            NAME_CONFIRM_RETRY[lang] if pending["field"] == "name"
            else CHIEF_COMPLAINT_CONFIRM_RETRY[lang]
        )
        return "retry", attempts, retry_text


    return "gave_up", pending["heard"], None


def _apply_name_resolution(profile: Dict[str, Any], name: str, confirmed: bool) -> Dict[str, Any]:
    profile = dict(profile)
    profile["name"] = name
    profile.pop("pending_confirmation", None)
    return _mark_confirmed(profile, "name", confirmed)


def _apply_chief_complaint_resolution(profile: Dict[str, Any], text: str, confirmed: bool) -> Dict[str, Any]:
    profile = dict(profile)
    profile["chief_complaint_description"] = text
    profile.pop("pending_confirmation", None)
    return _mark_confirmed(profile, "chief_complaint", confirmed)


def _apply_confirmation_layer(
    profile: Dict[str, Any], phase: str, message: str, lang: str,
) -> Tuple[Dict[str, Any], str, str, Optional[str]]:


    effective_message = message
    confirmation_reply: Optional[str] = None

    pending = profile.get("pending_confirmation")
    if pending:
        outcome, resolved_value, reply_override = _resolve_pending_confirmation(pending, message, lang)

        if outcome == "retry":
            profile = dict(profile)
            profile["pending_confirmation"] = {**pending, "attempts": resolved_value}
            return profile, phase, effective_message, reply_override

        confirmed = outcome in ("confirmed", "corrected")
        if pending["field"] == "name":
            if outcome == "corrected":


                resolved_value = _extract_name(resolved_value) or resolved_value
            profile = _apply_name_resolution(profile, resolved_value, confirmed)
            confirmation_reply = ASK_AGE[lang].format(name=resolved_value)
            return profile, phase, effective_message, confirmation_reply


        profile = _apply_chief_complaint_resolution(profile, resolved_value, confirmed)
        effective_message = resolved_value
        return profile, phase, effective_message, None

    if phase == "intake" and not profile.get("name"):
        heard = _extract_name(message)
        if _is_suspicious_name(heard):
            if _looks_like_garbled_name(heard):


                attempts = int(profile.get("name_repeat_attempts", 0)) + 1
                if attempts <= MAX_NAME_REPEAT_ATTEMPTS:
                    profile = dict(profile)
                    profile["name_repeat_attempts"] = attempts
                    return profile, phase, effective_message, NAME_UNCLEAR_REPEAT[lang]


                profile = _apply_name_resolution(profile, heard, confirmed=False)
                profile.pop("name_repeat_attempts", None)
                return profile, phase, effective_message, ASK_AGE[lang].format(name=heard)


            question = NAME_CONFIRM_QUESTION[lang].format(heard_name=heard)
            profile = _start_pending_confirmation(profile, "name", heard, None, question)
            confirmation_reply = question
        return profile, phase, effective_message, confirmation_reply

    if phase == "greeting":
        high_risk = _detect_high_risk_correction(message)
        if high_risk:
            profile = _start_pending_confirmation(
                profile, "chief_complaint", message, high_risk["suggested"], high_risk["question"],
            )
            return profile, phase, effective_message, high_risk["question"]

        corrected = _apply_silent_asr_corrections(message)
        effective_message = corrected
        probe_symptoms = _extractor.extract(corrected).get("symptoms") or []
        terms = _detect_uncertain_clinical_terms(corrected)
        if terms:
            profile = dict(profile)
            uncertain = dict(profile.get("uncertain_fields", {}))
            uncertain["clinical_terms"] = terms
            profile["uncertain_fields"] = uncertain
            if not probe_symptoms:


                profile["chief_complaint_description"] = message
                confirmation_reply = FOCUSED_FLANK_URINARY_QUESTION[lang]
                return profile, "interviewing", effective_message, confirmation_reply

    return profile, phase, effective_message, confirmation_reply


def _extract_corrected_name(text: str) -> Optional[str]:


    match = re.search(r"(?:اسمي|إسمي|اسمى|الاسم)\s*(?:هو\s*)?(.+)", text.strip())
    candidate = (match.group(1) if match else text).strip()


    candidate = re.split(r"\s*(?:مش|ليس|مو)\s+", candidate)[0].strip()
    candidate = candidate.strip(" .،,!?؟\"'").strip()


    if re.search(r"صحح|عدل|عدّل", text) and candidate.startswith("ل") and len(candidate) > 2:
        candidate = candidate[1:].strip()

    if not candidate:
        return None
    candidate = _extract_name(candidate)
    return None if _is_suspicious_name(candidate) else candidate


def _extract_corrected_age(text: str) -> Optional[int]:


    without_negated = re.sub(
        r"(?:مش|ليس|مو|ما)\s*\d{1,3}", " ", text.translate(_ARABIC_INDIC),
    )
    return _extract_age(without_negated)


def _extract_corrected_chief_complaint(text: str, lang: str) -> Tuple[Optional[str], Optional[str]]:


    normalized = normalize_text(text, lang)
    affirmed = re.sub(r"(?:مش|ليس|مو)\s+[^،,]*", " ", normalized)
    for keyword, complaint, label in _COMPLAINT_CORRECTION_HINTS:
        if keyword in affirmed:
            return complaint, label
    return None, None


def _detect_profile_correction(
    text: str, profile: Dict[str, Any], lang: str,
) -> Optional[Dict[str, Any]]:


    normalized = normalize_text(text, lang)
    has_strong = any(marker in normalized for marker in _STRONG_CORRECTION_MARKERS)
    has_weak = any(marker in normalized for marker in _WEAK_CORRECTION_MARKERS)


    has_weak = has_weak or bool(_LEADING_NEGATION_RE.match(normalized))
    if not (has_strong or has_weak):
        return None

    def _result(field, new_value):
        return {"field": field, "new_value": new_value, "source_text": text}

    if any(k in normalized for k in _NAME_CORRECTION_KEYWORDS):
        value = _extract_corrected_name(text)
        if has_strong or value is not None:
            return _result("name", value)
        return None

    if any(k in normalized for k in _AGE_CORRECTION_KEYWORDS):
        value = _extract_corrected_age(text)
        if has_strong or value is not None:
            return _result("age", value)
        return None

    if any(k in normalized for k in _COMPLAINT_CORRECTION_KEYWORDS):
        complaint, label = _extract_corrected_chief_complaint(text, lang)
        if complaint is not None:
            return {"field": "chief_complaint", "new_value": complaint,
                    "label": label, "source_text": text}

        return _result(None, None) if has_strong else None


    return _result(None, None) if has_strong else None


def _record_correction(
    profile: Dict[str, Any], field: str, old_value: Any, new_value: Any,
    source_text: str, confirmed: bool = True,
) -> Dict[str, Any]:

    profile = dict(profile)
    history = list(profile.get("correction_history", []))
    history.append({
        "field": field, "old_value": old_value, "new_value": new_value,
        "source_text": source_text, "confirmed": confirmed,
    })
    profile["correction_history"] = history
    return profile


def _apply_profile_correction(
    profile: Dict[str, Any], correction: Dict[str, Any], lang: str,
) -> Tuple[Dict[str, Any], str, Optional[str]]:

    field = correction["field"]
    value = correction["new_value"]

    if field == "name":
        profile = _record_correction(profile, "name", profile.get("name"), value,
                                     correction["source_text"])
        profile = dict(profile)
        profile["name"] = value
        profile.pop("pending_correction", None)
        profile = _mark_confirmed(profile, "name", True)
        return profile, CORRECTION_APPLIED_NAME[lang].format(value=value), None

    if field == "age":
        profile = _record_correction(profile, "age", profile.get("age"), value,
                                     correction["source_text"])
        profile = dict(profile)
        profile["age"] = value
        profile.pop("pending_correction", None)
        profile = _mark_confirmed(profile, "age", True)
        return profile, CORRECTION_APPLIED_AGE[lang].format(value=value), None


    label = correction.get("label")
    profile = _record_correction(profile, "chief_complaint",
                                 profile.get("chief_complaint_description"),
                                 correction["source_text"], correction["source_text"])
    profile = dict(profile)
    profile["chief_complaint_description"] = correction["source_text"]
    profile.pop("pending_correction", None)
    profile = _mark_confirmed(profile, "chief_complaint", True)
    prefix = (
        CORRECTION_APPLIED_COMPLAINT[lang].format(value=label) if label
        else CORRECTION_APPLIED_GENERIC[lang]
    )
    return profile, prefix, value


def _correction_clarification_question(field: Optional[str], lang: str) -> str:
    if field == "name":
        return CORRECTION_ASK_NAME[lang]
    if field == "age":
        return CORRECTION_ASK_AGE[lang]
    return CORRECTION_ASK_FIELD[lang]


def _next_intake_reply(profile: Dict[str, Any], lang: str) -> Optional[str]:


    if not profile.get("name"):
        return GREETING[lang]
    if profile.get("age") is None:
        return ASK_AGE[lang].format(name=profile["name"])
    if not profile.get("chief_complaint_description"):
        return ASK_COMPLAINT[lang]
    return None


def _apply_correction_layer(
    profile: Dict[str, Any], phase: str, chief_complaint: Optional[str],
    message: str, lang: str,
) -> Tuple[Dict[str, Any], str, Optional[str], str, str, Optional[str]]:


    pending_correction = profile.get("pending_correction")

    if pending_correction:
        field = pending_correction.get("field")


        redetected = _detect_profile_correction(message, profile, lang)
        if redetected and redetected.get("field"):
            field = redetected["field"]
            value = redetected["new_value"]
        elif field == "name":
            candidate = _extract_name(message)
            value = None if _is_suspicious_name(candidate) else candidate
        elif field == "age":
            value = _extract_corrected_age(message)
        elif field == "chief_complaint":
            value, _label = _extract_corrected_chief_complaint(message, lang)
        else:
            value = None

        if field and value is not None:
            correction = {"field": field, "new_value": value, "source_text": message}
            if field == "chief_complaint":
                complaint, label = _extract_corrected_chief_complaint(message, lang)
                correction["new_value"], correction["label"] = complaint, label
            profile, prefix, new_complaint = _apply_profile_correction(profile, correction, lang)
            if new_complaint:
                chief_complaint = new_complaint
                phase = "greeting"
            next_reply = _next_intake_reply(profile, lang)
            if next_reply:
                return profile, phase, chief_complaint, message, "", prefix + next_reply
            return profile, phase, chief_complaint, message, prefix, None

        attempts = int(pending_correction.get("attempts", 0)) + 1
        if attempts <= MAX_CORRECTION_ATTEMPTS:
            profile = dict(profile)
            profile["pending_correction"] = {**pending_correction, "field": field,
                                             "attempts": attempts}
            return (profile, phase, chief_complaint, message, "",
                    _correction_clarification_question(field, lang))

        profile = dict(profile)
        profile.pop("pending_correction", None)
        return profile, phase, chief_complaint, message, "", None

    if profile.get("pending_confirmation"):
        return profile, phase, chief_complaint, message, "", None

    correction = _detect_profile_correction(message, profile, lang)
    if not correction:
        return profile, phase, chief_complaint, message, "", None

    if correction["field"] and correction["new_value"] is not None:
        profile, prefix, new_complaint = _apply_profile_correction(profile, correction, lang)
        if new_complaint:
            chief_complaint = new_complaint
            phase = "greeting"
        next_reply = _next_intake_reply(profile, lang)
        if next_reply:
            return profile, phase, chief_complaint, message, "", prefix + next_reply
        return profile, phase, chief_complaint, message, prefix, None


    profile = dict(profile)
    profile["pending_correction"] = {"field": correction["field"], "attempts": 0}
    return (profile, phase, chief_complaint, message, "",
            _correction_clarification_question(correction["field"], lang))


def _load_flows() -> Dict[str, dict]:
    flows: Dict[str, dict] = {}
    for fname in sorted(os.listdir(_FLOWS_DIR)):
        if not fname.endswith(".json"):
            continue
        with open(os.path.join(_FLOWS_DIR, fname), "r", encoding="utf-8") as f:
            flow = json.load(f)
            flows[flow["complaint"]] = flow
    return flows


FLOWS = _load_flows()

_extractor = EntityExtractor()
_safety = MedicalSafetyLayer()

# MedicalSafetyLayer's vocabulary ("normal" where the canonical lattice says
# "routine"), ranked. DERIVED from the one canonical ranking rather than
# restated (Phase 3): the values are byte-identical to the literal that used to
# be here, but there is now a single urgency ordering in the service and this
# is a view onto it. The legacy key is kept because the safety layer's own
# output still uses it — translation happens at the boundary
# (vocabulary.canonical_urgency), not by maintaining a second table.
_SEVERITY_RANK = {
    "normal": 0,
    **{level: rank - 1
       for level, rank in reasoning_engine.vocabulary.URGENCY_RANK.items()
       if level != "routine"},
}


def _check_safety(message: str, lang: str) -> dict:


    raw_result = _safety.check(message)
    normalized_result = _safety.check(normalize_text(message, lang))
    if _SEVERITY_RANK[normalized_result["severity"]] > _SEVERITY_RANK[raw_result["severity"]]:
        return normalized_result
    return raw_result


def _safety_hint_text(safety_result: dict) -> Optional[str]:


    if safety_result["severity"] not in ("emergency", "urgent"):
        return None
    matched = [m.get("matched") for m in safety_result.get("matched_patterns", []) if m.get("matched")]
    return ", ".join(matched) if matched else None


def _apply_safety_continuation(
    safety_result: dict, session, profile: Dict[str, Any], lang: str,
    symbolic_urgency: Optional[str] = None, message: str = "",
) -> Tuple[str, Optional[str], Dict[str, Any]]:


    severity = safety_result["severity"]
    prior_session_urgency = session["urgency_level"]

    # Phase 3: the deterministic layer's verdict merged with the symbolic one.
    # `symbolic_urgency` is None in every mode except VD_SYMBOLIC_SAFETY=active,
    # and merge_urgency is a maximum, so with None this reduces to exactly the
    # pre-Phase-3 expression. Prolog can raise the level here; it has no way to
    # lower it, and the deterministic layer still ran first and unconditionally.
    effective_severity = reasoning_engine.merge_urgency(severity, symbolic_urgency)

    if effective_severity == "routine":
        return "", prior_session_urgency, profile

    session_urgency = reasoning_engine.merge_urgency(
        prior_session_urgency, effective_severity)

    already_shown = profile.get("safety_warning_shown_for")
    escalated = (
        already_shown is None
        or _SEVERITY_RANK.get(session_urgency, 0) > _SEVERITY_RANK.get(already_shown, 0)
    )

    if session_urgency == "emergency":
        # The emergency body is MedicalSafetyLayer's own text, verbatim. It is
        # absent only when the layer itself did not flag this turn, i.e. when
        # the symbolic layer alone escalated to emergency; the same template is
        # then requested directly rather than a second wording being written for
        # the occasion. No patient-facing emergency text is new in Phase 3.
        body = safety_result.get("response") or _safety._get_emergency_response(
            message or ("ع" if lang == "ar" else "e"))
        prefix = (
            body + SAFETY_EMERGENCY_CONTINUATION[lang]
            if escalated else SAFETY_EMERGENCY_REMINDER[lang]
        )
    else:
        prefix = SAFETY_URGENT_WARNING[lang] if escalated else SAFETY_URGENT_REMINDER[lang]

    profile = dict(profile)
    if escalated:
        profile["safety_warning_shown_for"] = session_urgency


    matched = [m.get("matched") for m in safety_result.get("matched_patterns", []) if m.get("matched")]
    if matched:
        flags = list(profile.get("safety_flags_detected", []))
        for m in matched:
            if m not in flags:
                flags.append(m)
        profile["safety_flags_detected"] = flags

    return prefix, session_urgency, profile


def _lang(text: str, requested: Optional[str] = None) -> str:
    if requested in ("ar", "en"):
        return requested
    detected = detect_language(text)
    return detected if detected in ("ar", "en") else "en"


def _detect_chief_complaint(entities: dict) -> str:
    symptoms = entities.get("symptoms") or []
    for complaint, flow in FLOWS.items():
        if complaint == "generic":
            continue
        if any(s in symptoms for s in flow.get("match_symptoms", [])):
            return complaint
    return "generic"


def _next_unfilled_slot(flow: dict, profile: dict) -> Optional[dict]:
    for slot in flow["slots"]:
        if not profile.get(slot["key"]):
            return slot
    return None


_planner, _fallback_planner = planner.build(
    flows=FLOWS,
    texts={"ASK_AGE": ASK_AGE, "ASK_AGE_RETRY": ASK_AGE_RETRY,
           "ASK_COMPLAINT": ASK_COMPLAINT, "WRAP_UP": WRAP_UP},
    helpers={
        "extract_name": _extract_name,
        "extract_age": _extract_age,
        "detect_chief_complaint": _detect_chief_complaint,
        "next_unfilled_slot": _next_unfilled_slot,
    },


    validators={
        "text_matches_language": reasoning._text_matches_language,
        "looks_coherent": reasoning._looks_coherent,
    },
)

# Phase 2. Wraps the planner above so Prolog chooses the clinical topic and the
# wrapped planner only words it. Consulted ONLY in VD_SYMBOLIC_INTERVIEW=active
# — see _select_planner. Constructing it boots no engine and costs nothing.
_symbolic_planner = planner.build_symbolic(
    inner=_planner,
    flows=FLOWS,
    texts={"ASK_AGE": ASK_AGE, "ASK_AGE_RETRY": ASK_AGE_RETRY,
           "ASK_COMPLAINT": ASK_COMPLAINT, "WRAP_UP": WRAP_UP},
    helpers={
        "extract_name": _extract_name,
        "extract_age": _extract_age,
        "detect_chief_complaint": _detect_chief_complaint,
        "next_unfilled_slot": _next_unfilled_slot,
    },
)

def _as_uuid(value: Any) -> Optional[uuid.UUID]:


    if value is None or isinstance(value, uuid.UUID):
        return value
    return uuid.UUID(value)


def _load_jsonb(value: Any) -> dict:
    if isinstance(value, str):
        return json.loads(value) if value else {}
    return value or {}


async def _log_message(pool, session_row_id, role: str, text: str, entities: Optional[dict] = None) -> None:
    await pool.execute(
        """
        INSERT INTO virtual_doctor_messages (session_id, role, message_text, extracted_entities)
        VALUES ($1, $2, $3, $4)
        """,
        session_row_id,
        role,
        text,
        json.dumps(entities, ensure_ascii=False) if entities else None,
    )


def _intake_questions(profile: dict) -> int:


    return (
        (1 if profile.get("name") else 0)
        + (1 if profile.get("age") is not None else 0)
        + (1 if profile.get("chief_complaint_description") else 0)
    )


async def _observe_structured_understanding(message, lang, entities):
    """Run the Phase 6 understanding layer and log how it compares with the
    legacy extractor. Returns the understanding, or None when the mode is off.

    The CALLER decides whether the result may contribute facts, exactly as with
    the symbolic layers — so shadow and active share one code path here and
    cannot drift apart.

    Never raises. The understanding layer is an addition to extraction, not a
    replacement for it: if this returns None or an unavailable result, the turn
    proceeds on the legacy extractor alone, which is what every turn did before
    Phase 6.
    """
    if not understanding.enabled():
        return None
    try:
        result = await understanding.understand(message, lang)
    except Exception as exc:  # noqa: BLE001 - understanding must not end a turn
        logger.warning("Structured understanding failed (%s: %s)", type(exc).__name__, exc)
        return None

    fields = understanding.divergence(result, entities)
    _UNDERSTANDING_DIVERGENCE.record(result, fields)
    logger.info(
        "understanding(%s) available=%s legacy=%s structured=%s agree=%s "
        "structured_only=%s legacy_only=%s denied=%s uncertain=%s "
        "newly_reachable=%s conflicts=%s rejected=%d malformed=%s%s call=%.0fms",
        fields["mode"], fields["available"],
        fields["legacy"] or "-", fields["structured"] or "-", fields["agree"] or "-",
        fields["structured_only"] or "-", fields["legacy_only"] or "-",
        fields["denied"] or "-", fields["uncertain"] or "-",
        fields["newly_reachable_safety"] or "-", fields["conflicts"] or "-",
        fields["n_rejected"], fields["malformed"],
        f" forbidden={fields['forbidden_keys']}" if fields["forbidden_keys"] else "",
        fields["elapsed_ms"],
    )
    return result


async def _observe_symbolic_safety(session_id, profile, entities, chief_complaint,
                                   safety_result, session, structured=None):
    """Run symbolic safety reasoning and log how it compares with the legacy path.

    Returns the verdict (or None when the mode is off). The CALLER decides
    whether it may influence urgency — this function never does, so shadow and
    active share one code path and cannot drift apart.

    Logs canonical urgency levels, rule ids and canonical evidence atoms only.
    Never patient text, never RAG passages, never names, never free-text
    descriptions: a safety divergence log is audit material that lands in
    ordinary application logs, so it must be safe to keep.
    """
    if reasoning_engine.safety_mode() == "off":
        return None

    # Structured observations contribute facts only when the understanding
    # layer is in `active` mode — in shadow it has already been logged and is
    # discarded here, so the facts this turn reasons over are identical to
    # Phase 5's. The contribution is additive in one direction: build_facts
    # resolves any overlap upward, so a structured denial cannot cancel a
    # symptom the extractor reported, and none of this can lower the
    # deterministic floor, which enters as a separate fact and is merged with a
    # maximum.
    present = denied = uncertain = ()
    if structured is not None and structured.available and understanding.active():
        present = structured.present_symptoms
        denied = structured.denied_symptoms
        uncertain = structured.uncertain_symptoms

    try:
        verdict = await reasoning_engine.decide_safety_async(
            session_id,
            profile=profile,
            entities=entities,
            chief_complaint=chief_complaint,
            safety_result=safety_result,
            present_symptoms=present,
            denied_symptoms=denied,
            uncertain_symptoms=uncertain,
        )
    except Exception as exc:  # noqa: BLE001 - safety observation must not end a turn
        logger.warning("Symbolic safety observation failed (%s: %s)",
                       type(exc).__name__, exc)
        return None

    deterministic = reasoning_engine.vocabulary.canonical_urgency(
        safety_result.get("severity"))
    prior = reasoning_engine.vocabulary.canonical_urgency(session["urgency_level"])
    legacy_final = reasoning_engine.merge_urgency(prior, deterministic)
    symbolic_final = reasoning_engine.merge_urgency(legacy_final, verdict.urgency)

    _SAFETY_DIVERGENCE.record(verdict, legacy_final, symbolic_final)

    fields = verdict.as_log_fields()
    logger.info(
        "symbolic(safety-%s) deterministic=%s session_prior=%s legacy_final=%s "
        "symbolic_only=%s symbolic_final=%s escalates=%s agree=%s rules=%s "
        "evidence=%s query=%.2fms%s",
        reasoning_engine.safety_mode(), deterministic or "-", prior or "-",
        legacy_final, fields["symbolic_urgency"] or "-", symbolic_final,
        symbolic_final != legacy_final, symbolic_final == legacy_final,
        fields["rules"] or "-", fields["evidence"] or "-", fields["query_ms"],
        f" degraded={fields['degraded_reason']}" if fields["degraded_reason"] else "",
    )
    return verdict


async def _observe_symbolic_corrections(session_id, profile_before, legacy_candidate):
    """Run symbolic contradiction reasoning and compare it with the Python layer.

    Phase 4 is parallel, not authoritative: the Python correction layer has
    already decided by the time this runs, and nothing here changes what the
    patient sees. `legacy_candidate` is that layer's own normalised output, so
    the comparison is like for like.

    Logs canonical slots, opaque value tokens, turn indices and classification
    atoms. Never raw text — not the message, not the name, not
    correction_history's source_text.
    """
    if reasoning_engine.correction_mode() == "off":
        return None
    try:
        decision = await reasoning_engine.decide_corrections_async(
            session_id, profile=profile_before, correction_candidate=legacy_candidate)
    except Exception as exc:  # noqa: BLE001 - observation must not end a turn
        logger.warning("Symbolic correction observation failed (%s: %s)",
                       type(exc).__name__, exc)
        return None

    legacy_field = (legacy_candidate or {}).get("field")
    symbolic_field = decision.profile_correction_slot
    _CORRECTION_DIVERGENCE.record(decision, legacy_field, symbolic_field)

    fields = decision.as_log_fields()
    logger.info(
        "symbolic(corrections-%s) legacy_field=%s symbolic_field=%s agree=%s "
        "kinds=%s contradictions=%s query=%.2fms%s",
        reasoning_engine.correction_mode(), legacy_field or "-", symbolic_field or "-",
        legacy_field == symbolic_field, fields["kinds"] or "-",
        fields["contradictions"] or "-", fields["query_ms"],
        f" degraded={fields['degraded_reason']}" if fields["degraded_reason"] else "",
    )
    return decision


class _CorrectionDivergenceCounters:
    """Aggregate symbolic-vs-legacy correction counters. PHI-free.

    Slots and classification atoms only — no values, no tokens, no session ids.
    """

    __slots__ = ("_lock", "_data")

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._data = {"turns": 0, "available": 0, "unavailable": 0,
                      "agree": 0, "disagree": 0,
                      "legacy_only": 0, "symbolic_only": 0, "kind_hits": {}}

    def record(self, decision, legacy_field, symbolic_field) -> None:
        with self._lock:
            self._data["turns"] += 1
            self._data["available" if decision.available else "unavailable"] += 1
            if legacy_field == symbolic_field:
                self._data["agree"] += 1
            else:
                self._data["disagree"] += 1
                if legacy_field and not symbolic_field:
                    self._data["legacy_only"] += 1
                elif symbolic_field and not legacy_field:
                    self._data["symbolic_only"] += 1
            for _, kind in decision.kinds:
                self._data["kind_hits"][kind] = self._data["kind_hits"].get(kind, 0) + 1

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return {**self._data, "kind_hits": dict(self._data["kind_hits"])}

    def reset(self) -> None:
        with self._lock:
            self._data.update({"turns": 0, "available": 0, "unavailable": 0,
                               "agree": 0, "disagree": 0,
                               "legacy_only": 0, "symbolic_only": 0})
            self._data["kind_hits"] = {}


_CORRECTION_DIVERGENCE = _CorrectionDivergenceCounters()


def correction_divergence_counters() -> Dict[str, Any]:
    """Aggregate symbolic-vs-legacy correction counters. PHI-free."""
    return _CORRECTION_DIVERGENCE.snapshot()


class _SafetyDivergenceCounters:
    """Aggregate counters for reviewing shadow-mode behaviour.

    Deliberately counters and rule ids only — no per-turn records, no session
    ids, nothing that could reconstruct a consultation. The questions these are
    meant to answer are "how often does symbolic differ", "does it ever
    downgrade" (which must stay 0) and "which rules actually fire".
    """

    __slots__ = ("_lock", "_data")

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._data = {
            "turns": 0, "available": 0, "unavailable": 0,
            "agree": 0, "escalated": 0, "downgraded": 0,
            "rule_hits": {},
        }

    def record(self, verdict, legacy_final: str, symbolic_final: str) -> None:
        with self._lock:
            self._data["turns"] += 1
            self._data["available" if verdict.available else "unavailable"] += 1
            legacy_rank = reasoning_engine.vocabulary.URGENCY_RANK.get(legacy_final, 0)
            symbolic_rank = reasoning_engine.vocabulary.URGENCY_RANK.get(symbolic_final, 0)
            if symbolic_rank > legacy_rank:
                self._data["escalated"] += 1
            elif symbolic_rank < legacy_rank:
                # Must never happen: the merge is a maximum. Counted so that a
                # regression shows up as a number rather than as silence.
                self._data["downgraded"] += 1
            else:
                self._data["agree"] += 1
            for flag in verdict.red_flags:
                self._data["rule_hits"][flag.rule_id] = (
                    self._data["rule_hits"].get(flag.rule_id, 0) + 1)

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return {**self._data, "rule_hits": dict(self._data["rule_hits"])}

    def reset(self) -> None:
        with self._lock:
            self._data.update({"turns": 0, "available": 0, "unavailable": 0,
                               "agree": 0, "escalated": 0, "downgraded": 0})
            self._data["rule_hits"] = {}


_SAFETY_DIVERGENCE = _SafetyDivergenceCounters()


def safety_divergence_counters() -> Dict[str, Any]:
    """Aggregate symbolic-vs-legacy safety counters. PHI-free."""
    return _SAFETY_DIVERGENCE.snapshot()


class _UnderstandingDivergenceCounters:
    """Aggregate structured-vs-legacy extraction counters.

    Counters and canonical atoms only, same rule as everywhere else: no
    per-turn records, no session ids, no raw speech, no correction values.

    The questions these answer are the ones that decide whether `active` is
    justified: how often does the model produce something the extractor cannot
    (`structured_only`, `denied`, `uncertain`), how often does it fail
    (`malformed`, `unavailable`), how often does it reach for a diagnosis
    despite the prompt (`forbidden_keys`), and which latent safety rules does
    it actually make reachable (`newly_reachable`).
    """

    __slots__ = ("_lock", "_data")

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._data = self._zero()

    @staticmethod
    def _zero() -> Dict[str, Any]:
        return {
            "turns": 0, "available": 0, "unavailable": 0, "malformed": 0,
            "agree": 0, "structured_only": 0, "legacy_only": 0,
            "denied": 0, "uncertain": 0, "conflicts": 0,
            "rejected_values": 0, "forbidden_keys": 0,
            "newly_reachable": {},
        }

    def record(self, result, fields: Dict[str, Any]) -> None:
        with self._lock:
            self._data["turns"] += 1
            self._data["available" if result.available else "unavailable"] += 1
            if result.malformed:
                self._data["malformed"] += 1
            self._data["agree"] += len(fields["agree"])
            self._data["structured_only"] += len(fields["structured_only"])
            self._data["legacy_only"] += len(fields["legacy_only"])
            self._data["denied"] += len(fields["denied"])
            self._data["uncertain"] += len(fields["uncertain"])
            self._data["conflicts"] += len(fields["conflicts"])
            self._data["rejected_values"] += fields["n_rejected"]
            self._data["forbidden_keys"] += len(fields["forbidden_keys"])
            for atom in fields["newly_reachable_safety"]:
                self._data["newly_reachable"][atom] = (
                    self._data["newly_reachable"].get(atom, 0) + 1)

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return {**self._data, "newly_reachable": dict(self._data["newly_reachable"])}

    def reset(self) -> None:
        with self._lock:
            self._data = self._zero()


_UNDERSTANDING_DIVERGENCE = _UnderstandingDivergenceCounters()


def understanding_divergence_counters() -> Dict[str, Any]:
    """Aggregate structured-vs-legacy extraction counters. PHI-free."""
    return _UNDERSTANDING_DIVERGENCE.snapshot()


def _select_planner():
    """The planner that drives this turn.

    Only VD_SYMBOLIC_INTERVIEW=active hands control to the symbolic wrapper.
    In `off` and `shadow` the existing planner runs untouched, so nothing the
    patient sees can change — shadow reasoning happens afterwards, in
    _log_interview_divergence, purely as observation.
    """
    if reasoning_engine.interview_active():
        return _symbolic_planner
    return _planner


async def _log_interview_divergence(ctx: PlannerInput, result) -> None:
    """Shadow mode: what WOULD Prolog have asked, and does it agree?

    Runs against the profile as it is AFTER this turn's updates — the same
    state the existing planner used to pick its question — so the comparison is
    like for like.

    Logs canonical topics and counts only. No patient speech, no question text,
    no profile values: a divergence log is an engineering signal and has no
    business carrying PHI.
    """
    if reasoning_engine.interview_mode() != "shadow":
        return
    try:
        profile_after = {**ctx.profile, **(result.profile_updates or {})}
        flow = FLOWS.get(ctx.chief_complaint or "generic", FLOWS["generic"])
        decision = await reasoning_engine.decide_interview_async(
            ctx.session_id or "shadow",
            profile=profile_after,
            entities=ctx.entities,
            chief_complaint=ctx.chief_complaint,
            flow_slots=flow.get("slots", []),
            asked_topics=ctx.profile.get(planner.ASKED_TOPICS_KEY) or [],
            safety_topics=(
                (reasoning_engine.fact_builder.SAFETY_FOLLOW_UP_TOPIC,)
                if ctx.safety_hint else ()
            ),
        )
        planner_topic = reasoning_engine.vocabulary.infer_topic(result.reply)
        agree = (
            decision.topic == planner_topic
            if decision.topic and planner_topic else None
        )
        logger.info(
            "symbolic(interview-shadow) symbolic_topic=%s planner_topic=%s agree=%s "
            "priority=%s complete=%s planner_ready=%s ranked=%s unanswered=%s "
            "asked_unanswered=%s query=%.2fms%s",
            decision.topic or "-", planner_topic or "-", agree,
            decision.priority, decision.complete, result.ready_for_diagnosis,
            list(decision.ranked) or "-", list(decision.unanswered) or "-",
            list(decision.asked_unanswered) or "-", decision.query_ms,
            f" degraded={decision.degraded_reason}" if decision.degraded_reason else "",
        )
    except Exception as exc:  # noqa: BLE001 - observation must never break a turn
        logger.warning("Interview divergence logging failed (%s: %s)",
                       type(exc).__name__, exc)


async def _run_planner(ctx: PlannerInput):

    active = _select_planner()

    if active is _planner and _planner is _fallback_planner:
        result = await _planner.plan(ctx)
        await _log_interview_divergence(ctx, result)
        return result

    started = time.monotonic()
    try:
        result = await active.plan(ctx)
        if not result.wording_valid:
            # A typed partial result is consumable only by active symbolic mode,
            # where Prolog can select a deterministic template from the
            # accepted post-turn profile. OFF/SHADOW (and degraded active mode)
            # retain the historical per-turn static fallback semantics.
            raise PlannerError("planner returned no trusted question wording")
        logger.info("planner=%s %.0fms complaint=%s ready=%s reply=%r",
                    result.source, (time.monotonic() - started) * 1000,
                    result.chief_complaint, result.ready_for_diagnosis,
                    (result.reply or "")[:60])
        await _log_interview_divergence(ctx, result)
        return result
    except PlannerError as exc:
        logger.warning("Planner '%s' failed (%s) after %.0fms — falling back to the "
                       "static flow for this turn", active.name, exc,
                       (time.monotonic() - started) * 1000)
    except Exception as exc:
        logger.exception("Planner '%s' raised unexpectedly (%s) — falling back", active.name, exc)

    result = await _fallback_planner.plan(ctx)
    result.source = f"{active.name}->static"
    await _log_interview_divergence(ctx, result)
    return result


async def _build_turn_context(
    session, message: str, chief_complaint: Optional[str], lang: str,
) -> Dict[str, Any]:


    empty: Dict[str, Any] = {"history": [], "chunks": [], "context_block": "",
                             "memory_ms": 0.0, "rag_ms": 0.0}
    if not PER_TURN_CONTEXT:
        return empty

    timings: Dict[str, float] = {"memory_ms": 0.0, "rag_ms": 0.0}

    async def _timed_load_recent():
        t0 = time.monotonic()
        try:
            return await memory.load_recent(session["id"])
        finally:
            timings["memory_ms"] = (time.monotonic() - t0) * 1000

    async def _timed_retrieve_for_turn():
        t0 = time.monotonic()
        try:
            return await retrieval.retrieve_for_turn(message, chief_complaint, lang)
        finally:
            timings["rag_ms"] = (time.monotonic() - t0) * 1000

    history_result, chunks_result = await asyncio.gather(
        _timed_load_recent(), _timed_retrieve_for_turn(), return_exceptions=True,
    )

    if isinstance(history_result, Exception):
        logger.warning(
            "Per-turn memory lookup failed (%s) — continuing with empty history",
            type(history_result).__name__,
        )
        history = []
    else:
        history = history_result

    if isinstance(chunks_result, Exception):
        logger.warning(
            "Per-turn RAG retrieval failed (%s) — continuing with empty chunks",
            type(chunks_result).__name__,
        )
        chunks = []
    else:
        chunks = chunks_result

    logger.info(
        "turn context: history=%d msg(s) rag=%d passage(s) pages=%s "
        "memory=%.0fms rag=%.0fms complaint=%s topics=%s",
        len(history), len(chunks),
        [retrieval.cite(c) for c in chunks] or "-",
        timings["memory_ms"], timings["rag_ms"], chief_complaint or "-",
        retrieval.infer_topics(message) or "-",
    )

    return {
        "history": history,
        "chunks": chunks,
        "context_block": retrieval.format_context(chunks),
        "memory_ms": round(timings["memory_ms"], 1),
        "rag_ms": round(timings["rag_ms"], 1),
    }


async def start_session(language: Optional[str], user_id: Optional[str]) -> dict:
    lang = language if language in ("ar", "en") else "en"
    session_id = str(uuid.uuid4())
    pool = await get_pool()

    row = await pool.fetchrow(
        """
        INSERT INTO virtual_doctor_sessions (user_id, session_id, language, phase, patient_profile)
        VALUES ($1, $2, $3, 'intake', '{}'::jsonb)
        RETURNING id
        """,
        uuid.UUID(user_id) if user_id else None,
        session_id,
        lang,
    )

    reply = GREETING[lang]
    await _log_message(pool, row["id"], "doctor", reply)


    asyncio.get_running_loop().run_in_executor(None, planner.warm)

    return {"session_id": session_id, "reply": reply, "phase": "intake", "language": lang}


async def handle_message(
    session_id: str, message: str, owner_user_id: Optional[str] = None
) -> dict:
    pool = await get_pool()
    # Ownership is part of the lookup, not a check applied to the row after
    # fetching it: a session belonging to another account is simply not found,
    # so there is no row to accidentally act on and nothing to leak about
    # whether the id exists. owner_user_id is optional only so that in-process
    # test harnesses can drive the engine directly; every HTTP path supplies it.
    if owner_user_id:
        session = await pool.fetchrow(
            "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1 AND user_id = $2",
            session_id,
            uuid.UUID(owner_user_id),
        )
    else:
        session = await pool.fetchrow(
            "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1", session_id
        )
    if not session:
        raise ValueError("session_not_found")

    lang = session["language"] or _lang(message)
    await _log_message(pool, session["id"], "patient", message)


    safety_result = _check_safety(message, lang)

    profile = _load_jsonb(session["patient_profile"])
    phase = session["phase"]
    chief_complaint = session["chief_complaint"]


    # Captured before the correction layer mutates anything: symbolic
    # provenance must see the state the correction was proposed AGAINST, and
    # the layer's own normalised candidate is what the symbolic decision is
    # compared with. _detect_profile_correction is pure, so calling it here
    # costs nothing and leaves the layer untouched.
    profile_before_correction = dict(profile)
    legacy_correction_candidate = _detect_profile_correction(message, profile, lang)

    (profile, phase, chief_complaint, effective_message,
     correction_prefix, correction_reply) = _apply_correction_layer(
        profile, phase, chief_complaint, message, lang,
    )

    # Phase 4, parallel only. The Python layer above has already decided; this
    # observes and logs. Nothing below reads the result.
    await _observe_symbolic_corrections(
        session_id, profile_before_correction, legacy_correction_candidate)


    if correction_reply is None:
        profile, phase, effective_message, confirmation_reply = _apply_confirmation_layer(
            profile, phase, effective_message, lang,
        )
    else:
        confirmation_reply = None

    entities = _extractor.extract(effective_message)

    # Phase 6 structured understanding. Runs ALONGSIDE the legacy extractor,
    # never instead of it — `entities` above is untouched and still drives
    # everything it drove before. Off by default; in shadow the comparison is
    # logged and discarded; only in active do its validated observations reach
    # fact_builder, and even then only additively.
    #
    # Placed after MedicalSafetyLayer (which ran on the raw message at the top
    # of this turn) so the deterministic floor is already established: if this
    # call times out or the model returns nonsense, the raw safety layer has
    # already protected the turn.
    structured = await _observe_structured_understanding(effective_message, lang, entities)

    # Phase 3 symbolic safety. Runs after MedicalSafetyLayer, never instead of
    # it, and contributes an urgency only in VD_SYMBOLIC_SAFETY=active — where
    # merge_urgency can only raise the level. In shadow it is logged and
    # discarded, so the patient-facing result is bit-identical to Phase 2.
    safety_verdict = await _observe_symbolic_safety(
        session_id, profile, entities, chief_complaint, safety_result, session,
        structured=structured)

    safety_prefix, session_urgency, profile = _apply_safety_continuation(
        safety_result, session, profile, lang,
        symbolic_urgency=(
            safety_verdict.urgency
            if safety_verdict is not None and reasoning_engine.safety_active()
            else None
        ),
        message=message,
    )

    # Symbolic reasoning, SHADOW MODE (Phase 1). Off unless VD_SYMBOLIC=1, and
    # even then its result is logged and discarded — nothing below reads it, so
    # urgency, the planner, corrections, the differential, the reply and TTS
    # are byte-for-byte what they were before this layer existed. Placed here
    # so it observes the same post-safety state the planner will see, and
    # deliberately fed only values already in hand: adding a query for it would
    # change this turn's I/O, which "no behaviour change" has to include.
    await reasoning_engine.observe_turn(
        session_id,
        profile=profile,
        entities=entities,
        chief_complaint=chief_complaint,
        safety_result=safety_result,
    )

    if correction_reply is not None:


        plan = None
    elif confirmation_reply is not None:


        plan = None
    else:


        turn_context = await _build_turn_context(session, effective_message, chief_complaint, lang)


        asked = await memory.doctor_turns(session["id"])
        plan = await _run_planner(PlannerInput(
            message=effective_message,
            lang=lang,
            phase=phase,
            chief_complaint=chief_complaint,
            profile=profile,
            entities=entities,
            history=turn_context["history"],
            chunks=turn_context["chunks"],
            context_block=turn_context["context_block"],
            turn_index=max(0, len(asked) - _intake_questions(profile)),
            asked_questions=asked,
            safety_hint=_safety_hint_text(safety_result),
            session_id=session_id,
            asked_topics=list(profile.get(planner.ASKED_TOPICS_KEY) or []),
        ))

        profile.update(plan.profile_updates)
        phase = plan.phase
        if plan.chief_complaint:
            chief_complaint = plan.chief_complaint

    urgency_level = session_urgency
    recommended_specialty_id = session["recommended_specialty_id"]
    differential = _load_jsonb(session["differential"]) if session["differential"] else None
    reasoning_result: Optional[dict] = None

    if plan is not None and plan.ready_for_diagnosis:


        full_history = await memory.load_recent(session["id"], limit=memory.FULL_HISTORY_LIMIT)
        reasoning_result = await reasoning.run_reasoning(
            chief_complaint, profile, lang, history=full_history
        )
        phase = "complete"


        urgency_level = (
            reasoning._more_urgent(urgency_level, reasoning_result["urgency_level"])
            if urgency_level else reasoning_result["urgency_level"]
        )
        recommended_specialty_id = reasoning_result["recommended_specialty_id"]
        differential = reasoning_result["differential"]
        reply = reasoning_result["reply"]


        asyncio.get_running_loop().run_in_executor(None, planner.warm)
    elif plan is not None and plan.reply is not None:
        reply = plan.reply
    elif plan is not None:
        reply = WRAP_UP[lang]


    if confirmation_reply is not None:
        reply = confirmation_reply
    if correction_reply is not None:
        reply = correction_reply


    if correction_prefix:
        reply = f"{correction_prefix}{reply}"
    if safety_prefix:
        reply = f"{safety_prefix}{reply}"

    await pool.execute(
        """
        UPDATE virtual_doctor_sessions
        SET phase = $2, chief_complaint = $3, patient_profile = $4::jsonb,
            urgency_level = $5, recommended_specialty_id = $6, differential = $7::jsonb,
            updated_at = CURRENT_TIMESTAMP
        WHERE session_id = $1
        """,
        session_id,
        phase,
        chief_complaint,
        json.dumps(profile, ensure_ascii=False),
        urgency_level,
        _as_uuid(recommended_specialty_id),
        json.dumps(differential, ensure_ascii=False) if differential else None,
    )
    await _log_message(pool, session["id"], "doctor", reply, entities)

    result = {
        "session_id": session_id,
        "reply": reply,
        "phase": phase,
        "chief_complaint": chief_complaint,
        "urgency_level": urgency_level,
        # symbolic_asked_topics is internal bookkeeping for the symbolic
        # interview planner (Phase 2/9), read back from patient_profile on
        # later turns — it must stay in what is persisted, but has no
        # business in a client-facing payload. Persistence above uses
        # `profile` directly and is unaffected by this copy.
        "profile_snapshot": {k: v for k, v in profile.items()
                             if k != planner.ASKED_TOPICS_KEY},
    }
    if reasoning_result:
        result["recommended_specialty_id"] = reasoning_result["recommended_specialty_id"]
        result["recommended_specialty_name_en"] = reasoning_result["recommended_specialty_name_en"]
        result["recommended_specialty_name_ar"] = reasoning_result["recommended_specialty_name_ar"]
        result["confidence"] = reasoning_result["confidence"]
        result["differential"] = reasoning_result["differential"]
    return result


async def get_session_state(
    session_id: str, owner_user_id: Optional[str] = None
) -> Optional[dict]:
    pool = await get_pool()
    if owner_user_id:
        session = await pool.fetchrow(
            "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1 AND user_id = $2",
            session_id,
            uuid.UUID(owner_user_id),
        )
    else:
        session = await pool.fetchrow(
            "SELECT * FROM virtual_doctor_sessions WHERE session_id = $1", session_id
        )
    if not session:
        return None

    messages = await pool.fetch(
        """
        SELECT role, message_text FROM virtual_doctor_messages
        WHERE session_id = $1 ORDER BY created_at
        """,
        session["id"],
    )

    return {
        "session_id": session["session_id"],
        "language": session["language"],
        "chief_complaint": session["chief_complaint"],
        "phase": session["phase"],
        "patient_profile": _load_jsonb(session["patient_profile"]),
        "urgency_level": session["urgency_level"],
        "recommended_specialty_id": str(session["recommended_specialty_id"]) if session["recommended_specialty_id"] else None,
        "differential": _load_jsonb(session["differential"]) if session["differential"] else None,
        "messages": [{"role": m["role"], "text": m["message_text"]} for m in messages],
    }
