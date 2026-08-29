const express = require('express');
const db = require('../config/database');
const { authenticate, authorizeAdmin } = require('../middleware/auth');
const { success } = require('../utils/response');
const { submit, decide, dto, adminDto } = require('../services/clinicApplication.service');

const applicationRoutes = express.Router();
applicationRoutes.post('/', authenticate, async (req, res, next) => { try { return success(res, await submit(req.user, req.body), 'Clinic application submitted', 201); } catch (error) { return next(error); } });
applicationRoutes.get('/me', authenticate, async (req, res, next) => { try { const rows = await db.query('SELECT * FROM medorbit.clinic_applications WHERE user_id=$1 ORDER BY submitted_at DESC', [req.user.sub]); return success(res, rows.rows.map(dto)); } catch (error) { return next(error); } });
applicationRoutes.post('/:id/withdraw', authenticate, async (req, res, next) => { try { const row = await db.query("UPDATE medorbit.clinic_applications SET status='withdrawn',withdrawn_at=NOW(),updated_at=NOW() WHERE id=$1 AND user_id=$2 AND status='pending' RETURNING *", [req.params.id, req.user.sub]); if (!row.rows.length) { const error = new Error('Pending clinic application not found'); error.statusCode = 404; throw error; } return success(res, dto(row.rows[0]), 'Clinic application withdrawn'); } catch (error) { return next(error); } });

const adminClinicApplicationRoutes = express.Router();
const adminSelect = `SELECT a.*,u.email AS applicant_email,p.first_name_ar,p.last_name_ar,p.first_name_en,p.last_name_en FROM medorbit.clinic_applications a JOIN medorbit.users u ON u.id=a.user_id LEFT JOIN medorbit.user_profiles p ON p.user_id=a.user_id`;
adminClinicApplicationRoutes.get('/', authenticate, authorizeAdmin, async (req, res, next) => { try { const values = []; let where = ''; if (req.query.status) { values.push(req.query.status); where = ' WHERE a.status=$1'; } const rows = await db.query(`${adminSelect}${where} ORDER BY a.submitted_at DESC LIMIT 100`, values); return success(res, rows.rows.map(adminDto)); } catch (error) { return next(error); } });
adminClinicApplicationRoutes.post('/:id/approve', authenticate, authorizeAdmin, async (req, res, next) => { try { return success(res, await decide(req.params.id, req.user, true), 'Clinic approved'); } catch (error) { return next(error); } });
adminClinicApplicationRoutes.post('/:id/reject', authenticate, authorizeAdmin, async (req, res, next) => { try { return success(res, await decide(req.params.id, req.user, false, req.body.rejection_reason), 'Clinic application rejected'); } catch (error) { return next(error); } });

module.exports = { applicationRoutes, adminClinicApplicationRoutes };
