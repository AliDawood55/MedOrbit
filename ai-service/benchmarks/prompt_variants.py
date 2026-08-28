"""
Phase 6.5 — candidate understanding prompts.

Variants live here, OUTSIDE production, until held-out evidence justifies
promoting one. v1 is the shipped Phase 6 prompt and is not restated: the runner
calls understanding.build_prompt directly for it, so the baseline is the real
baseline rather than a copy that could drift.

WHAT v2 CHANGES, AND WHY — each fix traces to a DEV failure
------------------------------------------------------------
Every change below was written against a dev-split failure and none against a
held-out sentence. No held-out text appears here verbatim; a unit test asserts
that for whichever variant is in production.

  1. EXACT-COPY, IN ENGLISH.
     dev `ar_bleeding_02` returned "严重出血" — the Chinese for "severe
     bleeding" — for Arabic input. The model UNDERSTOOD the sentence and then
     wrote the label in the wrong language, so the validator rejected a
     correct reading. qwen2.5 is a Chinese-origin model and this is its default
     pull, not a comprehension failure. Hence: copy the value character for
     character from the list, and the list is English regardless of the
     patient's language.

  2. EXPLICIT UNCERTAINTY EXAMPLES.
     dev `en_uncertain_01` put the literal string "uncertain" in the SYMPTOM
     field — it confused the two columns. dev `ar_uncertain_01` returned
     `absent` for "I am not sure". Both are structural, so both get a worked
     example rather than more prose.

  3. EXTRACT EVERY SYMPTOM.
     dev `ar_multi_01` ("headache and nausea") returned headache only.

  4. NEVER INFER FROM A DISEASE NAME.
     dev `ar_unsupported_01` (Arabic "appendicitis") returned `stomach_ache` —
     the model reasoned from the condition to its symptom. That is exactly the
     inference Phase 6 forbids: it is diagnosis run backwards.

  5. EMPTY FINDINGS UNLESS DESCRIBED.
     Six dev cases invented a `location`/`character`/`severity` finding from a
     sentence that described no such thing.

WHAT v2 DELIBERATELY DOES NOT DO
--------------------------------
No chain-of-thought, no reasoning steps, no condition vocabulary, no
instruction to infer anything unstated, and no widening of the allow-list. The
allow-list is still generated from vocabulary.SYMPTOMS at call time, so it
cannot drift from the validator.
"""

from __future__ import annotations

from virtual_doctor import understanding

_EXAMPLES = """EXAMPLES — copy this behaviour exactly:

"I have a headache"
{"symptoms": [{"symptom": "headache", "status": "present", "historical": false}]}

"I don't have any cough"
{"symptoms": [{"symptom": "cough", "status": "absent", "historical": false}]}

"I can't tell whether I'm running a temperature"
{"symptoms": [{"symptom": "fever", "status": "uncertain", "historical": false}]}

"بطني بيوجعني"
{"symptoms": [{"symptom": "stomach_pain", "status": "present", "historical": false}]}

"ما في كحة عندي"
{"symptoms": [{"symptom": "cough", "status": "absent", "historical": false}]}

"ما بعرف إذا في حرارة أو لا"
{"symptoms": [{"symptom": "fever", "status": "uncertain", "historical": false}]}

"عندي نزيف قوي"
{"symptoms": [{"symptom": "severe_bleeding", "status": "present", "historical": false}]}

"My stomach hurts and I feel dizzy"
{"symptoms": [{"symptom": "stomach_pain", "status": "present", "historical": false},
              {"symptom": "dizziness", "status": "present", "historical": false}]}

"I was coughing a lot last month, it stopped"
{"symptoms": [{"symptom": "cough", "status": "present", "historical": true}]}

"I think it is bronchitis"
{"symptoms": []}
"""


_EXAMPLES_V3 = _EXAMPLES + """
"I feel dizzy but I don't have any rash"
{"symptoms": [{"symptom": "dizziness", "status": "present", "historical": false},
              {"symptom": "skin_rash", "status": "absent", "historical": false}]}

"About four days now"
{"symptoms": [], "findings": {"duration": "about four days"}}

"Actually I'm 31, I said it wrong"
{"symptoms": [], "corrections": [{"field": "age", "old_value": "", "new_value": "31", "explicit": true}]}

"Is there parking nearby?"
{"symptoms": [], "findings": {}, "corrections": []}

"شكرا لك"
{"symptoms": [], "findings": {}, "corrections": []}
"""

_V3_EXTRA_RULES = """- If the patient mentions NO symptom from the list, "symptoms" MUST be [].
  An empty list is a correct and expected answer. Never fill it to avoid
  returning nothing.
- Something the patient says is FINISHED is not "absent". Use "historical":
  true and keep the status they used. "absent" means they say they do not have
  it now."""

_V2_TEMPLATE = """Patient said (language: {language}):
{message}

Extract ONLY what the patient stated about themselves, in their own words.

ALLOWED symptom values — the ONLY strings you may put in "symptom":
{symptoms}

ALLOWED finding keys — the ONLY keys you may put in "findings":
{slots}

status must be exactly one of: present, absent, uncertain
  present    they say they HAVE it
  absent     they say they do NOT have it
  uncertain  they are unsure, hedging, guessing, or say "maybe" / "I think"

{examples}
Return ONLY this JSON object:
{{
  "symptoms": [{{"symptom": "<allowed symptom>", "status": "<present|absent|uncertain>", "historical": false}}],
  "findings": {{"<allowed finding key>": "<what the patient said about it>"}},
  "corrections": [{{"field": "name|age|sex|chief_complaint", "old_value": "", "new_value": "", "explicit": true}}],
  "language": "{language}"
}}

Rules:
- The "symptom" value must be COPIED CHARACTER FOR CHARACTER from the allowed
  list above. The list is in English. Write it in English even when the patient
  speaks Arabic. Never translate it into any other language.
- If what the patient described is not on the allowed list, LEAVE IT OUT. Do not
  substitute the closest word.
- List EVERY symptom the patient mentions separately. Two symptoms in one
  sentence means two entries.
- NEVER output a disease, condition or diagnosis, in any field.
- NEVER infer a symptom from a disease name. If they name an illness, output no
  symptom for it.
- NEVER add a symptom the patient did not mention.
- Set "historical": true only when they say it is over or in the past.
- "findings" must be {{}} unless the patient actually described that attribute.
- "corrections" must be [] unless the patient is correcting something they said
  earlier.
- Return JSON only. No explanation, no extra keys."""


def build_v2(message: str, lang: str) -> str:
    return _V2_TEMPLATE.format(
        language="ar" if lang == "ar" else "en",
        message=message,
        symptoms=", ".join(understanding.ALLOWED_SYMPTOMS),
        slots=", ".join(understanding.ALLOWED_SLOTS),
        examples=_EXAMPLES,
    )


def build_v3(message: str, lang: str) -> str:
    return _V2_TEMPLATE.format(
        language="ar" if lang == "ar" else "en",
        message=message,
        symptoms=", ".join(understanding.ALLOWED_SYMPTOMS),
        slots=", ".join(understanding.ALLOWED_SLOTS),
        examples=_EXAMPLES_V3,
    ) + "\n" + _V3_EXTRA_RULES


_V4_EXTRA_RULES = """
- Extract ONLY what the patient says about THEMSELVES, right now. If they
  describe someone else — a relative, a friend, another patient — output no
  symptom for it.
- A QUESTION about a symptom is not a report of it. If the patient is asking
  whether something is serious, or asking about a condition in general, output
  no symptom."""


def build_v4(message: str, lang: str) -> str:
    return understanding.build_prompt(message, lang) + _V4_EXTRA_RULES
