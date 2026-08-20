const express = require('express');
const multer = require('multer');
const { createAiFeatureLimiter } = require('../middleware/rateLimit');

const db = require('../config/database');
const { authenticate } = require('../middleware/auth');
const { internalIdentityHeaders } = require('../services/aiBoundary.service');
const entitlementService = require('../services/entitlement.service');
const { ERROR_CODES, policy } = require('../config/billing');
const { success, error } = require('../utils/response');
const logger = require('../utils/logger');

/**
 * Virtual Doctor gateway.
 *
 * Before this existed, both the web and Flutter clients talked to the AI
 * service directly on port 8001 and sent `user_id: null`. The AI service
 * authenticated nothing, so consultations belonged to nobody, any caller could
 * read any session by id, and no entitlement check was possible anywhere.
 *
 * Every Virtual Doctor call now enters here instead. The route authenticates
 * the user, asks EntitlementService whether the call is allowed, and only then
 * forwards to the AI service over the internal service-to-service boundary
 * that /triage and /summarize already use. The AI service refuses anything
 * that does not carry that internal credential, so bypassing this gateway is
 * not merely discouraged — it fails.
 *
 * The identity forwarded is the one resolved from the access token by
 * middleware/auth.js against the users table. A client-supplied user_id is
 * never read, and the AI service rejects the request outright if one is
 * present in the payload.
 */

const router = express.Router();

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8001';

// Audio turns are short. The ceiling is generous enough for a long answer and
// small enough that a hostile client cannot use the gateway as an upload sink.
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024, files: 1 },
});

/**
 * Fair-use limiter. Applies to Pro as well as free users: "unlimited" is a
 * statement about product quota, not an invitation to saturate the AI workers
 * from one account.
 */
const voiceFairUse = createAiFeatureLimiter({
    max: policy.fairUse.chatbotMessagesPerMinute,
    message: 'Too many requests. Please slow down.',
});

async function forwardJson(path, { userId, body, method = 'POST' }) {
    const response = await fetch(`${AI_SERVICE_URL}${path}`, {
        method,
        headers: {
            'Content-Type': 'application/json',
            ...internalIdentityHeaders({ userId }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(120000),
    });
    const payload = await response.json().catch(() => null);
    return { status: response.status, payload };
}

/** Translate an entitlement denial into the project's error envelope. */
function denied(res, decision) {
    const status = decision.code === ERROR_CODES.VOICE_COOLDOWN ? 429 : 403;
    const messages = {
        [ERROR_CODES.VOICE_COOLDOWN]: 'Your next free consultation is not available yet.',
        [ERROR_CODES.FREE_QUOTA_EXHAUSTED]: 'Your free allowance for this period is used.',
        [ERROR_CODES.ENTITLEMENT_UNAVAILABLE]: 'Entitlement could not be determined. Please try again.',
    };
    return error(res, messages[decision.code] || 'Not permitted', status, decision.code, decision.meta || null);
}

/**
 * Start or rejoin a consultation.
 *
 * A refresh, a reconnect, or a duplicated request returns the SAME session
 * rather than starting a new one, because EntitlementService resolves an
 * existing active grant before it considers issuing a new one. None of those
 * events costs the user their free consultation.
 */
router.post('/start', authenticate, voiceFairUse, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const decision = await entitlementService.startVoiceSession(userId);
        if (!decision.allowed) return denied(res, decision);

        // Resuming, but a concurrent /start is still waiting on the AI service
        // and has not published its session id yet. Wait for it rather than
        // starting a second consultation — this is the double-tap case.
        if (decision.resumed && !decision.grant.vd_session_id) {
            const attached = await entitlementService.awaitSessionAttachment(decision.grant.id);
            if (!attached) {
                return error(res, 'Your consultation is still starting.', 409, 'SESSION_STARTING');
            }
            decision.grant = attached;
        }

        // Resuming: the consultation already exists upstream, so hand back its
        // current state instead of creating a second one.
        if (decision.resumed && decision.grant.vd_session_id) {
            const upstream = await forwardJson(
                `/virtual-doctor/session/${encodeURIComponent(decision.grant.vd_session_id)}`,
                { userId, method: 'GET' }
            );
            if (upstream.status < 400) {
                return success(res, {
                    ...upstream.payload,
                    session_id: decision.grant.vd_session_id,
                    resumed: true,
                    entitlement_source: decision.grant.entitlement_source,
                });
            }
            // The grant outlived the upstream session (an AI-service restart,
            // for instance). Finalize the orphan so the user is not stuck
            // holding an active grant pointing at nothing.
            await entitlementService.finalizeVoiceSession(userId, decision.grant.vd_session_id, 'abandoned');
            return error(res, 'Your previous consultation is no longer available.', 409, 'SESSION_UNAVAILABLE');
        }

        const language = req.body?.language === 'ar' ? 'ar' : 'en';
        const upstream = await forwardJson('/virtual-doctor/start', {
            userId,
            // No user_id in the body: identity travels in the internal header,
            // and the AI service rejects payload-supplied identity.
            body: { language },
        });

        if (upstream.status >= 400) {
            // The grant was reserved but the consultation never began. Release
            // it rather than charging the user for a session they never had —
            // and without starting a cooldown, since the failure was ours.
            await entitlementService.releaseUnusedGrant(decision.grant.id).catch(() => {});
            return error(res, 'Virtual Doctor is unavailable', 503, 'AI_SERVICE_ERROR');
        }

        await entitlementService.attachVoiceSession(decision.grant.id, upstream.payload.session_id);

        return success(res, {
            ...upstream.payload,
            resumed: false,
            entitlement_source: decision.grant.entitlement_source,
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * One conversational turn.
 *
 * Ownership is re-checked every turn rather than trusted from /start, so a
 * session id leaked or guessed by another account is useless: the lookup is
 * scoped to the caller and simply finds nothing.
 */
router.post('/message', authenticate, voiceFairUse, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const sessionId = req.body?.session_id;
        const message = req.body?.message;

        if (!sessionId || typeof message !== 'string') {
            return error(res, 'session_id and message are required', 400, 'VALIDATION_ERROR');
        }

        const auth = await entitlementService.authorizeVoiceSession(userId, sessionId);
        if (!auth.allowed) {
            if (auth.code === 'NOT_FOUND') return error(res, 'Session not found', 404, 'NOT_FOUND');
            return denied(res, auth);
        }

        const upstream = await forwardJson('/virtual-doctor/message', {
            userId,
            body: { session_id: sessionId, message },
        });

        if (upstream.status >= 400) {
            return error(res, 'Virtual Doctor is unavailable', upstream.status === 404 ? 404 : 503, 'AI_SERVICE_ERROR');
        }

        // A consultation that has reached its conclusion finalizes here, which
        // is what starts the free cooldown. Anchoring the cooldown to the end
        // of the consultation rather than its start is the product promise:
        // "24 hours after your consultation ends".
        if (upstream.payload?.phase === 'complete') {
            await entitlementService.finalizeVoiceSession(userId, sessionId, 'completed');
        }

        return success(res, upstream.payload);
    } catch (err) {
        return next(err);
    }
});

/** Rehydrate an in-progress consultation after a refresh or reconnect. */
router.get('/session/:sessionId', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const grant = await entitlementService.authorizeVoiceSession(userId, req.params.sessionId);
        if (!grant.allowed && grant.code === 'NOT_FOUND') {
            return error(res, 'Session not found', 404, 'NOT_FOUND');
        }

        const upstream = await forwardJson(
            `/virtual-doctor/session/${encodeURIComponent(req.params.sessionId)}`,
            { userId, method: 'GET' }
        );
        if (upstream.status >= 400) return error(res, 'Session not found', 404, 'NOT_FOUND');
        return success(res, upstream.payload);
    } catch (err) {
        return next(err);
    }
});

/**
 * Speech-to-text for one turn.
 *
 * Gated on holding an active consultation rather than merely being logged in,
 * so the transcription model cannot be used as a free standalone service by
 * anyone with an account.
 */
router.post('/transcribe', authenticate, voiceFairUse, upload.single('audio'), async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const sessionId = req.body?.session_id;
        if (!sessionId) return error(res, 'session_id is required', 400, 'VALIDATION_ERROR');
        if (!req.file) return error(res, 'audio is required', 400, 'VALIDATION_ERROR');

        const auth = await entitlementService.authorizeVoiceSession(userId, sessionId);
        if (!auth.allowed) {
            if (auth.code === 'NOT_FOUND') return error(res, 'Session not found', 404, 'NOT_FOUND');
            return denied(res, auth);
        }

        const form = new FormData();
        form.append('audio', new Blob([req.file.buffer], { type: req.file.mimetype }), req.file.originalname || 'audio.webm');
        if (req.body.language) form.append('language', req.body.language);

        const response = await fetch(`${AI_SERVICE_URL}/virtual-doctor/transcribe`, {
            method: 'POST',
            headers: internalIdentityHeaders({ userId }),
            body: form,
            signal: AbortSignal.timeout(120000),
        });
        const payload = await response.json().catch(() => null);
        if (response.status >= 400) {
            return error(res, 'Transcription failed', response.status, 'AI_SERVICE_ERROR');
        }
        return success(res, payload);
    } catch (err) {
        return next(err);
    }
});

/**
 * Text-to-speech for one doctor reply.
 *
 * Passes the audio bytes straight through. The upstream contract is that a TTS
 * failure must never block a consultation, so a non-200 is surfaced as-is and
 * the client carries on with text.
 */
router.post('/speak', authenticate, voiceFairUse, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const sessionId = req.body?.session_id;
        if (!sessionId) return error(res, 'session_id is required', 400, 'VALIDATION_ERROR');

        const auth = await entitlementService.authorizeVoiceSession(userId, sessionId);
        if (!auth.allowed) {
            if (auth.code === 'NOT_FOUND') return error(res, 'Session not found', 404, 'NOT_FOUND');
            return denied(res, auth);
        }

        const response = await fetch(`${AI_SERVICE_URL}/virtual-doctor/speak`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', ...internalIdentityHeaders({ userId }) },
            body: JSON.stringify({ text: req.body?.text, language: req.body?.language }),
            signal: AbortSignal.timeout(120000),
        });

        if (response.status >= 400) {
            return error(res, 'Speech synthesis unavailable', 503, 'TTS_UNAVAILABLE');
        }

        const audio = Buffer.from(await response.arrayBuffer());
        res.set({
            'Content-Type': 'audio/wav',
            'X-TTS-Voice': response.headers.get('X-TTS-Voice') || '',
            'X-TTS-Language': response.headers.get('X-TTS-Language') || '',
            'Cache-Control': 'private, max-age=86400',
        });
        return res.send(audio);
    } catch (err) {
        return next(err);
    }
});

/**
 * Generate the consultation report, then finalize the session.
 *
 * Producing the report is the natural end of a consultation, so this is where
 * a free grant is consumed and the 24-hour cooldown begins.
 */
router.post('/report/:sessionId', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const sessionId = req.params.sessionId;

        const auth = await entitlementService.authorizeVoiceSession(userId, sessionId);
        if (!auth.allowed && auth.code === 'NOT_FOUND') {
            return error(res, 'Session not found', 404, 'NOT_FOUND');
        }

        const upstream = await forwardJson(
            `/virtual-doctor/report/${encodeURIComponent(sessionId)}`,
            { userId, body: {} }
        );
        if (upstream.status >= 400) {
            const code = upstream.status === 503 ? 'PDF_UNAVAILABLE' : 'AI_SERVICE_ERROR';
            return error(res, 'Report generation failed', upstream.status === 503 ? 503 : 404, code);
        }

        await entitlementService.finalizeVoiceSession(userId, sessionId, 'completed');

        return success(res, {
            ...upstream.payload,
            download_url: `/api/virtual-doctor/report/${upstream.payload.report_id}/download`,
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * Download a report PDF.
 *
 * Ownership is resolved in the database here rather than upstream, because the
 * backend already shares the schema and can join the report to its session's
 * owner in one query. A report belonging to another account is reported as
 * missing, never as forbidden.
 */
router.get('/report/:reportId/download', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const owned = await db.query(
            `SELECT r.id
               FROM medorbit.virtual_doctor_reports r
               JOIN medorbit.virtual_doctor_sessions s ON s.id = r.session_id
              WHERE r.id = $1 AND s.user_id = $2`,
            [req.params.reportId, userId]
        );
        if (owned.rows.length !== 1) {
            return error(res, 'Report not found', 404, 'NOT_FOUND');
        }

        const response = await fetch(
            `${AI_SERVICE_URL}/virtual-doctor/report/${encodeURIComponent(req.params.reportId)}/download`,
            { headers: internalIdentityHeaders({ userId }), signal: AbortSignal.timeout(120000) }
        );
        if (response.status >= 400) return error(res, 'Report not found', 404, 'NOT_FOUND');

        const pdf = Buffer.from(await response.arrayBuffer());
        res.set({
            'Content-Type': 'application/pdf',
            'Content-Disposition': `attachment; filename="${req.params.reportId}.pdf"`,
        });
        return res.send(pdf);
    } catch (err) {
        return next(err);
    }
});

/**
 * Explicitly end a consultation.
 *
 * Lets a user who walks away close the session deliberately instead of waiting
 * out the idle timeout. It ends their own consultation only.
 */
router.post('/session/:sessionId/end', authenticate, async (req, res, next) => {
    try {
        const finalized = await entitlementService.finalizeVoiceSession(
            req.user.sub, req.params.sessionId, 'abandoned'
        );
        if (!finalized) return error(res, 'Session not found', 404, 'NOT_FOUND');
        return success(res, { status: finalized.status, next_free_at: finalized.next_free_at });
    } catch (err) {
        return next(err);
    }
});

/**
 * Model warm-up and readiness.
 *
 * Authenticated but not entitlement-gated: these load or report on a shared
 * model and carry no consultation content. They stay behind the fair-use
 * limiter so they cannot be used to thrash the model loader.
 */
for (const path of ['/transcribe/warmup', '/speak/warmup']) {
    router.post(path, authenticate, voiceFairUse, async (req, res, next) => {
        try {
            const query = req.query.language ? `?language=${encodeURIComponent(req.query.language)}` : '';
            const upstream = await forwardJson(`/virtual-doctor${path}${query}`, {
                userId: req.user.sub,
                body: undefined,
            });
            // Warm-up is best effort by design; a failure here must not look
            // like a broken consultation.
            if (upstream.status >= 400) return success(res, { warmed: false });
            return success(res, upstream.payload);
        } catch (err) {
            logger.warn({ billing_event: 'voice_warmup_failed' }, 'virtual-doctor.warmup_failed');
            return success(res, { warmed: false });
        }
    });
}

for (const path of ['/transcribe/status', '/speak/status']) {
    router.get(path, authenticate, async (req, res, next) => {
        try {
            const upstream = await forwardJson(`/virtual-doctor${path}`, {
                userId: req.user.sub,
                method: 'GET',
            });
            if (upstream.status >= 400) return error(res, 'Status unavailable', 503, 'AI_SERVICE_ERROR');
            return success(res, upstream.payload);
        } catch (err) {
            return next(err);
        }
    });
}

module.exports = router;
