"""
Virtual Doctor — safe numeric environment-variable parsing.

WHAT THIS FIXES
---------------
Every numeric setting in this package used to be read as a bare
`int(os.environ.get(...))` or `float(...)` at MODULE IMPORT TIME. That means a
single mistyped value in a deployment environment —

    VD_PLANNER_TIMEOUT=abc

— did not misconfigure the planner. It raised ValueError while `planner` was
being imported, which propagated through `interview_engine` and took the whole
service down at startup, with a traceback pointing at a module rather than at
the variable. A typo in an operational knob should never be able to do that.

The rule this module establishes:

    unset            -> the documented default
    valid            -> the parsed value          (identical to before)
    malformed        -> WARN, then the default
    out of bounds    -> WARN, then the default
    non-finite float -> WARN, then the default

Never an exception, never a partially configured module, and never a value the
call site cannot use.

WHY BOUNDS AT ALL, AND WHERE THEY COME FROM
-------------------------------------------
Bounds are not taste. Each one is derived from the USE SITE of the value it
guards, and a setting whose use site implies no bound gets type validation
only. Two of them fix real silent corruption rather than mere oddity:

    VD_HISTORY_MAX_CHARS  -> `text[:MAX_MESSAGE_CHARS]`
    RAG_MAX_CHUNK_CHARS   -> `chunk_text[:RAG_MAX_CHUNK_CHARS]`

A NEGATIVE value there does not fail. It truncates from the wrong END of the
string, silently feeding the model the tail of a message instead of its head.
That is a data bug that no exception would ever have surfaced.

WHAT THIS MODULE DELIBERATELY DOES NOT DO
-----------------------------------------
It does not touch the mode flags (VD_SYMBOLIC, VD_SYMBOLIC_*,
VD_STRUCTURED_UNDERSTANDING, VD_BOUNDED_RESPONSE, VD_PLANNER). Those already
warn-and-default to a safe non-active state, and their fail-safe direction —
never `active` — is a property of the modes themselves rather than of parsing.
Rewriting them through a generic helper would risk that guarantee for no gain.

FAIL-SAFE DIRECTION
-------------------
The fallback is ALWAYS the existing code default, never a permissive one. A
malformed value can therefore never grant a larger inference budget, a longer
timeout, a disabled safety check, or an experimental mode.
"""

from __future__ import annotations

import logging
import math
import os
from typing import Optional, Set, Tuple

logger = logging.getLogger("medorbit-ai.virtual_doctor.config")

_warned: Set[Tuple[str, str]] = set()

_MAX_LOGGED_NAME = 64


def reset_warning_state() -> None:
    """Forget which warnings have been emitted. Test support only."""
    _warned.clear()


def _warn(name: str, default: object, reason: str, raw: str) -> None:
    key = (name, raw)
    if key in _warned:
        return
    _warned.add(key)
    logger.warning("Invalid %s (%s); using default %r",
                   str(name)[:_MAX_LOGGED_NAME], reason, default)


def _raw(name: str) -> Optional[str]:
    value = os.environ.get(name)
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _check_bounds(name, value, default, minimum, maximum, exclusive_min, raw):
    if minimum is not None:
        if exclusive_min and value <= minimum:
            _warn(name, default, f"must be greater than {minimum}", raw)
            return default
        if not exclusive_min and value < minimum:
            _warn(name, default, f"must be at least {minimum}", raw)
            return default
    if maximum is not None and value > maximum:
        _warn(name, default, f"must be at most {maximum}", raw)
        return default
    return value


def env_int(name: str, default: int, *, minimum: Optional[int] = None,
            maximum: Optional[int] = None) -> int:
    """Parse an integer setting, falling back to `default` on anything invalid.

    `default` must be a real int. A bool default is rejected as a PROGRAMMING
    error rather than defaulted, because `isinstance(True, int)` is True in
    Python and a silently-accepted `True` would become the integer 1 — the kind
    of bug this module exists to prevent, not to commit.
    """
    if isinstance(default, bool) or not isinstance(default, int):
        raise TypeError(f"{name}: default must be an int, got {default!r}")

    raw = _raw(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except (TypeError, ValueError):
        _warn(name, default, "not an integer", raw)
        return default
    return _check_bounds(name, value, default, minimum, maximum, False, raw)


def env_float(name: str, default: float, *, minimum: Optional[float] = None,
              maximum: Optional[float] = None,
              exclusive_min: bool = False) -> float:
    """Parse a float setting, falling back to `default` on anything invalid.

    NaN and +/-Infinity are rejected explicitly. `float()` accepts all three
    happily, and each breaks a comparison in its own way: NaN makes every
    `<`/`>=` test False, so a NaN RAG_MIN_SCORE would silently accept every
    chunk and a NaN repeat-similarity would silently disable repeat detection.
    Infinity as a timeout is an unbounded wait.

    `exclusive_min` is for the four request timeouts, where the bound is
    genuinely "> 0" rather than ">= 0": `requests` rejects a non-positive
    timeout, so zero is not a smaller timeout, it is a broken one.
    """
    if isinstance(default, bool) or not isinstance(default, (int, float)):
        raise TypeError(f"{name}: default must be a number, got {default!r}")

    raw = _raw(name)
    if raw is None:
        return float(default)
    try:
        value = float(raw)
    except (TypeError, ValueError):
        _warn(name, float(default), "not a number", raw)
        return float(default)
    if not math.isfinite(value):
        _warn(name, float(default), "not finite", raw)
        return float(default)
    return float(_check_bounds(name, value, float(default), minimum, maximum,
                               exclusive_min, raw))
