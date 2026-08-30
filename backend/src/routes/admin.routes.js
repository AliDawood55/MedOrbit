const router = require('express').Router();
const db = require('../config/database');
const { authenticate, authorizeAdmin } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const { createAudit } = require('../services/audit.service');
const { collectMlReadiness } = require('../services/mlReadiness.service');

const SAFE_USER_COLUMNS = `
    id, email, role, is_active, email_verified, deleted_at,
    authorization_version, preferred_language, created_at, updated_at
`;

function mutationBlocked(req, target) {
    if (req.user.sub === target.id) return 'Administrators cannot modify their own security state';
    if (target.role === 'super_admin') return 'Super admin accounts cannot be modified through ordinary admin routes';
    if (target.role === 'admin' && req.user.role !== 'super_admin') return 'Only a super admin can modify an admin account';
    return null;
}

router.get('/ml-readiness',authenticate,authorizeAdmin,async(req,res,next)=>{
    try{const {systemIdentifier,...report}=await collectMlReadiness();return success(res,report,'ML readiness retrieved');}
    catch(error){return next(error);}
});

router.get('/users', authenticate, authorizeAdmin, async (req, res, next) => {
    try {
        const { role, active, search } = req.query;
        let query = `
            SELECT u.id, u.email, u.role, u.is_active, u.email_verified,
                   u.authorization_version,
                   up.first_name_en, up.last_name_en, up.phone, up.city
            FROM medorbit.users u
            LEFT JOIN medorbit.user_profiles up ON u.id=up.user_id
            WHERE 1=1`;
        const values = [];

        if (role) {
            values.push(role);
            query += ` AND u.role=$${values.length}`;
        }
        if (active != null) {
            values.push(active === 'true');
            query += ` AND u.is_active=$${values.length}`;
        }
        if (search) {
            values.push(`%${search}%`);
            query += ` AND (u.email ILIKE $${values.length}
                         OR up.first_name_en ILIKE $${values.length}
                         OR up.last_name_en ILIKE $${values.length})`;
        }
        query += ' ORDER BY u.created_at DESC';

        const result = await db.query(query, values);
        return success(res, result.rows, 'Users retrieved');
    } catch (err) {
        return next(err);
    }
});

// Operational summaries for the mobile administration console. These rows are
// deliberately metadata-only: administrators can monitor platform activity
// without this endpoint becoming a second clinical-record viewer.
const ACTIVITY_QUERIES = {
    appointments: `
        SELECT a.id, a.appointment_number AS reference, a.status,
               a.scheduled_date AS occurred_on, a.appointment_type AS detail,
               pu.email AS patient_email, du.email AS doctor_email
        FROM medorbit.appointments a
        JOIN medorbit.patients p ON p.id=a.patient_id
        JOIN medorbit.users pu ON pu.id=p.user_id
        JOIN medorbit.doctors d ON d.id=a.doctor_id
        JOIN medorbit.users du ON du.id=d.user_id
        ORDER BY a.scheduled_date DESC, a.start_time DESC
        LIMIT 100`,
    records: `
        SELECT r.id, r.record_number AS reference, r.record_type AS status,
               r.created_at AS occurred_on, NULL::text AS detail,
               pu.email AS patient_email, du.email AS doctor_email
        FROM medorbit.medical_records r
        JOIN medorbit.patients p ON p.id=r.patient_id
        JOIN medorbit.users pu ON pu.id=p.user_id
        JOIN medorbit.doctors d ON d.id=r.doctor_id
        JOIN medorbit.users du ON du.id=d.user_id
        ORDER BY r.created_at DESC
        LIMIT 100`,
    prescriptions: `
        SELECT p.id, p.prescription_number AS reference, p.status,
               p.prescription_date AS occurred_on, NULL::text AS detail,
               pu.email AS patient_email, du.email AS doctor_email
        FROM medorbit.prescriptions p
        JOIN medorbit.patients pa ON pa.id=p.patient_id
        JOIN medorbit.users pu ON pu.id=pa.user_id
        JOIN medorbit.doctors d ON d.id=p.doctor_id
        JOIN medorbit.users du ON du.id=d.user_id
        ORDER BY p.prescription_date DESC, p.created_at DESC
        LIMIT 100`,
    reviews: `
        SELECT r.id, ('Review · ' || r.rating || '/5') AS reference,
               CASE WHEN r.is_visible THEN 'visible' ELSE 'hidden' END AS status,
               r.created_at AS occurred_on, NULL::text AS detail,
               pu.email AS patient_email, du.email AS doctor_email
        FROM medorbit.doctor_reviews r
        JOIN medorbit.patients p ON p.id=r.patient_id
        JOIN medorbit.users pu ON pu.id=p.user_id
        JOIN medorbit.doctors d ON d.id=r.doctor_id
        JOIN medorbit.users du ON du.id=d.user_id
        ORDER BY r.created_at DESC
        LIMIT 100`
};

router.get('/activity/:kind', authenticate, authorizeAdmin, async (req, res, next) => {
    try {
        const query = ACTIVITY_QUERIES[req.params.kind];
        if (!query) return error(res, 'Unsupported activity type', 400, 'VALIDATION_ERROR');
        const result = await db.query(query);
        return success(res, result.rows, 'Administrative activity retrieved');
    } catch (err) {
        return next(err);
    }
});

async function setActiveState(req, res, next, isActive) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const oldResult = await client.query(
            `SELECT ${SAFE_USER_COLUMNS}
             FROM medorbit.users
             WHERE id=$1
             FOR UPDATE`,
            [req.params.id]
        );
        if (oldResult.rows.length !== 1) {
            await client.query('ROLLBACK');
            return error(res, 'User not found', 404, 'NOT_FOUND');
        }

        const oldUser = oldResult.rows[0];
        const blocked = mutationBlocked(req, oldUser);
        if (blocked) {
            await client.query('ROLLBACK');
            return error(res, blocked, 403, 'FORBIDDEN');
        }

        const updated = await client.query(
            `UPDATE medorbit.users
             SET is_active=$1,
                 authorization_version=authorization_version+1,
                 updated_at=NOW()
             WHERE id=$2
             RETURNING ${SAFE_USER_COLUMNS}`,
            [isActive, req.params.id]
        );
        await client.query(
            `UPDATE medorbit.user_sessions
             SET revoked_at=NOW()
             WHERE user_id=$1 AND revoked_at IS NULL`,
            [req.params.id]
        );

        await createAudit({
            user_id: req.user.sub,
            user_role: req.user.role,
            action: oldUser.role === 'admin'
                ? (isActive ? 'ADMIN_REACTIVATED' : 'ADMIN_DEACTIVATED')
                : (isActive ? 'USER_REACTIVATED' : 'USER_DEACTIVATED'),
            entity_type: 'USER',
            entity_id: req.params.id,
            old_values: oldUser,
            new_values: updated.rows[0],
            ip_address: req.ip,
            user_agent: req.headers['user-agent'],
        }, client);

        await client.query('COMMIT');
        return success(res, updated.rows[0], isActive ? 'User reactivated' : 'User deactivated');
    } catch (err) {
        await client.query('ROLLBACK');
        return next(err);
    } finally {
        client.release();
    }
}

router.put(
    '/users/:id/deactivate',
    authenticate,
    authorizeAdmin,
    (req, res, next) => setActiveState(req, res, next, false)
);

router.put(
    '/users/:id/reactivate',
    authenticate,
    authorizeAdmin,
    (req, res, next) => setActiveState(req, res, next, true)
);

router.put(
    '/users/:id/role',
    authenticate,
    authorizeAdmin,
    (_req, res) => error(
        res,
        'Role mutation is disabled until the controlled S1C administration workflow',
        403,
        'FORBIDDEN'
    )
);

module.exports = router;
