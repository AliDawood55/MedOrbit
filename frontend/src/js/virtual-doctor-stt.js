/**
 * MedOrbit v2 - Virtual Doctor speech-to-text (hands-free microphone capture)
 *
 * Permission is requested once; after that the microphone stays open and the
 * module decides turn boundaries by itself:
 *
 *   listening -> (energy rises)  -> capturing
 *   capturing -> (silence 1.0s)  -> uploading -> transcript -> listening
 *
 * Posts each detected utterance to the AI service:
 *   POST http://<host>:8001/virtual-doctor/transcribe
 *
 * Two details that matter for short answers like "yes" or "نعم":
 *
 * 1. PRE-ROLL. Voice activity is only recognised a few frames *after* speech
 *    starts, so a recorder started at that moment clips the first syllable.
 *    Instead a recorder runs continuously and is recycled every PREROLL_MS
 *    while nothing is being said, which means an utterance always carries up
 *    to PREROLL_MS of audio before its onset.
 *
 * 2. LANGUAGE PINNING. Whisper's auto-detect is unreliable on short clips
 *    (a 4.7s sample was detected as Latin at 0.43 confidence), so the caller
 *    pins the session language and it is sent with every turn.
 *
 * Every failure path re-arms listening, so the consultation is never left
 * silently dead.
 */
const VirtualDoctorSTT = (() => {

    const AI_BASE = API.getAiOrigin();

    // ---- Tunables. Adjust SILENCE_MS first when tuning turn-taking feel. ----
    const TUNING = {
        // How long the patient must stop talking before the turn is submitted.
        // Lower = snappier but cuts people off mid-thought; higher = sluggish.
        SILENCE_MS: 1000,

        // Reassure the patient if they go quiet without ever starting to speak.
        STILL_LISTENING_MS: 6000,

        // Consecutive above-threshold frames needed to call it speech. Guards
        // against a cough or a door closing opening a turn.
        SPEECH_ATTACK_FRAMES: 3,

        // Absolute noise gate, and how far above the measured room floor a
        // sound must sit to count as speech.
        ABS_MIN_RMS: 0.010,
        NOISE_FLOOR_MULT: 2.2,

        // Safety stop for an utterance that never ends (TV in the background).
        MAX_UTTERANCE_MS: 30000,

        // Client-side deadline for /transcribe. Comfortably above the server's
        // own 10s decode budget (VD_STT_TIMEOUT) plus upload, so this only
        // fires when the response genuinely never arrives — but it guarantees
        // the UI always leaves the "transcribing" state.
        UPLOAD_TIMEOUT_MS: 20000,

        // Below this much captured speech, an empty transcript is almost
        // certainly a cough or a knock, so stay quiet. At or above it the
        // patient really did say something and deserves to be asked to repeat
        // rather than being ignored.
        MIN_SPEECH_FOR_RETRY_MS: 400,

        // Rolling pre-roll window; also caps how much silence a blob can carry.
        PREROLL_MS: 3000,

        // Ignore blobs shorter than this — almost always a cough, not a word.
        MIN_UTTERANCE_MS: 300,

        // --- Barge-in (patient interrupts the doctor) ---
        // Interrupting is made slightly harder than starting a normal turn,
        // because the doctor's own voice can leak back through the speakers
        // even with echoCancellation on and a false trigger would cut it off
        // mid-sentence. The real discrimination is DURATION, not loudness:
        // echo leakage is intermittent, a person talking is sustained. Pushing
        // the amplitude bar much higher instead just means quiet speakers
        // cannot interrupt at all.
        BARGEIN_THRESHOLD_MULT: 1.3,

        // Net score, not a run: every frame over the bar adds one and every
        // frame under it subtracts one. Speech dips between syllables, so a
        // strict consecutive-frame run misses ordinary talking, while a
        // leaky count still ignores isolated clicks and echo transients.
        BARGEIN_ATTACK_FRAMES: 6,

        // Pre-roll is kept short while the doctor talks so that whatever echo
        // is sitting in the buffer when the patient cuts in cannot be long
        // enough to be transcribed as words.
        BARGEIN_PREROLL_MS: 500
    };

    let stream = null;
    let audioCtx = null;
    let analyser = null;
    let recorder = null;
    let chunks = [];
    let rafId = null;

    let state = 'idle';       // idle | listening | capturing | transcribing | error
    let cfg = {};
    // 'open'    — normal listening, a turn may start
    // 'closed'  — doctor holds the floor, input ignored entirely
    // 'bargein' — doctor is speaking but the patient may interrupt
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

    // ================= helpers =================

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

    /** getUserMedia needs a secure context; file:// and plain http on a remote
     *  host both fail with errors that do not say so. */
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

    // ================= recorder segments =================

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
                if (running) startSegment();   // rolling recycle while idle
                return;
            }
            const blob = new Blob(captured, { type: (recorder && recorder.mimeType) || 'audio/webm' });
            const spokenMs = Date.now() - utteranceStart;
            // Immediately re-arm so the patient can start their next sentence
            // while the previous one is still being transcribed.
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

    // ================= voice activity detection =================

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

        // Already sending an utterance upstream — do not open another turn.
        if (state === 'transcribing') {
            speechFrames = 0;
            if (now - segmentStart > TUNING.PREROLL_MS) stopSegment(true);
            return;
        }

        // Doctor holds the floor and cannot be interrupted.
        if (gateMode === 'closed') {
            speechFrames = 0;
            bargeFrames = 0;
            if (now - segmentStart > TUNING.PREROLL_MS) stopSegment(true);
            return;
        }

        // Doctor is speaking aloud, but the patient is allowed to cut in.
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
                // The caller silences the doctor and reopens the gate; the
                // short pre-roll below means this utterance is still caught
                // from very close to its onset.
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

        // Not capturing: track the room's noise floor and watch for speech onset.
        if (!isVoice) {
            noiseFloor = noiseFloor * 0.95 + rms * 0.05;
            speechFrames = 0;
            // Recycle the recorder so a turn never carries more than
            // PREROLL_MS of leading silence.
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

    // ================= upload =================

    async function upload(blob, spokenMs) {
        setState('transcribing', { audioMs: spokenMs });

        const form = new FormData();
        const ext = (blob.type || '').includes('mp4') ? 'mp4' : 'webm';
        form.append('audio', blob, `utterance.${ext}`);
        if (cfg.language) form.append('language', cfg.language);

        const sentAt = performance.now();
        // Without a deadline the UI can sit on "transcribing" forever: the
        // server serialises decoding through a single worker, so one slow turn
        // used to leave the patient staring at "أفهم ما قلته…" with no way out.
        // The server has its own decode deadline; this is the client-side
        // backstop for the request never coming back at all.
        const controller = new AbortController();
        const abortTimer = setTimeout(() => controller.abort(), TUNING.UPLOAD_TIMEOUT_MS);
        try {
            const res = await fetch(AI_BASE + '/virtual-doctor/transcribe', {
                method: 'POST', body: form, signal: controller.signal
            });
            if (!res.ok) {
                let detail = `HTTP ${res.status}`;
                try {
                    const body = await res.json();
                    if (body && body.detail) detail = body.detail;
                } catch (_) { /* non-JSON body */ }
                emitError({
                    code: 'server',
                    key: res.status === 413 ? 'stt.errTooLong' : 'stt.errServer',
                    detail, showHelp: false, fatal: false
                });
                resumeListening();
                return;
            }

            const data = await res.json();
            const roundTripMs = Math.round(performance.now() - sentAt);
            const text = (data.text || '').trim();

            if (!text) {
                // Staying silent here is right for a cough or a door slam, but
                // it is wrong when the patient actually spoke and got nothing
                // back — they are left with no feedback at all, which reads as
                // the app having frozen. Short answers (a name) are exactly the
                // case that returns empty, so speech-length audio now asks for
                // a repeat; only genuinely brief blips stay silent.
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
            // An abort is our own deadline firing, not a broken network.
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

    // ================= lifecycle =================

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

    /**
     * Who currently holds the floor.
     *   'open'    — patient may start a turn (normal listening)
     *   'closed'  — doctor is thinking; input ignored
     *   'bargein' — doctor is speaking aloud; a loud, sustained sound
     *               interrupts it via the onBargeIn callback
     */
    function setGateMode(mode) {
        const next = (mode === 'closed' || mode === 'bargein') ? mode : 'open';
        if (next === gateMode) return;
        gateMode = next;
        speechFrames = 0;
        bargeFrames = 0;
        if (gateMode === 'open') {
            resumeListening();
        } else {
            // Start a fresh segment so the buffer does not already hold the
            // doctor's audio when the patient interrupts.
            stopSegment(true);
        }
    }

    /** Back-compat shim for callers that only know open/closed. */
    function setGateOpen(open) {
        setGateMode(open ? 'open' : 'closed');
    }

    async function fetchStatus() {
        try {
            const res = await fetch(AI_BASE + '/virtual-doctor/transcribe/status');
            return res.ok ? await res.json() : null;
        } catch (_) {
            return null;
        }
    }

    /** Fire-and-forget model load. Cold-loading Whisper costs several seconds
     *  and would otherwise land on the patient's very first answer; starting
     *  it here lets it overlap the doctor's greeting. */
    function warmup() {
        // Pass the session language: Arabic and English load different model
        // sizes on CPU, so warming the wrong one leaves a full cold load on
        // the patient's first answer — long enough to look like a freeze.
        const qs = cfg.language ? `?language=${encodeURIComponent(cfg.language)}` : '';
        return fetch(AI_BASE + '/virtual-doctor/transcribe/warmup' + qs, { method: 'POST' })
            .then((res) => (res.ok ? res.json() : null))
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
