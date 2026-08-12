const express = require('express');

const db = require('../config/database');
const { authenticate } = require('../middleware/auth');
const { success, error } = require('../utils/response');

const router = express.Router();

router.get('/', authenticate, async (req, res, next) => {
    try {
        const result = await db.query(
            `SELECT id,
                    notification_type,
                    title_ar,
                    title_en,
                    message_ar,
                    message_en,
                    reference_id,
                    reference_type,
                    is_read,
                    read_at,
                    created_at
             FROM medorbit.notifications
             WHERE user_id=$1
             ORDER BY created_at DESC
             LIMIT 50`,
            [req.user.sub]
        );

        return success(res, result.rows, 'Notifications retrieved');
    } catch (err) {
        return next(err);
    }
});

router.get('/unread-count', authenticate, async (req, res, next) => {
    try {
        const result = await db.query(
            `SELECT count(*)::int AS count
             FROM medorbit.notifications
             WHERE user_id=$1 AND is_read=false`,
            [req.user.sub]
        );

        return success(res, { count: result.rows[0].count }, 'Unread notification count retrieved');
    } catch (err) {
        return next(err);
    }
});

router.put('/:id/read', authenticate, async (req, res, next) => {
    try {
        const result = await db.query(
            `UPDATE medorbit.notifications
             SET is_read=true,
                 read_at=COALESCE(read_at, NOW())
             WHERE id=$1 AND user_id=$2
             RETURNING id, notification_type, reference_id, reference_type,
                       is_read, read_at, created_at`,
            [req.params.id, req.user.sub]
        );

        if (!result.rows.length) {
            return error(res, 'Notification not found', 404, 'NOT_FOUND');
        }

        return success(res, result.rows[0], 'Notification marked as read');
    } catch (err) {
        return next(err);
    }
});

router.patch('/read-all', authenticate, async (req, res, next) => {
    try {
        const result = await db.query(
            `UPDATE medorbit.notifications
             SET is_read=true,
                 read_at=COALESCE(read_at, NOW())
             WHERE user_id=$1 AND is_read=false`,
            [req.user.sub]
        );

        return success(res, { updated: result.rowCount }, 'All notifications marked as read');
    } catch (err) {
        return next(err);
    }
});

router.delete('/:id', authenticate, async (req, res, next) => {
    try {
        const result = await db.query(
            `DELETE FROM medorbit.notifications
             WHERE id=$1 AND user_id=$2
             RETURNING id`,
            [req.params.id, req.user.sub]
        );

        if (!result.rows.length) {
            return error(res, 'Notification not found', 404, 'NOT_FOUND');
        }

        return success(res, null, 'Notification deleted');
    } catch (err) {
        return next(err);
    }
});

module.exports = router;
