"""
Phase 7B — safe numeric configuration parsing.

THE REGRESSION THIS FILE EXISTS FOR
-----------------------------------
Before Phase 7B, every numeric setting was read as a bare `int(os.environ...)`
at module import. A single typo —

    VD_PLANNER_TIMEOUT=abc

— did not misconfigure the planner; it raised ValueError while `planner` was
being imported, which propagated through `interview_engine` and took the
service down at startup. TestImportSafetyInSubprocess is the test that matters
here: it starts a REAL interpreter with malformed values set and asserts the
process both survives and loads the documented defaults. Unit-testing the
helper alone would not have caught the original bug, because the original bug
was about import time, not about parsing.

WHAT MUST NOT HAVE CHANGED
--------------------------
Everything, for every valid or unset configuration. TestValidConfigUnchanged
pins all nineteen settings at their documented defaults, and each hardened
module is checked with a valid override too. Phase 7B may only change what
happens to a MALFORMED value.

FAIL-SAFE DIRECTION
-------------------
The fallback is always the existing code default, never a permissive one, so a
malformed value cannot buy a bigger inference budget, a longer timeout, a
disabled cache-free path, or an experimental mode. TestMalformedCannotWeaken
asserts that directly.
"""

import os
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import config, memory, planner, response, understanding
from virtual_doctor.config import env_float, env_int
from virtual_doctor.reasoning_engine import prolog_engine, vocabulary

AI_SERVICE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

VAR = "VD_TEST_PHASE7B"


def setUpModule():
    config.reset_warning_state()


class _EnvCase(unittest.TestCase):
    def setUp(self):
        config.reset_warning_state()
        os.environ.pop(VAR, None)

    def tearDown(self):
        os.environ.pop(VAR, None)



class TestEnvInt(_EnvCase):
    def test_unset_returns_the_default(self):
        self.assertEqual(7, env_int(VAR, 7))

    def test_valid_value_is_parsed(self):
        with patch.dict(os.environ, {VAR: "42"}):
            self.assertEqual(42, env_int(VAR, 7))

    def test_malformed_returns_the_default(self):
        for bad in ("abc", "1.5", "0x10", "1,000", "None", "true", "٣abc", "--5"):
            with patch.dict(os.environ, {VAR: bad}):
                self.assertEqual(7, env_int(VAR, 7), bad)

    def test_surrounding_whitespace_is_tolerated(self):
        for good in ("  42", "42  ", "\t42\n"):
            with patch.dict(os.environ, {VAR: good}):
                self.assertEqual(42, env_int(VAR, 7), repr(good))

    def test_empty_or_whitespace_only_is_treated_as_unset(self):
        """An operator clearing a variable is not a malformed value, so this
        takes the default WITHOUT warning."""
        for blank in ("", "   ", "\t"):
            with patch.dict(os.environ, {VAR: blank}):
                with self.assertNoLogs("medorbit-ai.virtual_doctor.config", "WARNING"):
                    self.assertEqual(7, env_int(VAR, 7))

    def test_negative_is_allowed_when_no_minimum_is_declared(self):
        with patch.dict(os.environ, {VAR: "-5"}):
            self.assertEqual(-5, env_int(VAR, 7))

    def test_minimum_violation_returns_the_default(self):
        with patch.dict(os.environ, {VAR: "0"}):
            self.assertEqual(7, env_int(VAR, 7, minimum=1))
        with patch.dict(os.environ, {VAR: "-1"}):
            self.assertEqual(7, env_int(VAR, 7, minimum=0))

    def test_minimum_boundary_is_inclusive(self):
        with patch.dict(os.environ, {VAR: "1"}):
            self.assertEqual(1, env_int(VAR, 7, minimum=1))

    def test_maximum_violation_returns_the_default(self):
        with patch.dict(os.environ, {VAR: "11"}):
            self.assertEqual(7, env_int(VAR, 7, maximum=10))

    def test_maximum_boundary_is_inclusive(self):
        with patch.dict(os.environ, {VAR: "10"}):
            self.assertEqual(10, env_int(VAR, 7, maximum=10))

    def test_a_bool_default_is_a_programming_error_not_a_config_error(self):
        """isinstance(True, int) is True in Python. Silently accepting a bool
        default would turn it into 1 — exactly the class of bug this module
        exists to prevent."""
        with self.assertRaises(TypeError):
            env_int(VAR, True)
        with self.assertRaises(TypeError):
            env_int(VAR, "7")

    def test_a_boolean_looking_value_never_becomes_an_int(self):
        for bad in ("true", "True", "False", "yes"):
            with patch.dict(os.environ, {VAR: bad}):
                self.assertEqual(7, env_int(VAR, 7), bad)



class TestEnvFloat(_EnvCase):
    def test_unset_returns_the_default(self):
        self.assertEqual(2.5, env_float(VAR, 2.5))

    def test_valid_values_are_parsed(self):
        for good, want in (("1.5", 1.5), ("3", 3.0), ("-0.25", -0.25), ("1e2", 100.0)):
            with patch.dict(os.environ, {VAR: good}):
                self.assertEqual(want, env_float(VAR, 2.5), good)

    def test_malformed_returns_the_default(self):
        for bad in ("abc", "", "1,5", "None", "1.2.3", "true"):
            with patch.dict(os.environ, {VAR: bad}):
                self.assertEqual(2.5, env_float(VAR, 2.5), bad)

    def test_nan_is_rejected(self):
        """float('nan') parses fine and makes EVERY comparison False — a NaN
        RAG_MIN_SCORE would silently accept every chunk."""
        for bad in ("nan", "NaN", "-nan"):
            with patch.dict(os.environ, {VAR: bad}):
                self.assertEqual(2.5, env_float(VAR, 2.5), bad)

    def test_positive_infinity_is_rejected(self):
        for bad in ("inf", "Infinity", "+inf", "1e400"):
            with patch.dict(os.environ, {VAR: bad}):
                self.assertEqual(2.5, env_float(VAR, 2.5), bad)

    def test_negative_infinity_is_rejected(self):
        for bad in ("-inf", "-Infinity", "-1e400"):
            with patch.dict(os.environ, {VAR: bad}):
                self.assertEqual(2.5, env_float(VAR, 2.5), bad)

    def test_lower_bound_violation_returns_the_default(self):
        with patch.dict(os.environ, {VAR: "-0.5"}):
            self.assertEqual(0.6, env_float(VAR, 0.6, minimum=0.0, maximum=1.0))

    def test_upper_bound_violation_returns_the_default(self):
        with patch.dict(os.environ, {VAR: "1.5"}):
            self.assertEqual(0.6, env_float(VAR, 0.6, minimum=0.0, maximum=1.0))

    def test_bounds_are_inclusive(self):
        for value in ("0", "1", "0.5"):
            with patch.dict(os.environ, {VAR: value}):
                self.assertEqual(float(value),
                                 env_float(VAR, 0.6, minimum=0.0, maximum=1.0))

    def test_exclusive_minimum_rejects_the_bound_itself(self):
        """Timeouts are '> 0', not '>= 0': requests rejects a non-positive
        timeout, so zero is not a smaller timeout, it is a broken one."""
        with patch.dict(os.environ, {VAR: "0"}):
            self.assertEqual(20.0, env_float(VAR, 20.0, minimum=0.0, exclusive_min=True))
        with patch.dict(os.environ, {VAR: "-1"}):
            self.assertEqual(20.0, env_float(VAR, 20.0, minimum=0.0, exclusive_min=True))
        with patch.dict(os.environ, {VAR: "0.001"}):
            self.assertEqual(0.001, env_float(VAR, 20.0, minimum=0.0, exclusive_min=True))

    def test_a_bool_default_is_rejected(self):
        with self.assertRaises(TypeError):
            env_float(VAR, True)



class TestWarningBehaviour(_EnvCase):
    def test_a_warning_names_the_variable_and_the_default(self):
        with patch.dict(os.environ, {VAR: "abc"}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                env_int(VAR, 7)
        joined = "\n".join(logs.output)
        self.assertIn(VAR, joined)
        self.assertIn("7", joined)
        self.assertIn("Invalid", joined)

    def test_the_warning_is_emitted_once_per_offending_value(self):
        with patch.dict(os.environ, {VAR: "abc"}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                for _ in range(10):
                    env_int(VAR, 7)
        self.assertEqual(1, len(logs.output))

    def test_a_different_bad_value_warns_again(self):
        with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
            with patch.dict(os.environ, {VAR: "abc"}):
                env_int(VAR, 7)
            with patch.dict(os.environ, {VAR: "xyz"}):
                env_int(VAR, 7)
        self.assertEqual(2, len(logs.output))

    def test_an_oversized_hostile_value_is_never_logged(self):
        hostile = "A" * 10000
        with patch.dict(os.environ, {VAR: hostile}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                env_int(VAR, 7)
        joined = "\n".join(logs.output)
        self.assertNotIn(hostile, joined)
        self.assertNotIn("AAAA", joined)
        self.assertLess(len(joined), 300)

    def test_a_bounds_warning_says_which_bound(self):
        with patch.dict(os.environ, {VAR: "0"}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                env_int(VAR, 7, minimum=1)
        self.assertIn("at least 1", "\n".join(logs.output))

    def test_a_valid_value_logs_nothing(self):
        with patch.dict(os.environ, {VAR: "42"}):
            with self.assertNoLogs("medorbit-ai.virtual_doctor.config", "WARNING"):
                env_int(VAR, 7)



class TestValidConfigUnchanged(unittest.TestCase):
    """Every documented default, pinned. These are the values the service ran
    with before Phase 7B, and they must be byte-identical after it."""

    def test_memory_defaults(self):
        self.assertEqual(12, memory.HISTORY_LIMIT)
        self.assertEqual(600, memory.MAX_MESSAGE_CHARS)
        self.assertEqual(50, memory.FULL_HISTORY_LIMIT)

    def test_planner_defaults(self):
        self.assertEqual(25.0, planner.PLANNER_TIMEOUT)
        self.assertEqual(6, planner.MAX_INTERVIEW_TURNS)
        self.assertEqual(0.6, planner._REPEAT_SIMILARITY)
        self.assertEqual(3, planner.COMPLETENESS_MIN_FINDINGS)
        self.assertEqual(2, planner.COMPLETENESS_MIN_TURNS)

    def test_retrieval_defaults(self):
        from virtual_doctor import retrieval
        self.assertEqual(3, retrieval.RAG_TOP_K)
        self.assertEqual(0.60, retrieval.RAG_MIN_SCORE)
        self.assertEqual(1200, retrieval.RAG_MAX_CHUNK_CHARS)
        self.assertEqual(20.0, retrieval.RAG_EMBED_TIMEOUT)
        self.assertEqual(256, retrieval.RESULT_CACHE_SIZE)
        self.assertEqual(900.0, retrieval.RESULT_CACHE_TTL)
        self.assertEqual(128, retrieval.EMBED_CACHE_SIZE)

    def test_understanding_and_response_defaults(self):
        self.assertEqual(20.0, understanding.TIMEOUT)
        self.assertEqual(20.0, response.TIMEOUT)

    def test_symbolic_defaults(self):
        self.assertEqual(500, prolog_engine.MAX_RESULTS)
        self.assertEqual(200000, prolog_engine.INFERENCE_LIMIT)

    def test_types_are_what_the_call_sites_expect(self):
        for value in (memory.HISTORY_LIMIT, memory.MAX_MESSAGE_CHARS,
                      memory.FULL_HISTORY_LIMIT, planner.MAX_INTERVIEW_TURNS,
                      prolog_engine.MAX_RESULTS, prolog_engine.INFERENCE_LIMIT):
            self.assertIsInstance(value, int)
            self.assertNotIsInstance(value, bool)
        for value in (planner.PLANNER_TIMEOUT, understanding.TIMEOUT, response.TIMEOUT):
            self.assertIsInstance(value, float)


class TestValidOverridesStillApply(_EnvCase):
    """A valid override must reach the module exactly as before. Checked
    through the helper with each hardened setting's real bounds."""

    def test_symbolic_inference_limit_override(self):
        with patch.dict(os.environ, {"VD_SYMBOLIC_INFERENCE_LIMIT": "50000"}):
            self.assertEqual(50000, env_int("VD_SYMBOLIC_INFERENCE_LIMIT", 200000, minimum=1))

    def test_planner_timeout_override(self):
        with patch.dict(os.environ, {"VD_PLANNER_TIMEOUT": "7.5"}):
            self.assertEqual(7.5, env_float("VD_PLANNER_TIMEOUT", 25.0,
                                            minimum=0.0, exclusive_min=True))

    def test_understanding_timeout_override(self):
        with patch.dict(os.environ, {"VD_UNDERSTANDING_TIMEOUT": "45"}):
            self.assertEqual(45.0, env_float("VD_UNDERSTANDING_TIMEOUT", 20.0,
                                             minimum=0.0, exclusive_min=True))

    def test_response_timeout_override(self):
        with patch.dict(os.environ, {"VD_RESPONSE_TIMEOUT": "12.25"}):
            self.assertEqual(12.25, env_float("VD_RESPONSE_TIMEOUT", 20.0,
                                              minimum=0.0, exclusive_min=True))

    def test_retrieval_overrides(self):
        with patch.dict(os.environ, {"RAG_TOP_K": "5", "RAG_MIN_SCORE": "0.75",
                                     "VD_RAG_CACHE_SIZE": "0"}):
            self.assertEqual(5, env_int("RAG_TOP_K", 3, minimum=1))
            self.assertEqual(0.75, env_float("RAG_MIN_SCORE", 0.60,
                                             minimum=-1.0, maximum=1.0))
            self.assertEqual(0, env_int("VD_RAG_CACHE_SIZE", 256, minimum=0))

    def test_memory_overrides(self):
        with patch.dict(os.environ, {"VD_HISTORY_LIMIT": "20",
                                     "VD_FULL_HISTORY_LIMIT": "100"}):
            self.assertEqual(20, env_int("VD_HISTORY_LIMIT", 12, minimum=1))
            self.assertEqual(100, env_int("VD_FULL_HISTORY_LIMIT", 50, minimum=1))



class TestMalformedCannotWeaken(_EnvCase):
    def test_a_malformed_inference_limit_does_not_grant_a_bigger_budget(self):
        for bad in ("abc", "999999999999999999999999x", "-1", "0", "inf"):
            with patch.dict(os.environ, {"VD_SYMBOLIC_INFERENCE_LIMIT": bad}):
                self.assertEqual(200000,
                                 env_int("VD_SYMBOLIC_INFERENCE_LIMIT", 200000, minimum=1), bad)

    def test_a_malformed_timeout_never_becomes_unbounded(self):
        for bad in ("inf", "Infinity", "1e400", "nan", "abc"):
            with patch.dict(os.environ, {"VD_PLANNER_TIMEOUT": bad}):
                self.assertEqual(25.0, env_float("VD_PLANNER_TIMEOUT", 25.0,
                                                 minimum=0.0, exclusive_min=True), bad)

    def test_a_malformed_repeat_similarity_does_not_disable_repeat_detection(self):
        """A NaN or out-of-range threshold would make `overlap >= threshold`
        constant — at the permissive end, silently switching the check off."""
        for bad in ("nan", "2", "-1", "abc"):
            with patch.dict(os.environ, {"VD_PLANNER_REPEAT_SIMILARITY": bad}):
                self.assertEqual(0.6, env_float("VD_PLANNER_REPEAT_SIMILARITY", 0.6,
                                                minimum=0.0, maximum=1.0), bad)

    def test_a_malformed_min_score_does_not_accept_every_chunk(self):
        for bad in ("nan", "-2", "abc"):
            with patch.dict(os.environ, {"RAG_MIN_SCORE": bad}):
                self.assertEqual(0.60, env_float("RAG_MIN_SCORE", 0.60,
                                                 minimum=-1.0, maximum=1.0), bad)

    def test_a_negative_char_limit_cannot_truncate_from_the_wrong_end(self):
        """`text[:-5]` does not fail — it keeps everything BUT the last five
        characters. Silent data corruption, which is why these have a floor."""
        for bad in ("-5", "0", "abc"):
            with patch.dict(os.environ, {"VD_HISTORY_MAX_CHARS": bad}):
                self.assertEqual(600, env_int("VD_HISTORY_MAX_CHARS", 600, minimum=1), bad)


class TestMalformedNumericsCannotActivateExperimentalModes(_EnvCase):
    """Numeric hardening must not have touched the mode flags, whose fail-safe
    direction is 'never active'."""

    def test_mode_flags_still_default_safely_with_malformed_numerics_present(self):
        with patch.dict(os.environ, {
            "VD_PLANNER_TIMEOUT": "abc",
            "VD_SYMBOLIC_INFERENCE_LIMIT": "abc",
            "VD_UNDERSTANDING_TIMEOUT": "nan",
        }):
            os.environ.pop("VD_STRUCTURED_UNDERSTANDING", None)
            os.environ.pop("VD_BOUNDED_RESPONSE", None)
            self.assertEqual("off", understanding.mode())
            self.assertEqual("off", response.mode())
            self.assertFalse(prolog_engine.enabled())

    def test_an_invalid_mode_value_is_still_never_active(self):
        for bad in ("active!", "1", "yes", ""):
            with patch.dict(os.environ, {"VD_STRUCTURED_UNDERSTANDING": bad,
                                         "VD_BOUNDED_RESPONSE": bad}):
                self.assertFalse(understanding.active(), bad)
                self.assertFalse(response.active(), bad)



MALFORMED_ENV = {
    "VD_PLANNER_TIMEOUT": "abc",
    "VD_PLANNER_MAX_TURNS": "not-a-number",
    "VD_PLANNER_REPEAT_SIMILARITY": "nan",
    "VD_PLANNER_COMPLETENESS_MIN_FINDINGS": "3.7",
    "VD_PLANNER_COMPLETENESS_MIN_TURNS": "-",
    "VD_SYMBOLIC_INFERENCE_LIMIT": "inf",
    "VD_SYMBOLIC_MAX_RESULTS": "0",
    "VD_UNDERSTANDING_TIMEOUT": "abc",
    "VD_RESPONSE_TIMEOUT": "-1",
    "VD_HISTORY_LIMIT": "x",
    "VD_HISTORY_MAX_CHARS": "-5",
    "VD_FULL_HISTORY_LIMIT": "1e",
    "VD_RAG_CACHE_SIZE": "abc",
    "VD_RAG_CACHE_TTL": "-inf",
    "RAG_TOP_K": "0",
    "RAG_MIN_SCORE": "2.5",
    "RAG_MAX_CHUNK_CHARS": "-1",
    "RAG_EMBED_TIMEOUT": "0",
    "RAG_EMBED_CACHE_SIZE": "A" * 5000,
}

_PROBE = """
import json, sys
from virtual_doctor import memory, planner, response, retrieval, understanding
from virtual_doctor.reasoning_engine import prolog_engine
print("RESULT" + json.dumps({
    "HISTORY_LIMIT": memory.HISTORY_LIMIT,
    "MAX_MESSAGE_CHARS": memory.MAX_MESSAGE_CHARS,
    "FULL_HISTORY_LIMIT": memory.FULL_HISTORY_LIMIT,
    "PLANNER_TIMEOUT": planner.PLANNER_TIMEOUT,
    "MAX_INTERVIEW_TURNS": planner.MAX_INTERVIEW_TURNS,
    "REPEAT_SIMILARITY": planner._REPEAT_SIMILARITY,
    "COMPLETENESS_MIN_FINDINGS": planner.COMPLETENESS_MIN_FINDINGS,
    "COMPLETENESS_MIN_TURNS": planner.COMPLETENESS_MIN_TURNS,
    "INFERENCE_LIMIT": prolog_engine.INFERENCE_LIMIT,
    "MAX_RESULTS": prolog_engine.MAX_RESULTS,
    "UNDERSTANDING_TIMEOUT": understanding.TIMEOUT,
    "RESPONSE_TIMEOUT": response.TIMEOUT,
    "RAG_TOP_K": retrieval.RAG_TOP_K,
    "RAG_MIN_SCORE": retrieval.RAG_MIN_SCORE,
    "RAG_MAX_CHUNK_CHARS": retrieval.RAG_MAX_CHUNK_CHARS,
    "RAG_EMBED_TIMEOUT": retrieval.RAG_EMBED_TIMEOUT,
    "RESULT_CACHE_SIZE": retrieval.RESULT_CACHE_SIZE,
    "RESULT_CACHE_TTL": retrieval.RESULT_CACHE_TTL,
    "EMBED_CACHE_SIZE": retrieval.EMBED_CACHE_SIZE,
}))
"""

EXPECTED_DEFAULTS = {
    "HISTORY_LIMIT": 12, "MAX_MESSAGE_CHARS": 600, "FULL_HISTORY_LIMIT": 50,
    "PLANNER_TIMEOUT": 25.0, "MAX_INTERVIEW_TURNS": 6, "REPEAT_SIMILARITY": 0.6,
    "COMPLETENESS_MIN_FINDINGS": 3, "COMPLETENESS_MIN_TURNS": 2,
    "INFERENCE_LIMIT": 200000, "MAX_RESULTS": 500,
    "UNDERSTANDING_TIMEOUT": 20.0, "RESPONSE_TIMEOUT": 20.0,
    "RAG_TOP_K": 3, "RAG_MIN_SCORE": 0.60, "RAG_MAX_CHUNK_CHARS": 1200,
    "RAG_EMBED_TIMEOUT": 20.0, "RESULT_CACHE_SIZE": 256,
    "RESULT_CACHE_TTL": 900.0, "EMBED_CACHE_SIZE": 128,
}


def _run_probe(extra_env):
    env = dict(os.environ)
    env.update(extra_env)
    env["PYTHONIOENCODING"] = "utf-8"
    return subprocess.run([sys.executable, "-c", _PROBE], cwd=AI_SERVICE, env=env,
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=180)


def _parse(proc):
    import json
    for line in proc.stdout.splitlines():
        if line.startswith("RESULT"):
            return json.loads(line[len("RESULT"):])
    raise AssertionError(f"probe produced no result.\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")


class TestImportSafetyInSubprocess(unittest.TestCase):
    """A REAL interpreter, real imports, real malformed environment.

    This is the test the phase exists for: unit-testing the helper would not
    have caught the original bug, because the original bug was that import
    itself raised.
    """

    def test_every_module_imports_with_a_fully_malformed_environment(self):
        proc = _run_probe(MALFORMED_ENV)
        self.assertEqual(0, proc.returncode,
                         f"import failed.\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")

    def test_malformed_environment_yields_exactly_the_documented_defaults(self):
        values = _parse(_run_probe(MALFORMED_ENV))
        self.assertEqual(EXPECTED_DEFAULTS, values)

    def test_a_clean_environment_yields_the_same_defaults(self):
        clean = {k: "" for k in MALFORMED_ENV}
        values = _parse(_run_probe(clean))
        self.assertEqual(EXPECTED_DEFAULTS, values)

    def test_valid_overrides_reach_the_modules_through_a_real_import(self):
        values = _parse(_run_probe({
            "VD_PLANNER_TIMEOUT": "9.5",
            "VD_PLANNER_MAX_TURNS": "4",
            "VD_SYMBOLIC_INFERENCE_LIMIT": "12345",
            "RAG_TOP_K": "7",
        }))
        self.assertEqual(9.5, values["PLANNER_TIMEOUT"])
        self.assertEqual(4, values["MAX_INTERVIEW_TURNS"])
        self.assertEqual(12345, values["INFERENCE_LIMIT"])
        self.assertEqual(7, values["RAG_TOP_K"])

    def test_the_hostile_oversized_value_is_not_echoed_to_stderr(self):
        proc = _run_probe(MALFORMED_ENV)
        self.assertNotIn("A" * 100, proc.stderr)

    def test_a_malformed_environment_warns(self):
        proc = _run_probe(MALFORMED_ENV)
        self.assertIn("Invalid", proc.stderr)



class TestCanonicalTopicRemoved(unittest.TestCase):
    def test_the_alias_no_longer_exists(self):
        self.assertFalse(hasattr(vocabulary, "canonical_topic"))

    def test_no_source_file_references_it(self):
        import glob
        roots = ("virtual_doctor/**/*.py", "chatbot/**/*.py", "tests/*.py",
                 "benchmarks/*.py", "virtual_doctor/**/*.pl")
        offenders = []
        for pattern in roots:
            for path in glob.glob(os.path.join(AI_SERVICE, pattern), recursive=True):
                if os.path.basename(path) == os.path.basename(__file__):
                    continue
                with open(path, encoding="utf-8", errors="replace") as handle:
                    if "canonical_topic" in handle.read():
                        offenders.append(os.path.relpath(path, AI_SERVICE))
        self.assertEqual([], offenders)

    def test_canonical_slot_still_works(self):
        """The alias delegated to canonical_slot, which stays."""
        self.assertEqual("duration", vocabulary.canonical_slot("duration"))
        self.assertIsNone(vocabulary.canonical_slot("not_a_slot"))


if __name__ == "__main__":
    unittest.main()
