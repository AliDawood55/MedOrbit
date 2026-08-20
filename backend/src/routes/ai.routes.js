const express = require('express');
const multer = require('multer');

const { authenticate } = require('../middleware/auth');
const { findAuthorizedMedicalRecord } = require('../services/clinicalAuthorization.service');
const { internalIdentityHeaders } = require('../services/aiBoundary.service');
const { error } = require('../utils/response');

const router = express.Router();
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024, files: 1 },
});
const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8001';

async function forward(url, options) {
    const response = await fetch(`${AI_SERVICE_URL}${url}`, {
        ...options,
        signal: AbortSignal.timeout(120000),
    });
    const payload = await response.json().catch(() => null);
    return { status: response.status, payload };
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
