"""
Database connection pool for ai-service.
Uses asyncpg for async PostgreSQL access (schema: medorbit).
Loads environment from root .env (project root).
"""

import os
import logging
import asyncpg
from pathlib import Path
from dotenv import load_dotenv

# The Phase 7B numeric-config helper, reused rather than reimplemented. It is a
# leaf module — stdlib imports only — and `virtual_doctor/__init__.py` is
# empty, so this pulls in no package initialisation and creates no cycle in
# either import order (verified: `db` first, and `virtual_doctor.retrieval`
# first, which reaches `db` mid-import).
from virtual_doctor.config import env_int

# Load root .env from project root (two levels up from this file)
root_env = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(root_env)

logger = logging.getLogger("medorbit-ai.db")

_pool: asyncpg.Pool | None = None

# Applied to every query/command run through the pool (asyncpg's built-in
# per-operation timeout) so a stuck query can no longer hold a connection —
# and everything queued behind it — indefinitely.
DB_COMMAND_TIMEOUT_SECONDS = 10

DB_CONFIG = {
    "host": str(os.environ.get("DB_HOST", "localhost")),
    # Bounded to the real TCP port range. A malformed or out-of-range value
    # used to raise ValueError here, during import — and because db is imported
    # by chatbot/main.py and by four virtual_doctor modules, that took the whole
    # service down at startup with a traceback pointing at a module rather than
    # at the variable. It now warns and falls back to 5432.
    "port": env_int("DB_PORT", 5432, minimum=1, maximum=65535),
    "database": str(os.environ.get("DB_NAME", "medorbit")),
    "user": str(os.environ.get("DB_USER", "postgres")),
    "password": str(os.environ.get("DB_PASSWORD", "")),
    "min_size": 2,
    "max_size": 10,
    "command_timeout": DB_COMMAND_TIMEOUT_SECONDS,
}


async def _set_search_path(conn: asyncpg.Connection):
    await conn.execute("SET search_path TO medorbit, public")


async def get_pool() -> asyncpg.Pool:
    """Return the singleton connection pool, creating it on first call."""
    global _pool
    if _pool is None or _pool._closed:  # type: ignore[union-attr]
        # setup= runs on every connection checkout (unlike init=, which only
        # runs once when a physical connection is first created) — required
        # here since search_path doesn't survive being pooled/reused otherwise.
        _pool = await asyncpg.create_pool(**DB_CONFIG, setup=_set_search_path)
        logger.info("DB pool created: %s:%s/%s", DB_CONFIG["host"], DB_CONFIG["port"], DB_CONFIG["database"])
    return _pool


async def close_pool():
    """Close the pool on shutdown."""
    global _pool
    if _pool and not _pool._closed:  # type: ignore[union-attr]
        await _pool.close()
        _pool = None
        logger.info("DB pool closed")