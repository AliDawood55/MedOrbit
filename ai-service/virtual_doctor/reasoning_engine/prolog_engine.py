"""
Virtual Doctor — the only door to SWI-Prolog.

Nothing outside this module touches pyswip. That is not tidiness; it is what
makes two measured constraints enforceable in one place.

CONSTRAINT 1 — PySwip 0.3.3 IS NOT CONCURRENCY-SAFE
---------------------------------------------------
`Prolog._queryIsOpen` is a CLASS attribute (pyswip/prolog.py:125), not
thread-local, and `Prolog()` is effectively a process-wide singleton — a second
instance shares the same fact database. Measured during the Phase 0 audit:

    8 threads, no lock   -> 4 threads died with NestedQueryError
    8 threads, one lock  -> 1600 queries, 0 errors, 86ms total

So: one engine, one RLock, every operation serialized, every result fully
materialized before the lock is released. A raw `Prolog` object and a live
query generator are never returned to a caller — a generator held across an
`await` is precisely how the nested-query failure gets reintroduced.

CONSTRAINT 2 — GOALS ARE BUILT FROM TEMPLATES, NEVER FROM DATA
--------------------------------------------------------------
`query()` takes a static template plus keyword atoms, and every atom is
re-validated against the allow-list before substitution. There is no code path
that accepts a caller-assembled goal string, because string interpolation is
exactly what let `"chest_pain), halt, f(p,symptom,x"` execute during the audit.

FAILING SAFELY
--------------
If SWI-Prolog or pyswip is missing, `available()` is False and every entry
point returns an explicit absence. The engine never fabricates a result, and
in particular never invents an urgency — see ReasoningResult.unavailable.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional, Sequence

from . import vocabulary
from .result_models import Fact, StatedFact
from ..config import env_int

logger = logging.getLogger("medorbit-ai.virtual_doctor.reasoning_engine")

_RULES_DIR = Path(__file__).resolve().parent / "rules"

# Loaded in order, into the ONE governed engine — Phase 2 adds interview.pl
# alongside base.pl rather than standing up a second engine, so the lock, the
# session scope and the allow-list continue to cover everything.
# safety.pl, contradictions.pl and differential.pl are appended as their phases
# land.
RULE_FILES = ("base.pl", "interview.pl", "safety.pl", "contradictions.pl")

# A single query returning more than this means a rule is wrong, not that the
# consultation is unusually rich. Bounds memory on a runaway result set.
# minimum=1: passed as pyswip maxresult; 0 would return no solutions ever.
MAX_RESULTS = env_int("VD_SYMBOLIC_MAX_RESULTS", 500, minimum=1)

# Bounded execution, introduced in Phase 3 with the first genuinely
# combinational rules.
#
# INFERENCES, NOT WALL-CLOCK. call_with_time_limit/2 was the obvious choice and
# was rejected on evidence: it lives in library(time), which the container's
# swi-prolog-core package does not ship — verified, `source_sink
# 'library(time)' does not exist` on SWI 9.2.9 in the built image, while it
# works on the host's full 10.0.2 install. Using it would have meant upgrading
# the image to swi-prolog-nox (2 packages -> 19) purely for a timer.
#
# call_with_inference_limit/3 is a CORE built-in, verified present and
# identical on both 9.2.9 (container) and 10.0.2 (host). It also happens to be
# the better bound here: an inference count is deterministic and reproducible,
# where a wall-clock limit turns a loaded CI machine into a flaky test.
#
# Measured on both: an infinite loop is cut off in ~2ms, the cut-off surfaces
# as a normal solution rather than an exception, the engine stays healthy, and
# facts asserted beforehand remain retractable — which is what lets session
# cleanup still run in `finally`.
#
# 200k is ~4 orders of magnitude above a real turn (a full safety+interview
# turn is a few hundred inferences), so it can only ever catch a rule that has
# genuinely run away.
# minimum=1: interpolated into call_with_inference_limit/3, whose contract
# requires a positive integer budget.
INFERENCE_LIMIT = env_int("VD_SYMBOLIC_INFERENCE_LIMIT", 200000, minimum=1)

# Returned by call_with_inference_limit/3 when the goal was cut off.
INFERENCE_LIMIT_EXCEEDED = "inference_limit_exceeded"


class PrologBudgetExceeded(RuntimeError):
    """A goal exceeded the inference budget and was cut off."""

# Reentrant so a session scope can hold the lock across the queries made
# inside it — that is what makes cross-session fact interleaving impossible
# rather than merely cleaned up afterwards.
_LOCK = threading.RLock()

_prolog: Any = None
_state = {"loaded": False, "error": None, "init_ms": 0.0, "consulted": ()}


class PrologUnavailable(RuntimeError):
    """The symbolic engine could not be used for this request."""


def _load_engine() -> None:
    """Import pyswip, boot the engine and consult the rule files. Call locked.

    pyswip is imported HERE rather than at module scope so that a service
    running with VD_SYMBOLIC=0 pays none of it — measured at 69-81ms of import
    time plus the SWI runtime, for a feature it is not using.
    """
    global _prolog

    started = time.perf_counter()
    try:
        from pyswip import Prolog  # noqa: PLC0415 - deliberately lazy, see above
    except Exception as exc:  # noqa: BLE001 - missing SWI-Prolog surfaces here
        _state["error"] = f"{type(exc).__name__}: {exc}"
        _state["loaded"] = False
        logger.warning(
            "Symbolic reasoning unavailable — could not load pyswip/SWI-Prolog (%s). "
            "The Virtual Doctor continues on its existing deterministic path.",
            _state["error"],
        )
        return

    try:
        engine = Prolog()
        consulted = []
        for name in RULE_FILES:
            path = _RULES_DIR / name
            if not path.is_file():
                raise FileNotFoundError(f"rule file missing: {path}")
            # POSIX separators: SWI-Prolog treats a backslash as an escape in
            # a quoted path, so a Windows path must not be passed verbatim.
            engine.consult(path.as_posix())
            consulted.append(name)
    except Exception as exc:  # noqa: BLE001
        _prolog = None
        _state["error"] = f"{type(exc).__name__}: {exc}"
        _state["loaded"] = False
        logger.warning("Symbolic reasoning unavailable — rule load failed (%s)", _state["error"])
        return

    _prolog = engine
    _state["loaded"] = True
    _state["error"] = None
    _state["consulted"] = tuple(consulted)
    _state["init_ms"] = (time.perf_counter() - started) * 1000
    logger.info(
        "Symbolic reasoning engine ready in %.1fms (rules: %s)",
        _state["init_ms"], ", ".join(consulted),
    )


def _ensure_engine() -> Any:
    """Return the engine, booting it once. Call locked. Raises when unusable."""
    if _prolog is None and _state["error"] is None:
        _load_engine()
    if _prolog is None:
        raise PrologUnavailable(_state["error"] or "engine not initialised")
    return _prolog


def available() -> bool:
    """Whether symbolic reasoning can run. Boots the engine on first call."""
    with _LOCK:
        try:
            _ensure_engine()
            return True
        except PrologUnavailable:
            return False


def status() -> Dict[str, Any]:
    """Health/audit view. Never raises, so it is safe to expose over HTTP."""
    with _LOCK:
        try:
            _ensure_engine()
        except PrologUnavailable:
            pass
        return {
            "enabled": enabled(),
            "interview_mode": interview_mode(),
            "safety_mode": safety_mode(),
            "inference_limit": INFERENCE_LIMIT,
            "loaded": bool(_state["loaded"]),
            "load_error": _state["error"],
            "rule_files": list(_state["consulted"]),
            "init_ms": round(float(_state["init_ms"]), 2),
            "max_results": MAX_RESULTS,
            "prolog_version": _version_string(),
        }


def _version_string() -> Optional[str]:
    if not _state["loaded"]:
        return None
    try:
        rows = _raw_query("current_prolog_flag(version, V)")
    except Exception:  # noqa: BLE001 - status must never raise
        return None
    if not rows:
        return None
    raw = rows[0].get("V")
    if not isinstance(raw, int):
        return str(raw)
    return f"{raw // 10000}.{(raw // 100) % 100}.{raw % 100}"


def enabled() -> bool:
    """The VD_SYMBOLIC master switch. Default OFF.

    Read per call rather than cached at import so tests (and an operator with
    a restart) can flip it without reloading the module.
    """
    return os.environ.get("VD_SYMBOLIC", "0").strip().lower() in ("1", "true", "yes", "on")


# Phase 2 rollout, gated UNDER the master switch. Naming follows the project's
# existing VD_* / string-mode convention (VD_PLANNER=llm|static), rather than a
# second boolean, because three states are genuinely needed:
#
#   off      symbolic interview reasoning does not run at all
#   shadow   it runs, its choice is compared with the existing planner's and
#            the divergence is logged — the existing planner still controls
#            everything the patient sees                        (the default)
#   active   the symbolic topic controls WHAT is asked; the LLM only words it
#
# Default "shadow" so that turning on VD_SYMBOLIC alone can never change a
# consultation; reaching `active` takes a second, deliberate setting.
INTERVIEW_MODES = ("off", "shadow", "active")
INTERVIEW_MODE_DEFAULT = "shadow"


def interview_mode() -> str:
    """Resolved Phase 2 mode. Always "off" while VD_SYMBOLIC is off."""
    if not enabled():
        return "off"
    mode = os.environ.get("VD_SYMBOLIC_INTERVIEW", INTERVIEW_MODE_DEFAULT).strip().lower()
    if mode not in INTERVIEW_MODES:
        logger.warning(
            "Unknown VD_SYMBOLIC_INTERVIEW=%r — falling back to %r", mode, INTERVIEW_MODE_DEFAULT
        )
        return INTERVIEW_MODE_DEFAULT
    return mode


def interview_active() -> bool:
    """True only when the symbolic topic is allowed to control question choice."""
    return interview_mode() == "active"


# Phase 3 rollout, independent of the interview flag and gated under the same
# master switch. Same three states, same safe default, same "garbage falls back
# to shadow, never active" rule.
#
#   off      symbolic safety reasoning does not run
#   shadow   it runs and its verdict is logged and compared; patient-facing
#            urgency is entirely unaffected                     (the default)
#   active   its verdict joins the urgency merge, where it can only ESCALATE
SAFETY_MODES = ("off", "shadow", "active")
SAFETY_MODE_DEFAULT = "shadow"


def safety_mode() -> str:
    """Resolved Phase 3 mode. Always "off" while VD_SYMBOLIC is off."""
    if not enabled():
        return "off"
    mode = os.environ.get("VD_SYMBOLIC_SAFETY", SAFETY_MODE_DEFAULT).strip().lower()
    if mode not in SAFETY_MODES:
        logger.warning(
            "Unknown VD_SYMBOLIC_SAFETY=%r — falling back to %r", mode, SAFETY_MODE_DEFAULT
        )
        return SAFETY_MODE_DEFAULT
    return mode


def safety_active() -> bool:
    """True only when a symbolic verdict may escalate patient-facing urgency."""
    return safety_mode() == "active"


# Phase 4 rollout, independent of the interview and safety flags. Same three
# states, same safe default, same "invalid falls back to shadow".
#
#   off      symbolic contradiction reasoning does not run
#   shadow   it runs and is compared with the Python correction layer, which
#            stays authoritative for everything patient-facing   (the default)
#   active   its decision may VALIDATE a normalised correction candidate.
#            Even then Prolog never mutates anything — Python still applies the
#            profile update, the confirmation state, the correction_history
#            append, the persistence and the reply.
CORRECTION_MODES = ("off", "shadow", "active")
CORRECTION_MODE_DEFAULT = "shadow"


def correction_mode() -> str:
    """Resolved Phase 4 mode. Always "off" while VD_SYMBOLIC is off."""
    if not enabled():
        return "off"
    mode = os.environ.get("VD_SYMBOLIC_CORRECTIONS", CORRECTION_MODE_DEFAULT).strip().lower()
    if mode not in CORRECTION_MODES:
        logger.warning("Unknown VD_SYMBOLIC_CORRECTIONS=%r — falling back to %r",
                       mode, CORRECTION_MODE_DEFAULT)
        return CORRECTION_MODE_DEFAULT
    return mode


def correction_active() -> bool:
    """True only when a symbolic decision may validate a correction candidate."""
    return correction_mode() == "active"


# ---------------------------------------------------------------------------
# Goal construction — the only place a goal string is assembled
# ---------------------------------------------------------------------------

def _bind(template: str, atoms: Dict[str, Any]) -> str:
    """Substitute validated atoms into a static template.

    `template` is always a literal in this package's own source. `atoms` is the
    data path, so every value is re-validated here even though fact_builder
    already validated it: this is the last instruction before the string
    becomes executable, and the check is a regex over a few short atoms.
    """
    checked: Dict[str, Any] = {}
    for key, value in atoms.items():
        if isinstance(value, bool) or not isinstance(value, (str, int)):
            raise vocabulary.OutOfVocabulary(f"{key}: unsupported goal argument: {value!r}")
        checked[key] = value if isinstance(value, int) else vocabulary.require_atom(
            value, field=key
        )
    return template.format(**checked)


def _render_fact(fact: Fact) -> str:
    """A Fact as a vd_fact/4 term.

    Every argument is either an int or an atom that Fact.__post_init__ already
    matched against the allow-list, so there is nothing here left to escape.
    """
    return f"vd_fact({fact.session}, {fact.predicate}, {fact.subject}, {fact.value})"


def _render_stated(fact: StatedFact) -> str:
    """A StatedFact as a vd_stated/4 term.

    Every argument is an int or an atom StatedFact.__post_init__ already matched
    against the allow-list — including `value`, which for free text is an opaque
    token rather than the text itself.
    """
    return f"vd_stated({fact.session}, {fact.slot}, {fact.value}, {fact.turn})"


def _raw_query(goal: str, *, bounded: bool = True) -> List[Dict[str, Any]]:
    """Run a fully-formed goal and materialize every solution. Call locked.

    The materialization is the point: pyswip's cursor must be exhausted before
    the lock is released or the next query raises NestedQueryError.

    `bounded` wraps the goal in an inference budget (see INFERENCE_LIMIT). It is
    off only for the engine's own housekeeping goals — retractall, fact counting
    — which are not rule-driven and must run even when a rule has just blown its
    budget, because that is exactly when cleanup matters most.
    """
    engine = _ensure_engine()
    executed = (
        f"call_with_inference_limit(({goal}), {INFERENCE_LIMIT}, _VdBudget)"
        if bounded else goal
    )
    rows: List[Dict[str, Any]] = []
    for row in engine.query(executed, maxresult=MAX_RESULTS):
        row = dict(row)
        if row.pop("_VdBudget", None) == INFERENCE_LIMIT_EXCEEDED:
            # Cut off mid-goal. Whatever was collected is a partial answer to a
            # rule that misbehaved, so it is discarded rather than returned —
            # a truncated safety trace is worse than an admitted failure.
            raise PrologBudgetExceeded(
                f"goal exceeded {INFERENCE_LIMIT} inferences: {goal[:80]}"
            )
        rows.append(row)
    return rows


def query(template: str, /, **atoms: Any) -> List[Dict[str, Any]]:
    """Run a template goal with validated atom bindings, fully materialized.

    Returns plain dicts of plain values — no pyswip objects, no generator, so
    nothing a caller holds can outlive the lock.
    """
    with _LOCK:
        return _raw_query(_bind(template, atoms))


# ---------------------------------------------------------------------------
# Session scope
# ---------------------------------------------------------------------------

class SessionHandle:
    """Query interface bound to one session's facts.

    Holds a validated session atom and nothing else — deliberately not the
    engine, so there is no object a caller could use to escape the lock.
    """

    __slots__ = ("_key",)

    def __init__(self, key: str) -> None:
        self._key = key

    @property
    def key(self) -> str:
        return self._key

    def query(self, template: str, /, **atoms: Any) -> List[Dict[str, Any]]:
        """Run a template goal with `{s}` pre-bound to this session."""
        return _raw_query(_bind(template, {"s": self._key, **atoms}))


def _retract_session(key: str) -> None:
    """Remove every fact for one session. Call locked. Never raises.

    Unbounded deliberately: cleanup must succeed on the path where a rule just
    exhausted its inference budget, which is precisely when leaving facts behind
    would leak one consultation's state into the next.
    """
    for template in ("retractall(vd_fact({s}, _, _, _))",
                     "retractall(vd_stated({s}, _, _, _))"):
        try:
            _raw_query(_bind(template, {"s": key}), bounded=False)
        except Exception as exc:  # noqa: BLE001 - cleanup must not mask the real error
            logger.error("Failed to retract symbolic facts for %s (%s)", key, exc)


@contextmanager
def session_scope(session_key: str, facts: Sequence[Fact]) -> Iterator[SessionHandle]:
    """Assert one session's facts, expose a query handle, always clean up.

    The lock is held for the WHOLE scope rather than per operation. Two
    consultations therefore cannot have facts in the store at the same time,
    which makes cross-session leakage structurally impossible instead of
    merely tidied up afterwards. A turn holds the lock for well under a
    millisecond, so this costs nothing measurable.

    Cleanup runs in `finally`, so an exception raised by a query — or by the
    caller inside the `with` body — still leaves an empty store.
    """
    key = vocabulary.require_atom(session_key, field="session_key")
    stated = tuple(getattr(facts, "stated", ()) or ())
    plain = tuple(getattr(facts, "facts", facts) or ())
    with _LOCK:
        _ensure_engine()
        try:
            for fact in plain:
                if fact.session != key:
                    raise vocabulary.OutOfVocabulary(
                        f"fact belongs to session {fact.session!r}, not {key!r}"
                    )
                _raw_query(f"assertz({_render_fact(fact)})")
            for provenance in stated:
                if provenance.session != key:
                    raise vocabulary.OutOfVocabulary(
                        f"statement belongs to session {provenance.session!r}, not {key!r}"
                    )
                _raw_query(f"assertz({_render_stated(provenance)})")
            yield SessionHandle(key)
        finally:
            _retract_session(key)


def reset_for_tests() -> None:
    """Drop every fact and forget any recorded load failure.

    Exists so a test that simulates an unavailable engine does not poison the
    rest of the suite through module-global state.
    """
    global _prolog
    with _LOCK:
        if _prolog is not None:
            for predicate in ("vd_fact(_, _, _, _)", "vd_stated(_, _, _, _)"):
                try:
                    _raw_query(f"retractall({predicate})", bounded=False)
                except Exception:  # noqa: BLE001
                    pass
        else:
            _state["error"] = None
            _state["loaded"] = False
            _state["consulted"] = ()
            _state["init_ms"] = 0.0


def _fact_count_all() -> int:
    """Total facts across all sessions, both shapes. Test-only leakage probe."""
    total = 0
    with _LOCK:
        for predicate in ("vd_fact(_, _, _, _)", "vd_stated(_, _, _, _)"):
            rows = _raw_query(f"aggregate_all(count, {predicate}, N)", bounded=False)
            total += int(rows[0]["N"]) if rows else 0
    return total
