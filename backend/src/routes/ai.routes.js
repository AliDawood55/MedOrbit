const express = require('express');
const multer = require('multer');

const { authenticate } = require('../middleware/auth');
const { findAuthorizedMedicalRecord } = require('../services/clinicalAuthorization.service');
const { internalIdentityHeaders } = require('../services/aiBoundary.service');
const { error } = require('../utils/response');
const { createAiFeatureLimiter } = require('../middleware/rateLimit');
const { policy: billingPolicy } = require('../config/billing');

const router = express.Router();
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024, files: 1 },
});
const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8001';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const drugInteractionsLimiter = createAiFeatureLimiter({
    max: billingPolicy.fairUse.drugInteractionsPerMinute,
    message: 'Too many drug interaction checks. Please slow down.',
});

async function forward(url, options) {
    const response = await fetch(`${AI_SERVICE_URL}${url}`, {
        ...options,
        signal: AbortSignal.timeout(120000),
    });
    const payload = await response.json().catch(() => null);
    return { status: response.status, payload };
}

function normalizeMedicationList(value, fieldName) {
    if (value === undefined) return null;
    if (!Array.isArray(value) || value.length < 2 || value.length > 20) {
        throw Object.assign(new Error(`${fieldName} must contain between 2 and 20 items`), {
            statusCode: 400,
            code: 'VALIDATION_ERROR',
        });
    }

    const normalized = value.map((item) => String(item || '').trim());
    if (normalized.some((item) => !item || item.length > 120)) {
        throw Object.assign(new Error(`${fieldName} contains an invalid item`), {
            statusCode: 400,
            code: 'VALIDATION_ERROR',
        });
    }

    if (fieldName === 'medication_ids' && normalized.some((item) => !UUID.test(item))) {
        throw Object.assign(new Error('medication_ids must contain UUID values'), {
            statusCode: 400,
            code: 'VALIDATION_ERROR',
        });
    }

    return [...new Set(normalized)];
}

router.post('/triage', authenticate, async (req, res, next) => {
    try {
        const headers = { 'Content-Type': 'application/json' };
        if (req.user) Object.assign(headers, internalIdentityHeaders({ userId: req.user.sub }));

        const upstream = await forward('/triage', {
            method: 'POST',
            headers,
            body: JSON.stringify({ symptoms: req.body.symptoms, session_id: req.body.session_id }),
        });
        if (upstream.status >= 400) {
            return error(res, 'AI triage request failed', upstream.status, 'AI_SERVICE_ERROR');
        }
        return res.status(upstream.status).json(upstream.payload);
    } catch (err) {
        return next(err);
    }
});

// Stateless drug checks still cross the authenticated backend boundary. This
// gives clients one response envelope, server-side validation, a per-user AI
// burst limit, and an internal service credential without yet changing the
// existing direct AI endpoint before web/mobile clients have migrated.
router.post('/drug-interactions', authenticate, drugInteractionsLimiter, async (req, res, next) => {
    try {
        const medicationNames = normalizeMedicationList(req.body?.medication_names, 'medication_names');
        const medicationIds = normalizeMedicationList(req.body?.medication_ids, 'medication_ids');

        if (!medicationNames && !medicationIds) {
            return error(res, 'Provide medication_names or medication_ids', 400, 'VALIDATION_ERROR');
        }

        const upstream = await forward('/drug-interactions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                ...internalIdentityHeaders({ userId: req.user.sub }),
            },
            body: JSON.stringify({
                ...(medicationNames ? { medication_names: medicationNames } : {}),
                ...(medicationIds ? { medication_ids: medicationIds } : {}),
            }),
        });

        if (upstream.status >= 400) {
            return error(
                res,
                'AI drug interaction request failed',
                upstream.status >= 500 ? 502 : upstream.status,
                'AI_SERVICE_ERROR'
            );
        }

        return res.status(200).json({
            success: true,
            data: upstream.payload,
            message: 'Drug interactions checked',
            timestamp: new Date().toISOString(),
        });
    } catch (err) {
        if (err.statusCode) {
            return error(res, err.message, err.statusCode, err.code || 'VALIDATION_ERROR');
        }
        return next(err);
    }
});

router.post('/summarize', authenticate, upload.single('file'), async (req, res, next) => {
    try {
        const requestedRecordId = req.body.record_id || null;
        if (requestedRecordId && !req.user) {
            return error(res, 'Authentication required', 401, 'UNAUTHORIZED');
        }
        if (requestedRecordId) {
            const record = await findAuthorizedMedicalRecord(requestedRecordId, req.user);
            if (!record) return error(res, 'Record not found', 404, 'NOT_FOUND');
        }

        const form = new FormData();
        if (req.file) {
            form.append('file', new Blob([req.file.buffer], { type: req.file.mimetype }), req.file.originalname);
        } else if (req.body.text) {
            form.append('text', req.body.text);
        } else {
            return error(res, 'Provide either a file or text field', 400, 'VALIDATION_ERROR');
        }

        const headers = req.user
            ? internalIdentityHeaders({ userId: req.user.sub, recordId: requestedRecordId })
            : {};
        const upstream = await forward('/summarize', { method: 'POST', headers, body: form });
        if (upstream.status >= 400) {
            return error(res, 'AI summarization request failed', upstream.status, 'AI_SERVICE_ERROR');
        }
        return res.status(upstream.status).json(upstream.payload);
    } catch (err) {
        return next(err);
    }
});

module.exports = router;
