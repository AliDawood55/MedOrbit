const express = require('express');
const db = require('../config/database');
const { authenticate, authorizeAdmin } = require('../middleware/auth');
const { success } = require('../utils/response');
const { createAudit } = require('../services/audit.service');
const { submit, decide, dto, adminDto, notify } = require('../services/doctorApplication.service');

const applicationRoutes = express.Router();

applicationRoutes.post('/', authenticate, async (req, res, next) => {
    try { return success(res, await submit(req.user, req.body), 'Application submitted', 201); }
    catch (err) { return next(err); }
});

applicationRoutes.get('/me', authenticate, async (req, res, next) => {
    try {
        const result = await db.query(
            'SELECT * FROM medorbit.doctor_applications WHERE user_id=$1 ORDER BY submitted_at DESC',
            [req.user.sub]
        );
        return success(res, result.rows.map(dto));
    } catch (err) { return next(err); }
});

applicationRoutes.post('/:id/withdraw', authenticate, async (req, res, next) => {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const result = await client.query(
            `UPDATE medorbit.doctor_applications
             SET status='withdrawn',withdrawn_at=NOW(),updated_at=NOW()
             WHERE id=$1 AND user_id=$2 AND status='pending' RETURNING *`,
            [req.params.id, req.user.sub]
        );
        if (!result.rows.length) {
            const err = new Error('Pending application not found'); err.statusCode = 404; throw err;
        }
        await createAudit({
            user_id: req.user.sub, user_role: req.user.role,
            action: 'DOCTOR_APPLICATION_WITHDRAWN', entity_type: 'DOCTOR_APPLICATION',
            entity_id: result.rows[0].id, new_values: dto(result.rows[0]),
        }, client);
        await client.query('COMMIT');
        return success(res, dto(result.rows[0]), 'Application withdrawn');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {}); return next(err);
    } finally { client.release(); }
});

const adminDoctorApplicationRoutes = express.Router();
const reviewSelect = `
    SELECT a.*,u.email,
           up.first_name_ar,up.last_name_ar,up.first_name_en,up.last_name_en,
           s.name_ar AS specialty_name_ar,s.name_en AS specialty_name_en
    FROM medorbit.doctor_applications a
    JOIN medorbit.users u ON u.id=a.user_id
    LEFT JOIN medorbit.user_profiles up ON up.user_id=a.user_id
    JOIN medorbit.specialties s ON s.id=a.specialty_id`;

adminDoctorApplicationRoutes.get('/', authenticate, authorizeAdmin, async (req, res, next) => {
    try {
        const values = []; let where = '';
        if (req.query.status) { values.push(req.query.status); where = ' WHERE a.status=$1'; }
        const result = await db.query(`${reviewSelect}${where} ORDER BY a.submitted_at DESC LIMIT 100`, values);
        return success(res, result.rows.map(adminDto));
    } catch (err) { return next(err); }
});

adminDoctorApplicationRoutes.get('/:id', authenticate, authorizeAdmin, async (req, res, next) => {
    try {
        const result = await db.query(`${reviewSelect} WHERE a.id=$1`, [req.params.id]);
        if (!result.rows.length) { const err = new Error('Not found'); err.statusCode = 404; throw err; }
        return success(res, adminDto(result.rows[0]));
    } catch (err) { return next(err); }
});

adminDoctorApplicationRoutes.post('/:id/approve', authenticate, authorizeAdmin, async (req, res, next) => {
    try { return success(res, await decide(req.params.id, req.user, true), 'Doctor approved'); }
    catch (err) { return next(err); }
});

adminDoctorApplicationRoutes.post('/:id/reject', authenticate, authorizeAdmin, async (req, res, next) => {
    try { return success(res, await decide(req.params.id, req.user, false, req.body.rejection_reason), 'Application rejected'); }
    catch (err) { return next(err); }
});

adminDoctorApplicationRoutes.post('/doctors/:id/:action', authenticate, authorizeAdmin, async (req, res, next) => {
    const client = await db.getClient();
    try {
        if (!['suspend', 'reactivate'].includes(req.params.action)) {
            const err = new Error('Invalid action'); err.statusCode = 400; throw err;
        }
        await client.query('BEGIN');
        const status = req.params.action === 'suspend' ? 'suspended' : 'approved';
        const result = await client.query(
            `UPDATE medorbit.doctors
             SET approval_status=$1::varchar,
                 suspended_at=CASE WHEN $1::varchar='suspended' THEN NOW() ELSE NULL END,
                 suspended_by_user_id=CASE WHEN $1::varchar='suspended' THEN $2::uuid ELSE NULL END,
                 suspension_reason=CASE WHEN $1::varchar='suspended' THEN $3::text ELSE NULL END
             WHERE id=$4 RETURNING user_id,id,approval_status`,
            [status, req.user.sub, req.body.reason || null, req.params.id]
        );
        if (!result.rows.length) { const err = new Error('Doctor not found'); err.statusCode = 404; throw err; }
        const doctor = result.rows[0];
        await client.query('UPDATE medorbit.users SET authorization_version=authorization_version+1 WHERE id=$1', [doctor.user_id]);
        await client.query('UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL', [doctor.user_id]);
        await createAudit({
            user_id: req.user.sub, user_role: req.user.role,
            action: status === 'suspended' ? 'DOCTOR_SUSPENDED' : 'DOCTOR_REACTIVATED',
            entity_type: 'DOCTOR', entity_id: doctor.id, new_values: doctor,
        }, client);
        await notify(
            client, doctor.user_id,
            status === 'suspended' ? 'DOCTOR_SUSPENDED' : 'DOCTOR_REACTIVATED', doctor.id,
            status === 'suspended' ? 'Your doctor access was suspended.' : 'Your doctor access was reactivated. Please sign in again.'
        );
        await client.query('COMMIT');
        return success(res, doctor, `Doctor ${req.params.action}d`);
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {}); return next(err);
    } finally { client.release(); }
});

module.exports = { applicationRoutes, adminDoctorApplicationRoutes };
