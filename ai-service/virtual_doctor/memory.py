"""
Virtual Doctor — conversation memory.

Loads the recent transcript for a session so each turn can be reasoned about in
context rather than in isolation. Deliberately thin: virtual_doctor_messages is
already the single source of truth (the service keeps no in-process session
state), so this is a read model over it, not a second store.

ORDERING CAVEAT
---------------
virtual_doctor_messages has no monotonic sequence column — its primary key is a
random UUID — so created_at is the only ordering available. Two rows written in
the same microsecond could in principle come back transposed. This module
deliberately uses the same `ORDER BY created_at` that get_session_state() has
always used rather than inventing a different one: matching the existing
behaviour is worth more than a theoretical tie-break, and fixing it properly
would mean a schema change.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional

from db import get_pool

logger = logging.getLogger("medorbit-ai.virtual_doctor.memory")

# "At least the last 10 messages" is the requirement; 12 is the default so a
# 10-message window is still full after the current turn's patient message and
# doctor reply are appended.
HISTORY_LIMIT = int(os.environ.get("VD_HISTORY_LIMIT", "12"))

# Guard against one pathological answer (a dictated paragraph, or STT looping)
# crowding the entire window out of the prompt.
MAX_MESSAGE_CHARS = int(os.environ.get("VD_HISTORY_MAX_CHARS", "600"))

# The final diagnosis is one call per consultation, not per turn, so it can
# afford the WHOLE transcript rather than the per-turn HISTORY_LIMIT window.
# planner.MAX_INTERVIEW_TURNS=6 clinical + 2 intake questions, each with a
# patient reply, tops out around ~16 messages in the normal case — 50 is a
# defensive ceiling against a pathological session, not a real-world limit.
FULL_HISTORY_LIMIT = int(os.environ.get("VD_FULL_HISTORY_LIMIT", "50"))

ROLE_LABELS = {
    "en": {"patient": "Patient", "doctor": "Doctor"},
    "ar": {"patient": "المريض", "doctor": "الطبيب"},
}


async def load_recent(
    session_row_id: Any,
    limit: Optional[int] = None,
) -> List[Dict[str, str]]:
    """Return the last `limit` messages oldest-first. Never raises.

    Takes the sessions table's UUID primary key (not the public session_id
    string), matching the FK on virtual_doctor_messages.

    Fetches DESC + LIMIT so the database returns only the tail — reversing in
    Python afterwards — rather than loading a whole long consultation and
    slicing it here.
    """
    n = max(1, limit or HISTORY_LIMIT)
    try:
        pool = await get_pool()
        rows = await pool.fetch(
            """
            SELECT role, message_text
            FROM virtual_doctor_messages
            WHERE session_id = $1
            ORDER BY created_at DESC
            LIMIT $2
            """,
            session_row_id,
            n,
        )
    except Exception as exc:  # noqa: BLE001 - memory must never break a turn
        logger.warning("Could not load conversation memory (%s) — continuing without it", exc)
        return []

    history = [
        {"role": r["role"], "text": (r["message_text"] or "")[:MAX_MESSAGE_CHARS]}
        for r in reversed(rows)
    ]
    return history


async def doctor_turns(session_row_id: Any) -> List[str]:
    """Every question the doctor has asked this session, oldest first.

    Deliberately NOT derived from load_recent(): that returns a truncated
    window, so counting doctor turns in it plateaus once the conversation is
    longer than the window. The interview's turn cap depends on this count, and
    a cap that silently stops incrementing is a cap that never fires — which is
    exactly how a dynamic planner ends up looping forever.

    Also feeds the planner the list of questions already asked, which the
    window alone stops covering once the interview runs long.
    """
    try:
        pool = await get_pool()
        rows = await pool.fetch(
            """
            SELECT message_text
            FROM virtual_doctor_messages
            WHERE session_id = $1 AND role = 'doctor'
            ORDER BY created_at
            """,
            session_row_id,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("Could not load doctor turns (%s)", exc)
        return []
    return [(r["message_text"] or "").strip() for r in rows if (r["message_text"] or "").strip()]


def format_history(
    messages: List[Dict[str, str]],
    lang: str = "en",
    limit: Optional[int] = None,
) -> str:
    """Render the transcript as labelled lines for an LLM prompt.

    Role labels are localised so an Arabic consultation's prompt does not mix
    scripts — the reasoning model is measurably prone to language drift, and
    English scaffolding around Arabic content is one of the things that
    encourages it.
    """
    if not messages:
        return ""
    labels = ROLE_LABELS.get(lang, ROLE_LABELS["en"])
    window = messages[-limit:] if limit else messages
    return "\n".join(
        f"{labels.get(m['role'], m['role'])}: {m['text']}"
        for m in window
        if (m.get("text") or "").strip()
    )
