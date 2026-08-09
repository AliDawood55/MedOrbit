/**
 * MedOrbit v2 - Virtual Doctor hands-free consultation session
 *
 * Drives one continuous voice consultation against the Track A interview
 * engine, with no clicking after the microphone prompt:
 *
 *   /virtual-doctor/start                  -> doctor greets, asks for a name
 *   patient speaks -> STT -> /message      -> next question   (repeat)
 *   phase === 'complete'                   -> summary + PDF offer
 *
 * Turn ownership is explicit. While the doctor holds the floor the microphone
 * gate is shut, so nothing said or played during that window is treated as a
 * patient answer. Today that covers the thinking pause; once TTS lands the
 * same gate keeps the avatar's own voice out of the transcript — that is why
 * it exists now rather than later.
 */
const VirtualDoctorSession = (() => {

    const AI_BASE = API.getAiOrigin();

    // How long the doctor keeps the floor after its reply is on screen. With
    // no TTS this is just a settling beat; when TTS arrives, replace this with
    // "until playback ends" and the rest of the gating already works.
    const DOCTOR_FLOOR_MS = 700;

    let sessionId = null;
    let language = 'en';
    let phase = 'idle';
    let busy = false;
    let cfg = {};
    let turnCount = 0;
    let generation = 0;

    function emit(name, payload) {
        const fn = cfg[name];
        return typeof fn === 'function' ? fn(payload) : undefined;
    }

    async function api(path, options) {
        const res = await fetch(AI_BASE + path, options);
        if (!res.ok) {
            let detail = `HTTP ${res.status}`;
            try {
                const body = await res.json();
                if (body && body.detail) detail = body.detail;
            } catch (_) { /* non-JSON error body */ }
            const err = new Error(detail);
            err.status = res.status;
            throw err;
        }
        return res.json();
    }

    function jsonPost(path, payload) {
        return api(path, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload || {})
        });
    }

    /**
     * The doctor takes the floor, then hands it back.
     *
     * If the onDoctorTurn handler returns a promise — which it does once TTS
     * is wired in — the floor is held until that resolves, i.e. until speech
     * actually finishes or is interrupted. Without TTS it falls back to a
     * fixed beat, so this module stays usable with speech switched off.
     */
    async function doctorSpeaks(reply, meta) {
        emit('onState', { state: 'doctorSpeaking' });
        const handled = emit('onDoctorTurn', { text: reply, phase, meta: meta || {} });
        if (handled && typeof handled.then === 'function') {
            await handled;
        } else {
            await new Promise((resolve) => setTimeout(resolve, DOCTOR_FLOOR_MS));
        }
    }

    async function start(lang) {
        const myGeneration = ++generation;
        language = (lang === 'ar' || lang === 'en') ? lang : 'en';
        emit('onState', { state: 'connecting' });

        const res = await jsonPost('/virtual-doctor/start', { language, user_id: null });
        if (myGeneration !== generation) return null;
        sessionId = res.session_id;
        phase = res.phase;
        // The server echoes the session language; pin STT to it rather than
        // letting Whisper auto-detect, which is unreliable on short answers.
        language = res.language || language;

        await doctorSpeaks(res.reply);
        if (myGeneration !== generation) return null;
        emit('onState', { state: 'listening' });
        return { sessionId, language, reply: res.reply, phase };
    }

    /** Feed one transcribed patient utterance into the interview engine. */
    async function submit(text) {
        if (!sessionId || busy || phase === 'complete') return null;
        const myGeneration = generation;
        busy = true;
        turnCount += 1;
        const startedAt = performance.now();

        emit('onPatientTurn', { text });
        emit('onState', { state: 'thinking' });

        try {
            const res = await jsonPost('/virtual-doctor/message', {
                session_id: sessionId,
                message: text
            });
            if (myGeneration !== generation) return null;
            phase = res.phase;
            const elapsedMs = Math.round(performance.now() - startedAt);

            await doctorSpeaks(res.reply, { elapsedMs, turn: turnCount });
            if (myGeneration !== generation) return null;

            if (phase === 'complete') {
                emit('onState', { state: 'complete' });
                emit('onComplete', {
                    urgencyLevel: res.urgency_level,
                    specialtyEn: res.recommended_specialty_name_en,
                    specialtyAr: res.recommended_specialty_name_ar,
                    confidence: res.confidence,
                    differential: res.differential,
                    profile: res.profile_snapshot || {},
                    chiefComplaint: res.chief_complaint
                });
            } else {
                emit('onState', { state: 'listening' });
            }
            return res;
        } catch (err) {
            if (myGeneration !== generation) return null;
            console.error('[vd-session] message failed:', err);
            emit('onError', { key: 'session.errEngine', detail: err.message, fatal: false });
            emit('onState', { state: 'listening' });
            return null;
        } finally {
            busy = false;
        }
    }

    /**
     * Ask for the PDF. A 503 means the renderer is unavailable on this machine
     * (a known, separately-tracked environment fault) — the consultation and
     * its on-screen summary are unaffected, so this resolves to a status
     * rather than throwing.
     */
    async function requestReport() {
        if (!sessionId) return { ok: false, reason: 'no_session' };
        try {
            const res = await jsonPost(`/virtual-doctor/report/${sessionId}`, {});
            return { ok: true, reportId: res.report_id, downloadUrl: AI_BASE + res.download_url };
        } catch (err) {
            if (err.status === 503) {
                console.warn('[vd-session] PDF unavailable:', err.message);
                return { ok: false, reason: 'pdf_unavailable', detail: err.message };
            }
            return { ok: false, reason: 'error', detail: err.message };
        }
    }

    function init(options) {
        cfg = options || {};
    }

    function reset() {
        generation += 1;
        sessionId = null;
        phase = 'idle';
        busy = false;
        turnCount = 0;
    }

    return {
        init,
        start,
        submit,
        requestReport,
        reset,
        getPhase: () => phase,
        getLanguage: () => language,
        getSessionId: () => sessionId,
        isBusy: () => busy,
        DOCTOR_FLOOR_MS
    };
})();
