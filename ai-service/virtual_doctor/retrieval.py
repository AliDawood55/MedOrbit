"""
Virtual Doctor — medical knowledge retrieval (RAG), shared by every turn.

Previously this lived inside reasoning.py and ran exactly once per
consultation, at the final diagnosis. The dynamic planner needs the same
capability on *every* patient response, so it moves here as a standalone
service that both callers use. reasoning.py keeps its behaviour byte for byte;
it simply imports these functions instead of owning private copies.

TWO CACHE LAYERS, DELIBERATELY
------------------------------
They cache different things and neither subsumes the other:

  L1  _result_cache     query -> retrieved chunks     LRU + TTL
      Keyed by the normalised patient utterance plus the canonical chief
      complaint. A hit skips BOTH the Ollama round trip and the database scan.
      TTL'd because medical_knowledge can be re-ingested underneath a
      long-lived process, and a stale passage citing a page that no longer
      exists is worse than re-running a 0.3s query.

  L2  _embed_cache      text -> embedding vector      LRU (no TTL)
      Survives an L1 miss whose *query text* is unchanged but whose cache key
      differs. Embeddings are a pure function of (model, text), so they cannot
      go stale the way retrieval results can — hence no TTL.

WHY THE KEY IS NOT THE QUERY
----------------------------
The embedded query is anchored with English clinical terms (see
build_turn_query) and therefore varies with the complaint; the cache key is
built from the *normalised* utterance instead so that "٧ من ١٠" and "7 من 10",
or the same answer re-sent after a dropped connection, collapse to one entry.
Keying on the raw query text would make the cache almost never hit.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import os
import threading
import time
from collections import OrderedDict
from typing import Any, Dict, List, Optional, Tuple

import requests

from chatbot.utils.text_normalizer import normalize_text
from db import get_pool

logger = logging.getLogger("medorbit-ai.virtual_doctor.retrieval")

# --- Ollama endpoints -------------------------------------------------------
# Same derivation convention as reasoning.py: one configured host, several
# endpoints, so a deployment only ever sets OLLAMA_URL.
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
OLLAMA_EMBED_URL = os.environ.get(
    "OLLAMA_EMBED_URL", OLLAMA_URL.replace("/api/generate", "/api/embed")
)
OLLAMA_EMBED_LEGACY_URL = OLLAMA_EMBED_URL.replace("/api/embed", "/api/embeddings")

# Must match the model medical_knowledge was ingested with (rag/ingest_book.py);
# vectors from different models are not comparable.
EMBED_MODEL = os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text")

RAG_TOP_K = int(os.environ.get("RAG_TOP_K", "3"))

# Empirically chosen, unchanged from the original reasoning.py implementation:
# nomic-embed-text packs embeddings into a narrow cone, so similarity has a high
# floor. Measured over the ingested corpus across all five complaints in both
# languages: relevant chunks 0.647-0.781, nonsense 0.450-0.558, corpus mean
# 0.557. 0.60 sits in the empty gap between the two bands.
RAG_MIN_SCORE = float(os.environ.get("RAG_MIN_SCORE", "0.60"))

RAG_MAX_CHUNK_CHARS = int(os.environ.get("RAG_MAX_CHUNK_CHARS", "1200"))
RAG_EMBED_TIMEOUT = float(os.environ.get("RAG_EMBED_TIMEOUT", "20"))

# How long Ollama should keep the embedding model resident between calls.
#
# Ollama evicts models to make room, and on a 4GB card loading qwen2:7b
# (2.31GB) throws out nomic-embed-text (0.32GB). Measured: a warm embed is
# 0.067s, but the first embed after a chat call pays a 4.85s reload — which is
# exactly the 53ms -> 5.8s spread seen in the per-turn logs. The two models fit
# together (2.63GB of 4GB), so pinning the small one is nearly free and removes
# the reload entirely.
#
# Sent per request rather than relying on the server-side OLLAMA_KEEP_ALIVE,
# because Ollama runs on the host, outside this compose project — a per-request
# value is the only knob reachable from here. "-1" pins indefinitely.
#
# keep_alive alone is NOT sufficient: measured, loading qwen2:7b evicts the
# embedder anyway (Ollama frees room for a large model regardless of the idle
# TTL). It fixes the *idle* path — a warm embed goes 1.452s -> 0.057s — but not
# the post-LLM path. See EMBED_ON_CPU for that half.
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "1h")

# Run the embedding model on CPU (num_gpu=0), which is the actual fix for the
# 53ms -> 5.8s spikes seen in the per-turn logs.
#
# nomic-embed-text is a 137M-parameter model; it does not need a GPU. Keeping
# it off the card means it can never be evicted by the planner's LLM and never
# queues behind it. Measured, embed latency straight after a qwen2 chat call:
#
#     on GPU   0.216 / 0.928 / 0.797s   (mean 0.647s, 0.32GB VRAM)
#     on CPU   0.070 / 0.063 / 0.061s   (mean 0.065s, 0.00GB VRAM)
#
# 10x faster on the contended path, marginally faster even warm (0.059s vs
# 0.080s), and it hands 0.32GB of a 4GB card back to the planner and Whisper.
# Set VD_EMBED_ON_CPU=0 on a machine with VRAM to spare.
EMBED_ON_CPU = os.environ.get("VD_EMBED_ON_CPU", "1") not in ("0", "false", "False")
EMBED_OPTIONS: Optional[Dict[str, Any]] = {"num_gpu": 0} if EMBED_ON_CPU else None

# --- Cache configuration (env-tunable) --------------------------------------
RESULT_CACHE_SIZE = int(os.environ.get("VD_RAG_CACHE_SIZE", "256"))
RESULT_CACHE_TTL = float(os.environ.get("VD_RAG_CACHE_TTL", "900"))
EMBED_CACHE_SIZE = int(os.environ.get("RAG_EMBED_CACHE_SIZE", "128"))

# English seed phrases per canonical complaint. The corpus is an English
# textbook and nomic-embed-text is a weak cross-lingual matcher: measured, a raw
# Arabic symptom query topped out at 0.567 (noise) and surfaced a behavioural
# assessment page for chest pain; adding these anchors lifted the same case to
# 0.68 and returned the *same* pages as the equivalent English query.
COMPLAINT_ANCHORS: Dict[str, List[str]] = {
    "headache": ["headache"],
    "chest_pain": ["chest pain"],
    "abdominal_pain": ["abdominal pain", "stomach pain"],
    "rash": ["skin rash"],
    "fever_cough": ["fever", "cough"],
    "generic": [],
}

# Surface forms (Arabic and English) -> canonical English clinical term.
#
# This exists because the retrieval query needs an English anchor and the two
# obvious sources both failed:
#
#   * The JSON flow's slot name worked, but coupling the query (and therefore
#     the cache key) to the flow means both break when the planner replaces it.
#   * chatbot.entities.extractor was the natural reuse candidate, but measured
#     on real utterances it returns no symptoms for "عندي ألم في وسط الصدر" —
#     or even for "I have pain in the centre of my chest" — so it cannot anchor
#     the very complaint the corpus is richest in.
#
# Inferring the topic from the utterance keeps the query a pure function of
# (utterance, complaint), which is exactly what the cache key covers, and
# survives the flow being deleted. Measured over 9 real turns: bare utterances
# put 1/9 above the 0.60 floor, complaint anchors alone 2/9, this 7/9.
#
# Substring matching is deliberate — Arabic is heavily inflected and prefixed
# ("الذراع", "بالذراع"), so stemming would cost more than it returns here.
TOPIC_LEXICON: Dict[str, List[str]] = {
    "chest pain": ["صدر", "chest"],
    "headache": ["صداع", "راس", "رأس", "headache", "migraine"],
    "abdominal pain": ["بطن", "معدة", "abdomen", "stomach", "belly"],
    "fever": ["حمى", "حرارة", "سخونة", "fever"],
    "cough": ["سعال", "كحة", "cough"],
    "skin rash": ["طفح", "جلد", "حكة", "rash", "itch"],
    "duration": ["منذ", "ساعات", "ساعة", "أيام", "يوم", "اسبوع", "أسبوع",
                 "hour", "day", "week", "since", "ago", "month"],
    "severity": ["شديد", "متوسط", "خفيف", "بسيط", "severe", "moderate", "mild",
                 "out of"],
    "radiation": ["ينتشر", "تنتشر", "الذراع", "الفك", "الظهر", "الرقبة",
                  "radiat", "spread", "arm", "jaw", "neck"],
    "character pressure tightness": ["ضغط", "ضيق", "حرقة", "طعن", "pressure",
                                     "tight", "burning", "stab", "sharp", "dull"],
    "associated symptoms": ["غثيان", "تعرق", "دوخة", "تقيؤ", "nausea", "sweat",
                            "dizz", "vomit"],
    "shortness of breath": ["ضيق تنفس", "تنفس", "نفس", "breath"],
    "triggers exertion": ["مجهود", "جهد", "درج", "مشي", "exert", "stairs", "walk"],
}


def infer_topics(utterance: str) -> List[str]:
    """Canonical English clinical terms implied by an utterance.

    Pure function of the utterance — no conversation state, no flow — so it is
    safe to use in both the query and the cache key.
    """
    if not utterance:
        return []
    lowered = utterance.lower()
    return [
        canonical
        for canonical, forms in TOPIC_LEXICON.items()
        if any(form.lower() in lowered for form in forms)
    ]


# ---------------------------------------------------------------------------
# Cache primitives
# ---------------------------------------------------------------------------

class TtlLruCache:
    """Bounded LRU with per-entry expiry.

    Hand-rolled rather than functools.lru_cache for two reasons: that decorator
    has no TTL, and it would memoise a failure forever — turning one transient
    Ollama blip into a permanently context-free consultation.
    """

    def __init__(self, maxsize: int, ttl: float, name: str = "cache"):
        self._maxsize = max(1, maxsize)
        self._ttl = ttl
        self._name = name
        self._data: "OrderedDict[str, Tuple[float, Any]]" = OrderedDict()
        self._lock = threading.Lock()
        self._stats = {"hits": 0, "misses": 0, "evictions": 0, "expirations": 0}

    def get(self, key: str) -> Optional[Any]:
        now = time.monotonic()
        with self._lock:
            entry = self._data.get(key)
            if entry is None:
                self._stats["misses"] += 1
                return None
            expires_at, value = entry
            if self._ttl > 0 and now >= expires_at:
                # Expired: drop it and report a miss, not a stale hit.
                del self._data[key]
                self._stats["expirations"] += 1
                self._stats["misses"] += 1
                return None
            self._data.move_to_end(key)  # refresh LRU recency
            self._stats["hits"] += 1
            return value

    def put(self, key: str, value: Any) -> None:
        with self._lock:
            self._data[key] = (time.monotonic() + self._ttl, value)
            self._data.move_to_end(key)
            while len(self._data) > self._maxsize:
                self._data.popitem(last=False)  # evict least-recently-used
                self._stats["evictions"] += 1

    def clear(self) -> None:
        with self._lock:
            self._data.clear()

    def stats(self) -> Dict[str, Any]:
        with self._lock:
            total = self._stats["hits"] + self._stats["misses"]
            return {
                **self._stats,
                "entries": len(self._data),
                "maxsize": self._maxsize,
                "ttl_seconds": self._ttl,
                "hit_rate": round(self._stats["hits"] / total, 4) if total else 0.0,
            }


_result_cache = TtlLruCache(RESULT_CACHE_SIZE, RESULT_CACHE_TTL, "rag_result")
# No TTL: an embedding is a pure function of (model, text) and cannot go stale.
_embed_cache = TtlLruCache(EMBED_CACHE_SIZE, 0, "rag_embed")


def get_stats() -> Dict[str, Any]:
    """Cache counters. Used by tests and by latency profiling."""
    return {
        "result_cache": _result_cache.stats(),
        "embed_cache": _embed_cache.stats(),
        "config": {
            "top_k": RAG_TOP_K,
            "min_score": RAG_MIN_SCORE,
            "embed_model": EMBED_MODEL,
            "embed_on_cpu": EMBED_ON_CPU,
            "keep_alive": OLLAMA_KEEP_ALIVE,
        },
    }


def reset_stats_for_tests() -> None:
    _result_cache.clear()
    _embed_cache.clear()


# ---------------------------------------------------------------------------
# Query construction
# ---------------------------------------------------------------------------

def normalize_utterance(text: str, lang: Optional[str] = None) -> str:
    """Canonical form of a patient answer, for cache keying only.

    Reuses the project's existing normalizer (Arabic hamza/diacritic folding,
    English punctuation stripping) rather than inventing a second one, so the
    cache collapses the same variants the safety layer already treats as equal.
    """
    if not text:
        return ""
    try:
        normalized = normalize_text(text, lang or "en")
    except Exception:  # noqa: BLE001 - normalisation must never break retrieval
        normalized = text
    return " ".join(str(normalized).split()).strip().lower()


def turn_cache_key(utterance: str, chief_complaint: Optional[str],
                   lang: Optional[str] = None) -> str:
    """Cache key: normalised utterance + canonical complaint (+ model).

    Exactly the two components the design calls for. Every other input to
    build_turn_query() — the inferred topics — is itself a pure function of the
    utterance, so this key still fully determines the query with nothing left
    uncovered. Notably it does NOT depend on the interview's current slot,
    which is what makes it outlive the JSON flow.

    The model is part of the key because a model switch invalidates every
    stored vector and therefore every stored result.
    """
    raw = "\x00".join((
        EMBED_MODEL,
        chief_complaint or "generic",
        normalize_utterance(utterance, lang),
    ))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def build_turn_query(utterance: str, chief_complaint: Optional[str]) -> str:
    """Embeddable text for ONE patient turn: English anchors + what they said.

    A bare answer is not retrievable: measured on real turns, raw utterances
    score 0.48-0.52 against the corpus — below the 0.60 floor — so an Arabic
    consultation retrieved nothing at all. Two anchors fix that, and both are
    derived only from inputs the cache key already covers:

      * the canonical complaint's English phrases, when the complaint is known;
      * clinical terms inferred from the utterance itself (infer_topics).

    Measured over 9 real turns, passages retrieved: bare 1/9, complaint anchor
    alone 2/9, both anchors 7/9. The remaining 2 are utterances that carry no
    standalone clinical content ("three hours ago") and only become meaningful
    once the complaint is known — which the planner establishes far more
    reliably than the current flow does.
    """
    parts: List[str] = list(COMPLAINT_ANCHORS.get(chief_complaint or "", []))
    parts.extend(infer_topics(utterance))
    said = (utterance or "").strip()
    if said:
        parts.append(said)
    return ". ".join(p for p in parts if p)


def build_profile_query(chief_complaint: str, profile: Dict[str, Any]) -> str:
    """Embeddable text for the WHOLE consultation, used at final diagnosis.

    Unchanged from the original reasoning.py implementation.
    """
    parts: List[str] = list(COMPLAINT_ANCHORS.get(chief_complaint, []))
    if not parts:
        parts = [(chief_complaint or "").replace("_", " ")]

    for key, value in profile.items():
        if isinstance(value, str) and value.strip():
            # The key is already an English slot name ("duration", "radiation");
            # it carries the English anchor even when the value is Arabic.
            parts.append(f"{key.replace('_', ' ')}: {value.strip()}")

    return ". ".join(p for p in parts if p)


# ---------------------------------------------------------------------------
# Embedding
# ---------------------------------------------------------------------------

def _embed_uncached(text: str) -> Optional[List[float]]:
    """Embed one string via Ollama. Returns None on any failure.

    No "search_query:" task prefix: ingest_book.py embedded the chunks without
    a "search_document:" prefix, and prefixing only one side of the comparison
    would skew every score.
    """
    body: Dict[str, Any] = {
        "model": EMBED_MODEL, "input": [text], "keep_alive": OLLAMA_KEEP_ALIVE,
    }
    if EMBED_OPTIONS:
        body["options"] = EMBED_OPTIONS

    try:
        response = requests.post(
            OLLAMA_EMBED_URL, json=body, timeout=RAG_EMBED_TIMEOUT,
        )
        if response.status_code == 404:
            raise FileNotFoundError  # older Ollama: fall through to legacy endpoint
        response.raise_for_status()
        vectors = response.json().get("embeddings") or []
        if vectors and vectors[0]:
            return vectors[0]
        logger.warning("Embedding endpoint returned no vector for the retrieval query")
        return None
    except FileNotFoundError:
        pass
    except Exception as exc:  # noqa: BLE001 - retrieval must never be fatal
        logger.warning("Embedding call failed (%s) — continuing without medical context", exc)
        return None

    legacy_body: Dict[str, Any] = {
        "model": EMBED_MODEL, "prompt": text, "keep_alive": OLLAMA_KEEP_ALIVE,
    }
    if EMBED_OPTIONS:
        legacy_body["options"] = EMBED_OPTIONS

    try:
        response = requests.post(
            OLLAMA_EMBED_LEGACY_URL, json=legacy_body, timeout=RAG_EMBED_TIMEOUT,
        )
        response.raise_for_status()
        return response.json().get("embedding") or None
    except Exception as exc:  # noqa: BLE001
        logger.warning("Legacy embedding call failed (%s) — continuing without medical context", exc)
        return None


def embed(text: str) -> Optional[List[float]]:
    """Cache-wrapped embedding. Only successful vectors are cached."""
    key = f"{EMBED_MODEL}\x00{text}"
    hit = _embed_cache.get(key)
    if hit is not None:
        return list(hit)

    vector = _embed_uncached(text)
    if not vector:
        return vector  # failures are never cached
    _embed_cache.put(key, list(vector))
    return vector


# ---------------------------------------------------------------------------
# Retrieval
# ---------------------------------------------------------------------------

async def _search(vector: List[float]) -> List[Dict[str, Any]]:
    """Top-K passages above threshold. Never raises."""
    try:
        pool = await get_pool()
        rows = await pool.fetch(
            """
            SELECT chunk_text, source, page_start, page_end,
                   cosine_similarity(embedding, $1::real[]) AS score
            FROM medical_knowledge
            ORDER BY score DESC NULLS LAST
            LIMIT $2
            """,
            vector,
            RAG_TOP_K,
        )
    except Exception as exc:  # noqa: BLE001 - e.g. table not yet migrated
        logger.warning(
            "medical_knowledge lookup failed (%s) — continuing without medical context", exc
        )
        return []

    chunks: List[Dict[str, Any]] = []
    for row in rows:
        score = float(row["score"]) if row["score"] is not None else 0.0
        if score < RAG_MIN_SCORE:
            continue
        chunks.append({
            "text": (row["chunk_text"] or "")[:RAG_MAX_CHUNK_CHARS],
            "source": row["source"],
            "page_start": row["page_start"],
            "page_end": row["page_end"],
            "score": round(score, 4),
        })
    return chunks


async def retrieve(
    query_text: str,
    *,
    cache_key: Optional[str] = None,
    label: str = "",
) -> List[Dict[str, Any]]:
    """Retrieve passages for an arbitrary query. Never raises.

    Any failure (Ollama down, DB down, table missing, empty corpus) degrades to
    an empty list so the caller behaves exactly as it did before RAG existed.
    """
    if not query_text or not query_text.strip():
        return []

    if cache_key:
        cached = _result_cache.get(cache_key)
        if cached is not None:
            logger.info("RAG cache HIT (%s) — %d passage(s), no embed, no DB scan",
                        label or "query", len(cached))
            # Copy out: callers must not mutate a shared cached entry.
            return [dict(c) for c in cached]

    started = time.monotonic()
    # requests is blocking and callers are on the event loop.
    vector = await asyncio.to_thread(embed, query_text)
    embed_ms = (time.monotonic() - started) * 1000
    if not vector:
        return []

    search_started = time.monotonic()
    chunks = await _search(vector)
    search_ms = (time.monotonic() - search_started) * 1000

    if cache_key:
        _result_cache.put(cache_key, [dict(c) for c in chunks])

    if chunks:
        logger.info(
            "RAG MISS (%s) — %d passage(s) scores=%s embed=%.0fms search=%.0fms",
            label or "query", len(chunks), [c["score"] for c in chunks], embed_ms, search_ms,
        )
    else:
        logger.info(
            "RAG MISS (%s) — nothing scored >= %.2f (embed=%.0fms search=%.0fms)",
            label or "query", RAG_MIN_SCORE, embed_ms, search_ms,
        )
    return chunks


async def retrieve_for_turn(
    utterance: str,
    chief_complaint: Optional[str],
    lang: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Per-turn retrieval: fresh context for the patient's latest answer.

    Depends only on what the patient said and the canonical complaint — no
    interview position, no flow state — so the caller can be the slot machine
    today and the dynamic planner tomorrow with no change here.
    """
    return await retrieve(
        build_turn_query(utterance, chief_complaint),
        cache_key=turn_cache_key(utterance, chief_complaint, lang),
        label=f"turn/{chief_complaint or 'generic'}",
    )


async def retrieve_for_profile(
    chief_complaint: str, profile: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """Whole-consultation retrieval, used at final diagnosis."""
    query = build_profile_query(chief_complaint, profile)
    return await retrieve(
        query,
        cache_key=hashlib.sha256(f"profile\x00{EMBED_MODEL}\x00{query}".encode()).hexdigest(),
        label=f"profile/{chief_complaint}",
    )


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

def cite(chunk: Dict[str, Any]) -> str:
    """'p. 59' / 'pp. 114-115' for one chunk."""
    start, end = chunk.get("page_start"), chunk.get("page_end")
    if start and end and end != start:
        return f"pp. {start}-{end}"
    if start:
        return f"p. {start}"
    return "n.p."


def format_context(chunks: List[Dict[str, Any]]) -> str:
    """Render retrieved passages as a labelled prompt block."""
    if not chunks:
        return ""
    source = chunks[0].get("source") or "medical reference"
    passages = "\n\n".join(
        f"[{i}] ({cite(c)}) {' '.join((c['text'] or '').split())}"
        for i, c in enumerate(chunks, start=1)
    )
    return (
        f"MEDICAL CONTEXT — verbatim passages retrieved from {source}. "
        f"Treat these as your primary evidence:\n\n{passages}\n"
    )
