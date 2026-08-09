# Virtual Doctor Clinical Voice Assistant Improvement Plan

**Scope:** `ai-service/virtual_doctor/` (router, schemas, interview_engine, planner, reasoning, retrieval, memory, report_generator, voice/stt, voice/tts, flows/*.json), plus the reused-not-modified `chatbot/nlu/safety.py`, `chatbot/entities/extractor.py` + `medical_entities.json`, `chatbot/medical/symptom_engine.py`, and `chatbot/nlu/data/{palestinian_dialect,arabic_synonyms,medical_synonyms}.json`.

**Method:** Direct source reading of every file above (not assumed), cross-checked against the fresh, verified general architecture audit at `docs/medical_voice_assistant_audit.md` (committed the same day as this report, matches the current code exactly — treated as ground truth for architecture facts rather than re-derived). In addition, this report includes **live, executed verification** of the extractor and safety layer against the exact Arabic test phrases this task specifies (via the project's `.venv`, read-only, no files modified) — this is called out explicitly wherever a finding rests on it, so the reader can tell measured fact from static-reading inference. Phase 0 constraints observed throughout: no code, tests, or config changed; nothing staged or committed.

---

## 1. Executive Summary

**Current maturity.** The Virtual Doctor's engineering is genuinely more sophisticated than its clinical vocabulary. Underneath a working, well-instrumented turn-based voice pipeline (real STT via faster-whisper, real TTS via Piper, both with measured-and-tuned per-language model sizing) sits a two-planner interview engine: a dynamic `LLMPlanner` (qwen2.5:3b, RAG-grounded, anti-repetition guarded) that asks genuinely different questions depending on what the patient has said, with a deterministic `StaticPlanner` JSON-flow as its per-turn fallback. That part of the design is sound and is the right foundation to build on.

**Why quality is not enough yet — the core finding of this audit.** The dynamic planner is dynamic in *phrasing and ordering*, not in *clinical scope*. Every consultation is boxed into exactly 10 known finding keys (`duration, severity, location, location_character, character, radiation, triggers, appearance, exposure, associated_symptoms`) and 5 complaint categories (`headache, chest_pain, abdominal_pain, fever_cough, rash` + `generic`). There is no `sex`, `medications`, `allergies`, `past_medical_history`, `surgical_history`, `pregnancy`, or any urinary/flank/kidney-stone vocabulary anywhere in the schema, the flows, or the entity extractor. This was confirmed by direct code reading (Section 4) and then confirmed **live**: running the extractor and safety layer against this task's own Arabic test phrases (Section 15) shows `"عندي وجع بالخاصرة"` (flank pain), `"عندي جفاف وأملاح"` (dehydration/electrolytes), `"عندي حرقان بول ودم بالبول"` (dysuria + hematuria), and `"الدكتور حكالي عندي زائدة"` (doctor already said appendicitis) all extract **zero symptoms and zero safety severity** — the system has literally nothing to say about any of them beyond falling to the fully generic 3-question flow. A live-verified, previously-undocumented bug compounds this: the Palestinian-dialect layer *does* correctly recognize the very natural `"بطني بوجعني من اليمين"` ("my belly hurts, on the right") as a stomach symptom — but it maps it to the key `stomach_ache`, while `flows/abdominal_pain.json`'s `match_symptoms` only accepts `stomach_pain`. The two keys silently never match, so a real, correctly-detected right-sided abdominal complaint — the single most classic appendicitis presentation in the entire task brief — is routed to the generic flow instead of the abdominal-pain flow that actually asks about migration, fever, and vomiting (see Sections 4, 8, 15 for the full trace).

**Static vocabulary vs. dynamic phrasing — resolving the central question of this audit.** Is this a scripted assistant or a dynamic clinical assistant? **Both, in different layers.** The *conversation* is dynamic: the LLM planner reads history, avoids repeats (a real, tested token-overlap guard, not a prompt plea), and phrases a fresh question each turn. The *clinical knowledge the conversation can act on* is static and narrow: a fixed 10-field vocabulary, a fixed 5-complaint set, and a safety net (`chatbot/nlu/safety.py`) whose Arabic patterns were live-verified in this audit to miss a sudden/thunderclap headache (`"صداع شديد فجأة"`) and Arabic hematuria (`"دم بالبول"`, while the *English* pattern for the same concept — `blood in urine` — already exists), even though both are explicitly named as target red flags in this task's own brief.

**Safest path to improve it.** Do not start with streaming/architecture work (Phase 5 of the existing general audit's roadmap) — the turn-based pipeline already works end to end and streaming is the highest-architectural-risk item in that roadmap. Start instead with the cheapest, most safety-relevant, most concretely-verified gaps: closing the two live-confirmed Arabic safety-pattern misses, and fixing the `stomach_ache`/`stomach_pain` key mismatch. Both are small, isolated, and directly serve the "quality is not good enough yet" complaint without touching planner logic, RAG, or voice infrastructure. See Section 17.

---

## 2. Current Virtual Doctor Flow

```
POST /virtual-doctor/start                          [router.py]
  -> interview_engine.start_session(language, user_id)
     -> INSERT virtual_doctor_sessions (phase='intake')
     -> reply = GREETING[lang]                        ("what is your name?")
     -> planner.warm() fired in background             (loads qwen2.5:3b while
                                                          the patient types)

Client records audio -> POST /virtual-doctor/transcribe  [router.py -> voice/stt.py]
  -> stt.transcribe(bytes, language_hint)
     -> faster-whisper, single-worker executor, cooperative TRANSCRIBE_TIMEOUT
     -> returns {text, detected_language, language_probability, timed_out, ...}

Client sends the transcript -> POST /virtual-doctor/message   [router.py]
  -> interview_engine.handle_message(session_id, message)
     1. _check_safety(message, lang)                    [reuses chatbot.nlu.safety
                                                           .MedicalSafetyLayer, raw +
                                                           normalized text, worse-of-two]
        -> emergency/urgent: SHORT-CIRCUITS here. Persists, replies, returns.
           No planner, no RAG, no LLM ever runs on a flagged turn.
     2. EntityExtractor.extract(message)                 [reuses chatbot.entities
                                                           .extractor.EntityExtractor,
                                                           unmodified]
     3. _build_turn_context(): asyncio.gather(
            memory.load_recent(session_id),               <- last HISTORY_LIMIT=12 msgs
            retrieval.retrieve_for_turn(msg, complaint, lang)  <- RAG, per turn
        )                                                 independent failure-degrade
     4. _run_planner(PlannerInput(...))
        -> LLMPlanner.plan() [default] or StaticPlanner.plan() [VD_PLANNER=static]
           - intake (name/age) handled deterministically by regex, not the LLM
           - LLMPlanner: one Ollama /api/chat call (qwen2.5:3b, JSON mode) asks
             the next question, grounded in the RAG context_block + conversation
             history + "ALREADY ESTABLISHED" findings; a SEPARATE minimal call
             (_check_readiness) decides whether to stop asking
           - any LLMPlanner failure (timeout/bad JSON/wrong script/incoherent/
             repeated question) -> PlannerError -> falls back to StaticPlanner
             for that turn only
        -> StaticPlanner: fixed JSON flow per complaint (5 complaints + generic),
           asks the next unfilled slot in file order, no ranking
     5. if ready_for_diagnosis:
           reasoning.run_reasoning(complaint, profile, lang, full_history)
             -> asyncio.gather(
                    symptom_engine.match(symptoms)          <- DB rule engine,
                                                                unmodified
                    retrieval.retrieve_for_profile(...)     <- whole-consultation RAG
                )
             -> qwen2:7b /api/chat, JSON mode, language-drift guarded,
                one strict retry, templated fallback on repeated failure
             -> final_urgency = MORE severe of (rule_engine, LLM)   <- _more_urgent(),
                                                                        never downgrades
     6. persist profile/phase/urgency/differential; log the turn
     7. return MessageResponse (reply, phase, urgency_level, profile_snapshot,
                                 differential, recommended_specialty, confidence)

Doctor's reply -> POST /virtual-doctor/speak            [router.py -> voice/tts.py]
  -> tts.synthesize(text, language) -> Piper -> WAV bytes (cached, hash-keyed)

Consultation complete -> POST /virtual-doctor/report/{session_id}  [router.py
                                                          -> report_generator.py]
  -> isolated child process (pdf_worker.py) renders a bilingual RTL-aware PDF
     via WeasyPrint; 503 (not 500) if the native PDF stack is unavailable
```

Every stage above is named from the actual function/module it runs, confirmed by direct reading this session, not inferred from documentation.

---

## 3. Current Patient Journey

Concretely, opening a voice consultation today:

1. **Greets the patient?** Yes — `GREETING[lang]`, e.g. *"Hello, I'm the MedOrbit virtual doctor assistant. Before we begin, what is your name?"* — and explicitly frames itself as an assistant, not a human doctor, in the very first sentence.
2. **Asks for name?** Yes, immediately, before anything clinical (`interview_engine._extract_name`, strips leading politeness like "my name is").
3. **Asks for age?** Yes, next (`_extract_age` — handles digits, Arabic-Indic numerals, spelled-out numbers in both English and Arabic, and compound Arabic ages like "أربعة وثلاثون"=34; re-asks once on failure via `ASK_AGE_RETRY` rather than storing a bad value).
4. **Asks chief complaint?** Yes, third (`ASK_COMPLAINT`, *"what's bothering you today?"*).
5. **Continues with clinical questions?** Yes — either the LLM planner's dynamic question or the matching static flow's next slot, capped at `MAX_INTERVIEW_TURNS=6` clinical questions (intake excluded).
6. **Adapts to answers?** Partially, and this is the crux of Section 1's finding: the LLM planner genuinely reads the conversation and avoids repeating itself (`_is_repeat`, 0.6 token-overlap threshold, tuned via direct A/B testing per the code's own comments) — real adaptive behavior. But it can only ever adapt *within* the 10-key finding vocabulary and the complaint the entity extractor or the model itself proposes from a hard-coded `CANONICAL_COMPLAINTS` set of 6. A patient whose real complaint is flank pain gets a "generic" interview (duration/severity/associated symptoms) dressed up in dynamically-phrased sentences — the phrasing is adaptive, the clinical substance is not.
7. **Generates an assessment?** Yes, once the planner decides it has enough (either the dedicated readiness call or the 6-turn hard cap) — a differential (2-4 conditions with likelihood), an urgency level, a recommended specialty (DB rule-engine-backed), a next step, and a confidence score, all persisted and offered as a PDF.

---

## 4. Current Clinical State

Inspected `schemas.py`, `interview_engine.py`, `planner.py` (`KNOWN_FINDING_KEYS`, `_known_summary`), `reasoning.py`, all 6 `flows/*.json`, and `report_generator.py`'s field handling.

### Currently implemented (first-class, structured, always asked about or always captured)
- `name`, `age` (intake, regex-extracted, deterministic)
- `chief_complaint_description` (verbatim answer to "what's bothering you")
- `duration`, `severity`, `location`, `location_character`, `character`, `radiation`, `triggers`, `appearance`, `exposure`, `associated_symptoms` — the 10-key `KNOWN_FINDING_KEYS` vocabulary shared by both planners and the report
- `associated_symptoms_detected` — a list, populated separately by `EntityExtractor.extract()` on every turn (not planner-dependent)
- `phase`, `chief_complaint`, `urgency_level`, `recommended_specialty_id`, `differential` — session-row columns, not part of the JSONB profile

### Partially implemented — captured, but not reliably surfaced
- **`other` catch-all dict.** When the LLM planner extracts a finding outside the 10 known keys (e.g. it decides to record an allergy or a medication mentioned in passing), `LLMPlanner._store_answer` namespaces it under `profile["other"][slug]` rather than discarding it — so out-of-vocabulary facts *can* survive one turn. But this was verified this session to have two real downstream gaps:
  1. `report_generator.py`'s `symptoms_summary` is built as `{key: value for key, value in profile.items() if key not in _EXCLUDED_PROFILE_KEYS and isinstance(value, str) and value.strip()}` (`report_generator.py:233-237`) — `other` is a `dict`, not a `str`, so **the entire `other` sub-dict is silently excluded from the patient-facing PDF report**, even when it holds a real captured fact.
  2. `reasoning.py`'s `_build_user_prompt` builds `profile_lines` the same top-level-only way (`profile.items()` with no recursion into `other`) — a captured allergy would render as one ugly, unlabeled line (`- other: {'allergies': 'penicillin'}`) in the differential prompt rather than a clean "Allergies: penicillin" the model can act on cleanly.
  - Net effect: the *only* place these facts are guaranteed to reach is the raw database JSONB — not the report, not cleanly the LLM prompt.
- **Static-flow's chief-complaint detection can silently miss a correctly-extracted symptom.** Live-verified this session (Section 15): `"بطني بوجعني من اليمين"` is correctly extracted as symptom `stomach_ache` by the Palestinian-dialect layer, but `flows/abdominal_pain.json`'s `match_symptoms` is `["stomach_pain"]` — a different key from the same `medical_entities.json` vocabulary. `interview_engine._detect_chief_complaint` does exact-set membership, so this returns `"generic"`, not `"abdominal_pain"`, despite a real symptom being correctly detected. Confirmed by direct execution, not inference.

### Missing entirely — no field, no question, no vocabulary entry anywhere
| Field | Status |
|---|---|
| `sex` | Missing. Not in `KNOWN_FINDING_KEYS`, no flow asks it, no gating anywhere depends on it. |
| `medications` | Missing as a first-class field (only reachable via the lossy `other` path above). |
| `allergies` | Same as medications. |
| `past medical history` | Missing entirely. |
| `surgical history` | Missing entirely — directly relevant to Section 8's "the doctor already said appendicitis" scenario. |
| `pregnancy possibility` | Missing entirely, and un-gateable anyway since `sex` doesn't exist. |
| `urinary symptoms` (dysuria, hematuria) | Missing from `medical_entities.json`'s 14 symptoms, missing from every flow, missing from both safety pattern lists in Arabic. Live-verified: `"عندي حرقان بول ودم بالبول"` extracts zero symptoms and zero safety severity. |
| `GI symptoms` (vomiting, appetite loss) as distinct fields | Partially — `abdominal_pain.json` asks about them as one bundled free-text slot (`associated_symptoms`: "nausea, vomiting, diarrhea, constipation, fever, or blood in your stool?"), not as separate structured booleans a reasoning pass can check individually. |
| `fever` as a global structured field | Partially — only `fever_cough.json` asks about it directly; other complaints (notably `abdominal_pain`) bundle it inside the same free-text `associated_symptoms` slot as GI symptoms above, and `fever` *is* one of the 14 `medical_entities.json` symptom keys, so it is at least detectable as a background entity even outside that flow. |
| `hydration / dehydration signs` | Missing entirely — no symptom key, no flow question, no safety pattern. Live-verified: `"عندي جفاف وأملاح"` extracts nothing. |
| `pain migration` | Missing — no flow captures "started at X, moved to Y" as a distinct, structured fact (the classic appendicitis pattern). |
| `right lower quadrant / flank pain as locations` | `location`/`location_character` exist as free-text slots, but there is no symptom vocabulary or safety pattern for "flank" (`خاصرة`) at all — live-verified zero extraction. |
| `red flags` as an explicit, stored, per-turn list | Missing as data — red-flag detection is a side effect of `MedicalSafetyLayer.check()` short-circuiting the whole interview; there is no running, inspectable "red flags checked / red flags present" list in the profile the way the task brief's target design implies. |
| `risk factors` | Missing entirely. |

---

## 5. Current Question Selection

- **Is it static-flow-based, LLM-based, or mixed?** Mixed, by design, with a documented fallback contract (`planner.py`'s module docstring): `LLMPlanner` is the default (`VD_PLANNER=llm`), `StaticPlanner` is both a selectable mode and the mandatory per-turn fallback whenever the LLM fails in any of five specific ways (timeout, bad JSON, empty question, wrong script, repeated question).
- **Does it use missing information to decide the next question?** Only loosely. The LLM prompt lists `ALREADY ESTABLISHED` findings and instructs the model not to re-ask them, but there is no explicit **ranked list of missing fields** handed to the model — it infers what's missing from what's present, from inside a single free-form generation call. The `StaticPlanner` is the only piece with a literal "missing" concept (`_next_unfilled_slot`), and it is a fixed linear scan of the flow's JSON slot order, not a value-ranked choice.
- **Does it rank questions by clinical value?** No, in both planners. `StaticPlanner` always asks slots in file order regardless of what the patient just said. `LLMPlanner` leaves the choice of *which* missing thing to ask about entirely to the model's own judgment inside one JSON-mode call — there is no separate scoring step (unlike the readiness decision, which the code deliberately *did* split into its own call after measuring that a combined call degrades reliability — the same lesson has not yet been applied to question *selection*).
- **Does it avoid repetition?** Yes, genuinely — `_is_repeat()` is a real, tested, deterministic guard (normalized token-overlap ≥ `VD_PLANNER_REPEAT_SIMILARITY=0.6`, tuned via direct A/B evidence documented in the code, including a specific example of two differently-worded rewordings of the same Arabic question that a looser 0.7 threshold let through). A repeat raises `PlannerError`, which routes that turn to the static flow — repetition can never reach the patient.
- **Does it adapt to different patients?** Within a complaint category, yes — different answers genuinely produce different next questions (this is real LLM generation, not templating). Across complaint categories, only the 5 hard-coded ones get differentiated RAG anchoring (`retrieval.COMPLAINT_ANCHORS`) and differentiated static flows; everything else (flank pain, urinary symptoms, dehydration, and — per Section 15 — several of this task's own worked examples) collapses to the same undifferentiated `generic` path regardless of how clinically distinct the actual complaints are.

---

## 6. Dynamic Clinical Interview Design (proposed — not implemented)

Target pipeline, per the task brief:

```
Patient utterance
  -> STT transcript                         [voice/stt.py — exists]
  -> transcript validation                  [NEW]
  -> clinical information extraction        [extend EntityExtractor / KNOWN_FINDING_KEYS]
  -> update structured patient state        [extend ClinicalProfile schema]
  -> detect red flags                       [extend MedicalSafetyLayer + a per-complaint
                                              red-flag registry, not just the global regex net]
  -> identify missing high-value information [NEW — MissingFieldRanker]
  -> generate next best clinical question   [existing LLMPlanner, fed ranked candidates]
  -> retrieve relevant evidence             [retrieval.py — exists]
  -> reason safely                          [reasoning.py — exists]
  -> respond
  -> TTS                                    [voice/tts.py — exists]
```

Components needed (design only):

1. **`ClinicalProfile` schema (extends today's flat JSONB profile).** Add the fields listed as "missing" in Section 4 as first-class keys, not `other`-namespaced. Group them the way the task brief does — demographics (`sex`), history (`medications`, `allergies`, `past_medical_history`, `surgical_history`), complaint-specific structured booleans (`fever`, `vomiting`, `dysuria`, `hematuria`, hydration signs), and derived/tracking fields (`pain_migration`, `red_flags_checked: []`, `missing_high_value_fields: []`). This directly extends `KNOWN_FINDING_KEYS` and the flow JSON schema, not a rewrite of either.

2. **`RedFlagRegistry` — complaint-specific, not just the global regex net.** Today, red-flag detection is one global regex pass (`MedicalSafetyLayer`) that runs identically regardless of complaint. The design gap it should close: a "sudden, worst headache of life" is a red flag *specifically for headache*, and "blood in urine" is a red flag *specifically for flank/urinary complaints* — neither needs to be a standing global pattern that risks false-positiving on unrelated complaints. A registry keyed by canonical complaint (mirroring `retrieval.COMPLAINT_ANCHORS`'s existing per-complaint structure) lets Section 7's complaint-specific red flags be added without growing the global pattern lists indefinitely. The existing global safety layer remains the safety-critical backstop that runs on *every* turn regardless of complaint (this is not a replacement for it — Section 14 explains why both are needed).

3. **`MissingFieldRanker`.** Given the active complaint's required-field list (an extension of today's flow JSON) and the current profile, produce an ordered candidate list: unfilled red-flag-relevant fields first, then unfilled complaint-defining fields, then unfilled general fields. This is the piece neither planner has today (Section 5) — it turns "the model infers what's missing" into "the model is handed a ranked list and picks from it," which is exactly the kind of narrowing that `reasoning.py`'s own `_check_readiness` split proved measurably more reliable for a 3B model than asking it to do everything in one call.

4. **`QuestionGenerator`.** The existing `LLMPlanner._ask()`, unchanged in mechanism, but fed the ranked candidate list from (3) instead of the full `KNOWN_FINDING_KEYS` free-for-all — narrows the model's job from "invent what to ask" to "phrase the top-ranked missing thing naturally," which should also make repetition and off-topic drift rarer.

5. **`StaticPlanner` fallback, extended.** More flows (Section 7), each carrying its own red-flag list from (2) — the fallback path must degrade to *something clinically appropriate*, not just to `generic`, for the new complaint categories.

This section is design-only per the task's instruction — no schema, flow file, or code change was made.

---

## 7. Complaint-Specific Clinical Profiles (proposed)

### Headache
**Currently:** `flows/headache.json` asks duration, severity, location, associated symptoms (nausea/light sensitivity/blurred vision) — reasonable coverage of the *quality* of a headache, none of the *danger signs*.
**Red flags to add:** sudden/"worst headache of life" onset (live-verified missing from `URGENT_PATTERNS_AR` — `"صداع شديد فجأة"` is unflagged today), new focal neurological symptoms (weakness, speech difficulty, vision loss distinct from "blurred"), fever + neck stiffness together (meningitis pattern — today's flow only asks about nausea/light/vision as one bundled question, not stiffness), vomiting, head trauma preceding onset, and age/pattern-change in a patient with no prior headache history (unanswerable today — no history field exists).
**Adaptive behavior:** if the patient volunteers "sudden" or "worst ever" in the duration/character answer, the next question should jump straight to a focused neuro-red-flag check rather than continuing the fixed slot order — this is exactly what `MissingFieldRanker` (Section 6) would do by re-ranking red-flag fields to the top the moment a trigger phrase appears in `associated_symptoms_detected`.

### Chest Pain
**Currently:** `flows/chest_pain.json` already asks character (pressure/tightness), radiation (arm/jaw/back/neck), and a bundled associated-symptoms question covering shortness of breath, sweating, dizziness, nausea, and exertional worsening — genuinely close to a real cardiac-risk screen already, and its safety coverage is the strongest of any complaint: live-verified, `"وجع صدر مع ضيق نفس"` (chest pain + shortness of breath) correctly triggers `emergency` severity today.
**Red flags to add:** fainting/syncope as a distinct question (currently absent — "dizziness" is asked but is not the same signal as loss of consciousness), explicit cardiac risk factors (diabetes, hypertension, smoking, family history — none captured anywhere, ties to the missing `risk_factors` field).
**Adaptive behavior:** already the best-covered complaint; the main gap is upstream (no risk-factor field to weight the differential with), not the question flow itself.

### Abdominal Pain
**Currently:** `flows/abdominal_pain.json` asks duration, location + character, a bundled GI-symptoms question, and food-relation/recurrence — but as Sections 4 and 8 show, a large share of real Palestinian-dialect right-sided abdominal complaints never reach this flow at all due to the `stomach_ache`/`stomach_pain` key mismatch.
**Red flags to add (once the flow is actually reached):** pain migration (periumbilical → right lower quadrant is the textbook appendicitis pattern and has no field today), rebound tenderness/worsening-with-movement as a distinct question (today folded into nothing), fever, loss of appetite, and — because reproductive-age patients can present with ectopic pregnancy as an abdominal-pain differential — pregnancy possibility when clinically relevant, currently unaskable because `sex` doesn't exist as a field to gate the question on.
**Adaptive behavior:** if the patient reports right-sided location + fever + loss of appetite, the next question should specifically probe migration and rebound rather than continuing to the generic food-relation slot — again, exactly the re-ranking `MissingFieldRanker` is designed to do.

### Flank Pain / Kidney Stone / Urinary Issues — does not exist today
**Currently:** confirmed absent as a category everywhere it would need to exist: no entry in `retrieval.COMPLAINT_ANCHORS`, no entry in `planner.CANONICAL_COMPLAINTS` (derived from the same dict), no `flows/*.json` file, no `match_symptoms`, and no symptom keys for flank pain, dysuria, or hematuria in `chatbot/entities/medical_entities.json`'s 14-symptom vocabulary. Live-verified: `"عندي وجع بالخاصرة"` and `"عندي حرقان بول ودم بالبول"` both extract zero symptoms.
**Proposed new category `flank_pain`** with questions/red flags: flank location (one-sided vs. both, confirmable now that a real `خاصرة` vocabulary entry would exist), radiation to groin (classic stone pattern), burning urination (dysuria), visible blood in urine (hematuria — and note the *English* safety pattern for this already exists, `blood in (vomit|stool|urine)`, so the Arabic side needs to be brought to parity, not invented from scratch), fever/chills (pyelonephritis red flag — distinguishes an infected obstructed kidney, a surgical emergency, from an uncomplicated stone), nausea/vomiting, hydration status, and prior history of stones.
**Adaptive behavior:** burning + blood + fever together should escalate urgency (possible infected stone) even without tripping the global safety regex, which is exactly what a complaint-specific red-flag registry (Section 6) is for.

### Fever/Cough
**Currently:** `flows/fever_cough.json` already asks duration, severity/character (dry vs. productive), a bundled symptom-and-exposure question, and travel/contact history — reasonably complete for a first pass.
**Red flags to add:** explicit shortness-of-breath-at-rest as its own question (today it's folded into the same bundled question as sore throat/body aches, which under-weights it), chest pain co-occurring with fever/cough (should route toward the chest-pain red-flag set, not stay purely respiratory), and an immunocompromise/chronic-condition flag — unaskable today since `past_medical_history` doesn't exist.
**Adaptive behavior:** if oxygen-related distress or chest pain is volunteered, the next question should escalate toward the chest-pain/emergency line of questioning rather than continuing the fever/cough slot order.

---

## 8. Appendicitis / Flank Pain Example Design

This section walks the task's three example utterances through **actual, live-verified current behavior** (Section 15's method), then the proposed design.

**`"عندي وجع بالخاصرة وجفاف ونسبة أملاح"`** (flank pain + dehydration + electrolytes)
- **Today:** `EntityExtractor.extract()` returns `symptoms: []`. `MedicalSafetyLayer.check()` returns `severity: "normal"`. Nothing about this utterance is clinically actionable to the system — it falls straight to the 3-question `generic` flow (duration / severity / "any other symptoms?"), losing the flank location, the dehydration, and the electrolyte concern entirely unless the patient happens to restate them in free text that a later turn's slot happens to capture verbatim.
- **Should do (design):** recognize `خاصرة` as a flank-pain symptom, route to the proposed `flank_pain` complaint (Section 7), ask about radiation to the groin, burning/blood in urine, fever, and hydration specifically — and separately recognize `جفاف`/`أملاح` as dehydration/electrolyte concerns worth a direct question about fluid intake, dizziness on standing, and reduced urination, regardless of which complaint category wins.

**`"بطني بوجعني من اليمين"`** (right-sided belly pain)
- **Today:** live-verified — `EntityExtractor.extract()` correctly returns `symptoms: ["stomach_ache"]` (the Palestinian-dialect layer does its job here). But `interview_engine._detect_chief_complaint()` then returns `"generic"`, not `"abdominal_pain"`, because `flows/abdominal_pain.json`'s `match_symptoms` only accepts `"stomach_pain"` — a different key. The patient is asked three generic questions instead of the abdominal-pain flow's location/character, GI-symptom, and recurrence questions, and *right-sidedness*, the single most appendicitis-suggestive detail in this sentence, is never specifically probed.
- **Should do (design):** fix the key mismatch first (Section 17 — this is small enough to be the safest first coding batch on its own), then, once correctly routed to `abdominal_pain`, ask specifically about pain migration and rebound tenderness given the already-known right-sided location, per Section 7.

**`"الدكتور حكالي عندي زائدة ومحتاج عملية"`** (a doctor already said appendicitis, surgery needed)
- **Today:** live-verified — `EntityExtractor.extract()` returns `symptoms: []` (no vocabulary entry recognizes "زائدة" as a clinical concept at all — it only appears in `safety.py`'s emergency pattern as part of the *unrelated* phrase `جرعة زائدة`, "excessive dose," which correctly does **not** false-positive on this sentence — verified, `safety_severity: "normal"`). The system has no way to recognize that the patient is not reporting undiagnosed symptoms but relaying an *existing clinician's diagnosis and treatment plan*. It would proceed to ask the same generic differential-building questions it would ask a patient with no diagnosis at all, which is clinically backwards — the priority here is not to build a differential from scratch, it is to confirm urgency and reinforce the existing clinical guidance.
- **Should do (design), per the task's explicit safety requirement:**
  1. **Not give a final diagnosis** — already true by construction today (`reasoning.py` always frames output as a differential/next-step, never a certainty), and should stay true.
  2. **Ask relevant clarifying questions** — when did the doctor say this, has surgery been scheduled, are symptoms worsening in the meantime.
  3. **Check red flags** — fever, worsening pain, vomiting — because a scheduled-but-not-yet-treated appendicitis can still progress to rupture.
  4. **Distinguish appendicitis-like from urinary/kidney-stone-like features** — right lower quadrant + migration + fever/vomiting points one way; flank + radiation to groin + dysuria/hematuria points the other (this is exactly what the new `flank_pain` category from Section 7 is for).
  5. **Identify urgency** — "surgery needed" plus any worsening should escalate urgency directly, not wait for a full generic interview to complete.
  6. **Respect the existing diagnosis as high-priority information** — this needs an explicit new signal (a "clinician already diagnosed X" detection, not present anywhere today) that short-circuits straight to confirming urgency/next-step rather than running the full slot-filling interview from zero.
  7. **Advise following the clinician's guidance** — the final reply should explicitly reinforce "follow your doctor's advice about the surgery" rather than compete with it with an independent differential.

---

## 9. Medical Knowledge / Real Data Plan

**What exists now.** Exactly one source: *Macleods Clinical Examination, 14th Edition* (per `rag/ingest_book.py` and `retrieval.py`'s own comments; confirmed in this project's memory of the RAG ingestion work), chunked (1000 chars, 200 overlap, clean-boundary preference), embedded via Ollama `nomic-embed-text`, stored as `REAL[]` (no pgvector in this Postgres image — a documented, deliberate constraint). `COMPLAINT_ANCHORS` in `retrieval.py` only anchors 5 complaints; there is no anchor for flank pain, urinary symptoms, or dehydration, so even if the textbook happens to contain relevant sections (a general clinical-examination textbook plausibly does cover renal colic and the acute abdomen), **the current anchor system cannot reach them** for those queries — this is a retrieval-configuration gap, not necessarily a corpus-coverage gap, and the two should be measured separately before assuming a new source is needed.

**Is it enough?** No, on two separate axes: (1) one general-examination textbook cannot cover drug references, emergency red-flag quick-reference material, or localized guidance, and (2) even within its own scope, coverage is only reachable for the 5 anchored complaints today.

**What's missing, and proposed source categories** (quality over quantity, no blind scraping, per the task's instruction):

| Category | Why needed | Metadata to store | Update cadence | Licensing concern | Evaluation method |
|---|---|---|---|---|---|
| **Clinical guidelines** (e.g. WHO clinical guidelines, which are published for open reuse) | Textbook prose is general; guidelines give the specific red-flag/escalation criteria this product needs (e.g. explicit "when to refer for renal colic") | source name, publication year, guideline body, section/topic tag, review-cycle date | Re-ingest on each guideline revision (WHO/similar bodies version their documents) | Generally reusable with attribution — verify per-document license before ingesting, do not assume | Precision@K against a held-out labeled query set per Section 10/14 |
| **Drug references** | Any medication/dose confirmation feature (Section 14) needs a grounded source, not model memory | drug name (generic + local brand), dose range, contraindication flags, source edition | Infrequent, but must track edition changes (dosing guidance does change) | Must be an openly-licensed formulary (e.g. WHO Essential Medicines List) — a copyrighted commercial drug reference must not be scraped | Spot-check a sample of dose statements against the source document by hand |
| **Emergency / red-flag quick-reference** | Directly grounds Section 6/7's red-flag registry in a citable source rather than hand-authored regex alone | complaint category tag, red-flag description, source, page/section | Rare — red-flag criteria are stable | Same open-licensing bar as guidelines | Manual review that each registry entry traces to a real citation |
| **Licensed textbooks** (expanding beyond Macleods) | Broader clinical coverage (e.g. a dedicated emergency medicine or urology text) | same schema as the existing ingestion pipeline already uses (`source, chunk_index, page_start, page_end, embedding_dim, embedding_model, content_hash`) | Only on acquiring a new licensed edition | **Must be confirmed licensed for this use before ingestion** — the existing Macleods PDF's licensing status for this exact use was not re-verified in this audit and should be confirmed alongside any expansion (Open Question, Section 18) | Precision@K, same as above |
| **Local/regional guidelines** (Palestinian MOH or equivalent, if available) | The product is explicitly Palestinian-dialect-facing; local emergency numbers and referral pathways are already hardcoded in `safety.py` (Red Crescent/101) — clinical guidance should ideally be similarly locally grounded, not purely generic | source, jurisdiction, effective date | Track official revisions | Confirm public-availability/reuse terms before ingesting | Confirm cited guidance matches what a Palestinian clinician would actually recommend (requires clinician review, not just automated scoring) |

No source in this table should be treated as "ingest now" — each needs an explicit licensing confirmation first, per the task's own instruction not to recommend random scraping.

---

## 10. RAG Improvement Plan

Each item below states why, how to measure, and success criteria — none is a "just add technology" recommendation.

| Improvement | Why | How to measure | Success criteria |
|---|---|---|---|
| **Metadata: complaint/topic tags per chunk** | Today's `COMPLAINT_ANCHORS`/`TOPIC_LEXICON` (`retrieval.py`) are hand-authored English-term dictionaries maintained separately from the corpus itself — adding a new complaint (e.g. `flank_pain`) means hand-writing new anchor terms with no guarantee they match what's actually in the ingested text. Tagging chunks at ingestion time with their actual topic would let anchors be derived from the corpus rather than guessed. | Compare anchor-derived-from-metadata retrieval vs. today's hand-authored anchors on the same held-out query set | Equal-or-better Precision@K on existing 5 complaints, and *non-zero* retrieval on a new complaint (flank pain) without hand-writing new anchor terms |
| **Section/heading-aware chunking** | Current chunking is character-count-based with only clean-boundary (not semantic-boundary) preference — a chunk can span two unrelated subsections of the textbook, diluting the embedding | Manually sample 20 chunks, check whether each stays within one logical section | Reduced rate of "mixed-topic" chunks in a manual sample, measured before/after |
| **Complaint-specific retrieval (formalized)** | Directly extends the existing, already-working anchor mechanism rather than replacing it — this is a data/config change, not an architecture change | Retrieval hit-rate per complaint category, tracked as an ongoing metric once Section 13 observability work lands | Every complaint category (including new ones from Section 7) has retrievable, on-topic passages |
| **Hybrid retrieval (dense + keyword)** | Justified specifically because Arabic queries were measured (per `retrieval.py`'s own comments) to sit close to the 0.60 threshold even with anchoring — a keyword/BM25 fallback could catch cases dense similarity narrowly misses, without the cost of a always-on reranker | A/B: dense-only vs. dense+keyword on the same held-out set, specifically the Arabic subset | Measurable recall improvement on Arabic queries specifically, not just aggregate |
| **Reranking** | The existing general audit (`docs/medical_voice_assistant_audit.md`, Section 8) already recommends measuring before adding this — this report agrees and does not repeat the recommendation independently; it should be evaluated together with the hybrid-retrieval experiment above so the two aren't confounded | Precision@K before/after, on the same held-out set | Only adopt if it beats the hybrid-retrieval-alone result by a measured margin |
| **Citation correctness** | `format_context()` already numbers and cites passages (`[1] (p. 59) ...`) and the reasoning prompt already instructs the model to ground its answer in them — but nothing currently verifies the model's claim actually matches the cited passage after generation | Manual spot-check: sample N differentials, verify each cited page supports the claim made from it | Documented citation-correctness rate as a baseline, tracked over time |
| **Grounding check** | Same gap as above, generalized: trust today is prompt-instruction-only ("diagnose strictly based on the provided context") with no automated post-generation check | Same sampling method as citation correctness | A documented rate, not a pass/fail gate initially — automate only once the manual baseline shows it's worth it |
| **Empty-evidence behavior** | Already good, worth preserving explicitly rather than "improving": `_retrieve_medical_context`/`retrieve()` degrade to `[]` on any failure, and `reasoning.py` correctly reverts to the *non-RAG* system prompt when the context block is empty rather than instructing the model to ground itself in nothing | Confirm this behavior stays byte-for-byte true after any of the above changes | No regression — an empty-evidence turn must never see the RAG-grounded system prompt with an empty context block |

---

## 11. STT Improvement Plan

Inspected `voice/stt.py` directly.

- **Arabic quality:** genuinely strong relative to effort already invested — per-language, per-device model sizing is driven by real measured WER (FLEURS ar_eg: `small` 21.4% vs `medium` 7.1%), not a guess, and both CUDA and CPU paths default to the more accurate size for Arabic specifically because the code's own comments document Arabic as the accuracy bottleneck.
- **Dialect issues:** not benchmarked by faster-whisper's own model choice (Whisper is a general multilingual model, not Palestinian-dialect-tuned) — the real dialect handling in this codebase happens *after* transcription, in `chatbot/nlu/data/palestinian_dialect.json` (see Section 15's live results — that layer does meaningful, verified work).
- **Medical terminology / dose/medication risk:** confirmed via direct reading — `_transcribe_sync`'s `common` dict passes no `initial_prompt`, so Whisper receives no vocabulary bias toward clinical terms, drug names, or the Arabic dialect words this exact task cites (`خاصرة`, `زائدة`, `جفاف`, `أملاح`). This is a real, unmitigated risk specifically for the terms this task cares about most.
- **Confidence handling:** `TranscriptionResponse` already carries `language_probability` and `timed_out` (schemas.py), and `_pick_supported_language` already uses probability to snap a misdetected language — but nothing in `interview_engine.handle_message()` currently branches on a low-confidence transcript; a garbled or uncertain transcription is used exactly as-is.
- **Partial-transcript limitations:** none possible today — decoding is always a full, already-uploaded clip (`decode_audio` on the whole blob), consistent with the general audit's finding that there is no streaming layer anywhere in this codebase.
- **Speed:** already well-tuned per the code's own measured comments — CUDA `medium` at ~0.6s vs CPU `medium` at ~3s per utterance is the documented reason CPU falls back to `small` for English (where the accuracy cost is small) but keeps `medium` for Arabic (where it isn't).
- **CPU/GPU fallback:** real and tested against an actual failure mode — `_get_model` explicitly falls back CUDA→CPU only after a real smoke-transcribe fails (not just model construction, which the code's own comment notes can succeed even when cuBLAS is missing).

**Recommendations:**
1. **Add an `initial_prompt`** seeded with a short list of the clinical/dialect terms this exact product needs biased toward — `خاصرة`, `زائدة`, `جفاف`, `أملاح`, `حرقان`, common drug names — Whisper supports this natively and it costs nothing architecturally; it directly targets the exact terminology risk this task calls out.
2. **Confirmation prompts on low confidence.** Wire `language_probability` (already returned) and `timed_out` (already returned) into `interview_engine`: when either signals low confidence, have the planner ask a short "did I hear that right — you said X?" confirmation turn instead of silently proceeding on a possibly-wrong transcript. This is additive to the existing schema, not a new field.
3. **Benchmark approach:** extend the existing FLEURS-based methodology (already used to choose model sizes, per the code's comments) with a small labeled set built specifically from this task's own Arabic phrases (Section 15) plus their dialect variants, so future model/prompt changes can be measured against the exact vocabulary this product cares about rather than generic FLEURS coverage alone.

---

## 12. TTS Improvement Plan

Inspected `voice/tts.py` directly.

- **Arabic pronunciation:** Piper's `ar_JO-kareem-medium` voice auto-diacritizes (tashkeel) by default, which the code's own docstring/comments already identify as the single biggest quality lever measured for this project (documented in project memory as roughly 10% WER with tashkeel vs. ~40% without on real doctor-reply sentences) — this is already the correct default and should not be changed without re-measuring.
- **Medication names / general Latin terms:** `_AR_TRANSLITERATIONS` is a tiny, hand-authored fixed map (`medorbit`, `ai`, `pdf` only) applied via `_LATIN_RUN` regex substitution — any Latin drug or brand name outside this map will still be read letter-by-letter by the Arabic voice (the code's own comment gives the concrete failure example: "MedOrbit" → "مذابه" before the fix). This is a real, unaddressed gap specifically relevant to any future medication-confirmation feature (Section 14).
- **Numbers and units:** no dedicated handling found in `voice/tts.py` — Piper's own text-frontend handles this by default, but there is no project-specific verification (e.g. that a dose like "500 mg" or an age like "34" is read naturally in Arabic) — flagged as unverified rather than assumed broken.
- **Latency:** already strong and measured — Piper synthesizes at roughly 10x real-time on this project's hardware per the module docstring, and a two-level cache (in-memory LRU + disk, content-hash-keyed, write-then-rename for crash safety) makes repeated lines near-instant.
- **Caching:** genuinely well-built — `_cache_put`'s write-then-rename pattern specifically avoids serving a truncated WAV as a permanent cache hit after a crash mid-write, a real production concern correctly handled.
- **Interruption readiness (backend scope only — see caveat below):** `voice/tts.py` itself has no cancellation mechanism for an in-flight synthesis — `/speak` synthesizes the full reply and returns it as one response; there is no way to abort a synthesis already in progress. **Caveat, scoped honestly:** this audit's inspection was limited to `ai-service/virtual_doctor/` as instructed, which does not include the frontend voice-orchestration JS. Prior project work (not re-verified in this session, and outside this audit's file scope) is understood to have added *client-side* interruption — stopping local audio playback and reopening the microphone when the patient starts speaking over the doctor. That is a real capability at the client layer, but it does not change the finding above: the *backend* has no mechanism to cancel a TTS synthesis or an in-flight LLM call once started, which matters for Section 13's latency work and for any future work that tries to cut a long synthesis short before it's even generated (as opposed to just muting playback of an already-generated one).
- **Voice quality:** not benchmarked with a formal MOS-style rating in this audit (nor in the general audit) — flagged as an evaluation gap, not a known defect.

**Recommendations:**
1. Expand the Latin transliteration map to cover common drug names likely to appear in an Arabic reply, or add a general-purpose transliteration fallback (rather than a fixed 3-entry map) for names not on the list.
2. Explicitly verify number/unit reading in Arabic with a short manual test set (ages, doses, durations) — currently unverified either way.
3. Any future medication-confirmation feature (Section 14) should be designed knowing TTS cannot yet reliably speak arbitrary drug names — the confirmation UX may need to fall back to spelling out the name letter-by-letter or displaying text prominently rather than relying on audio alone for an unfamiliar drug name.

---

## 13. Speed / Latency Plan

**Already-strong existing practice** (confirmed by direct reading, not assumed): `router.py` exposes `/transcribe/warmup` and `/speak/warmup`, and `interview_engine.start_session` fires `planner.warm()` in the background the moment a session starts, specifically so the ~9s Whisper cold-load and the ~7.48s-cold/~1.8s-warm Ollama planner-model load land during the greeting rather than on the patient's first real answer (all figures per the code's own measured comments). `retrieval.py` separately pins the embedding model to CPU (`EMBED_ON_CPU`) specifically because loading the 7B reasoning model was measured to evict the embedder from a 4GB card otherwise (0.067s warm vs. 4.85s reload) — this is genuine, evidence-driven latency engineering already in place.

**Slow parts remaining, and why:**
- **The reasoning model (`qwen2:7b`) itself is only warmed *reactively*** — `interview_engine.handle_message` re-warms it via `planner.warm()` right after a reasoning call finishes (to prepare for the *next* consultation), but the *first* reasoning call of a freshly-started process still pays a full cold load, unlike the planner model which is warmed proactively at session start.
- **Ollama contention between the 3B planner and 7B reasoning models** is documented as solved for the *embedder* (pinned to CPU) but not for the planner/reasoning pair themselves — the general audit's Section 9 flags this as an open, unmitigated risk, not fixed this session.
- **No aggregated latency metrics.** Per-module timing already exists and is genuinely good (`retrieval.py`'s `embed_ms`/`search_ms`, `stt.py`'s `processing_seconds`, `tts.py`'s `synthesis_seconds`, `planner.py`'s per-turn logged timing) — but nothing aggregates these into P50/P95 dashboards or correlates them per consultation via a request/session ID, confirmed absent by the general audit's Section 13 and not contradicted by anything read in this session.

**Recommendations:**
1. Warm the reasoning model (`qwen2:7b`) proactively too, likely alongside `planner.warm()` at session start — as a measured tradeoff, not blindly: warming a model that will never be used (a session that gets safety-short-circuited, or abandoned before reaching readiness) wastes VRAM/time, so this should be A/B measured the same rigorous way the existing warmup decisions were, not just copy-pasted.
2. Extend the existing per-module timing fields into one correlation-ID-tagged latency event per turn (reusing the already-present numeric fields, not inventing new ones), which directly unblocks P50/P95 tracking without new instrumentation work.
3. Suggested metrics, matching what's already partially logged: STT `processing_seconds` (exists), planner/reasoning LLM latency (exists in logs, not aggregated), RAG `embed_ms`/`search_ms` (exists), TTS `synthesis_seconds` (exists), and end-to-end turn latency (not currently computed as a single number anywhere — would need to be derived from the above once correlated).

---

## 14. Safety Plan

Grounded in Section 15's live-verified gaps, not hypothetical ones.

- **Emergency escalation:** already correct in structure — `_check_safety()` runs before anything else on every turn and short-circuits the whole interview (no planner, RAG, or LLM call can ever suppress a flagged turn), replying with the Red Crescent/101 localized emergency message. This must not change.
- **Urgent referral:** structurally correct (separate severity tier, non-blocking), but content-incomplete — Section 15 shows two concrete Arabic misses (`"صداع شديد فجأة"`, thunderclap headache; `"دم بالبول"`, hematuria) that should be urgent at minimum. Both are additive pattern-list changes, not architecture changes.
- **Uncertainty language / no definitive diagnosis:** already correct and enforced in two independent places — `reasoning.py`'s prompts explicitly instruct "this is decision support, never a certain diagnosis," and `_more_urgent()` structurally prevents the LLM from ever downgrading a rule-engine urgency call, which is the more safety-critical of the two guarantees.
- **No overriding clinician instructions:** **not implemented today**, and directly demonstrated by Section 8's third worked example — a patient relaying an existing doctor's appendicitis diagnosis gets no special handling at all; the system would proceed to build its own differential from scratch rather than prioritizing and reinforcing the existing clinical guidance. This needs the new "clinician-already-diagnosed" detection signal proposed in Section 8.
- **Avoid false reassurance:** no explicit mechanism either way found in this audit — `reasoning.py`'s fallback text (`_FALLBACK_NEXT_STEP`, "please book an appointment...") is appropriately cautious by default, but nothing actively checks that a *successful* LLM generation doesn't produce falsely-reassuring language on a borderline case. Flagged as unverified, not confirmed broken.
- **Pregnancy-sensitive questions:** cannot exist today — no `sex` field exists to gate the question on, confirmed in Section 4. This blocks the abdominal-pain ectopic-pregnancy consideration from Section 7 entirely until `sex` is added first.
- **Medication/dose confirmation:** no mechanism anywhere — no `medications` field, no readback/confirmation logic in `interview_engine.py` or `reasoning.py`, confirmed by direct reading. Section 12 additionally flags that even if this were added, Piper's TTS cannot yet reliably *speak* an arbitrary drug name back to the patient, which the confirmation UX would need to account for.
- **Red-flag priority over conversation completion:** already true by construction — the safety check runs before the planner every single turn, not just at interview start or completion, so a red flag volunteered mid-interview (not just at intake) still short-circuits immediately. This is a genuine existing strength worth preserving exactly as-is through any of this plan's other changes.

**Concrete, additive fixes this section recommends** (design only — not applied in this Phase 0 pass): add an Arabic hematuria pattern to `URGENT_PATTERNS_AR` (bringing it to parity with the already-existing English `blood in (vomit|stool|urine)` pattern), add a thunderclap/sudden-severe-headache Arabic pattern, and add the "clinician already diagnosed X" detection signal from Section 8. All three are small, isolated, and independently testable — see Section 17.

---

## 15. Evaluation Plan

**Method note:** every "current behavior" cell below is a **live execution result**, produced this session via the project's `.venv` calling `EntityExtractor.extract()` and `MedicalSafetyLayer.check()` directly and, for the eighth case, `interview_engine._detect_chief_complaint()` — not a guess from reading the code. No files were modified to run this; it is read-only use of the existing, unmodified modules.

| Arabic case | Expected symptoms/questions | Red flags expected | **Current extracted symptoms** | **Current safety severity** | Expected safe response | Should escalate? | What should NOT happen |
|---|---|---|---|---|---|---|---|
| `عندي وجع بالخاصرة` | Flank pain category; ask radiation/dysuria/hematuria/fever | Fever+pain = possible infected stone | **`[]`** | **`normal`** | Ask flank-specific follow-ups | Not automatically — depends on follow-up | Falling silently to the 3-question generic flow with no flank vocabulary at all (**this is what happens today**) |
| `عندي حرقان بول ودم بالبول` | Dysuria + hematuria → flank/urinary category | Hematuria alone is at least urgent-tier | **`[]`** | **`normal`** | Ask about flank pain, fever, duration; note hematuria as needing follow-up | Yes, at least "urgent" | Treating visible blood in urine as a non-event (**this is what happens today** — confirmed live) |
| `بطني بوجعني من اليمين ومعي حرارة` | Abdominal pain, RLQ-leaning, with fever | Fever + right-sided pain suggests appendicitis workup | **`["fever", "stomach_ache"]`** | **`normal`** | Route to abdominal_pain flow; ask migration/rebound given fever+RLQ | Urgent-leaning given fever | Routing to `generic` despite two real symptoms being correctly extracted (**this is what happens today** — the `stomach_ache`/`stomach_pain` key mismatch, confirmed live via `_detect_chief_complaint`) |
| `صداع شديد فجأة` | Headache category; sudden/severe onset is the single highest-priority red flag in the whole headache profile | Thunderclap headache = classic SAH red flag, should be urgent at minimum | **`["headache"]`** | **`normal`** | Should trigger an urgent-tier safety response, not just an ordinary headache-flow question | **Yes — urgent at minimum** | Treating this identically to an ordinary mild headache (**this is what happens today** — confirmed live, a genuine safety gap) |
| `وجع صدر مع ضيق نفس` | Chest pain + dyspnea — classic cardiac emergency combo | Emergency | **`["chest_pain"]`** | **`emergency`** (matched `ضيق نفس`) | Immediate emergency escalation, Red Crescent/101 | Yes — already correctly emergency | Nothing — **this one already works correctly**, included here to show the safety layer is not universally weak, only unevenly covered |
| `الدكتور حكالي عندي زائدة` | Should recognize "existing diagnosis relayed by patient" as a distinct signal, not a fresh undiagnosed complaint | Surgery mentioned = urgent-leaning regardless of the system's own differential | **`[]`** | **`normal`** | Confirm timeline, ask about worsening, reinforce "follow your doctor's advice," check for red flags in the meantime | At least urgent, pending follow-up | Running a full from-scratch generic interview as if no diagnosis exists (**this is what happens today** — confirmed live) |
| `عندي جفاف وأملاح` | Dehydration/electrolyte concern; ask fluid intake, dizziness on standing, urination frequency | Severe dehydration can itself be urgent | **`[]`** | **`normal`** | Ask hydration-specific follow-ups | Depends on severity of follow-up answers | Extracting nothing at all (**this is what happens today** — confirmed live) |
| `عندي ألم بطن وغثيان` | Abdominal pain + nausea | Routine-to-urgent depending on follow-up | *(not separately re-run — same vocabulary path as the fever/stomach case above; "الم بطن" is a literal `medical_entities.json` entry so this one is expected to extract correctly, unlike the dialect-phrased case above)* | — | Ask location/character/migration | Depends on follow-up | — |

**Additional cases run this session, beyond the task's own list, that further calibrate the picture:**

| Case | Extracted symptoms | Safety severity | Note |
|---|---|---|---|
| `عندي صداع شديد مع غثيان` | `["headache", "nausea"]` | `normal` | Correct symptom detection; the *severe* modifier does not push this to urgent — consistent with the thunderclap-headache gap above, since "severe" alone (without "sudden") is also not in `URGENT_PATTERNS_AR` for headache specifically |
| `الدكتور حكالي عندي زائدة ومحتاج عملية` (full sentence incl. "needs surgery") | `[]` | `normal` | Confirms "زائدة" never false-positives against the unrelated `جرعة زائدة` (overdose) safety pattern — a correct *absence* of a false positive, but still a missed opportunity to recognize the diagnosis-relay signal |

**System-level evaluation** (proposed, not run this session — would require load/concurrency testing outside Phase 0's read-only scope): P50/P95 latency per endpoint, throughput under concurrent Ollama load, and VRAM contention specifically between the planner (3B) and reasoning (7B) models, extending the general audit's existing recommendation in the same area.

---

## 16. Recommended Implementation Roadmap

### Batch 1 — Characterize current virtual_doctor patient state and question flow
**Goal:** Lock in today's exact behavior (including known quirks like the `stomach_ache`/`stomach_pain` mismatch) with characterization tests before changing anything, following the same discipline the existing `tests/test_characterization_*` files already establish.
**Files likely to change:** new `tests/test_characterization_virtual_doctor_clinical_state.py` only.
**Tests to add:** assert `_detect_chief_complaint` output for each of this report's live-verified phrases (Section 15), pinning today's actual (imperfect) behavior first.
**Risk:** none — test-only.
**Success criteria:** every Section 15 finding has a corresponding red (failing-as-expected, i.e. documenting current behavior) or green test.

### Batch 2 — Add structured clinical state fields
**Goal:** Promote `sex`, `medications`, `allergies`, `past_medical_history`, `surgical_history` from "not captured" / "lossy `other`" to first-class `KNOWN_FINDING_KEYS` entries, and fix the `report_generator.py` `symptoms_summary` gap so `other`-namespaced facts stop being silently dropped from the PDF.
**Files likely to change:** `virtual_doctor/planner.py` (`KNOWN_FINDING_KEYS`), `virtual_doctor/report_generator.py` (`_EXCLUDED_PROFILE_KEYS`/`symptoms_summary` construction, `_SLOT_LABELS`).
**Tests to add:** a scripted consultation that states an allergy/medication and asserts it appears in the final PDF's `symptoms_summary` (today, verified, it would not).
**Risk:** low — additive keys, no removal of existing behavior.
**Success criteria:** a stated allergy/medication survives from profile → reasoning prompt → PDF report, end to end.

### Batch 3 — Fix the symptom-key mismatch + add complaint-specific high-value question policy
**Goal:** Reconcile `stomach_ache`/`stomach_pain` (and audit every other flow's `match_symptoms` against the actual dialect/entity vocabulary for the same class of bug); add the new `flank_pain` complaint category (Section 7) with its own flow file and red-flag list.
**Files likely to change:** `chatbot/entities/medical_entities.json` or `virtual_doctor/flows/*.json` (whichever direction the fix takes — a design decision, not made in this Phase 0 report), new `virtual_doctor/flows/flank_pain.json`, `virtual_doctor/retrieval.py` (`COMPLAINT_ANCHORS`), `virtual_doctor/planner.py` (`CANONICAL_COMPLAINTS` derives from the same dict, so this follows automatically).
**Tests to add:** `_detect_chief_complaint("بطني بوجعني من اليمين")` returns `"abdominal_pain"`, not `"generic"`; a new flank-pain phrase routes to the new category.
**Risk:** low-medium — touches shared vocabulary files also used by the chatbot layer; needs the same "ask before touching a shared file twice" discipline already established for this codebase.
**Success criteria:** every Section 15 "routed to generic incorrectly" row now routes correctly.

### Batch 4 — Improve dynamic next-best-question logic
**Goal:** Build the `MissingFieldRanker` from Section 6; feed `LLMPlanner._ask()` a ranked candidate list instead of the open `KNOWN_FINDING_KEYS` free-for-all.
**Files likely to change:** `virtual_doctor/planner.py`.
**Tests to add:** given a profile with a red-flag-relevant field still empty, the ranker places it first; given all red-flag fields filled, general fields rank next.
**Risk:** medium — changes the LLM prompt shape, which the code's own history shows is sensitive to exactly this kind of change (the readiness-call split was discovered via measurable A/B regressions from a similar-looking prompt change) — must be A/B measured, not assumed safe.
**Success criteria:** measured reduction in turns-to-first-red-flag-question on the new evaluation set (Section 15).

### Batch 5 — Add clinical evidence/RAG quality improvements
**Goal:** Add complaint/topic metadata at ingestion (Section 10); add `flank_pain` to `COMPLAINT_ANCHORS`/`TOPIC_LEXICON`; measure hybrid retrieval on the Arabic subset before deciding on reranking.
**Files likely to change:** `virtual_doctor/retrieval.py`; `rag/ingest_book.py` if new source categories from Section 9 are approved.
**Tests to add:** retrieval evaluation harness (new, not a unit test), per the general audit's own Section 14 recommendation.
**Risk:** low — measurement-first, consistent with the general audit's existing Phase 3 recommendation.
**Success criteria:** documented Precision@K/Recall@K baseline including the new flank-pain category specifically.

### Batch 6 — Improve STT confidence and medical term confirmation
**Goal:** Add `initial_prompt` medical/dialect vocabulary biasing; wire `language_probability`/`timed_out` into a confirmation-question path in `interview_engine`.
**Files likely to change:** `virtual_doctor/voice/stt.py`, `virtual_doctor/interview_engine.py`.
**Tests to add:** WER on the Section 15 phrase set specifically (extending the existing FLEURS-based benchmark), before/after `initial_prompt`.
**Risk:** low — additive parameter, existing fallback behavior unchanged if it has no effect.
**Success criteria:** measured WER improvement on this project's own dialect/clinical vocabulary, not just generic benchmark numbers.

### Batch 7 — Improve latency/warmup
**Goal:** Proactively warm the reasoning model at session start (A/B measured per Section 13); correlate existing per-module timing into one per-turn latency record.
**Files likely to change:** `virtual_doctor/interview_engine.py`, `virtual_doctor/reasoning.py` (warmup function), logging config.
**Tests to add:** none new required beyond existing timing assertions; add a latency-regression smoke test if one doesn't already exist.
**Risk:** low — additive, matches the existing warmup pattern already proven safe for the planner model.
**Success criteria:** first reasoning call of a fresh process no longer pays the full cold-load cost, measured before/after.

### Batch 8 — Add evaluation cases
**Goal:** Formalize Section 15's table (plus its dialect variants) as a repeatable, version-controlled evaluation set — not one-off manual verification like this report's.
**Files likely to change:** new `tests/eval/` (or similar) directory, per the general audit's Section 14 recommendation.
**Tests to add:** the harness itself.
**Risk:** low — additive, no production behavior change.
**Success criteria:** this report's Section 15 table becomes a CI-trackable regression suite, not a point-in-time snapshot.

---

## 17. Safest First Coding Batch

**Recommendation: close the two live-verified Arabic safety-pattern gaps first — thunderclap headache and hematuria — as one small, isolated batch, with the `stomach_ache`/`stomach_pain` key-mismatch fix bundled in as a close second item in the same batch.**

Why this ordering, given the task's own stated priority "Safety > correctness > grounding > reliability > latency": both safety-pattern gaps are confirmed, live, and directly named in this task's own brief (a sudden/severe headache and blood in urine are both explicitly listed as target red flags in the prompt that requested this audit) — this is the highest-leverage, lowest-risk place to start precisely because it is a *safety* gap, not a convenience or quality-of-life gap. Concretely:

- **Change scope:** two new regex alternatives added to `URGENT_PATTERNS_AR` in `chatbot/nlu/safety.py` (an Arabic hematuria pattern, symmetric with the already-existing English `blood in (vomit|stool|urine)`; an Arabic sudden/thunderclap-headache pattern). No architecture, no LLM, no new module.
- **Independently testable:** each is a pure function of input text → severity; a characterization test can assert today's `"normal"` result, then a follow-up test asserts the fixed `"urgent"` result, mirroring exactly the "characterize current behavior → fix → verify → re-run full suite" discipline this codebase's existing `test_characterization_*` files already establish.
- **Zero dependency on anything else in this roadmap** — does not touch the planner, RAG, voice pipeline, or schema, so it carries none of the LLM-prompt-sensitivity risk flagged for Batch 4, and none of the shared-file risk flagged for Batch 3.
- **The `stomach_ache`/`stomach_pain` fix** is comparably small and isolated (a one-key change in either `flows/abdominal_pain.json`'s `match_symptoms` or the dialect mapping), which is why it is proposed as a same-batch companion rather than its own separate phase — but it is listed second because it is a *correctness* gap, not a *safety* gap, per the stated priority order.

*(Per the task instructions, this is a recommendation only — nothing was implemented in this audit.)*

---

## 18. Open Questions

Decisions that need product/owner input before further coding, several sharpened by this audit's specific findings:

1. **Arabic dialect priority.** The existing Palestinian-dialect layer (`palestinian_dialect.json`) already does real, verified work (Section 15's `بطني` → `stomach_ache` result) — is extending *that* file with the new terms this task cites (`خاصرة`, `جفاف`, `أملاح`, urinary terms) the intended path, or should a broader dialect strategy be considered first?
2. **Exact medical sources allowed for RAG ingestion**, per Section 9 — none of the proposed new categories (guidelines, drug references, additional textbooks) should be ingested without an explicit licensing confirmation; this is a decision this audit cannot make.
3. **Whether the existing Macleods PDF's licensing was ever formally confirmed for this exact use** — referenced in prior project memory as untracked-by-git and unverified; worth resolving before expanding the corpus rather than after.
4. **Whether voice is turn-based now or a streaming target** — this audit's ai-service-scoped inspection confirms the backend is fully turn-based with no cancellation plumbing; prior project work (outside this audit's file scope) is understood to have added client-side playback interruption. Is closing that gap (true backend-level cancellation/streaming) an actual near-term goal, or is the current turn-based-backend-plus-client-side-interruption split acceptable as the long-term shape?
5. **Whether physician review is required** before an AI-generated differential/urgency reaches a patient, or whether the existing "decision support only" framing (already correctly enforced in `reasoning.py`'s prompts) is considered sufficient on its own — this materially affects how much weight future batches should put on differential accuracy vs. transparency/citation (Section 10).
6. **Retention policy for transcripts/audio** — not evaluated in this Phase 0 pass (out of the specified inspection scope), but directly relevant to any dialect/vocabulary data collected under Batch 8's evaluation harness.
7. **Whether to support emergency local numbers beyond the Red Crescent/101 already hardcoded** — relevant if any new red-flag category (e.g. the proposed flank-pain/urinary category) should escalate to a different local service.
8. **Whether patient profile should persist across sessions** — directly relevant to Section 8's "the doctor already told me X" scenario: a cross-session record would let a returning patient's prior-diagnosis context carry forward automatically rather than needing to be re-detected from a single utterance each time.
9. **Which of Batch 2's new fields (`sex` specifically) are safe to ask for directly vs. should remain optional/skippable**, given the sensitivity of demographic questions in a voice-first, potentially-public-space consultation context.
