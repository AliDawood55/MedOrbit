const router = require('express').Router();
const db = require('../config/database');
const { authenticate, authorizeAdmin } = require('../middleware/auth');
const { closeRelationship } = require('../services/careRelationship.service');
const { success, error } = require('../utils/response');

router.get('/', authenticate, authorizeAdmin, async (req, res, next) => {
    try {
        const page = Math.max(Number.parseInt(req.query.page, 10) || 1, 1);
        const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 25, 1), 100);
        const status = req.query.status || null;
        if (status && !['pending', 'active', 'ended', 'revoked'].includes(status)) {
            return error(res, 'Invalid relationship status', 400, 'VALIDATION_ERROR');
        }
        const result = await db.query(
            `SELECT r.id, r.doctor_id, r.patient_id, r.status, r.source,
                    r.source_reference_id, r.started_at, r.ended_at,
                    r.created_by_user_id, r.ended_by_user_id, r.end_reason,
                    r.created_at, r.updated_at,
                    COUNT(*) OVER()::int AS total
             FROM medorbit.doctor_patient_relationships r
             WHERE ($1::varchar IS NULL OR r.status=$1)
             ORDER BY r.created_at DESC
             LIMIT $2 OFFSET $3`,
            [status, limit, (page - 1) * limit]
        );
        const total = result.rows[0]?.total || 0;
        return success(res, {
            items: result.rows.map(({ total: _total, ...row }) => row),
            pagination: { page, limit, total },
        }, 'Care relationships retrieved');
    } catch (err) {
        return next(err);
    }
});

router.post('/:id/revoke', authenticate, authorizeAdmin, async (req, res, next) => {
    const client = await db.getClient();
    try {
        if (!String(req.body.reason || '').trim()) {
            return error(res, 'Revocation reason is required', 400, 'VALIDATION_ERROR');
        }
        await client.query('BEGIN');
        const locked = await client.query(
            `SELECT id FROM medorbit.doctor_patient_relationships
             WHERE id=$1 AND status='active' FOR UPDATE`,
            [req.params.id]
        );
        if (!locked.rows[0]) {
            await client.query('ROLLBACK');
            return error(res, 'Relationship not found', 404, 'NOT_FOUND');
        }
        const relationship = await closeRelationship({
            relationshipId: locked.rows[0].id,
            status: 'revoked',
            actorUserId: req.user.sub,
            actorRole: req.user.role,
            reason: String(req.body.reason).trim(),
        }, client);
        await client.query('COMMIT');
        return success(res, relationship, 'Care relationship revoked');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        return next(err);
    } finally {
        client.release();
    }
});

module.exports = router;
