const VirtualDoctorSTT = (() => {

function vdBase() {
        return API.getOrigin() + '/api/virtual-doctor';
    }

    function authHeaders(extra) {
        const token = API.getAccessToken();
        return Object.assign({}, extra || {}, token ? { Authorization: 'Bearer ' + token } : {});
    }

function activeSessionId() {
        if (typeof cfg.getSessionId === 'function') return cfg.getSessionId();
        if (typeof VirtualDoctorSession !== 'undefined') return VirtualDoctorSession.getSessionId();
        return null;
    }

const TUNING = {

SILENCE_MS: 1000,

STILL_LISTENING_MS: 6000,

SPEECH_ATTACK_FRAMES: 3,

ABS_MIN_RMS: 0.010,
        NOISE_FLOOR_MULT: 2.2,

MAX_UTTERANCE_MS: 30000,

UPLOAD_TIMEOUT_MS: 20000,

MIN_SPEECH_FOR_RETRY_MS: 400,

PREROLL_MS: 3000,

MIN_UTTERANCE_MS: 300,

BARGEIN_THRESHOLD_MULT: 1.3,

BARGEIN_ATTACK_FRAMES: 6,

BARGEIN_PREROLL_MS: 500
    };

    let stream = null;
    let audioCtx = null;
    let analyser = null;
    let recorder = null;
    let chunks = [];
    let rafId = null;

    let state = 'idle';
    let cfg = {};

let gateMode = 'open';
    let running = false;

    let bargeFrames = 0;
    let speechFrames = 0;
    let noiseFloor = 0.005;
    let utteranceStart = 0;
    let lastVoiceAt = 0;
    let segmentStart = 0;
    let discardSegment = false;
    let quietSince = 0;
    let stillListeningFired = false;

function t(key, fallback) {
        if (typeof I18n !== 'undefined' && I18n.t) {
            const val = I18n.t(key);
            if (val && val !== key) return val;
        }
        return fallback;
    }

    function setState(next, detail) {
        if (state === next && !detail) return;
        state = next;
        if (typeof cfg.onStateChange === 'function') cfg.onStateChange(next, detail || {});
    }

    function emitError(detail) {
        if (typeof cfg.onError === 'function') cfg.onError(detail);
    }

function checkEnvironment() {
        if (window.isSecureContext === false || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            return { ok: false, code: window.location.protocol === 'file:' ? 'insecure_file' : 'insecure_origin' };
        }
        if (typeof MediaRecorder === 'undefined') return { ok: false, code: 'no_mediarecorder' };
        return { ok: true };
    }

    function pickMimeType() {
        const candidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus', 'audio/mp4'];
        for (const type of candidates) {
            if (MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(type)) return type;
        }
        return '';
    }

    function describeMicError(err) {
        switch ((err && err.name) || '') {
            case 'NotAllowedError':
            case 'PermissionDeniedError':
                return { code: 'denied', key: 'stt.errDenied', showHelp: true, fatal: true };
            case 'NotFoundError':
            case 'DevicesNotFoundError':
                return { code: 'no_device', key: 'stt.errNoDevice', showHelp: false, fatal: true };
            case 'NotReadableError':
            case 'TrackStartError':
                return { code: 'busy', key: 'stt.errBusy', showHelp: false, fatal: true };
            case 'SecurityError':
                return { code: 'insecure_origin', key: 'stt.errInsecure', showHelp: true, fatal: true };
            default:
                return { code: 'unknown', key: 'stt.errGeneric', showHelp: false, fatal: true };
        }
    }

function startSegment() {
        if (!stream) return;
        chunks = [];
        discardSegment = false;
        const mimeType = pickMimeType();
        try {
            recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream);
        } catch (err) {
            console.warn('[vd-stt] MediaRecorder init failed:', err);
            emitError({ code: 'unknown', key: 'stt.errGeneric', showHelp: false, fatal: true });
            return;
        }

        recorder.addEventListener('dataavailable', (e) => {
            if (e.data && e.data.size > 0) chunks.push(e.data);
        });

        recorder.addEventListener('stop', () => {
            const captured = chunks.slice();
            chunks = [];
            if (discardSegment || !running) {
                if (running) startSegment();
                return;
            }
            const blob = new Blob(captured, { type: (recorder && recorder.mimeType) || 'audio/webm' });
            const spokenMs = Date.now() - utteranceStart;

startSegment();
            if (blob.size === 0 || spokenMs < TUNING.MIN_UTTERANCE_MS) {
                setState('listening');
                return;
            }
            upload(blob, spokenMs);
        });

        segmentStart = Date.now();
        recorder.start();
    }

    function stopSegment(discard) {
        discardSegment = !!discard;
        if (recorder && recorder.state !== 'inactive') recorder.stop();
    }

function vadTick() {
        if (!running || !analyser) return;
        rafId = requestAnimationFrame(vadTick);

        const buf = new Uint8Array(analyser.fftSize);
        analyser.getByteTimeDomainData(buf);
        let sum = 0;
        for (let i = 0; i < buf.length; i++) {
            const v = (buf[i] - 128) / 128;
            sum += v * v;
        }
        const rms = Math.sqrt(sum / buf.length);
        const now = Date.now();

        if (typeof cfg.onLevel === 'function') {
            cfg.onLevel(Math.min(1, rms * 6), state === 'capturing');
        }

if (state === 'transcribing') {
            speechFrames = 0;
            if (now - segmentStart > TUNING.PREROLL_MS) stopSegment(true);
            return;
        }

if (gateMode === 'closed') {
            speechFrames = 0;
            bargeFrames = 0;
            if (now - segmentStart > TUNING.PREROLL_MS) stopSegment(true);
            return;
        }

if (gateMode === 'bargein') {
            speechFrames = 0;
            const bargeThreshold = Math.max(
                TUNING.ABS_MIN_RMS,
                noiseFloor * TUNING.NOISE_FLOOR_MULT
            ) * TUNING.BARGEIN_THRESHOLD_MULT;

            bargeFrames = rms > bargeThreshold
                ? bargeFrames + 1
                : Math.max(0, bargeFrames - 1);

            if (bargeFrames >= TUNING.BARGEIN_ATTACK_FRAMES) {
                bargeFrames = 0;

if (typeof cfg.onBargeIn === 'function') cfg.onBargeIn();
            }
            if (now - segmentStart > TUNING.BARGEIN_PREROLL_MS) stopSegment(true);
            return;
        }

        const threshold = Math.max(TUNING.ABS_MIN_RMS, noiseFloor * TUNING.NOISE_FLOOR_MULT);
        const isVoice = rms > threshold;

        if (state === 'capturing') {
            if (isVoice) {
                lastVoiceAt = now;
            } else if (now - lastVoiceAt >= TUNING.SILENCE_MS) {
                setState('transcribing');
                stopSegment(false);
                return;
            }
            if (now - utteranceStart > TUNING.MAX_UTTERANCE_MS) {
                setState('transcribing');
                stopSegment(false);
            }
            return;
        }

if (!isVoice) {
            noiseFloor = noiseFloor * 0.95 + rms * 0.05;
            speechFrames = 0;

if (now - segmentStart > TUNING.PREROLL_MS) stopSegment(true);
            if (!stillListeningFired && quietSince && now - quietSince > TUNING.STILL_LISTENING_MS) {
                stillListeningFired = true;
                setState('listening', { stillListening: true });
            }
            return;
        }

        speechFrames++;
        if (speechFrames >= TUNING.SPEECH_ATTACK_FRAMES) {
            utteranceStart = now - TUNING.PREROLL_MS;
            lastVoiceAt = now;
            stillListeningFired = false;
            setState('capturing');
        }
    }

async function upload(blob, spokenMs) {
        setState('transcribing', { audioMs: spokenMs });

        const form = new FormData();
        const ext = (blob.type || '').includes('mp4') ? 'mp4' : 'webm';
        form.append('audio', blob, `utterance.${ext}`);
        if (cfg.language) form.append('language', cfg.language);

form.append('session_id', activeSessionId() || '');

        const sentAt = performance.now();

const controller = new AbortController();
        const abortTimer = setTimeout(() => controller.abort(), TUNING.UPLOAD_TIMEOUT_MS);
        try {
            const res = await fetch(vdBase() + '/transcribe', {
                method: 'POST', headers: authHeaders(), body: form, signal: controller.signal
            });
            if (!res.ok) {
                let detail = `HTTP ${res.status}`;
                try {
                    const body = await res.json();

if (body?.error?.message) detail = body.error.message;
                    else if (body && body.detail) detail = body.detail;
                } catch (_) {   }
                emitError({
                    code: 'server',
                    key: res.status === 413 ? 'stt.errTooLong' : 'stt.errServer',
                    detail, showHelp: false, fatal: false
                });
                resumeListening();
                return;
            }

            const data = unwrap(await res.json());
            const roundTripMs = Math.round(performance.now() - sentAt);
            const text = (data.text || '').trim();

            if (!text) {

const spokeLongEnough = (spokenMs || 0) >= TUNING.MIN_SPEECH_FOR_RETRY_MS;
                if (data.timed_out || spokeLongEnough) {
                    emitError({
                        code: 'no_speech',
                        key: data.timed_out ? 'stt.errTimeout' : 'stt.errNoSpeech',
                        detail: '', showHelp: false, fatal: false
                    });
                }
                resumeListening();
                return;
            }

            if (typeof cfg.onTranscript === 'function') {
                cfg.onTranscript({
                    text,
                    language: data.detected_language,
                    languageProbability: data.language_probability,
                    audioSeconds: data.audio_seconds,
                    processingSeconds: data.processing_seconds,
                    roundTripMs,
                    model: data.model
                });
            }
        } catch (err) {

            const aborted = err && err.name === 'AbortError';
            if (!aborted) console.error('[vd-stt] upload failed:', err);
            emitError({
                code: aborted ? 'timeout' : 'network',
                key: aborted ? 'stt.errTimeout' : 'stt.errNetwork',
                detail: aborted ? '' : err.message, showHelp: false, fatal: false
            });
            resumeListening();
        } finally {
            clearTimeout(abortTimer);
        }
    }

    function resumeListening() {
        if (!running) return;
        speechFrames = 0;
        quietSince = Date.now();
        stillListeningFired = false;
        setState('listening');
    }

async function start() {
        if (running) return true;

        const env = checkEnvironment();
        if (!env.ok) {
            emitError({
                code: env.code,
                key: env.code === 'no_mediarecorder' ? 'stt.errGeneric'
                    : env.code === 'insecure_file' ? 'stt.errFileProtocol' : 'stt.errInsecure',
                showHelp: true, fatal: true
            });
            setState('error');
            return false;
        }

        setState('requesting');
        try {
            stream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    channelCount: 1,
                    echoCancellation: true,
                    noiseSuppression: true,
                    autoGainControl: true
                }
            });
        } catch (err) {
            console.warn('[vd-stt] getUserMedia failed:', err);
            emitError(describeMicError(err));
            setState('error');
            return false;
        }

        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            audioCtx = new Ctx();
            if (audioCtx.state === 'suspended') await audioCtx.resume();
            analyser = audioCtx.createAnalyser();
            analyser.fftSize = 1024;
            audioCtx.createMediaStreamSource(stream).connect(analyser);
        } catch (err) {
            console.error('[vd-stt] audio graph failed:', err);
            emitError({ code: 'unknown', key: 'stt.errGeneric', showHelp: false, fatal: true });
            setState('error');
            return false;
        }

        running = true;
        gateMode = 'open';
        noiseFloor = 0.005;
        bargeFrames = 0;
        quietSince = Date.now();
        stillListeningFired = false;
        startSegment();
        setState('listening');
        vadTick();
        return true;
    }

    function stop() {
        running = false;
        if (rafId) cancelAnimationFrame(rafId);
        rafId = null;
        stopSegment(true);
        recorder = null;
        if (audioCtx) { audioCtx.close().catch(() => {}); audioCtx = null; }
        analyser = null;
        if (stream) { stream.getTracks().forEach((tr) => tr.stop()); stream = null; }
        setState('idle');
    }

function setGateMode(mode) {
        const next = (mode === 'closed' || mode === 'bargein') ? mode : 'open';
        if (next === gateMode) return;
        gateMode = next;
        speechFrames = 0;
        bargeFrames = 0;
        if (gateMode === 'open') {
            resumeListening();
        } else {

stopSegment(true);
        }
    }

function setGateOpen(open) {
        setGateMode(open ? 'open' : 'closed');
    }

function unwrap(payload) {
        return payload && typeof payload === 'object' && 'data' in payload ? payload.data : payload;
    }

    async function fetchStatus() {
        try {
            const res = await fetch(vdBase() + '/transcribe/status', { headers: authHeaders() });
            return res.ok ? unwrap(await res.json()) : null;
        } catch (_) {
            return null;
        }
    }

function warmup() {

const qs = cfg.language ? `?language=${encodeURIComponent(cfg.language)}` : '';
        return fetch(vdBase() + '/transcribe/warmup' + qs, { method: 'POST', headers: authHeaders() })
            .then((res) => (res.ok ? res.json().then(unwrap) : null))
            .catch(() => null);
    }

    function init(options) {
        cfg = options || {};
        return { tuning: TUNING };
    }

    return {
        init,
        start,
        stop,
        setGateMode,
        setGateOpen,
        getGateMode: () => gateMode,
        fetchStatus,
        warmup,
        setLanguage: (lang) => { cfg.language = lang; },
        getState: () => state,
        isRunning: () => running,
        TUNING
    };
})();
