"""
Phase 7C — DB_PORT parsing safety.

The last instance of the bug class Phase 7B fixed. `db.py` read the port as a
bare `int(os.environ.get("DB_PORT", "5432"))` at module import, and `db` is
imported by `chatbot/main.py` and by four `virtual_doctor` modules — so a
single mistyped port took the entire service down at startup with a traceback
pointing at a module rather than at the variable.

WHY THE SUBPROCESS TESTS ARE THE REAL ONES
------------------------------------------
`db` is already in `sys.modules` by the time this file runs, and `DB_CONFIG` is
built once at import. Re-reading `os.environ` in-process therefore proves
nothing about import-time behaviour. TestImportSafetyInSubprocess starts a
fresh interpreter with a malformed `DB_PORT` and asserts the process survives
and the documented default is loaded — which is the property that was actually
broken.

A note on `.env`: `db.py` calls `load_dotenv(root_env)`, and the project's
`.env` sets `DB_PORT=5432`. `load_dotenv` defaults to `override=False`, so an
explicitly exported variable still wins — which is why the malformed-value
tests below work, and why "unset" is exercised against the helper directly
rather than by unsetting the variable.
"""

import json
import os
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import db
from virtual_doctor import config
from virtual_doctor.config import env_int

AI_SERVICE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# The exact call db.py makes. Kept in one place so a divergence between what is
# tested and what ships is impossible to introduce silently.
DEFAULT_PORT = 5432
PORT_MIN, PORT_MAX = 1, 65535


def parse_port():
    return env_int("DB_PORT", DEFAULT_PORT, minimum=PORT_MIN, maximum=PORT_MAX)


class _EnvCase(unittest.TestCase):
    def setUp(self):
        config.reset_warning_state()

    def tearDown(self):
        config.reset_warning_state()


# ===========================================================================
# 1. Parsing behaviour
# ===========================================================================

class TestDbPortParsing(_EnvCase):
    def test_unset_uses_the_existing_default(self):
        saved = os.environ.pop("DB_PORT", None)
        try:
            self.assertEqual(5432, parse_port())
        finally:
            if saved is not None:
                os.environ["DB_PORT"] = saved

    def test_the_standard_port_is_accepted(self):
        with patch.dict(os.environ, {"DB_PORT": "5432"}):
            self.assertEqual(5432, parse_port())

    def test_a_valid_custom_port_is_accepted(self):
        for value, want in (("6543", 6543), ("15432", 15432), ("1", 1)):
            with patch.dict(os.environ, {"DB_PORT": value}):
                self.assertEqual(want, parse_port(), value)

    def test_malformed_falls_back_to_the_default(self):
        for bad in ("abc", "5432abc", "54.32", "0x1538", "5,432", "None",
                    "true", "localhost:5432"):
            with patch.dict(os.environ, {"DB_PORT": bad}):
                self.assertEqual(5432, parse_port(), bad)

    def test_empty_falls_back_to_the_default(self):
        with patch.dict(os.environ, {"DB_PORT": ""}):
            self.assertEqual(5432, parse_port())

    def test_whitespace_only_falls_back_to_the_default(self):
        for blank in ("   ", "\t", "\n"):
            with patch.dict(os.environ, {"DB_PORT": blank}):
                self.assertEqual(5432, parse_port(), repr(blank))

    def test_surrounding_whitespace_around_a_valid_port_is_tolerated(self):
        with patch.dict(os.environ, {"DB_PORT": "  6543  "}):
            self.assertEqual(6543, parse_port())

    def test_zero_is_rejected(self):
        """Port 0 asks the OS to pick one — never what a client config means."""
        with patch.dict(os.environ, {"DB_PORT": "0"}):
            self.assertEqual(5432, parse_port())

    def test_negative_is_rejected(self):
        for bad in ("-1", "-5432"):
            with patch.dict(os.environ, {"DB_PORT": bad}):
                self.assertEqual(5432, parse_port(), bad)

    def test_the_top_of_the_tcp_range_is_accepted(self):
        with patch.dict(os.environ, {"DB_PORT": "65535"}):
            self.assertEqual(65535, parse_port())

    def test_above_the_tcp_range_is_rejected(self):
        for bad in ("65536", "70000", "999999999"):
            with patch.dict(os.environ, {"DB_PORT": bad}):
                self.assertEqual(5432, parse_port(), bad)

    def test_the_port_is_an_int_and_never_a_bool(self):
        with patch.dict(os.environ, {"DB_PORT": "5432"}):
            value = parse_port()
        self.assertIsInstance(value, int)
        self.assertNotIsInstance(value, bool)


class TestWarnings(_EnvCase):
    def test_a_malformed_port_warns_naming_the_variable_and_default(self):
        with patch.dict(os.environ, {"DB_PORT": "abc"}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                parse_port()
        joined = "\n".join(logs.output)
        self.assertIn("DB_PORT", joined)
        self.assertIn("5432", joined)

    def test_an_out_of_range_port_says_which_bound(self):
        with patch.dict(os.environ, {"DB_PORT": "65536"}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                parse_port()
        self.assertIn("at most 65535", "\n".join(logs.output))

    def test_an_oversized_hostile_value_is_not_echoed(self):
        hostile = "9" * 10000
        with patch.dict(os.environ, {"DB_PORT": hostile}):
            with self.assertLogs("medorbit-ai.virtual_doctor.config", "WARNING") as logs:
                self.assertEqual(5432, parse_port())
        joined = "\n".join(logs.output)
        self.assertNotIn(hostile, joined)
        self.assertNotIn("9999999999", joined)
        self.assertLess(len(joined), 300)

    def test_a_valid_port_logs_nothing(self):
        with patch.dict(os.environ, {"DB_PORT": "6543"}):
            with self.assertNoLogs("medorbit-ai.virtual_doctor.config", "WARNING"):
                parse_port()


# ===========================================================================
# 2. Nothing else about the DB config changed
# ===========================================================================

class TestOtherDbConfigUnchanged(unittest.TestCase):
    def test_the_loaded_config_still_has_exactly_the_same_keys(self):
        self.assertEqual(
            {"host", "port", "database", "user", "password",
             "min_size", "max_size", "command_timeout"},
            set(db.DB_CONFIG),
        )

    def test_non_port_fields_are_untouched(self):
        self.assertEqual(str(os.environ.get("DB_HOST", "localhost")), db.DB_CONFIG["host"])
        self.assertEqual(str(os.environ.get("DB_NAME", "medorbit")), db.DB_CONFIG["database"])
        self.assertEqual(str(os.environ.get("DB_USER", "postgres")), db.DB_CONFIG["user"])
        self.assertEqual(str(os.environ.get("DB_PASSWORD", "")), db.DB_CONFIG["password"])

    def test_pooling_and_timeout_settings_are_untouched(self):
        self.assertEqual(2, db.DB_CONFIG["min_size"])
        self.assertEqual(10, db.DB_CONFIG["max_size"])
        self.assertEqual(10, db.DB_COMMAND_TIMEOUT_SECONDS)
        self.assertEqual(db.DB_COMMAND_TIMEOUT_SECONDS, db.DB_CONFIG["command_timeout"])

    def test_the_pool_api_is_unchanged(self):
        self.assertTrue(callable(db.get_pool))
        self.assertTrue(callable(db.close_pool))
        self.assertTrue(callable(db._set_search_path))

    def test_the_live_port_is_a_valid_port(self):
        self.assertIsInstance(db.DB_CONFIG["port"], int)
        self.assertGreaterEqual(db.DB_CONFIG["port"], PORT_MIN)
        self.assertLessEqual(db.DB_CONFIG["port"], PORT_MAX)

    def test_no_second_env_parser_was_introduced(self):
        """Phase 7C reuses the Phase 7B helper; db.py must not grow its own."""
        with open(os.path.join(AI_SERVICE, "db.py"), encoding="utf-8") as handle:
            source = handle.read()
        self.assertIn("from virtual_doctor.config import env_int", source)
        self.assertNotIn('int(os.environ', source)
        self.assertNotIn("def env_int", source)


# ===========================================================================
# 3. Import safety — a real interpreter, the property that was broken
# ===========================================================================

_PROBE = """
import json
import db
print("RESULT" + json.dumps({
    "port": db.DB_CONFIG["port"],
    "host": db.DB_CONFIG["host"],
    "database": db.DB_CONFIG["database"],
    "min_size": db.DB_CONFIG["min_size"],
    "max_size": db.DB_CONFIG["max_size"],
    "command_timeout": db.DB_CONFIG["command_timeout"],
}))
"""


def _run_probe(extra_env):
    env = dict(os.environ)
    env.update(extra_env)
    env["PYTHONIOENCODING"] = "utf-8"
    return subprocess.run([sys.executable, "-c", _PROBE], cwd=AI_SERVICE, env=env,
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=180)


def _parse(proc):
    for line in proc.stdout.splitlines():
        if line.startswith("RESULT"):
            return json.loads(line[len("RESULT"):])
    raise AssertionError(f"probe produced no result.\nSTDOUT:\n{proc.stdout}\n"
                         f"STDERR:\n{proc.stderr}")


class TestImportSafetyInSubprocess(unittest.TestCase):
    def test_a_malformed_port_no_longer_kills_the_import(self):
        proc = _run_probe({"DB_PORT": "abc"})
        self.assertEqual(0, proc.returncode,
                         f"import failed.\nSTDERR:\n{proc.stderr}")
        self.assertEqual(5432, _parse(proc)["port"])

    def test_every_malformed_shape_survives_import(self):
        for bad in ("abc", "", "   ", "0", "-1", "65536", "54.32", "9" * 5000):
            proc = _run_probe({"DB_PORT": bad})
            self.assertEqual(0, proc.returncode, f"{bad[:20]!r} crashed import")
            self.assertEqual(5432, _parse(proc)["port"], bad[:20])

    def test_a_valid_override_still_reaches_the_config_through_a_real_import(self):
        self.assertEqual(6543, _parse(_run_probe({"DB_PORT": "6543"}))["port"])
        self.assertEqual(65535, _parse(_run_probe({"DB_PORT": "65535"}))["port"])

    def test_the_hostile_value_is_not_echoed_to_stderr(self):
        proc = _run_probe({"DB_PORT": "9" * 5000})
        self.assertNotIn("9" * 100, proc.stderr)

    def test_a_malformed_port_warns_at_import(self):
        proc = _run_probe({"DB_PORT": "abc"})
        self.assertIn("Invalid DB_PORT", proc.stderr)

    def test_non_port_config_is_identical_across_malformed_and_valid_runs(self):
        bad = _parse(_run_probe({"DB_PORT": "abc"}))
        good = _parse(_run_probe({"DB_PORT": "5432"}))
        for key in ("host", "database", "min_size", "max_size", "command_timeout"):
            self.assertEqual(good[key], bad[key], key)

    def test_importing_db_first_does_not_deadlock_or_cycle(self):
        """db -> virtual_doctor.config, with nothing imported beforehand."""
        proc = subprocess.run(
            [sys.executable, "-c", "import db; import virtual_doctor.config; print('OK')"],
            cwd=AI_SERVICE, capture_output=True, text=True, timeout=180)
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("OK", proc.stdout)

    def test_importing_a_virtual_doctor_module_first_does_not_cycle(self):
        """virtual_doctor.retrieval -> db -> virtual_doctor.config, i.e. db is
        reached while the virtual_doctor package is already being imported."""
        proc = subprocess.run(
            [sys.executable, "-c", "import virtual_doctor.retrieval; import db; print('OK')"],
            cwd=AI_SERVICE, capture_output=True, text=True, timeout=180)
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("OK", proc.stdout)

    def test_a_chatbot_module_that_imports_db_still_imports(self):
        """chatbot/** reaches db too, so the new dependency must not break it."""
        proc = subprocess.run(
            [sys.executable, "-c",
             "import chatbot.medical.symptom_engine; print('OK')"],
            cwd=AI_SERVICE, capture_output=True, text=True, timeout=180,
            env={**os.environ, "DB_PORT": "abc"})
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("OK", proc.stdout)


if __name__ == "__main__":
    unittest.main()
