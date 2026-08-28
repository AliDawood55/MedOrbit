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

from virtual_doctor.config import env_int

root_env = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(root_env)

logger = logging.getLogger("medorbit-ai.db")

_pool: asyncpg.Pool | None = None

DB_COMMAND_TIMEOUT_SECONDS = 10

DB_CONFIG = {
    "host": str(os.environ.get("DB_HOST", "localhost")),
    "port": env_int("DB_PORT", 5432, minimum=1, maximum=65535),
    "database": str(os.environ.get("DB_NAME", "medorbit")),
    "user": str(os.environ.get("DB_USER", "postgres")),
    "password": str(os.environ.get("DB_PASSWORD", "")),
    "min_size": 2,
    "max_size": 10,
    "command_timeout": DB_COMMAND_TIMEOUT_SECONDS,
}

if os.environ.get("NODE_ENV") == "test":
    if os.environ.get("MEDORBIT_TEST_ISOLATION") != "docker":
        raise RuntimeError("Unsafe AI test database: MEDORBIT_TEST_ISOLATION must be docker")
    if DB_CONFIG["host"] != "postgres" or not DB_CONFIG["database"].endswith("_test"):
        raise RuntimeError("Unsafe AI test database: Docker postgres and a *_test database are required")


async def _set_search_path(conn: asyncpg.Connection):
    await conn.execute("SET search_path TO medorbit, public")


async def get_pool() -> asyncpg.Pool:
    """Return the singleton connection pool, creating it on first call."""
    global _pool
    if _pool is None or _pool._closed:  # type: ignore[union-attr]
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
