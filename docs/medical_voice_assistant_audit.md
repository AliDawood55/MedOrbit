# Medical Voice Assistant Architecture Audit

**Scope:** `ai-service/`, with emphasis on `ai-service/virtual_doctor/`. Read-only audit — no production code, tests, or configuration were modified while producing this report.

**Method:** Direct source inspection (every file cited below was read, not assumed), plus a fully-passing test-suite run (`.venv/Scripts/python -m unittest discover -s tests -v` → 353 tests, 0 failures, 0 errors) used as ground truth for "what currently works."

---

## 1. Executive Summary

**Current project maturity:** Mid-stage prototype with unusually strong engineering discipline in places, and real architectural debt in others. The NLU/chatbot layer (`chatbot/`) is a hand-built, rule-based system that recently went through a long, deliberate bug-fixing pass (documented in this same session) and is now internally consistent and fully tested. The Virtual Doctor module (`virtual_doctor/`) is a separate, more modern subsystem with a real (if narrow) RAG pipeline, an LLM-driven dynamic planner with a deterministic fallback, and — notably — **working, turn-based STT and TTS already implemented** (faster-whisper + Piper). It is not wired into the web/mobile backend yet (confirmed: no reference to `virtual-doctor` anywhere in `backend/src`).

**What is working:** The safety layer (`chatbot/nlu/safety.py`) is deterministic, regex-based, and — as of this session — has had two confirmed false-positive bugs fixed and one product-policy gap closed, all under direct test coverage. The turn-based voice pipeline (STT/TTS) is production-quality in its narrow scope: real timeout handling, real device fallback (CUDA→CPU), real caching, real language-specific model sizing based on measured WER data. The RAG pipeline over the ingested textbook is a well-instrumented, cache-aware, fail-soft dense retriever. `db.py`'s connection pool now has a command timeout (added this session).

**Biggest gaps:** (1) There is no streaming, no WebSocket layer, no VAD-based barge-in, and no partial-transcript handling anywhere — the voice pipeline is strictly record-full-clip → transcribe → reply → synthesize-full-reply, which is not yet a "voice assistant" in the interruptible, real-time sense the product goal describes. (2) The clinical conversation engine's *patient state* has no structured fields for medications, allergies, past medical history, or risk factors — only free-text `chief_complaint_description` plus a fixed, complaint-agnostic set of slot keys (duration/severity/location/character/radiation/triggers/associated_symptoms). (3) `ai-service`'s FastAPI app has **no authentication/authorization at all** (`CORSMiddleware(allow_origins=["*"])`, no auth dependency on any route) and Virtual Doctor sessions are looked up by `session_id` alone with no ownership check — a real risk once this is exposed beyond a trusted internal network. (4) The chatbot layer (`chatbot/main.py`'s `/chat`) and the Virtual Doctor layer are two entirely separate NLU stacks that don't share code, meaning any future "smart voice doctor" work has to decide which one it's building on rather than extending both.

**Is the project ready for voice features now, or does it need architecture work first?** Basic turn-based voice (record → transcribe → LLM turn → synthesize → play) can be built today by wiring the *already-existing* `/virtual-doctor/transcribe` and `/virtual-doctor/speak` endpoints into a client — that part is genuinely ready. **Real-time streaming voice with barge-in is not ready** and needs new architecture (a WebSocket/streaming layer, a VAD component, cancellation plumbing through the whole turn pipeline) before it can be built safely. The clinical reasoning engine needs a patient-state redesign (Section 6) before it can honestly be called "dynamic, patient-specific" rather than "a fixed slot list per complaint category."

---

## 2. Current Architecture

### Main modules
- `chatbot/main.py` — FastAPI app, the legacy/production chatbot surface. Routes: `GET /health`, `POST /chat`, `POST /triage`, `POST /drug-interactions`, `POST /prescription-check`, `POST /summarize`. Mounts `virtual_doctor.router` under `/virtual-doctor`.
- `chatbot/nlu/` — normalization, synonym resolution, tokenization, intent classification, ranking, entity linking, slot filling, safety. Self-contained, JSON-data-driven (`intents.json`, `medical_entities.json`, `arabic_synonyms.json`, `medical_synonyms.json`, `palestinian_dialect.json`).
- `chatbot/medical/` — rule-based `SymptomSpecialtyEngine` (DB-backed triage), `DrugInteractionMatcher` (DB-backed), `DocumentExtractor` (OCR), `ReportSummarizerLLM` (Ollama-backed).
- `rag/retriever.py` — **not a retriever.** A pure function that maps extracted entities into a structured JSON "context" dict describing what the (separate) Node backend is expected to have already found. No embeddings, no vector search, no DB call.
- `rag/ingest_book.py` — offline CLI script; the *only* place embeddings are actually produced (chunks a PDF textbook, embeds via Ollama `nomic-embed-text`, batch-inserts into `medorbit.medical_knowledge`).
- `virtual_doctor/` — the newer subsystem: `interview_engine.py` (turn orchestration + safety short-circuit), `planner.py` (StaticPlanner JSON-flow + LLMPlanner dynamic questioning), `reasoning.py` (final differential/urgency synthesis), `retrieval.py` (the *real* RAG: dense vector search over `medical_knowledge`), `memory.py` (transcript read model), `report_generator.py` (PDF report), `voice/stt.py` + `voice/tts.py` (faster-whisper / Piper), `router.py` (FastAPI routes), `schemas.py` (Pydantic request/response models).
- `llm/llm_service.py` — the `/chat` endpoint's LLM call (single Ollama `/api/generate` call, template-selected system prompt by "context type", fail-soft fallback replies).
- `db.py` — single `asyncpg` pool singleton, `command_timeout=10` (added this session), schema fixed via `search_path` on every checkout.
- `tests/` — 353 unittest-based tests across 7 files (see Section 2's "Tests" subsection).

### Request flow — `/chat` (chatbot layer)
```
POST /chat → ChatRequest
  → special-flow branch (drug_check / report_summary)? handled inline, returns early
  → MedicalSafetyLayer.check(message)  [emergency bypass point #1]
  → IntentClassifier.classify(message, context)
      → safety.check() again (bypass point #2, same regexes, redundant call)
      → tokenize → synonym-resolve → keyword match → regex patterns
      → Step 9: "emergency" intent keyword override (bypass point #3, independent
        of safety.py — this is the mechanism this session's Cluster I/I2 work
        had to patch separately from safety.py)
      → ranking (IntentRanker, score-sum normalization, tie-break by dict order)
  → EntityExtractor.extract(message, context)
  → SlotFiller.update_state(...) [unbounded in-memory dict, keyed by hash(message) — see Section 12]
  → rag.retriever.retrieve_context(message, entities)  [JSON context builder, NOT retrieval]
  → response_source decision: RULE (canned small-talk) / RAG-label (find_nearest etc.) / LLM
  → llm_service.generate_response(...)  [single Ollama call, 60s timeout]
  → ChatResponse
```
**Note:** there are literally three independent places emergency detection can fire in this one request (`safety.check()` called twice with identical patterns, plus classifier.py's own keyword-based override). This redundancy is safety-conservative (more chances to catch a real emergency) but architecturally confusing and was the direct cause of two separate, hard-to-find bugs fixed this session (Cluster E's regex bugs, Cluster I/I2's policy exemption needing two independent patches).

### Virtual Doctor flow
```
POST /virtual-doctor/start → creates session row, returns greeting (name-intake phase)
POST /virtual-doctor/message → interview_engine.handle_message():
  → pool.fetchrow(session by session_id)  [no ownership/auth check]
  → _check_safety(message, lang)  [same MedicalSafetyLayer, raw+normalized text, worse-of-two]
     → emergency/urgent: short-circuits, persists, returns — planner never runs
  → EntityExtractor.extract(message)
  → _build_turn_context(): asyncio.gather(memory.load_recent(), retrieval.retrieve_for_turn())
     — parallelized this session (RAG Performance batches R1-R3); independent
       per-branch degradation on failure (deliberately, per this session's work)
  → _run_planner(): LLMPlanner.plan() with PlannerError fallback to StaticPlanner
     — LLMPlanner: qwen2.5:3b via Ollama /api/chat, JSON mode, RAG-grounded,
       language-drift-guarded (CJK rejection, coherence check, one strict retry)
     — StaticPlanner: fixed JSON flow per complaint (5 complaints + generic),
       deterministic slot order, no LLM call
  → if ready_for_diagnosis: reasoning.run_reasoning()
     — asyncio.gather(symptom_engine.match(), retrieval.retrieve_for_profile())
     — qwen2:7b via Ollama /api/chat, JSON mode, same language-drift guards
     — _more_urgent(): rule-engine urgency can only be escalated by the LLM,
       never downgraded — the single most safety-critical line in this codebase
  → pool.execute(persist session) → _log_message(persist turn) → MessageResponse
GET /virtual-doctor/session/{id} → current state
POST /virtual-doctor/report/{id} → PDF via isolated subprocess (pdf_worker.py)
POST /virtual-doctor/transcribe → faster-whisper (turn-based, full clip)
POST /virtual-doctor/speak → Piper (turn-based, full reply)
```

### RAG flow (real one — `virtual_doctor/retrieval.py`)
```
utterance + chief_complaint → build_turn_query() [anchors with English clinical
  terms + inferred topic lexicon, since corpus is an English textbook and
  nomic-embed-text is a weak cross-lingual matcher]
→ cache check (TtlLruCache, query→chunks, TTL 900s)
→ embed() [Ollama nomic-embed-text, cached, no TTL — embeddings are pure functions]
→ _search() [pool.fetch, cosine_similarity() SQL function over REAL[] columns
  — no pgvector in this Postgres image]
→ threshold filter (RAG_MIN_SCORE=0.60, empirically tuned)
→ format_context() [numbered, cited passages: "[1] (p. 59) ..."]
```
This is Naive/dense RAG with hand-tuned query anchoring and a static confidence gate — no reranking, no hybrid keyword search, no HyDE, no graph structure. It only covers one ingested textbook (`Macleods Clinical Examination`).

### LLM/Ollama flow
Three independent call sites, all direct `requests.post` to Ollama (wrapped in `asyncio.to_thread` as of this session's RAG Performance batch R1): `llm/llm_service.py` (`/api/generate`, chatbot `/chat`), `virtual_doctor/planner.py` (`/api/chat`, qwen2.5:3b, JSON mode), `virtual_doctor/reasoning.py` (`/api/chat`, qwen2:7b, JSON mode). No shared client, no shared retry policy, no streaming anywhere.

### Database/memory flow
Single `asyncpg` pool (`db.py`), `min_size=2, max_size=10, command_timeout=10`. Virtual Doctor session/message tables are the *only* persistent conversation memory — no separate vector-indexed patient memory, no cross-session patient history linkage found.

### Safety flow
`MedicalSafetyLayer.check()` (regex-based, deterministic) runs first in both the chatbot and Virtual Doctor flows. As of this session: the false-positive `" Cardi"` and `"سم "` regex bugs are fixed, and an approved "informational ER-place query" exemption is implemented **independently in two places** (`safety.py` and `classifier.py`'s own Step 9 override) because they are architecturally separate mechanisms — flagged as a maintenance risk in Section 7.

### Tests currently present
| File | Focus |
|---|---|
| `test_nlu_pipeline.py` | ~190 tests: normalizer, synonyms, tokenizer, safety layer, intent classifier, entity extractor, slot filler, context resolver, ranker, full pipeline, latency budgets |
| `test_emergency_localization.py` | Palestinian Red Crescent / 101 localized emergency copy, chatbot vs. Virtual Doctor consistency |
| `test_characterization_batch_a.py` | `db.py`, `synonyms.py`, `report_generator.py` import behavior, `llm_service.py` fallback paths (all mocked, no real DB/network) |
| `test_characterization_rag_phase0.py` | `virtual_doctor/retrieval.py`, `memory.py`, `planner.py`, `reasoning.py`, `interview_engine.py` fail-soft/fallback behavior (mocked Ollama/DB) |
| `test_characterization_cluster_a.py` / `_b.py` / `_e.py` | Classifier keyword-collision fixes, dialect-corruption fixes, safety-regex fixes — the bulk of this session's regression protection |

**Total: 353 tests, 0 failures, 0 errors** (verified by direct run for this audit).

---

## 3. What Already Works Well

- **The full test suite is green and characterizes real behavior, not aspirational behavior.** Several test files (`test_characterization_*`) exist specifically to pin exact current outputs (including known quirks) before/after each fix, which is a genuinely good practice already established — worth continuing for any voice work.
- **Medical safety is deterministic and now well-covered.** No LLM is in the emergency-detection path; regex-based detection runs first, has direct test coverage for both true positives and previously-confirmed false positives, and the Virtual Doctor flow's `_more_urgent()` escalate-only merge is a correct, load-bearing safety invariant with its own test.
- **RAG in Virtual Doctor is fail-soft by design and well-instrumented.** Every retrieval/embedding failure mode degrades to an empty context rather than raising or blocking; caching is deliberate and correctly bounded (`TtlLruCache`, unlike some unbounded caches elsewhere in the chatbot layer).
- **Async correctness improved substantially this session.** Blocking `requests.post` calls in `planner.py`/`reasoning.py` are now off the event loop (`asyncio.to_thread`), and independent I/O (`memory.load_recent()` + `retrieval.retrieve_for_turn()`, and `symptom_engine.match()` + `retrieval.retrieve_for_profile()`) now run concurrently via `asyncio.gather`, with an explicit, tested decision about per-branch failure semantics.
- **The StaticPlanner fallback is a real safety net, not decoration.** Any LLM failure (timeout, malformed JSON, wrong-language output, off-vocabulary complaint) degrades *for that turn only* to a deterministic JSON-flow question — confirmed by direct code reading and by `PlannerError` handling in `interview_engine._run_planner`.
- **The STT/TTS implementations already handle real production concerns**: CUDA/CPU fallback with measured per-language model sizing, a hard transcription deadline that can't wedge the single-worker executor, write-then-rename TTS disk caching (crash-safe), and status endpoints that let a client warn the user before a slow first load.
- **Voice-specific "language pinning"** — `StartResponse.language` is echoed back so the client can force STT to the session's language instead of re-detecting on every short answer — is a subtle but correct design choice already in place.

---

## 4. Current Medical Voice Assistant Readiness

**Is the current system already a voice doctor? No.** What exists is a **turn-based, non-streaming voice-enabled text consultation**: a client can record a full audio clip, POST it to `/virtual-doctor/transcribe`, get text back, send that text to `/virtual-doctor/message`, get a text reply, POST that reply to `/virtual-doctor/speak`, and play the resulting WAV. This works today, end to end, with no missing server-side piece for that exact flow.

**What is missing for a real voice doctor** (i.e., a live, interruptible spoken conversation):

| Capability | Status |
|---|---|
| STT | **Implemented** (faster-whisper, turn-based, full-clip only) |
| TTS | **Implemented** (Piper, turn-based, full-reply only) |
| VAD | **Partially implemented** — faster-whisper's own `vad_filter=True` trims silence around a single already-recorded clip; there is no standalone, real-time VAD component for detecting speech start/end in a live audio stream |
| WebSocket/streaming | **Not implemented** — confirmed via repo-wide search; every endpoint is standard FastAPI request/response over HTTP |
| Audio session state | **Not implemented** — no concept of an in-progress recording session distinct from the text conversation session |
| Barge-in (interrupting TTS playback) | **Not implemented** — no mechanism exists to cancel an in-flight TTS synthesis or signal a client to stop playback |
| Cancellation | **Partially implemented** — STT has a cooperative internal deadline (`TRANSCRIBE_TIMEOUT`) so a stuck transcription can't wedge the worker forever, but there is no way for a *client* to cancel an in-flight request (no request-scoped cancellation token reaches the Ollama calls, for instance) |
| Duplicate message prevention | **Not implemented** — `interview_engine.handle_message()` has no idempotency key; a retried/duplicated client POST would be processed as two separate turns |
| Transcript confidence handling | **Partially implemented** — `TranscriptionResponse` returns `language_probability` and a `timed_out` flag, but there is no confidence-based UX path (e.g., "I didn't catch that clearly, could you repeat?") wired into `interview_engine` — the transcript is used as-is regardless of confidence |

---

## 5. Clinical Conversation Engine Audit

Inspected: `virtual_doctor/interview_engine.py`, `planner.py`, `reasoning.py`, the 6 static flow JSON files, `schemas.py`.

| Capability | Supported? | Detail |
|---|---|---|
| Dynamic question selection | **Partially** | `LLMPlanner` asks a genuinely different next question based on conversation state (via a qwen2.5:3b call grounded in RAG passages + "already established" findings) — this is real dynamic behavior, not templated. But it is capped at `MAX_INTERVIEW_TURNS=6` clinical questions and falls back to the fully static, complaint-agnostic-slot-order `StaticPlanner` on any LLM failure. |
| Complaint-specific questions | **Partially** | 5 static flows exist (`chest_pain`, `headache`, `abdominal_pain`, `fever_cough`, `rash`) plus `generic` — real complaint-specific branching, but only for those 5 categories, and only in the *static* fallback path. The dynamic `LLMPlanner` is grounded in the complaint via `COMPLAINT_ANCHORS`/RAG, but its actual question content is model-generated, not from a curated complaint-specific question bank. |
| Patient state | **Minimal** | `patient_profile` (JSONB) holds `name`, `age`, `chief_complaint_description`, and whatever keys appear in `KNOWN_FINDING_KEYS` (`duration, severity, location, location_character, character, radiation, triggers, appearance, exposure, associated_symptoms`) plus an `other` catch-all dict and `associated_symptoms_detected` (from the entity extractor). **No dedicated fields for sex, medications, allergies, past medical history, or risk factors exist anywhere in the schema or the planner's known-finding vocabulary.** |
| Red flag detection | **Yes, but upstream of the planner** | `MedicalSafetyLayer` runs before the planner on every turn and short-circuits the whole interview if triggered — the planner itself has no red-flag awareness of its own; it simply never sees a flagged turn. |
| Differential diagnosis | **Yes** | `reasoning.run_reasoning()` produces a genuine LLM-generated differential (2-4 conditions with likelihood), combined with a DB-backed rule-engine urgency/specialty via `SymptomSpecialtyEngine`, with the escalate-only merge described in Section 3. |
| Next-best-question logic | **Partially** | The dynamic planner has a real "readiness" gate (a *separate*, minimal LLM call — deliberately split out after direct A/B testing showed a combined call collapsed readiness detection to 0%) that decides when enough information has been gathered, gated on `COMPLETENESS_MIN_FINDINGS`/`COMPLETENESS_MIN_TURNS`. This is genuine next-best-question logic, but it optimizes for "enough to stop," not explicitly for "highest information-gain question next" — there's no scoring of candidate questions against missing high-value fields (sex/meds/allergies/risk factors, none of which exist as fields at all — see above). |
| Structured state updates | **Yes** | Each turn's `profile_updates` are merged into the JSONB profile deterministically; both planners return the same `PlannerResult` shape, so the engine's persistence logic is planner-agnostic. |
| Avoiding repetitive generic questions | **Yes, with a specific, tested mechanism** | `_is_repeat()` compares a candidate question against `asked_questions` via normalized token-overlap (threshold 0.6, deliberately tuned via direct A/B testing documented in the code) — a real, working anti-repetition guard, not just a prompt instruction. |

### Gaps identified
1. **No structured fields for medications, allergies, past medical history, sex, or risk factors** — the product goal explicitly lists these as required next-question inputs, and none of them exist in `KNOWN_FINDING_KEYS`, the profile schema, or the LLM prompt's "already established" summary beyond whatever lands in the unstructured `other` catch-all.
2. **The LLM planner has no explicit missing-high-value-information scoring** — readiness is a binary "enough vs. not enough" gate, not a ranked "ask about X next because it's the highest-value unknown" mechanism.
3. **Complaint-specific coverage is narrow (5 complaints)** — any complaint outside chest pain/headache/abdominal pain/fever+cough/rash falls to the fully generic flow, both statically and (implicitly) in how RAG anchors are built (`COMPLAINT_ANCHORS` only has entries for those same 5 + generic).
4. **The two planners' "clinical intelligence" lives in different places** — the static flow's clinical logic is the JSON files' slot order; the dynamic planner's is entirely inside an LLM prompt. There's no shared, inspectable clinical rule set both paths draw from.

---

## 6. Patient State and Memory Audit

**A. Medical knowledge** — `medorbit.medical_knowledge` (one ingested textbook, chunked, embedded via `nomic-embed-text`, `REAL[]` columns, cosine similarity via a Postgres function). Static, offline-ingested, shared/global (not patient-specific). No update path exists other than re-running `rag/ingest_book.py`.

**B. Patient-specific memory** — `virtual_doctor_sessions.patient_profile` (JSONB, one row per consultation session). This is genuinely per-*session*, not per-*patient*: there is no evidence of a persistent, cross-session patient record (e.g., "this patient had a prior consultation for chest pain last month") — each session starts with an empty profile. `user_id` is accepted at `/virtual-doctor/start` but not used to load any prior history.

**C. Conversation history** — `virtual_doctor_messages` (role, text, timestamp, per-session). Read via `memory.load_recent()` (windowed, `HISTORY_LIMIT=12`, `MAX_MESSAGE_CHARS=600` per message) for per-turn context, and `memory.load_recent(limit=FULL_HISTORY_LIMIT=50)` for the final diagnosis pass. No vector index over history — pure recency-windowed SQL read. Ordering caveat documented in code: no monotonic sequence column, ordered by `created_at` only (a known, accepted limitation, not a bug).

**D. Clinical state** — the `patient_profile` JSONB *is* the clinical state, plus `phase`, `chief_complaint`, `urgency_level`, `recommended_specialty_id`, `differential` (JSONB) as separate session-row columns. There is no separate "clinical state machine" object distinct from this profile — phase transitions (`intake` → `greeting` → `interviewing` → `reasoning` → `complete`) are tracked as a plain string column.

### What needs redesign
The core gap is that **"patient-specific memory," "conversation history," and "clinical state" are currently all conflated into one per-session JSONB blob** with no schema beyond a flat key set tuned for the static flow's original slot list. There is no distinction between:
- facts that should persist *across* sessions for a returning patient (allergies, chronic conditions, current medications),
- facts that are *this consultation's* working state (current complaint's duration/severity/etc.), and
- facts that are purely *derived* (differential, urgency, recommended specialty).

### Recommended future state shape (recommendation only — not implemented)
```
PatientRecord (cross-session, keyed by user_id — does not exist today):
  demographics: { age, sex, ... }
  known_allergies: [...]
  active_medications: [...]
  chronic_conditions: [...]
  risk_factors: [...]

ConsultationState (per-session, replaces today's flat patient_profile):
  chief_complaint: str
  onset/duration/severity/character/radiation/triggers/associated_symptoms: (as today)
  red_flags_checked: [...]           # explicit, not implicit via safety.py side-effect
  missing_high_value_fields: [...]    # drives next-best-question selection
  confidence_per_field: { field: float }  # ties into STT confidence, Section 4

ConversationTurn (unchanged in spirit, today's virtual_doctor_messages):
  role, text, timestamp, extracted_entities
```
This is a recommendation for future design discussion, not a schema to implement now — it would require new tables/columns and is out of scope for this audit.

---

## 7. Medical Safety Audit

Inspected: `chatbot/nlu/safety.py`, `chatbot/intent/classifier.py` (Step 3 and Step 9), `virtual_doctor/interview_engine.py::_check_safety`, `virtual_doctor/reasoning.py::_more_urgent`.

- **Emergency detection**: regex-based (`EMERGENCY_PATTERNS_AR`, a mixed Arabic/English list despite the name), runs deterministically, no LLM involved. As of this session, two confirmed false-positive bugs are fixed (a broken `" Cardi"` fragment that flagged "cardiologist" as an emergency; a missing word boundary on `"سم "` that flagged any word ending in those two letters — "name," "body," "fee" — as poisoning) and both are under direct regression test.
- **Urgent detection**: separate `URGENT_PATTERNS_AR` list, checked only if no emergency pattern matched — unchanged by this session's work, not separately audited for false positives here (out of this session's approved scope).
- **False positive prevention**: now meaningfully better than at the start of this engagement, but the *mechanism* for preventing false positives (narrow, hand-written exemptions for specific known-bad patterns) is reactive, not systematic — future false positives would need to be found the same way these were (via failing tests), not via any general safeguard.
- **Refusal/escalation behavior**: emergency detection **escalates** (directs to Red Crescent/101, localized to Nablus/West Bank) rather than refusing outright — appropriate for a triage assistant.
- **Whether the LLM can bypass safety**: **No, by construction.** In both the chatbot and Virtual Doctor flows, the safety check runs and can short-circuit *before* any LLM is ever called for that turn. `reasoning.py`'s `_more_urgent()` additionally ensures that even when the LLM *is* involved (final differential), it can only escalate the rule-engine's urgency, never downgrade it — confirmed by direct test (`test_llm_cannot_downgrade_rule_engine_emergency`, etc.).
- **Whether RAG content is treated as untrusted**: **Yes, functionally** — retrieved textbook passages are injected as "MEDICAL CONTEXT" into the LLM prompt with an explicit instruction not to hallucinate beyond it, but there is no separate validation step that checks the LLM's output against the retrieved text after generation (i.e., trust is enforced by prompt instruction, not by a post-hoc grounding check).
- **Remaining risks**:
  1. **Two independent emergency-override mechanisms exist by construction** (`safety.py`'s regex layer and `classifier.py`'s Step 9 keyword-based override, which duplicates `intents.json`'s own `"emergency"` intent keywords). This session had to patch the same policy decision in *both* places (Cluster I and Cluster I2) because they don't share logic — any future safety-pattern change must remember to check both.
  2. `URGENT_PATTERNS_AR` was not re-audited this session and may contain similar unguarded substring patterns to the ones found and fixed in `EMERGENCY_PATTERNS_AR` — not confirmed either way, flagged as an open question.
  3. No systematic false-positive test corpus exists beyond the specific cases discovered ad hoc this session — see Section 14 for a proposed evaluation approach.

---

## 8. RAG Audit

**Is it real retrieval or structured context only?** Both exist, and it is important not to conflate them:
- `rag/retriever.py` (used by `/chat`) is **structured context only** — no embeddings, no vector search, zero database calls. It builds a JSON dict describing what the caller (a separate Node backend) is expected to have already found via its own search.
- `virtual_doctor/retrieval.py` is **real retrieval** — dense vector search over `medorbit.medical_knowledge`.

**Where real retrieval happens:** exclusively inside `virtual_doctor/`, via `retrieval.retrieve()` → `_search()` → `pool.fetch(... cosine_similarity(embedding, $1::real[]) ...)`.

**Data source assumptions:** a single, offline-ingested textbook (`Macleods Clinical Examination, 14th Edition`). No live document ingestion pipeline, no per-clinic or per-patient documents, no citation to anything other than this one source.

**Chunking quality:** sliding-window, character-based (1000 chars, 200 overlap), with clean-boundary preference (paragraph → sentence → space → hard cut) — reasonable for prose, not semantically aware (no section/heading awareness, so a chunk can span unrelated subsections).

**Metadata:** `source`, `chunk_index`, `page_start`, `page_end`, `embedding_dim`, `embedding_model`, `content_hash` — enough for citation and resumable re-ingestion, no clinical metadata (e.g., "this passage is about pediatric dosing" tagging).

**Embeddings:** `nomic-embed-text` via Ollama, stored as `REAL[]` (no pgvector in this Postgres image — a documented, deliberate constraint, not an oversight), similarity via a hand-written `cosine_similarity()` SQL function.

**Query construction:** hand-tuned anchoring (`COMPLAINT_ANCHORS` + `TOPIC_LEXICON` substring matching) to compensate for the embedder's weak cross-lingual matching — measured and documented in code (raw Arabic utterances scored 0.48-0.52 against the corpus, below the 0.60 floor, until anchoring lifted real cases to 0.68-0.78).

**Reranking:** none.

**Grounding:** prompt-level only ("diagnose strictly based on the provided Medical Context... do not hallucinate") — no automated post-generation check that the LLM's claims are actually supported by the retrieved text.

**Hallucination controls:** the `_more_urgent()` escalate-only merge (Section 7) is the main *safety-relevant* hallucination control; there is no general factual-grounding verifier.

**Security risks:** none of the retrieved content is user-supplied (it's a fixed, offline-ingested textbook), so classic RAG document-injection risk (a malicious document poisoning future answers) is low *today* — but this would change immediately if any future work adds live/user-uploaded document ingestion, which the architecture does not currently guard against (no sanitization/provenance-tagging layer visible for a hypothetical future ingestion path).

### Proposed improvements (each with justification and a measurement plan — not blind technology additions)
| Improvement | Why | How to measure |
|---|---|---|
| Reranking (cross-encoder or LLM-judge rerank of top-K before use) | Current retrieval is pure dense similarity with no second-pass relevance check; the 0.60 threshold was tuned on only 5 complaints × 2 languages | Precision@K on a held-out labeled query set (Section 14) before/after |
| Post-generation grounding check | Currently trust is prompt-only; a differential citing a condition not actually supported by the retrieved passage would not be caught | "Citation correctness" metric (Section 14): sample differentials, manually verify each cited page actually supports the claim |
| Broader corpus / multi-source ingestion | Single textbook limits coverage severely — any complaint outside its scope gets an ungrounded LLM answer with no visible signal to the clinician that it was ungrounded | Track "empty retrieval" rate per complaint category in production logs (requires Section 13's observability work first) |

---

## 9. Ollama / LLM Audit

**Model calls:** three independent call sites (Section 2). No shared HTTP client, no shared config, no shared retry logic between them.

**Timeouts:** `llm_service.py` — 60s. `planner.py` — `VD_PLANNER_TIMEOUT` (default 25s). `reasoning.py` — hardcoded 60s. All explicit, none infinite.

**Async/blocking behavior:** fixed this session — all three now wrap `requests.post` in `asyncio.to_thread`, so a slow Ollama call no longer blocks the event loop for other concurrent requests.

**Streaming support:** **none.** All three call sites use `"stream": False`. This is consistent with the current turn-based product but is a hard blocker for any "the assistant starts speaking before the full response is generated" UX.

**Structured output handling:** `planner.py`/`reasoning.py` use Ollama's `"format": "json"` mode plus a hand-written `_extract_json()` fallback (regex-extract a `{...}` span if direct `json.loads` fails) — reasonably robust. `llm_service.py`'s `/chat` path is free-text, no structured output.

**Fallback behavior:** every call site fails soft — `llm_service.py` returns a canned reply string per failure type (timeout/connection/other); `planner.py` raises `PlannerError` → `StaticPlanner` fallback; `reasoning.py` returns a templated fallback dict on unparseable/wrong-language output after one strict retry.

**Concurrency risks:** all three call sites can run concurrently across different requests (no global lock), but they compete for the *same* Ollama server's GPU/CPU. `retrieval.py`'s code comments document real measured contention (loading `qwen2:7b` evicts the embedding model, a 0.067s→4.85s regression) and mitigate it for the embedding path specifically (pinned to CPU, `keep_alive` tuning) — the same contention risk is not documented as solved for the *planner vs. reasoning* model pair (`qwen2.5:3b` vs `qwen2:7b`), only worked around by warming the planner model in the background after reasoning finishes (`interview_engine.py`'s `planner.warm()` fire-and-forget call).

**Model config:** `MODEL_NAME`/`OLLAMA_MODEL` (`llm_service.py`, default `qwen2:7b`), `VD_PLANNER_MODEL` (default `qwen2.5:3b`), `reasoning.py` reuses `OLLAMA_MODEL`. All env-overridable.

**Latency risks:** documented in code comments with real measurements (e.g., `medium` Whisper on CPU: ~3s per utterance vs ~0.6s on CUDA; a full `qwen2:7b` cold load: ~7.48s vs ~1.8s warm) — the team clearly already benchmarks this, but no automated latency regression test exists (see Section 14).

**Benchmark gaps:** no repeatable, automated benchmark suite for LLM latency/throughput under concurrent load — the measurements found in code comments appear to be one-off manual tests, not CI-tracked.

---

## 10. STT/TTS/Voice Architecture Gap Analysis

The current implementation (Section 4) covers turn-based STT/TTS well. What follows is the architecture needed for the streaming/interruptible version described in the product goal — **design only, not implemented**:

- **STT pipeline (streaming)**: would need a persistent audio ingestion channel (WebSocket) feeding fixed-size frames into a streaming-capable decoder. `faster-whisper` as currently used decodes a complete, already-uploaded clip — moving to streaming requires either chunked incremental decoding (non-trivial with Whisper's architecture, which is not natively streaming) or a sliding-window "record N seconds, decode, continue" approach with careful boundary handling so words aren't cut mid-utterance.
- **TTS pipeline (streaming)**: Piper synthesizes a full WAV per call today; streaming playback would need sentence/clause-level chunked synthesis so playback can start before the full reply is generated — requires the LLM call itself to be streamed first (Section 9's biggest gap), since TTS can't start on text that hasn't been generated.
- **VAD**: needs a dedicated, real-time component (e.g., Silero VAD — already a transitive dependency of the current voice stack per `requirements-voice.txt`'s comments, but not used directly by any code in this repo today) to detect speech start/end in a live stream, distinct from faster-whisper's post-hoc silence trimming.
- **Streaming**: requires a WebSocket (or gRPC/SSE) layer that does not exist anywhere in this codebase today — this is the single largest missing architectural piece for the full product goal.
- **Barge-in**: requires (a) the VAD/streaming layer to detect the patient starting to speak while TTS is playing, (b) a cancellation signal that reaches the in-flight TTS synthesis and/or tells the client to stop playback, and (c) a decision about what happens to the just-interrupted assistant turn (discard vs. resume vs. treat as answered). None of this exists; the interview engine's turn model assumes one full request/response per turn.
- **Cancellation**: STT already has an internal cooperative deadline (Section 4); this needs to be generalized so a client-initiated cancel (e.g., patient interrupts) can propagate through `interview_engine.handle_message()` → planner/reasoning Ollama calls, which currently have no cancellation token wired through them.
- **Audio session state**: needs a new concept distinct from the text `session_id` — e.g., is the mic currently open, is TTS currently playing, is a barge-in currently being processed — none of which the current `MessageRequest`/`MessageResponse` schema models.
- **Partial transcripts**: requires streaming STT (above) to emit incremental hypotheses; not meaningful without it.
- **Transcript confidence**: `language_probability` already exists in `TranscriptionResponse` (Section 4) but per-word/segment confidence from faster-whisper is not currently surfaced, and nothing consumes the existing confidence signal today.
- **Medication/dose confirmation**: no existing mechanism anywhere in the codebase for explicit read-back confirmation of high-stakes spoken values (a dose, a medication name) — this is a genuine new requirement, not a gap in an existing partial implementation.
- **Arabic dialect support**: STT already has documented, measured per-language model sizing specifically because Arabic accuracy was found to be the bottleneck (Section 3) — this is a real strength to build on. The NLU layer's Palestinian-dialect normalization (`chatbot/nlu/data/palestinian_dialect.json`, extensively hardened this session) is chatbot-layer only; it is **not** currently connected to the Virtual Doctor flow's entity extraction in a way that was verified during this audit — worth explicit confirmation before assuming dialect coverage carries over.
- **Medical terminology risk**: Whisper is a general-purpose ASR model with no medical-vocabulary fine-tuning or prompt-based term-boosting in the current integration (`_transcribe_sync` passes no `initial_prompt`) — a genuine risk for drug names and clinical terms, not yet mitigated anywhere.

---

## 11. Security and Privacy Audit

- **Patient data isolation**: `virtual_doctor_sessions`/`_messages` are scoped by `session_id` (a UUID) with no ownership/auth check found anywhere in `router.py` or `interview_engine.py` — any caller who knows or guesses a `session_id` can read/write that consultation. UUIDs are hard to guess, but this is **not** the same as an enforced authorization boundary.
- **Authorization boundaries**: **none exist in `ai-service` itself.** `chatbot/main.py`'s FastAPI app has `CORSMiddleware(allow_origins=["*"])` and no auth dependency on any route, including Virtual Doctor's. Confirmed via direct code reading, not inferred. This may be intentional today (an internal-only service behind a trusted backend), but that assumption was not found written down anywhere and should be confirmed (Section 18).
- **Cross-user retrieval risk**: the RAG corpus itself (`medical_knowledge`) is global, shared textbook content with no tenant/user scoping needed. The real cross-user risk is the session-ownership gap above, not RAG document leakage.
- **Logs and PHI**: `db.py`, `retrieval.py`, and the LLM service modules log operational metadata (model names, timings, cache hit/miss) but this audit did **not** find evidence of raw patient message text or full transcripts being logged at INFO level in the reviewed files — worth a dedicated grep-based confirmation before voice work begins, since STT will introduce a new raw-audio-adjacent data path.
- **Prompt injection**: patient free-text is interpolated directly into LLM prompts (planner/reasoning) with no sanitization beyond the existing safety-pattern checks — a patient could in principle attempt to inject instructions into their "answer." The safety-critical parts of the system (emergency detection, urgency escalate-only merge) run outside the LLM's control, which limits the blast radius of a successful injection, but this was not stress-tested in this audit.
- **RAG document injection**: low risk today (fixed, offline-ingested corpus, no live ingestion path) — see Section 8.
- **Secrets/env**: `db.py` loads `.env` from the project root; `DB_PASSWORD` defaults to an empty string if unset (a footgun for misconfiguration, not a code vulnerability per se). No hardcoded secrets found in the files reviewed for this audit.
- **File/audio storage**: TTS output is cached to disk (`virtual_doctor/generated/tts/*.wav`, content-hash-keyed) with no expiry/cleanup mechanism found — grows unbounded over time. PDF reports are similarly written to `virtual_doctor/generated/reports/` with no retention policy found. Uploaded audio for STT is processed in-memory and not persisted to disk by the code reviewed (confirmed in `stt.py` — decoded via `io.BytesIO`, never written to a file).
- **Retention policy gaps**: no retention/deletion policy found anywhere for session transcripts, TTS cache files, or generated PDF reports — a real gap for any healthcare-adjacent product before production use.

---

## 12. Concurrency and Distributed Systems Audit

- **Async blocking calls**: the major ones (LLM HTTP calls) are fixed as of this session (`asyncio.to_thread`). STT/TTS synthesis already correctly run via `loop.run_in_executor`. `document_extractor.py` (OCR) was not re-verified for blocking behavior in this audit.
- **Shared mutable state**: `chatbot/nlu/slots.py`'s `SlotFiller.conversation_states` dict is unbounded, in-memory, keyed by `hash(message)` (not a session ID — a real design smell, since two identical messages from different users would collide) with no TTL — flagged in an earlier phase of this engagement, not yet fixed. `chatbot/nlu/entity_linker.py`'s per-instance caches are similarly unbounded.
- **Request cancellation**: no evidence of FastAPI request-cancellation propagating into any downstream Ollama/DB call in either flow — if a client disconnects mid-request, the in-flight LLM call almost certainly continues to completion server-side, wasting the resource.
- **Duplicate processing**: no idempotency key anywhere in `interview_engine.handle_message()` or `/chat` — a retried POST is processed as a brand-new turn.
- **DB connection pool**: single pool (`db.py`), `min_size=2, max_size=10`, `command_timeout=10` (added this session) — reasonable for current load, no evidence of pool-exhaustion handling/backpressure beyond asyncpg's own default queuing behavior.
- **Ollama concurrency**: no explicit concurrency limit on requests to Ollama from `ai-service` — under load, multiple simultaneous consultations would all queue on the same local Ollama instance with no visible backpressure or queuing signal returned to callers.
- **STT/TTS service failures**: both degrade gracefully at the API layer (`503 tts_unavailable`, structured `TranscriptionTimeout`/`AudioDecodeError`/`AudioTooLongError` exceptions mapped to specific HTTP statuses in `router.py`) — this is genuinely well-handled.
- **Retries/timeouts/backoff**: `rag/ingest_book.py` (offline script) has real retry-with-backoff; **none of the three live LLM call sites retry at all** — a single Ollama hiccup is one failed turn, not retried. This is a deliberate, documented tradeoff in some cases (fail-soft to the static flow) but not universally (`llm_service.py`'s `/chat` path has no fallback beyond a canned reply).
- **Graceful degradation**: strong in the Virtual Doctor flow specifically (RAG failure → empty context, LLM failure → static flow / templated output, memory failure → empty history) — this is one of the codebase's clearer strengths, not a gap.

---

## 13. Observability Audit

**Current state**: logging exists (Python `logging`, structured-ish via `%s` formatting) at INFO/WARNING/ERROR across most modules, but this audit found **no correlation IDs of any kind** — no request ID, no conversation ID propagated through log lines, no way to reconstruct "everything that happened for this one consultation turn" from logs alone without manually correlating timestamps.

**Gaps and recommendations** (all currently missing unless noted):
- **Request ID**: not present. Recommend a FastAPI middleware generating one per request, included in every log line for that request.
- **Conversation/session ID**: partially present — `session_id` appears in some log messages (e.g., planner logging) but not consistently injected as structured context across all modules touched by one turn.
- **User ID (privacy-safe)**: not present in logs (a reasonable default for PHI-adjacent data, but means production debugging can't currently be scoped to "this user's issue" without a DB lookup first).
- **Model name/version**: partially present — `reasoning.py`/`planner.py` log the model name on load/warm, not consistently on every inference call.
- **RAG query / retrieved document IDs**: partially present — `retrieval.py` logs chunk count and citation strings (`cite()` output) on both cache hit and miss, which is a genuinely good existing signal; it does not log a stable document/chunk ID separately from the human-readable citation.
- **Retrieval / LLM / STT / TTS latency**: **already measured and logged** in several places (`retrieval.py`'s `embed_ms`/`search_ms`, `planner.py`'s per-turn timing, `stt.py`'s `processing_seconds`, `tts.py`'s `synthesis_seconds`) — this is a real existing strength, just not yet aggregated into any dashboard/metrics system (no Prometheus/StatsD/OpenTelemetry integration found).
- **Token usage**: not tracked anywhere — none of the three Ollama call sites parse or log token counts from the response.
- **Structured errors**: partially present — HTTP-layer errors are reasonably structured (`HTTPException` with specific status codes and messages in `router.py`), but there's no consistent internal error-code taxonomy shared across modules.

**Explicit note per the task's constraint**: this audit does **not** recommend logging raw patient audio or full transcript text — the latency/status metadata already being logged is the right pattern to extend, not the content itself.

---

## 14. Evaluation Plan

No formal evaluation dataset or automated benchmark suite currently exists (confirmed — `tests/` contains unit/characterization tests, not a clinical/retrieval/voice quality benchmark). Proposed, not implemented:

**Clinical evaluation** — a labeled set of simulated patient scripts spanning: easy single-complaint cases (one per existing static flow: chest pain, headache, abdominal pain, fever+cough, rash), moderate cases with 2+ co-occurring symptoms, complex cases requiring several turns to reach readiness, explicit red-flag scripts (must trigger `safety.py`, zero tolerance for miss), scripts with deliberately missing information (does the planner ask for it?), scripts with internally conflicting symptom reports (does reasoning surface the conflict or silently pick one?), Arabic-dialect phrasings of the same complaints (reusing/extending `palestinian_dialect.json`'s existing vocabulary as a seed), and STT-error-injected variants (feed a known-wrong transcript and check the conversation still asks a sensible clarifying question rather than confidently proceeding on garbage).

**Retrieval evaluation** — Recall@K and Precision@K against a manually labeled set of (query, relevant-page) pairs drawn from the ingested textbook; MRR/nDCG if multiple relevant passages per query are labeled; citation correctness (Section 8) via manual spot-check that a cited page actually supports the claim made from it.

**Voice evaluation** — WER on a held-out Arabic + English audio set (ideally including Palestinian-dialect speech, given the documented FLEURS-based tuning already done); medical-term accuracy specifically (drug names, clinical terms) as a separate, stricter metric than overall WER; end-to-end turn latency (record-stop → reply-audio-start); barge-in responsiveness once implemented (time from patient speech onset to TTS playback stopping); TTS clarity (subjective MOS-style rating, since Piper's output quality was not benchmarked in this audit).

**System evaluation** — P50/P95 latency per endpoint under concurrent load; throughput (consultations/hour a single Ollama instance can sustain); error rate; RAM/VRAM usage per loaded model combination (Whisper size × Piper voice × qwen2.5:3b × qwen2:7b, since `retrieval.py`'s own comments already document real VRAM contention between models); a concurrent-request benchmark specifically targeting the Ollama-contention risk flagged in Section 9.

---

## 15. Priority Roadmap

### Phase 1 — Safety, correctness, and state foundations
**Goals:** Close the authorization gap; consolidate the two independent emergency-override mechanisms into one; add idempotency to `handle_message()`; bound `SlotFiller`'s unbounded state.
**Files likely to change:** `virtual_doctor/router.py`, `interview_engine.py`, `chatbot/nlu/safety.py` + `chatbot/intent/classifier.py` (consolidation), `chatbot/nlu/slots.py`.
**Tests to add:** session-ownership rejection tests, duplicate-turn idempotency tests, slot-state eviction tests.
**Risks:** touching the emergency-override consolidation is medical-safety-sensitive by definition (per this session's own standing rule) — needs the same explicit-approval discipline already established.
**Success criteria:** unauthorized session access rejected; a single source of truth for the ER-place exemption; no unbounded in-memory growth under sustained load.

### Phase 2 — Clinical conversation engine
**Goals:** Add structured fields for sex, medications, allergies, past medical history, risk factors to the patient-state schema (Section 6's recommendation); extend `LLMPlanner`'s "missing high-value information" awareness to those fields.
**Files likely to change:** `virtual_doctor/schemas.py`, `interview_engine.py`, `planner.py`, DB migration (outside `ai-service`, coordinate with backend owner).
**Tests to add:** characterization tests for the new fields' extraction and persistence, readiness-gate tests confirming high-value-field gaps block premature readiness.
**Risks:** schema change touches persisted data shape — needs explicit backward-compatibility handling for in-flight sessions.
**Success criteria:** a scripted consultation with a stated allergy/medication is reflected in the final report; readiness gate demonstrably waits for at least one high-value field beyond the current fixed set.

### Phase 3 — RAG quality and grounding
**Goals:** Build the retrieval evaluation set (Section 14); measure current Precision@K/Recall@K as a baseline; only then decide whether reranking or corpus expansion is justified.
**Files likely to change:** none in `ai-service` initially — this phase is measurement-first; `virtual_doctor/retrieval.py` only if measurement justifies a change.
**Tests to add:** the retrieval evaluation harness itself (new, not a unit test).
**Risks:** low — measurement work, no production behavior change until a follow-up phase acts on the results.
**Success criteria:** a documented Precision@K/Recall@K baseline exists; a specific, evidence-backed recommendation (not a guess) for whether reranking is worth its complexity.

### Phase 4 — Voice pipeline: STT/TTS/VAD
**Goals:** Wire the *already-existing* turn-based STT/TTS into an actual client flow end-to-end (this is mostly integration work, not new `ai-service` code); add a real-time VAD component; add medical-term boosting to STT (`initial_prompt` or similar).
**Files likely to change:** `virtual_doctor/voice/stt.py` (VAD, term-boosting), new client-side integration (outside `ai-service`).
**Tests to add:** WER benchmark harness (Section 14), medical-term-accuracy subset.
**Risks:** medium — STT/TTS core is stable; VAD is new and needs its own false-positive/false-negative characterization before trusting it in a clinical context.
**Success criteria:** a live client can complete a full voice consultation turn-by-turn; measured WER on the medical-term subset meets an agreed threshold (to be set after baseline measurement).

### Phase 5 — Streaming and barge-in
**Goals:** Add a WebSocket/streaming layer; stream LLM output; stream TTS synthesis; implement barge-in cancellation.
**Files likely to change:** new module (`virtual_doctor/voice/stream.py` or similar), `router.py`, `llm_service.py`/`reasoning.py`/`planner.py` (streaming Ollama calls), `interview_engine.py` (cancellation plumbing).
**Tests to add:** barge-in latency tests, cancellation-propagation tests, partial-transcript handling tests.
**Risks:** **highest architectural risk in this roadmap** — this is genuinely new infrastructure, not an extension of existing patterns; needs its own design review before implementation, not just an approval-gated coding batch.
**Success criteria:** measured barge-in response time under an agreed threshold; no orphaned/leaked Ollama calls after a cancelled turn (verified under load).

### Phase 6 — Observability and evaluation
**Goals:** Add request/conversation correlation IDs; aggregate the latency signals that already exist (Section 13) into a real metrics pipeline; stand up the clinical/retrieval/voice evaluation harnesses from Section 14 as repeatable, CI-trackable suites.
**Files likely to change:** new middleware, logging config, new `tests/eval/` (or similar) directory.
**Tests to add:** the evaluation harnesses themselves.
**Risks:** low — additive, no production behavior change.
**Success criteria:** any single consultation's full request path can be reconstructed from logs via one correlation ID; evaluation metrics are tracked over time, not one-off.

### Phase 7 — Scaling and production hardening
**Goals:** Concurrency limits on Ollama calls; retry/backoff on the live LLM call sites; TTS cache and PDF report retention policy; connection-pool backpressure handling.
**Files likely to change:** `llm/llm_service.py`, `virtual_doctor/planner.py`/`reasoning.py`, `virtual_doctor/voice/tts.py`, `report_generator.py`, `db.py`.
**Tests to add:** load tests, cache-eviction tests, retry-behavior tests.
**Risks:** medium — retry logic on LLM calls must not silently violate the existing "single attempt, fail-soft" safety posture without careful review (a retried planner call could double-ask a question if not idempotent).
**Success criteria:** documented, agreed retention policy is enforced automatically; measured throughput under concurrent load meets an agreed target.

---

## 16. Recommended First Implementation Batch

**Bound `chatbot/nlu/slots.py`'s `SlotFiller.conversation_states`** (Phase 1's smallest, most isolated item).

Why this one first: it is a confirmed, already-documented defect (unbounded in-memory dict, keyed by `hash(message)` rather than a session identifier, no TTL) with zero dependency on any of the bigger architectural decisions in this roadmap (voice, RAG, patient-state schema). It is small, independently testable (add a TTL/LRU eviction mechanism, write a characterization test proving old entries are evicted and active ones survive), and carries essentially no product-behavior risk — it's a memory-safety fix, not a feature change. It also establishes the exact same "characterize current behavior → fix → verify → re-run full suite" discipline this session already used successfully across every other batch, which is worth continuing before tackling anything higher-risk.

*(Per the task instructions, this is a recommendation only — not implemented in this audit.)*

---

## 17. Files Inspected

`chatbot/main.py`, `chatbot/intent/classifier.py`, `chatbot/intent/intents.json`, `chatbot/nlu/safety.py`, `chatbot/nlu/synonyms.py`, `chatbot/nlu/normalizer.py`, `chatbot/nlu/ranker.py`, `chatbot/nlu/slots.py`, `chatbot/nlu/entity_linker.py`, `chatbot/nlu/pipeline.py`, `chatbot/nlu/data/palestinian_dialect.json`, `chatbot/entities/extractor.py`, `chatbot/entities/medical_entities.json`, `chatbot/medical/symptom_engine.py`, `chatbot/medical/drug_interaction_matcher.py`, `chatbot/utils/text_normalizer.py`, `rag/retriever.py`, `rag/ingest_book.py`, `llm/llm_service.py`, `db.py`, `virtual_doctor/router.py`, `virtual_doctor/interview_engine.py`, `virtual_doctor/planner.py`, `virtual_doctor/reasoning.py`, `virtual_doctor/retrieval.py`, `virtual_doctor/memory.py`, `virtual_doctor/report_generator.py`, `virtual_doctor/schemas.py`, `virtual_doctor/voice/stt.py`, `virtual_doctor/voice/tts.py`, `virtual_doctor/flows/*.json`, `virtual_doctor/requirements-voice.txt`, `requirements.txt` (root), `tests/` (all 7 test files, by directory listing and prior direct reads), `backend/src/services/chatbot/ai-client.service.js` (integration point only, read-only). Full test suite executed: `.venv/Scripts/python -m unittest discover -s tests -v` (353 tests, 0 failures, 0 errors).

---

## 18. Open Questions

Decisions that require product/owner approval before further coding:

1. **Which STT engine for production** — continue with faster-whisper (already integrated, measured, working) or evaluate alternatives? If continuing, which model size/device tier is the production target (CPU-only deployment vs. GPU-equipped)?
2. **Which TTS engine for production** — continue with Piper (GPL-3.0 licensing note already flagged in the code itself — Section 10/`tts.py` docstring) or evaluate a non-copyleft alternative before any binary distribution?
3. **Must voice support Palestinian/Arabic dialect from day one**, or is Modern Standard Arabic + English sufficient for an initial voice launch?
4. **Is Ollama the production LLM target, or development-only?** This materially affects Phase 5's streaming work (self-hosted Ollama streaming vs. a hosted API with different streaming semantics).
5. **What medical sources are licensed/allowed for RAG ingestion beyond the current textbook?** The current corpus is one book — expanding it is a licensing question, not just an engineering one.
6. **Retention policy for audio, transcripts, TTS cache files, and generated PDF reports** — none currently exists (Section 11); this needs an explicit decision, likely with legal/compliance input given the medical context.
7. **Whether clinicians review AI-generated differentials/reports before they reach a patient**, or whether the current "decision support only, not a diagnosis" disclaimer is considered sufficient without human-in-the-loop review — this affects how much weight Phase 2/3 work should put on differential accuracy vs. transparency/citation.
8. **Whether `ai-service` will remain an internal-only, unauthenticated service behind a trusted backend, or needs its own auth layer** — Section 11's biggest open finding; the current `allow_origins=["*"]`/no-auth posture may be intentional (internal network only) but was not found documented anywhere and should be confirmed explicitly before any Phase 1 authorization work is scoped.
9. **Should `patient_profile` become cross-session (a real patient record) or remain per-consultation** — Section 6's redesign recommendation assumes cross-session memory is a goal; confirm this is actually wanted before designing for it.
