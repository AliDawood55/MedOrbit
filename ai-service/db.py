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

# Load root .env from project root (two levels up from this file)
root_env = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(root_env)

logger = logging.getLogger("medorbit-ai.db")

_pool: asyncpg.Pool | None = None

DB_CONFIG = {
    "host": str(os.environ.get("DB_HOST", "localhost")),
    "port": int(os.environ.get("DB_PORT", "5432")),
    "database": str(os.environ.get("DB_NAME", "medorbit")),
    "user": str(os.environ.get("DB_USER", "postgres")),
    "password": str(os.environ.get("DB_PASSWORD", "")),
    "min_size": 2,
    "max_size": 10,
}


async def get_pool() -> asyncpg.Pool:
    """Return the singleton connection pool, creating it on first call."""
    global _pool
    if _pool is None or _pool._closed:  # type: ignore[union-attr]
        _pool = await asyncpg.create_pool(**DB_CONFIG)
        # Set search_path on every new connection
        async def _init(conn: asyncpg.Connection):
            await conn.execute("SET search_path TO medorbit, public")
        _pool._init = _init  # type: ignore[attr-defined]
        logger.info("DB pool created: %s:%s/%s", DB_CONFIG["host"], DB_CONFIG["port"], DB_CONFIG["database"])
    return _pool


async def close_pool():
    """Close the pool on shutdown."""
    global _pool
    if _pool and not _pool._closed:  # type: ignore[union-attr]
        await _pool.close()
        _pool = None
        logger.info("DB pool closed")