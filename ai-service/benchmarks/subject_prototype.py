"""
Phase 8.1 — experimental subject-attribution schema. EVALUATION ONLY.

Nothing here is production. `virtual_doctor/understanding.py` is untouched;
this exists to answer one question before anyone considers changing it:

    If the model is asked WHO each observation belongs to as a separate field,
    does attribution become reliable?

WHY THIS, AND WHY NOW
---------------------
Phase 8.1's first run answered the prior question definitively: model capacity
alone does not fix attribution. qwen2:7b scored *identically* to qwen2.5:3b on
the two failure shapes —

    third-party      10 false positives, 7 of them safety atoms (both models)
    question-as-report 7 false positives, 6 of them safety atoms (both models)

— while being clearly better everywhere else (17 vs 25 control FPs, F1 0.533 vs
0.462, and a perfect 10/10 on positive controls). A failure that does not move
between a 3B and a 7B of the same family is not a capacity problem. It is a
problem with what the task asks for: v1 asks "which symptoms are in this
sentence?", and in "my brother had a seizure" the honest answer to THAT question
is `seizure`. The model is not hallucinating; it is answering the question asked.

So the change is to the question, not to the model.

THE FAIL-CLOSED RULE
--------------------
    subject == "patient"  -> eligible to become a patient fact
    subject == "other"    -> never a patient fact
    subject == "unknown"  -> never a patient fact
    subject missing       -> never a patient fact
    subject unrecognised  -> never a patient fact

Absence of an explicit "patient" is treated as "not the patient". That
direction is deliberate and is the whole safety argument: the cost of dropping
a real symptom is one missed escalation that MedicalSafetyLayer still catches
from raw text, while the cost of keeping someone else's is a consultation
escalated on a person who is not in the room.

NO LEXICAL HEURISTICS
---------------------
There is no `if "my brother" in text` here, in any language. The filter reads
only the model's own structured claim about the subject. If the model cannot
make that claim reliably, the prototype fails and that is the finding — patching
it with regexes would measure the regexes, not the model.
"""

from __future__ import annotations

from typing import Any, Dict, Mapping, Tuple

from virtual_doctor import understanding

# Only this value survives. Everything else — including a missing field — is
# treated as "not the patient".
PATIENT = "patient"
RECOGNISED_SUBJECTS = ("patient", "other", "unknown")

_V5_SCHEMA_RULES = """

Every symptom you output MUST also say WHOSE symptom it is, in a "subject"
field:

  "subject": "patient"   the person you are talking to has it themselves
  "subject": "other"     someone else has it (a relative, a friend, anyone else)
  "subject": "unknown"   you cannot tell whose it is

Set "subject": "other" when the patient describes another person.
Set "subject": "unknown" when the patient is ASKING about a symptom in general
rather than reporting one, or when it is otherwise unclear whose it is.

Example shape:
{"symptoms": [{"symptom": "seizure", "status": "present", "subject": "other"}]}

Only "patient" means the person you are talking to. If you are not certain it is
theirs, do not write "patient"."""


def build_v5(message: str, lang: str) -> str:
    """Production prompt v1 plus the subject field. Deliberately a minimal
    delta from the SHIPPED prompt, so any change measured is attributable to
    the schema rather than to the accumulated wording of v2/v3/v4."""
    return understanding.build_prompt(message, lang) + _V5_SCHEMA_RULES


def filter_by_subject(payload: Any) -> Tuple[Any, Dict[str, int]]:
    """Drop every observation not explicitly claimed for the patient.

    Runs BEFORE understanding.parse_understanding, so the production validator
    and its allow-list still do all the actual validation — this only removes
    entries first. That ordering matters: the prototype is a narrowing filter
    on top of the trust boundary, never a replacement for it.

    Returns the narrowed payload plus counts, so a model that simply stopped
    emitting anything is distinguishable from one that attributed correctly.
    """
    stats = {"total": 0, "patient": 0, "other": 0, "unknown": 0,
             "missing": 0, "unrecognised": 0}
    if not isinstance(payload, Mapping):
        return payload, stats

    raw = payload.get("symptoms")
    if not isinstance(raw, (list, tuple)):
        return payload, stats

    kept = []
    for entry in raw:
        stats["total"] += 1
        if not isinstance(entry, Mapping):
            # A bare string carries no subject claim, so it fails closed like
            # everything else that does not say "patient".
            stats["missing"] += 1
            continue
        subject = entry.get("subject")
        subject = subject.strip().lower() if isinstance(subject, str) else None
        if subject is None:
            stats["missing"] += 1
            continue
        if subject not in RECOGNISED_SUBJECTS:
            stats["unrecognised"] += 1
            continue
        stats[subject] += 1
        if subject == PATIENT:
            kept.append(entry)

    narrowed = dict(payload)
    narrowed["symptoms"] = kept
    return narrowed, stats
