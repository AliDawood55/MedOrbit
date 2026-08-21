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

    /**
     * Entitlement denials are not consultation errors.
     *
     * A cooldown or an exhausted allowance is a normal product state that the
     * UI must render as a paywall, so they are separated from genuine faults
     * here rather than being surfaced as "something went wrong".
     */
    function isEntitlementDenial(err) {
        return err && (
            err.code === 'VOICE_COOLDOWN' ||
            err.code === 'FREE_QUOTA_EXHAUSTED' ||
            err.code === 'SUBSCRIPTION_REQUIRED' ||
            err.code === 'SUBSCRIPTION_INACTIVE'
        );
    }

    /**
     * The doctor takes the floor, then hands it back.
     *
     * If the onDoctorTurn handler returns a promise — which it does once TTS
     * is wired in — the floor is held until that resolves, i.e. until speech
     * actually finishes or is interrupted. Without TTS it falls back to a
     * fixed beat, so this module stays usable with speech switched off.
     */
    /**
     * A start() (or a mid-flight message()) can lose the race against an
     * explicit end/reset: the server has already created or holds an active
     * session, but local state was cleared before the response landed, so
     * nothing else will ever ask the server to close it. Best-effort finalize
     * it here instead of leaving it orphaned until stale-grant expiry.
     */
    async function finalizeOrphanedSession(id) {
        if (!id) return;
        try {
            await API.virtualDoctor.endSession(id);
        } catch (err) {
            console.error('[vd-session] orphaned-session cleanup failed:', err);
        }
    }

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

        let res;
        try {
            // No user_id is sent. Identity comes from the access token the API
            // layer attaches, and is resolved server-side — a client-supplied
            // id would be forgeable and the backend does not read one.
            const envelope = await API.virtualDoctor.start(language);
            res = envelope.data;
        } catch (err) {
            if (myGeneration !== generation) return null;
            if (isEntitlementDenial(err)) {
                // The server decides eligibility and returns the authoritative
                // instant the next free consultation unlocks. The UI counts
                // down to that timestamp; it never computes eligibility itself.
                emit('onState', { state: 'paywalled' });
                emit('onPaywall', {
                    code: err.code,
                    nextFreeAt: err.details?.next_free_at || null,
                    upgradeAvailable: err.details?.upgrade_available !== false
                });
                return null;
            }
            throw err;
        }

        if (myGeneration !== generation) {
            // The user ended/reset while this start() was in flight, but the
            // server went ahead and created a real session — it needs an
            // explicit end too, or it stays active with no local id to close
            // it. This is the ONLY orphan-cleanup site: sessionId has not
            // been assigned yet, so nothing else could have already ended
            // this session. Once sessionId is assigned below, end() owns
            // finalization — a later generation mismatch (e.g. after
            // doctorSpeaks) just returns, since an explicit end() already
            // sent the one /end this session needs.
            await finalizeOrphanedSession(res.session_id);
            return null;
        }
        sessionId = res.session_id;
        phase = res.phase;
        // The server echoes the session language; pin STT to it rather than
        // letting Whisper auto-detect, which is unreliable on short answers.
        language = res.language || language;

        // A refresh or reconnect returns the SAME consultation rather than
        // starting a new one, so neither costs the user their free session.
        if (res.resumed) {
            emit('onResumed', { sessionId, phase });
        }

        await doctorSpeaks(res.reply);
        if (myGeneration !== generation) return null;
        emit('onState', { state: 'listening' });
        return { sessionId, language, reply: res.reply, phase, resumed: Boolean(res.resumed) };
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
            const envelope = await API.virtualDoctor.message(sessionId, text);
            const res = envelope.data;
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
            if (isEntitlementDenial(err)) {
                emit('onState', { state: 'paywalled' });
                emit('onPaywall', {
                    code: err.code,
                    nextFreeAt: err.details?.next_free_at || null,
                    upgradeAvailable: err.details?.upgrade_available !== false
                });
                return null;
            }
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
            const envelope = await API.virtualDoctor.report(sessionId);
            const res = envelope.data;
            return {
                ok: true,
                reportId: res.report_id,
                // Served by the backend, which verifies the report belongs to
                // the caller before streaming a byte of it.
                downloadUrl: API.virtualDoctor.reportDownloadUrl(res.report_id)
            };
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

    /**
     * User-requested end of an in-progress consultation.
     *
     * A session that already reached phase 'complete' was finalized
     * server-side by the message/report lifecycle already — resetting the UI
     * on top of that must NOT re-finalize it as abandoned. So the server end
     * call only fires for a session that is still active.
     *
     * Local state (including sessionId) is cleared synchronously via reset()
     * before the network call, for two reasons: the caller's mic/audio
     * cleanup never waits on the network, and a second end() call — from a
     * double click, since the button disappears with the UI it clears, this
     * only guards stray re-entry — finds no sessionId and skips straight to
     * a no-op rather than firing a second request.
     */
    async function end() {
        const id = sessionId;
        const hadActiveSession = Boolean(id) && phase !== 'complete';
        reset();

        if (!hadActiveSession) {
            return { ended: false, reason: id ? 'already_complete' : 'no_session' };
        }

        try {
            await API.virtualDoctor.endSession(id);
            return { ended: true };
        } catch (err) {
            // The local session is already gone; the server grant is left for
            // its own stale-grant expiry to clean up (see
            // entitlement.service.js), so this is not a stuck state.
            console.error('[vd-session] end failed:', err);
            return { ended: false, reason: 'error', detail: err.message };
        }
    }

    return {
        init,
        start,
        submit,
        requestReport,
        reset,
        end,
        getPhase: () => phase,
        getLanguage: () => language,
        getSessionId: () => sessionId,
        isBusy: () => busy,
        DOCTOR_FLOOR_MS
    };
})();
