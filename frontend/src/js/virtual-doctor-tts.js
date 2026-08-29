const VirtualDoctorTTS = (() => {

function vdBase() {
        return API.getOrigin() + '/api/virtual-doctor';
    }

    function authHeaders(extra) {
        const token = API.getAccessToken();
        return Object.assign({}, extra || {}, token ? { Authorization: 'Bearer ' + token } : {});
    }

function activeSessionId() {
        if (typeof VirtualDoctorSession !== 'undefined' && typeof VirtualDoctorSession.getSessionId === 'function') {
            return VirtualDoctorSession.getSessionId();
        }
        return null;
    }

const MAX_CHUNK_CHARS = 300;
    const MIN_CHUNK_CHARS = 2;

    let audioEl = null;
    let unlocked = false;
    let generation = 0;
    let speaking = false;
    let currentAbort = null;
    const cache = new Map();

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

if (out.length && piece.length < MIN_CHUNK_CHARS) {
                out[out.length - 1] += ' ' + piece;
                continue;
            }

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

function ensureAudio() {
        if (!audioEl) {
            audioEl = new Audio();
            audioEl.preload = 'auto';
        }
        return audioEl;
    }

function unlock() {
        if (unlocked) return Promise.resolve(true);
        const el = ensureAudio();

        el.src = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';
        return el.play()
            .then(() => { el.pause(); unlocked = true; return true; })
            .catch(() => { unlocked = false; return false; });
    }

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
            } catch (_) {   }
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

async function speak(text, lang, handlers) {
        const cb = handlers || {};
        stop();
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

return { ok: false, spoken, detail: err.message };
        } finally {
            if (myGeneration === generation) {
                speaking = false;
                currentAbort = null;
                if (typeof cb.onEnd === 'function') cb.onEnd({ spoken });
            }
        }
    }

function stop() {
        generation++;
        speaking = false;
        if (currentAbort) {
            try { currentAbort.abort(); } catch (_) {   }
            currentAbort = null;
        }
        if (audioEl) {
            try {
                audioEl.pause();
                audioEl.currentTime = 0;
            } catch (_) {   }
        }
    }

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
