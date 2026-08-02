#!/usr/bin/env python3
"""
Ingest a medical textbook PDF into the medical_knowledge RAG table.

    python ai-service/rag/ingest_book.py                # full run, defaults
    python ai-service/rag/ingest_book.py --dry-run      # chunk only, no DB/Ollama
    python ai-service/rag/ingest_book.py --end-page 40  # small slice first

Pipeline: stream pages with pypdf -> sliding-window chunks -> batch-embed via
Ollama (nomic-embed-text) -> batch-insert into medorbit.medical_knowledge.

DESIGNED FOR A LARGE BOOK
-------------------------
The target file is ~65 MB / 1400+ pages, and embedding it is minutes of local
GPU/CPU work. Three things follow from that:

  * Nothing is accumulated in memory. Pages are streamed, chunks are emitted
    from a sliding buffer, and each batch is embedded and inserted before the
    next is built. Peak memory is one batch, not one book.
  * The run is resumable. (source, chunk_index) is UNIQUE, so a re-run skips
    ahead to the highest chunk already stored and continues. Kill it with
    Ctrl-C and start it again; it picks up where it stopped.
  * Inserts are batched via execute_values, not one round trip per chunk.

EMBEDDINGS ARE STORED AS REAL[], NOT vector(768)
------------------------------------------------
The postgis image has no pgvector — see db/20_medical_knowledge.sql for the
reasoning and the later swap-in path. Nothing in this script depends on that
choice beyond passing a plain list of floats.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import sys
import time
import unicodedata
from pathlib import Path
from typing import Iterator, List, NamedTuple, Optional, Sequence

import psycopg2
import requests
from dotenv import load_dotenv
from psycopg2.extras import execute_values
from pypdf import PdfReader

# ai-service/rag/ingest_book.py -> repo root is two levels up.
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
load_dotenv(_REPO_ROOT / ".env")

# The real filename, spaces and all. The task brief called it "Macleods.pdf";
# what is actually on disk is the full title, so that is the default and
# --pdf overrides it.
DEFAULT_PDF = _REPO_ROOT / "ai-service" / "data" / "Macleods Clinical Examination 14th Edition.pdf"

DEFAULT_MODEL = "nomic-embed-text"
DEFAULT_CHUNK_SIZE = 1000
DEFAULT_OVERLAP = 200
DEFAULT_EMBED_BATCH = 32
DEFAULT_INSERT_BATCH = 200

# Shortest chunk worth embedding. Below this it is nearly always a stray page
# number, running header, or figure caption fragment — noise in a RAG index.
MIN_CHUNK_CHARS = 120

log = logging.getLogger("ingest_book")


# --------------------------------------------------------------------------
# Ollama
# --------------------------------------------------------------------------

class OllamaEmbedder:
    """Batch embedding client for a local Ollama server.

    Prefers POST /api/embed, which takes a list and returns a list — one HTTP
    round trip per batch instead of per chunk. Falls back to the older
    single-item /api/embeddings when the server predates that endpoint.
    """

    def __init__(self, base_url: str, model: str, timeout: int = 180, retries: int = 3):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self.retries = retries
        self.session = requests.Session()
        self._batch_supported = True

    def _post(self, path: str, payload: dict) -> dict:
        """POST with retry/backoff. Local models stall under load far more
        often than they hard-fail, so transient errors are worth retrying."""
        last_error: Optional[Exception] = None
        for attempt in range(1, self.retries + 1):
            try:
                res = self.session.post(
                    f"{self.base_url}{path}", json=payload, timeout=self.timeout
                )
                if res.status_code == 404:
                    raise FileNotFoundError(path)
                res.raise_for_status()
                return res.json()
            except FileNotFoundError:
                raise
            except Exception as exc:  # noqa: BLE001 - retry anything transient
                last_error = exc
                if attempt < self.retries:
                    backoff = 2 ** attempt
                    log.warning(
                        "Ollama %s failed (attempt %d/%d): %s — retrying in %ds",
                        path, attempt, self.retries, exc, backoff,
                    )
                    time.sleep(backoff)
        raise RuntimeError(f"Ollama {path} failed after {self.retries} attempts: {last_error}")

    def embed(self, texts: Sequence[str]) -> List[List[float]]:
        if self._batch_supported:
            try:
                data = self._post("/api/embed", {"model": self.model, "input": list(texts)})
                vectors = data.get("embeddings")
                if vectors and len(vectors) == len(texts):
                    return vectors
                log.warning("/api/embed returned %s vectors for %d inputs — falling back",
                            len(vectors) if vectors else 0, len(texts))
                self._batch_supported = False
            except FileNotFoundError:
                log.info("This Ollama has no /api/embed; using /api/embeddings one at a time.")
                self._batch_supported = False

        out: List[List[float]] = []
        for text in texts:
            data = self._post("/api/embeddings", {"model": self.model, "prompt": text})
            vector = data.get("embedding")
            if not vector:
                raise RuntimeError(f"Ollama returned no embedding: {json.dumps(data)[:200]}")
            out.append(vector)
        return out


def resolve_ollama_url(explicit: Optional[str]) -> str:
    """Pick an Ollama base URL that actually answers.

    host.docker.internal is the container-side name and does not resolve when
    this script is run directly on the host, which is the normal way to run an
    ingestion. Rather than fail with a DNS error, try the configured host and
    fall back to localhost.
    """
    candidates: List[str] = []
    if explicit:
        candidates.append(explicit)
    else:
        # .env's OLLAMA_URL points at /api/generate; keep only scheme://host:port.
        env_url = os.environ.get("OLLAMA_URL", "")
        if env_url:
            match = re.match(r"^(https?://[^/]+)", env_url.strip())
            if match:
                candidates.append(match.group(1))
        candidates.append("http://host.docker.internal:11434")
        candidates.append("http://127.0.0.1:11434")

    seen, ordered = set(), []
    for url in candidates:
        url = url.rstrip("/")
        if url not in seen:
            seen.add(url)
            ordered.append(url)

    for url in ordered:
        try:
            res = requests.get(f"{url}/api/tags", timeout=5)
            if res.ok:
                log.info("Ollama: %s", url)
                return url
        except Exception:  # noqa: BLE001 - just means "try the next candidate"
            continue

    raise SystemExit(
        "Could not reach Ollama at any of: " + ", ".join(ordered)
        + "\nStart it with `ollama serve`, or pass --ollama-url."
    )


def assert_model_present(base_url: str, model: str) -> None:
    """Fail now with a clear message rather than 1400 pages into the run."""
    try:
        tags = requests.get(f"{base_url}/api/tags", timeout=10).json()
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"Could not list Ollama models: {exc}")

    names = {m.get("name", "") for m in tags.get("models", [])}
    # Ollama reports "nomic-embed-text:latest" for a "nomic-embed-text" pull.
    if model in names or f"{model}:latest" in names:
        return
    raise SystemExit(
        f"Model '{model}' is not installed in Ollama.\n"
        f"Installed: {', '.join(sorted(names)) or '(none)'}\n"
        f"Pull it with:  ollama pull {model}"
    )


# --------------------------------------------------------------------------
# PDF -> text -> chunks
# --------------------------------------------------------------------------

class Chunk(NamedTuple):
    index: int
    text: str
    page_start: int
    page_end: int


_WS_RUN = re.compile(r"[ \t ]+")
_BLANK_RUNS = re.compile(r"\n\s*\n\s*\n+")
# Words split across a line break by hyphenation: "examina-\ntion" -> "examination".
_HYPHEN_BREAK = re.compile(r"(\w)-\n(\w)")


def normalise(text: str) -> str:
    """Flatten PDF text extraction artefacts into clean prose."""
    # NFKC folds ligatures (ﬁ -> fi) and full-width forms that pypdf emits.
    text = unicodedata.normalize("NFKC", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _HYPHEN_BREAK.sub(r"\1\2", text)
    text = _WS_RUN.sub(" ", text)
    text = _BLANK_RUNS.sub("\n\n", text)
    return text.strip()


def iter_pages(pdf_path: Path, start_page: int, end_page: Optional[int]) -> Iterator[tuple[int, str]]:
    """Yield (1-based page number, normalised text), skipping unreadable pages.

    A single malformed page must not abort an hour-long ingestion, so
    extraction failures are logged and skipped.
    """
    reader = PdfReader(str(pdf_path), strict=False)
    total = len(reader.pages)
    last = min(end_page or total, total)
    log.info("PDF has %d pages; reading %d-%d", total, start_page, last)

    for page_no in range(start_page, last + 1):
        try:
            raw = reader.pages[page_no - 1].extract_text() or ""
        except Exception as exc:  # noqa: BLE001
            log.warning("Page %d could not be extracted (%s) — skipped", page_no, exc)
            continue
        text = normalise(raw)
        if text:
            yield page_no, text


def _cut_point(buffer: str, size: int) -> int:
    """Where to end a chunk: the latest clean boundary at or before `size`.

    Prefers a paragraph break, then a sentence end, then a space, searching
    back at most 20% of the chunk. Falls back to a hard cut so a run of text
    with no boundaries can't stall the loop.
    """
    if len(buffer) <= size:
        return len(buffer)

    floor = max(1, int(size * 0.8))
    window = buffer[:size]
    for pattern in ("\n\n", ". ", ".\n", "? ", "! ", "\n", " "):
        found = window.rfind(pattern)
        if found >= floor:
            return found + len(pattern)
    return size


def iter_chunks(
    pages: Iterator[tuple[int, str]],
    chunk_size: int,
    overlap: int,
) -> Iterator[Chunk]:
    """Sliding-window chunker over a stream of pages.

    Holds only the working buffer (roughly one chunk plus one page), so memory
    is flat regardless of book length. `marks` tracks where each page's text
    starts inside the buffer so every chunk can report the page range it came
    from.
    """
    buffer = ""
    marks: List[tuple[int, int]] = []  # (offset in buffer, page number)
    index = 0

    def pages_spanned(end: int) -> tuple[int, int]:
        covering = [page for offset, page in marks if offset < end]
        if not covering:
            return (marks[0][1], marks[0][1]) if marks else (0, 0)
        return covering[0], covering[-1]

    def emit(upto: int) -> Optional[Chunk]:
        nonlocal index
        text = buffer[:upto].strip()
        if len(text) < MIN_CHUNK_CHARS:
            return None
        first, last = pages_spanned(upto)
        chunk = Chunk(index=index, text=text, page_start=first, page_end=last)
        index += 1
        return chunk

    for page_no, page_text in pages:
        marks.append((len(buffer), page_no))
        buffer = f"{buffer}\n\n{page_text}" if buffer else page_text

        while len(buffer) >= chunk_size:
            cut = _cut_point(buffer, chunk_size)
            chunk = emit(cut)
            if chunk:
                yield chunk

            # Keep `overlap` characters of tail as the next chunk's head so a
            # sentence straddling the boundary stays retrievable from both.
            keep_from = max(0, cut - overlap)
            buffer = buffer[keep_from:]
            marks = [(max(0, off - keep_from), pg) for off, pg in marks if off >= keep_from] \
                or ([(0, page_no)] if buffer else [])

    tail = emit(len(buffer))
    if tail:
        yield tail


# --------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------

def connect():
    """Connect using the same root .env credentials the ai-service uses."""
    try:
        return psycopg2.connect(
            host=os.environ.get("DB_HOST", "localhost"),
            port=int(os.environ.get("DB_PORT", "5432")),
            dbname=os.environ.get("DB_NAME", "medorbit"),
            user=os.environ.get("DB_USER", "postgres"),
            password=os.environ.get("DB_PASSWORD", ""),
            options=f"-c search_path={os.environ.get('DB_SCHEMA', 'medorbit')},public",
        )
    except psycopg2.OperationalError as exc:
        raise SystemExit(
            f"Could not connect to PostgreSQL: {exc}\n"
            "Check DB_* in the root .env (DB_HOST=localhost when running on the host)."
        )


def assert_table_exists(conn) -> None:
    with conn.cursor() as cur:
        cur.execute("SELECT to_regclass('medorbit.medical_knowledge')")
        if cur.fetchone()[0] is None:
            raise SystemExit(
                "Table medorbit.medical_knowledge does not exist.\n"
                "Apply the migration first:\n"
                "  docker exec -i medorbit-postgres psql -U postgres -d medorbit "
                "< db/20_medical_knowledge.sql"
            )


def resume_point(conn, source: str) -> int:
    """Highest chunk_index already stored for this source, or -1."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT COALESCE(MAX(chunk_index), -1) FROM medical_knowledge WHERE source = %s",
            (source,),
        )
        return cur.fetchone()[0]


def delete_source(conn, source: str) -> int:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM medical_knowledge WHERE source = %s", (source,))
        deleted = cur.rowcount
    conn.commit()
    return deleted


def insert_batch(conn, rows: list[tuple]) -> int:
    """Insert a batch, ignoring chunks already stored for this source.

    ON CONFLICT DO NOTHING is what makes re-running safe: the UNIQUE
    (source, chunk_index) constraint absorbs overlap between runs.
    """
    with conn.cursor() as cur:
        execute_values(
            cur,
            """
            INSERT INTO medical_knowledge
              (source, chunk_index, chunk_text, embedding, embedding_dim,
               embedding_model, page_start, page_end, content_hash)
            VALUES %s
            ON CONFLICT (source, chunk_index) DO NOTHING
            """,
            rows,
            page_size=DEFAULT_INSERT_BATCH,
        )
        inserted = cur.rowcount
    conn.commit()
    return inserted


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Ingest a PDF textbook into medorbit.medical_knowledge.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--pdf", type=Path, default=DEFAULT_PDF, help="Path to the PDF")
    p.add_argument("--source", default=None,
                   help="Source label stored on every row (default: the PDF filename stem)")
    p.add_argument("--model", default=DEFAULT_MODEL, help="Ollama embedding model")
    p.add_argument("--ollama-url", default=None,
                   help="Ollama base URL (default: OLLAMA_URL from .env, then localhost)")
    p.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE, help="Characters per chunk")
    p.add_argument("--overlap", type=int, default=DEFAULT_OVERLAP, help="Character overlap between chunks")
    p.add_argument("--embed-batch", type=int, default=DEFAULT_EMBED_BATCH, help="Chunks per embedding request")
    p.add_argument("--start-page", type=int, default=1, help="First page (1-based)")
    p.add_argument("--end-page", type=int, default=None, help="Last page (1-based, inclusive)")
    p.add_argument("--limit", type=int, default=None, help="Stop after N chunks (smoke tests)")
    p.add_argument("--reset", action="store_true", help="Delete existing rows for this source first")
    p.add_argument("--dry-run", action="store_true",
                   help="Chunk and report stats only — no Ollama calls, no DB writes")
    p.add_argument("-v", "--verbose", action="store_true", help="Debug logging")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )

    if not args.pdf.exists():
        raise SystemExit(f"PDF not found: {args.pdf}")
    if args.overlap >= args.chunk_size:
        raise SystemExit("--overlap must be smaller than --chunk-size")

    source = args.source or args.pdf.stem
    log.info("Source label: %s", source)
    log.info("PDF: %s (%.1f MB)", args.pdf, args.pdf.stat().st_size / 1e6)

    pages = iter_pages(args.pdf, args.start_page, args.end_page)
    chunks = iter_chunks(pages, args.chunk_size, args.overlap)

    # ---- dry run: chunking only -------------------------------------------
    if args.dry_run:
        count = chars = 0
        first_preview = None
        started = time.time()
        for chunk in chunks:
            if first_preview is None:
                first_preview = chunk
            count += 1
            chars += len(chunk.text)
            if args.limit and count >= args.limit:
                break
        log.info("DRY RUN: %d chunks, avg %d chars, %.1fs",
                 count, chars // max(count, 1), time.time() - started)
        if first_preview:
            log.info("First chunk (pages %d-%d):\n%s",
                     first_preview.page_start, first_preview.page_end,
                     first_preview.text[:400] + ("..." if len(first_preview.text) > 400 else ""))
        return 0

    # ---- preflight ---------------------------------------------------------
    base_url = resolve_ollama_url(args.ollama_url)
    assert_model_present(base_url, args.model)
    embedder = OllamaEmbedder(base_url, args.model)

    conn = connect()
    assert_table_exists(conn)

    if args.reset:
        log.warning("--reset: deleted %d existing rows for source '%s'",
                    delete_source(conn, source), source)

    skip_through = resume_point(conn, source)
    if skip_through >= 0:
        log.info("Resuming: chunks 0-%d already stored, continuing from %d",
                 skip_through, skip_through + 1)

    # ---- ingest ------------------------------------------------------------
    started = time.time()
    pending: list[Chunk] = []
    seen = inserted = skipped = 0
    dim: Optional[int] = None

    def flush() -> None:
        nonlocal pending, inserted, dim
        if not pending:
            return
        vectors = embedder.embed([c.text for c in pending])
        rows = []
        for chunk, vector in zip(pending, vectors):
            if dim is None:
                dim = len(vector)
                log.info("Embedding dimension: %d", dim)
            elif len(vector) != dim:
                raise SystemExit(
                    f"Inconsistent embedding size at chunk {chunk.index}: "
                    f"{len(vector)} vs {dim}"
                )
            rows.append((
                source,
                chunk.index,
                chunk.text,
                vector,
                len(vector),
                args.model,
                chunk.page_start,
                chunk.page_end,
                hashlib.sha256(chunk.text.encode("utf-8")).hexdigest(),
            ))
        inserted += insert_batch(conn, rows)
        pending = []

    try:
        for chunk in chunks:
            seen += 1
            if chunk.index <= skip_through:
                skipped += 1
                continue

            pending.append(chunk)
            if len(pending) >= args.embed_batch:
                flush()
                rate = inserted / max(time.time() - started, 0.001)
                log.info("… %d inserted (page %d, %.1f chunks/s)",
                         inserted, chunk.page_end, rate)

            if args.limit and (inserted + len(pending)) >= args.limit:
                break
        flush()
    except KeyboardInterrupt:
        log.warning("Interrupted — flushing what is already embedded.")
        try:
            flush()
        except Exception as exc:  # noqa: BLE001
            log.error("Could not flush final batch: %s", exc)
        log.warning("Stopped. Re-run the same command to resume from chunk %d.",
                    skip_through + inserted + 1)
        return 130
    finally:
        conn.close()

    elapsed = time.time() - started
    log.info("Done: %d chunks seen, %d skipped (already stored), %d inserted in %.1fs",
             seen, skipped, inserted, elapsed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
