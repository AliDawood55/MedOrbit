/**
 * MedOrbit v2 - Virtual Doctor speech output (TTS)
 *
 * Speaks each doctor reply aloud via the AI service:
 *   POST <backend>/api/virtual-doctor/speak  ->  audio/wav
 *
 * The reply is split into sentences and played in order. That buys three
 * things at once:
 *   - playback starts as soon as the FIRST sentence is ready instead of
 *     waiting for the whole paragraph,
 *   - the next sentence is fetched while the current one plays, so there is
 *     no gap between them,
 *   - subtitles have a natural unit to display and stay in sync without
 *     needing word-level timings, which Piper does not give us.
 *
 * Contract: speak() NEVER rejects. Failure resolves with {ok: false} and
 * reports through onError, because a broken voice must not be able to stall a
 * consultation — the text is on screen regardless.
 */
const VirtualDoctorTTS = (() => {


    /**
     * Authenticated call into the MedOrbit backend's Virtual Doctor gateway.
     *
     * These endpoints used to be called on the AI service directly, with no
     * credential at all. They now require both an access token and ownership
     * of an active consultation, so the model cannot be driven by anyone who
     * merely has an account, let alone by an anonymous caller.
     */
    function vdBase() {
        return API.getOrigin() + '/api/virtual-doctor';
    }

    function authHeaders(extra) {
        const token = API.getAccessToken();
        return Object.assign({}, extra || {}, token ? { Authorization: 'Bearer ' + token } : {});
    }

    /** The consultation this turn belongs to. */
    function activeSessionId() {
        if (typeof cfg.getSessionId === 'function') return cfg.getSessionId();
        if (typeof VirtualDoctorSession !== 'undefined') return VirtualDoctorSession.getSessionId();
        return null;
    }

    // Backend rejects >800 chars; split well below that.
    const MAX_CHUNK_CHARS = 300;
    const MIN_CHUNK_CHARS = 2;

    let audioEl = null;
    let unlocked = false;
    let generation = 0;          // bumped on every stop/new utterance
    let speaking = false;
    let currentAbort = null;
    const cache = new Map();     // `${lang}|${text}` -> object URL

    // ================= text -> sentences =================

    /** Split on sentence enders in both scripts, keeping the punctuation.
     *  Arabic uses ؟ and ، and the full stop is the same glyph as Latin. */
    function splitSentences(text) {
        const raw = String(text || '')
            .replace(/\s+/g, ' ')
            .trim();
        if (!raw) return [];

        const parts = raw.match(/[^.!?؟۔\n]+[.!?؟۔]*\s*/g) || [raw];
        const out = [];

        for (let piece of parts) {
            piece = piece.trim();
            if (!piece) continue;

            // A fragment too small to be a sentence (a stray "?" or an
            // abbreviation tail) belongs with what came before it.
            if (out.length && piece.length < MIN_CHUNK_CHARS) {
                out[out.length - 1] += ' ' + piece;
                continue;
            }

            // Very long sentences get broken on commas so the first audio
            // still arrives quickly.
            while (piece.length > MAX_CHUNK_CHARS) {
                let cut = piece.lastIndexOf('،', MAX_CHUNK_CHARS);
                if (cut < MAX_CHUNK_CHARS * 0.4) cut = piece.lastIndexOf(',', MAX_CHUNK_CHARS);
                if (cut < MAX_CHUNK_CHARS * 0.4) cut = piece.lastIndexOf(' ', MAX_CHUNK_CHARS);
                if (cut <= 0) cut = MAX_CHUNK_CHARS;
                out.push(piece.slice(0, cut + 1).trim());
                piece = piece.slice(cut + 1).trim();
            }
            if (piece) out.push(piece);
        }
        return out;
    }

    // ================= audio element =================

    function ensureAudio() {
        if (!audioEl) {
            audioEl = new Audio();
            audioEl.preload = 'auto';
        }
        return audioEl;
    }

    /**
     * Browsers refuse programmatic audio until the page has seen a user
     * gesture. The doctor's greeting plays after an async round trip, long
     * after the click that started the consultation, so the element is primed
     * during that click instead.
     */
    function unlock() {
        if (unlocked) return Promise.resolve(true);
        const el = ensureAudio();
        // 1 sample of silence — enough to satisfy the gesture requirement.
        el.src = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';
        return el.play()
            .then(() => { el.pause(); unlocked = true; return true; })
            .catch(() => { unlocked = false; return false; });
    }

    // ================= fetching =================

    function cacheKey(text, lang) { return lang + '|' + text; }

    async function fetchClip(text, lang, signal) {
        const key = cacheKey(text, lang);
        const hit = cache.get(key);
        if (hit) return { url: hit, cached: true };

        const res = await fetch(vdBase() + '/speak', {
            method: 'POST',
            headers: authHeaders({ 'Content-Type': 'application/json' }),
            body: JSON.stringify({ text, language: lang, session_id: activeSessionId() }),
            signal
        });
        if (!res.ok) {
            let detail = `HTTP ${res.status}`;
            try {
                const body = await res.json();
                if (body && body.detail) detail = body.detail;
            } catch (_) { /* non-JSON body */ }
            const err = new Error(detail);
            err.status = res.status;
            throw err;
        }
        const blob = await res.blob();
        const url = URL.createObjectURL(blob);
        cache.set(key, url);
        return {
            url,
            cached: res.headers.get('X-TTS-Cached') === '1',
            synthesisSeconds: parseFloat(res.headers.get('X-TTS-Synthesis-Seconds') || '0')
        };
    }

    function playUrl(url, myGeneration) {
        return new Promise((resolve) => {
            const el = ensureAudio();
            let settled = false;
            const done = (reason) => {
                if (settled) return;
                settled = true;
                el.removeEventListener('ended', onEnded);
                el.removeEventListener('error', onError);
                resolve(reason);
            };
            const onEnded = () => done('ended');
            const onError = () => done('error');

            el.addEventListener('ended', onEnded);
            el.addEventListener('error', onError);
            el.src = url;
            el.play().catch(() => done('blocked'));

            // stop() bumps the generation; poll so a cancel resolves promptly
            // even mid-clip.
            const guard = setInterval(() => {
                if (myGeneration !== generation) {
                    clearInterval(guard);
                    done('cancelled');
                } else if (settled) {
                    clearInterval(guard);
                }
            }, 50);
        });
    }

    // ================= public =================

    /**
     * Speak `text`. Resolves when playback finishes, is interrupted, or fails.
     * Any previous utterance is cancelled first, so speech can never overlap.
     */
    async function speak(text, lang, handlers) {
        const cb = handlers || {};
        stop();                       // enforce "one voice at a time"
        const myGeneration = ++generation;

        const sentences = splitSentences(text);
        if (!sentences.length) return { ok: true, spoken: 0 };

        const abort = new AbortController();
        currentAbort = abort;
        speaking = true;
        if (typeof cb.onStart === 'function') cb.onStart({ sentences: sentences.length });

        let spoken = 0;
        let firstAudioMs = null;
        const startedAt = performance.now();

        try {
            // Kick off the first fetch, then keep exactly one request in
            // flight ahead of playback.
            let pending = fetchClip(sentences[0], lang, abort.signal);

            for (let i = 0; i < sentences.length; i++) {
                let clip;
                try {
                    clip = await pending;
                } catch (err) {
                    if (myGeneration !== generation || err.name === 'AbortError') {
                        return { ok: true, spoken, interrupted: true };
                    }
                    throw err;
                }
                if (myGeneration !== generation) return { ok: true, spoken, interrupted: true };

                if (firstAudioMs === null) firstAudioMs = Math.round(performance.now() - startedAt);

                // Prefetch the next sentence while this one is playing.
                pending = (i + 1 < sentences.length)
                    ? fetchClip(sentences[i + 1], lang, abort.signal).catch((e) => { throw e; })
                    : null;

                if (typeof cb.onSubtitle === 'function') {
                    cb.onSubtitle({ text: sentences[i], index: i, total: sentences.length, lang });
                }

                const reason = await playUrl(clip.url, myGeneration);
                if (reason === 'cancelled') return { ok: true, spoken, interrupted: true };
                if (reason === 'blocked') {
                    throw new Error('audio_blocked');
                }
                spoken++;
            }

            return { ok: true, spoken, firstAudioMs };
        } catch (err) {
            console.warn('[vd-tts] speech failed:', err);
            if (typeof cb.onError === 'function') {
                cb.onError({
                    key: err.message === 'audio_blocked' ? 'tts.errBlocked' : 'tts.errUnavailable',
                    detail: err.message
                });
            }
            // Deliberately resolve, not reject: the consultation continues on
            // text alone.
            return { ok: false, spoken, detail: err.message };
        } finally {
            if (myGeneration === generation) {
                speaking = false;
                currentAbort = null;
                if (typeof cb.onEnd === 'function') cb.onEnd({ spoken });
            }
        }
    }

    /** Cut speech off immediately (used for barge-in). Safe to call anytime. */
    function stop() {
        generation++;
        speaking = false;
        if (currentAbort) {
            try { currentAbort.abort(); } catch (_) { /* already aborted */ }
            currentAbort = null;
        }
        if (audioEl) {
            try {
                audioEl.pause();
                audioEl.currentTime = 0;
            } catch (_) { /* not playing */ }
        }
    }

    /** Unwrap the backend's {success, data} envelope. */
    function unwrap(payload) {
        return payload && typeof payload === 'object' && 'data' in payload ? payload.data : payload;
    }

    async function fetchStatus() {
        try {
            const res = await fetch(vdBase() + '/speak/status', { headers: authHeaders() });
            return res.ok ? unwrap(await res.json()) : null;
        } catch (_) {
            return null;
        }
    }

    /** Load the voices up front so the greeting is not delayed by a model load. */
    function warmup() {
        return fetch(vdBase() + '/speak/warmup', { method: 'POST', headers: authHeaders() })
            .then((res) => (res.ok ? res.json().then(unwrap) : null))
            .catch(() => null);
    }

    function clearCache() {
        cache.forEach((url) => URL.revokeObjectURL(url));
        cache.clear();
    }

    return {
        speak,
        stop,
        unlock,
        warmup,
        fetchStatus,
        clearCache,
        splitSentences,
        isSpeaking: () => speaking
    };
})();
