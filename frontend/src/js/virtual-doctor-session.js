const VirtualDoctorSession = (() => {

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

function isEntitlementDenial(err) {
        return err && (
            err.code === 'VOICE_COOLDOWN' ||
            err.code === 'FREE_QUOTA_EXHAUSTED' ||
            err.code === 'SUBSCRIPTION_REQUIRED' ||
            err.code === 'SUBSCRIPTION_INACTIVE'
        );
    }

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

const envelope = await API.virtualDoctor.start(language);
            res = envelope.data;
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
            throw err;
        }

        if (myGeneration !== generation) {

await finalizeOrphanedSession(res.session_id);
            return null;
        }
        sessionId = res.session_id;
        phase = res.phase;

language = res.language || language;

if (res.resumed) {
            emit('onResumed', { sessionId, phase });
        }

        await doctorSpeaks(res.reply);
        if (myGeneration !== generation) return null;
        emit('onState', { state: 'listening' });
        return { sessionId, language, reply: res.reply, phase, resumed: Boolean(res.resumed) };
    }

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

async function requestReport() {
        if (!sessionId) return { ok: false, reason: 'no_session' };
        try {
            const envelope = await API.virtualDoctor.report(sessionId);
            const res = envelope.data;
            return {
                ok: true,
                reportId: res.report_id,

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
