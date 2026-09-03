const express = require('express');
const db = require('../config/database');
const { success, error } = require('../utils/response');
const { authenticate, authorize, authorizeAdmin } = require('../middleware/auth');
const { createAudit } = require('../services/audit.service');
const { queueEmail } = require('../services/email.service');
const { generateToken, hashToken } = require('../utils/token');

const router = express.Router();

// Known facility types — invalid values are ignored rather than erroring.
const VALID_CLINIC_TYPES = new Set([
  'clinic', 'pharmacy', 'hospital', 'laboratory', 'dental', 'radiology', 'emergency'
]);

// GET /api/clinics - List clinics with filters
router.get('/', authenticate, async (req, res, next) => {
  try {
    const { city, region, service, insurance, search, type, page = 1, limit = 10 } = req.query;

    let query = `
      SELECT
        c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
        c.city, c.region, c.latitude, c.longitude, c.phone, c.email,
        c.website, c.operating_hours, c.services, c.insurance_accepted,
        c.type, c.logo_url, c.is_active, c.verification_status
      FROM medorbit.clinics c
      WHERE c.is_active = true AND c.approval_status = 'approved'
    `;

    const params = [];
    let paramIndex = 1;

    if (type && VALID_CLINIC_TYPES.has(type)) {
      query += ` AND c.type = $${paramIndex}`;
      params.push(type);
      paramIndex++;
    }

    if (region) {
      query += ` AND c.region ILIKE $${paramIndex}`;
      params.push(`%${region}%`);
      paramIndex++;
    }

    if (city) {
      query += ` AND c.city ILIKE $${paramIndex}`;
      params.push(`%${city}%`);
      paramIndex++;
    }

    if (service) {
      query += ` AND $${paramIndex} = ANY(c.services)`;
      params.push(service);
      paramIndex++;
    }

    if (insurance) {
      query += ` AND $${paramIndex} = ANY(c.insurance_accepted)`;
      params.push(insurance);
      paramIndex++;
    }

    if (search) {
      query += ` AND (c.name_ar ILIKE $${paramIndex} OR c.name_en ILIKE $${paramIndex})`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    // Count
    const countResult = await db.query(
      `SELECT COUNT(*) FROM (${query}) as count_query`,
      params
    );
    const total = parseInt(countResult.rows[0].count);

    query += ` ORDER BY c.name_en`;
    query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(parseInt(limit), (parseInt(page) - 1) * parseInt(limit));

    const result = await db.query(query, params);

    return success(res, {
      clinics: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        totalPages: Math.ceil(total / parseInt(limit))
      }
    }, 'Clinics retrieved successfully');

  } catch (err) {
    next(err);
  }
});

// GET /api/clinics/directory-filters - server-driven city and service filters.
router.get('/directory-filters', authenticate, async (_req, res, next) => {
  try {
    const result = await db.query(`
      SELECT ARRAY_REMOVE(ARRAY_AGG(DISTINCT c.city ORDER BY c.city), NULL) AS cities,
             ARRAY_REMOVE(ARRAY_AGG(DISTINCT service ORDER BY service), NULL) AS services
      FROM medorbit.clinics c
      LEFT JOIN LATERAL UNNEST(c.services) AS service ON true
      WHERE c.is_active=true AND c.approval_status='approved'
    `);
    return success(res, result.rows[0] || { cities: [], services: [] }, 'Clinic directory filters retrieved');
  } catch (err) { return next(err); }
});

async function ownedClinic(userId, queryable = db, lock = false) {
  const result = await queryable.query(
    `SELECT * FROM medorbit.clinics WHERE owner_user_id=$1 AND is_active=true AND approval_status='approved'${lock ? ' FOR UPDATE' : ''}`,
    [userId]
  );
  if (!result.rows.length) { const err = new Error('Clinic approval is required before using the workspace'); err.statusCode = 403; err.code = 'CLINIC_APPROVAL_REQUIRED'; throw err; }
  return result.rows[0];
}

function clinicError(message, statusCode = 400, code = 'VALIDATION_ERROR') {
  const err = new Error(message); err.statusCode = statusCode; err.code = code; return err;
}

function normalizedEmail(value) {
  const email = String(value || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 255) {
    throw clinicError('A valid contact email is required');
  }
  return email;
}

function contactVerificationUrl(token) {
  const base = (process.env.FRONTEND_URL || 'http://localhost:8080/public').replace(/\/+$/, '');
  return `${base}/clinic-contact-email-verify.html?token=${encodeURIComponent(token)}`;
}

async function notifyClinicOwner(client, userId, type, referenceId, titleEn, titleAr, messageEn, messageAr, referenceType = 'CLINIC_CREDENTIAL_CHANGE') {
  await client.query(
    `INSERT INTO medorbit.notifications
      (user_id,notification_type,title_en,title_ar,message_en,message_ar,reference_id,reference_type,channel)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,'in_app')`,
    [userId, type, titleEn, titleAr, messageEn, messageAr, referenceId, referenceType],
  );
}

router.get('/me', authenticate, authorize('clinic'), async (req, res, next) => {
  try { return success(res, await ownedClinic(req.user.sub), 'Clinic workspace retrieved'); }
  catch (err) { return next(err); }
});

router.put('/me', authenticate, authorize('clinic'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    const allowed = ['name_ar', 'name_en', 'address_ar', 'address_en', 'city', 'region', 'phone', 'email', 'website', 'services', 'operating_hours', 'logo_url'];
    const values = []; const assignments = [];
    for (const key of allowed) if (Object.prototype.hasOwnProperty.call(req.body, key)) { assignments.push(`${key}=$${values.length + 1}`); values.push(req.body[key]); }
    if (!assignments.length) return success(res, await ownedClinic(req.user.sub), 'No clinic changes submitted');
    await client.query('BEGIN'); const existing = await ownedClinic(req.user.sub, client, true); values.push(existing.id);
    const updated = await client.query(`UPDATE medorbit.clinics SET ${assignments.join(',')},updated_at=NOW() WHERE id=$${values.length} RETURNING *`, values);
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:'CLINIC_OWNER_UPDATED_PROFILE',entity_type:'CLINIC',entity_id:existing.id,old_values:existing,new_values:updated.rows[0] }, client);
    await client.query('COMMIT'); return success(res, updated.rows[0], 'Clinic profile updated');
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

router.get('/me/doctors', authenticate, authorize('clinic'), async (req, res, next) => {
  try { const clinic = await ownedClinic(req.user.sub); const result = await db.query(`SELECT d.id,p.first_name_ar,p.last_name_ar,p.first_name_en,p.last_name_en,s.name_ar AS specialty_ar,s.name_en AS specialty_en,dca.is_primary FROM medorbit.doctor_clinic_assignments dca JOIN medorbit.doctors d ON d.id=dca.doctor_id JOIN medorbit.users u ON u.id=d.user_id LEFT JOIN medorbit.user_profiles p ON p.user_id=u.id LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id WHERE dca.clinic_id=$1 AND dca.is_active=true AND u.is_active=true ORDER BY p.first_name_en`, [clinic.id]); return success(res,result.rows,'Clinic doctors retrieved'); }
  catch (err) { return next(err); }
});

router.get('/eligible-doctors', authenticate, authorize('clinic'), async (_req, res, next) => {
  try { const result = await db.query(`SELECT d.id,p.first_name_ar,p.last_name_ar,p.first_name_en,p.last_name_en,s.name_ar AS specialty_ar,s.name_en AS specialty_en FROM medorbit.doctors d JOIN medorbit.users u ON u.id=d.user_id LEFT JOIN medorbit.user_profiles p ON p.user_id=u.id LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id WHERE u.is_active=true AND d.approval_status='approved' ORDER BY p.first_name_en LIMIT 250`); return success(res,result.rows,'Eligible doctors retrieved'); }
  catch (err) { return next(err); }
});

router.get('/me/doctor-invitations', authenticate, authorize('clinic'), async (req, res, next) => {
  try {
    const clinic = await ownedClinic(req.user.sub);
    const result = await db.query(`SELECT i.id,i.status,i.message,i.created_at,i.responded_at,d.id AS doctor_id,p.first_name_ar,p.last_name_ar,p.first_name_en,p.last_name_en,s.name_ar AS specialty_ar,s.name_en AS specialty_en FROM medorbit.clinic_doctor_invitations i JOIN medorbit.doctors d ON d.id=i.doctor_id JOIN medorbit.users u ON u.id=d.user_id LEFT JOIN medorbit.user_profiles p ON p.user_id=u.id LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id WHERE i.clinic_id=$1 ORDER BY i.created_at DESC`, [clinic.id]);
    return success(res, result.rows, 'Clinic doctor invitations retrieved');
  } catch (err) { return next(err); }
});

router.post('/me/doctor-invitations', authenticate, authorize('clinic'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    const doctorId = String(req.body?.doctor_id || '');
    const message = String(req.body?.message || '').trim().slice(0, 1000) || null;
    if (!doctorId) throw clinicError('Doctor id is required');
    await client.query('BEGIN');
    const clinic = await ownedClinic(req.user.sub, client, true);
    const doctor = (await client.query(`SELECT d.id,d.user_id FROM medorbit.doctors d JOIN medorbit.users u ON u.id=d.user_id WHERE d.id=$1 AND d.approval_status='approved' AND u.is_active=true`, [doctorId])).rows[0];
    if (!doctor) throw clinicError('Approved doctor not found', 404, 'NOT_FOUND');
    const active = await client.query('SELECT 1 FROM medorbit.doctor_clinic_assignments WHERE doctor_id=$1 AND clinic_id=$2 AND is_active=true', [doctor.id, clinic.id]);
    if (active.rows.length) throw clinicError('This doctor already works at your clinic', 409, 'ALREADY_ASSIGNED');
    const pending = await client.query("SELECT 1 FROM medorbit.clinic_doctor_invitations WHERE clinic_id=$1 AND doctor_id=$2 AND status='pending'", [clinic.id, doctor.id]);
    if (pending.rows.length) throw clinicError('A pending invitation already exists for this doctor', 409, 'INVITATION_PENDING');
    const invitation = (await client.query(`INSERT INTO medorbit.clinic_doctor_invitations(clinic_id,doctor_id,invited_by_user_id,message) VALUES($1,$2,$3,$4) RETURNING *`, [clinic.id, doctor.id, req.user.sub, message])).rows[0];
    await client.query(`INSERT INTO medorbit.notifications(user_id,notification_type,title_en,title_ar,message_en,message_ar,reference_id,reference_type,channel) VALUES($1,'CLINIC_DOCTOR_INVITATION','Clinic invitation','دعوة من منشأة صحية',$2,$3,$4,'CLINIC_DOCTOR_INVITATION','in_app')`, [doctor.user_id, `${clinic.name_en} invited you to join its clinic.`, `دعتك ${clinic.name_ar} للانضمام إلى منشأتها الصحية.`, invitation.id]);
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:'CLINIC_DOCTOR_INVITATION_SENT',entity_type:'CLINIC_DOCTOR_INVITATION',entity_id:invitation.id,new_values:invitation }, client);
    await client.query('COMMIT'); return success(res, invitation, 'Doctor invitation sent', 201);
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

// Legacy endpoint kept only to give older clients a clear upgrade message.
// A clinic never creates an employment relationship unilaterally.
router.post('/me/doctors', authenticate, authorize('clinic'), (_req, res) =>
  error(res, 'Doctors must accept a clinic invitation before they are linked', 409, 'INVITATION_REQUIRED')
);

router.delete('/me/doctors/:doctorId', authenticate, authorize('clinic'), async (req,res,next) => {
  const client=await db.getClient();
  try { await client.query('BEGIN');const clinic=await ownedClinic(req.user.sub,client,true);const result=await client.query('UPDATE medorbit.doctor_clinic_assignments SET is_active=false,ended_at=NOW() WHERE clinic_id=$1 AND doctor_id=$2 AND is_active=true RETURNING *',[clinic.id,req.params.doctorId]);if(!result.rows.length){const err=new Error('Doctor link not found');err.statusCode=404;err.code='NOT_FOUND';throw err;}await createAudit({user_id:req.user.sub,user_role:req.user.role,action:'CLINIC_OWNER_REMOVED_DOCTOR',entity_type:'CLINIC_DOCTOR_ASSIGNMENT',old_values:result.rows[0]},client);await client.query('COMMIT');return success(res,result.rows[0],'Doctor removed from clinic'); }
  catch(err){await client.query('ROLLBACK').catch(()=>{});return next(err);} finally {client.release();}
});

// Operational clinic contact emails are separate from the owner account email.
// A value becomes a usable clinic contact only after its holder proves control
// of that inbox through the one-time link sent below.
router.get('/me/contact-emails', authenticate, authorize('clinic'), async (req, res, next) => {
  try {
    const clinic = await ownedClinic(req.user.sub);
    const rows = await db.query(
      `SELECT id,email,status,verified_at,verification_expires_at,created_at
       FROM medorbit.clinic_contact_emails WHERE clinic_id=$1 ORDER BY created_at ASC`,
      [clinic.id],
    );
    return success(res, rows.rows, 'Clinic contact emails retrieved');
  } catch (err) { return next(err); }
});

router.post('/me/contact-emails', authenticate, authorize('clinic'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    const email = normalizedEmail(req.body?.email);
    const token = generateToken();
    await client.query('BEGIN');
    const clinic = await ownedClinic(req.user.sub, client, true);
    const existing = await client.query(
      `SELECT id,status FROM medorbit.clinic_contact_emails
       WHERE lower(email)=lower($1) FOR UPDATE`,
      [email],
    );
    if (existing.rows.length && existing.rows[0].status === 'verified') {
      throw clinicError('This email is already verified for a clinic contact', 409, 'EMAIL_IN_USE');
    }
    if (existing.rows.length && existing.rows[0].status === 'pending') {
      await client.query('DELETE FROM medorbit.clinic_contact_emails WHERE id=$1', [existing.rows[0].id]);
    }
    const row = (await client.query(
      `INSERT INTO medorbit.clinic_contact_emails
       (clinic_id,email,status,verification_token_hash,verification_expires_at)
       VALUES($1,$2,'pending',$3,NOW()+INTERVAL '24 hours') RETURNING id,email,status,verification_expires_at`,
      [clinic.id, email, hashToken(token)],
    )).rows[0];
    const url = contactVerificationUrl(token);
    await queueEmail(
      email,
      'Verify your MedOrbit clinic contact email',
      `<p>Confirm this email as a contact for <strong>${clinic.name_en}</strong>.</p><p><a href="${url}">Verify clinic contact email</a></p><p>This link expires in 24 hours.</p>`,
      `Verify this clinic contact email within 24 hours: ${url}`,
      client,
    );
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:'CLINIC_CONTACT_EMAIL_ADDED',entity_type:'CLINIC_CONTACT_EMAIL',entity_id:row.id,new_values:{ email, status:'pending' } }, client);
    await client.query('COMMIT');
    return success(res, row, 'Verification email sent', 201);
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

router.post('/contact-emails/verify', async (req, res, next) => {
  const client = await db.getClient();
  try {
    const token = String(req.body?.token || '');
    if (!/^[a-f0-9]{64}$/i.test(token)) throw clinicError('Invalid verification link', 400, 'INVALID_VERIFICATION_TOKEN');
    await client.query('BEGIN');
    const row = (await client.query(
      `UPDATE medorbit.clinic_contact_emails
       SET status='verified',verified_at=NOW(),verification_token_hash=NULL,verification_expires_at=NULL,updated_at=NOW()
       WHERE verification_token_hash=$1 AND status='pending' AND verification_expires_at > NOW()
       RETURNING id,email,clinic_id`,
      [hashToken(token)],
    )).rows[0];
    if (!row) throw clinicError('This verification link is invalid, used, or expired', 400, 'INVALID_VERIFICATION_TOKEN');
    await createAudit({ action:'CLINIC_CONTACT_EMAIL_VERIFIED',entity_type:'CLINIC_CONTACT_EMAIL',entity_id:row.id,new_values:{ email:row.email,status:'verified' } }, client);
    await client.query('COMMIT');
    return success(res, { email: row.email }, 'Clinic contact email verified');
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

router.delete('/me/contact-emails/:id', authenticate, authorize('clinic'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const clinic = await ownedClinic(req.user.sub, client, true);
    const deleted = await client.query(
      'DELETE FROM medorbit.clinic_contact_emails WHERE id=$1 AND clinic_id=$2 RETURNING id,email,status',
      [req.params.id, clinic.id],
    );
    if (!deleted.rows.length) throw clinicError('Clinic contact email not found', 404, 'NOT_FOUND');
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:'CLINIC_CONTACT_EMAIL_REMOVED',entity_type:'CLINIC_CONTACT_EMAIL',entity_id:deleted.rows[0].id,old_values:deleted.rows[0] }, client);
    await client.query('COMMIT'); return success(res, null, 'Clinic contact email removed');
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

router.get('/me/credential-change-requests', authenticate, authorize('clinic'), async (req, res, next) => {
  try {
    const clinic = await ownedClinic(req.user.sub);
    const rows = await db.query(
      `SELECT id,current_registration_number,requested_registration_number,reason,status,decision_note,created_at,reviewed_at
       FROM medorbit.clinic_credential_change_requests WHERE clinic_id=$1 ORDER BY created_at DESC`,
      [clinic.id],
    );
    return success(res, rows.rows, 'Credential change requests retrieved');
  } catch (err) { return next(err); }
});

router.post('/me/credential-change-requests', authenticate, authorize('clinic'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    const requested = String(req.body?.registration_number || '').trim().slice(0, 120);
    const reason = String(req.body?.reason || '').trim().slice(0, 2000);
    if (!requested || reason.length < 10) throw clinicError('A new registration number and a reason of at least 10 characters are required');
    await client.query('BEGIN');
    const clinic = await ownedClinic(req.user.sub, client, true);
    if (requested === clinic.registration_number) throw clinicError('The requested registration number is unchanged');
    const row = (await client.query(
      `INSERT INTO medorbit.clinic_credential_change_requests
       (clinic_id,requested_by_user_id,current_registration_number,requested_registration_number,reason)
       VALUES($1,$2,$3,$4,$5) RETURNING *`,
      [clinic.id, req.user.sub, clinic.registration_number, requested, reason],
    )).rows[0];
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:'CLINIC_CREDENTIAL_CHANGE_REQUESTED',entity_type:'CLINIC_CREDENTIAL_CHANGE',entity_id:row.id,new_values:row }, client);
    await client.query(
      `INSERT INTO medorbit.notifications
        (user_id,notification_type,title_en,title_ar,message_en,message_ar,reference_id,reference_type,channel)
       SELECT id,'CLINIC_CREDENTIAL_CHANGE_REQUESTED','Clinic credential change request','طلب تغيير بيانات ترخيص منشأة',$1,$2,$3,'CLINIC_CREDENTIAL_CHANGE','in_app'
       FROM medorbit.users
       WHERE role IN ('admin','super_admin') AND is_active=true AND email_verified=true AND deleted_at IS NULL`,
      [`${clinic.name_en} requested a registration-number change for review.`, `قدّمت ${clinic.name_ar} طلب تغيير رقم التسجيل للمراجعة.`, row.id],
    );
    await client.query('COMMIT'); return success(res, row, 'Credential change request submitted', 201);
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

router.get('/admin/credential-change-requests', authenticate, authorizeAdmin, async (req, res, next) => {
  try {
    const status = String(req.query.status || 'pending');
    const values = []; const filter = ['pending','approved','rejected'].includes(status) ? (values.push(status), 'WHERE r.status=$1') : '';
    const rows = await db.query(
      `SELECT r.*,c.name_ar,c.name_en,u.email AS owner_email
       FROM medorbit.clinic_credential_change_requests r
       JOIN medorbit.clinics c ON c.id=r.clinic_id
       JOIN medorbit.users u ON u.id=c.owner_user_id ${filter}
       ORDER BY r.created_at DESC LIMIT 100`, values,
    );
    return success(res, rows.rows, 'Clinic credential requests retrieved');
  } catch (err) { return next(err); }
});

router.post('/admin/credential-change-requests/:id/decide', authenticate, authorizeAdmin, async (req, res, next) => {
  const client = await db.getClient();
  try {
    const approved = req.body?.approved === true;
    const note = String(req.body?.decision_note || '').trim().slice(0, 2000);
    if (!approved && !note) throw clinicError('A rejection note is required');
    await client.query('BEGIN');
    const request = (await client.query(
      `SELECT r.*,c.owner_user_id FROM medorbit.clinic_credential_change_requests r
       JOIN medorbit.clinics c ON c.id=r.clinic_id WHERE r.id=$1 FOR UPDATE`, [req.params.id],
    )).rows[0];
    if (!request || request.status !== 'pending') throw clinicError('Pending credential change request not found', 404, 'NOT_FOUND');
    if (approved) await client.query('UPDATE medorbit.clinics SET registration_number=$1,updated_at=NOW() WHERE id=$2', [request.requested_registration_number, request.clinic_id]);
    const row = (await client.query(
      `UPDATE medorbit.clinic_credential_change_requests
       SET status=$1,reviewed_by_user_id=$2,reviewed_at=NOW(),decision_note=$3,updated_at=NOW()
       WHERE id=$4 RETURNING *`,
      [approved ? 'approved' : 'rejected', req.user.sub, note || null, request.id],
    )).rows[0];
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:approved?'CLINIC_CREDENTIAL_CHANGE_APPROVED':'CLINIC_CREDENTIAL_CHANGE_REJECTED',entity_type:'CLINIC_CREDENTIAL_CHANGE',entity_id:row.id,new_values:row }, client);
    await notifyClinicOwner(client, request.owner_user_id, approved ? 'CLINIC_CREDENTIAL_CHANGE_APPROVED' : 'CLINIC_CREDENTIAL_CHANGE_REJECTED', row.id, 'Clinic credential change decision', 'قرار تغيير بيانات ترخيص المنشأة', approved ? 'Your clinic registration number change was approved.' : `Your clinic registration number change was rejected. ${note}`, approved ? 'تمت الموافقة على تغيير رقم تسجيل منشأتك.' : `تم رفض تغيير رقم تسجيل منشأتك. ${note}`);
    await client.query('COMMIT'); return success(res, row, approved ? 'Credential change approved' : 'Credential change rejected');
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

// GET /api/clinics/nearby - Find nearby clinics
router.get('/nearby', authenticate, async (req, res, next) => {
  try {
    const { lat, lng, radius = 5, type } = req.query; // radius in km

    if (!lat || !lng) {
      return error(res, 'Latitude and longitude required', 400, 'VALIDATION_ERROR');
    }

    let query = `
      SELECT
        c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
        c.city, c.region, c.latitude, c.longitude, c.phone,
        c.type, c.services, c.logo_url,
        ROUND(
          6371 * acos(
            cos(radians($1)) * cos(radians(c.latitude)) *
            cos(radians(c.longitude) - radians($2)) +
            sin(radians($1)) * sin(radians(c.latitude))
          )::numeric, 2
        ) as distance_km
      FROM medorbit.clinics c
      WHERE c.is_active = true AND c.approval_status = 'approved'
    `;

    const params = [lat, lng];
    let paramIndex = 3;

    if (type && VALID_CLINIC_TYPES.has(type)) {
      query += ` AND c.type = $${paramIndex}`;
      params.push(type);
      paramIndex++;
    }

    query += `
      AND
        6371 * acos(
          cos(radians($1)) * cos(radians(c.latitude)) *
          cos(radians(c.longitude) - radians($2)) +
          sin(radians($1)) * sin(radians(c.latitude))
        ) <= $${paramIndex}
      ORDER BY distance_km
    `;
    params.push(parseFloat(radius));

    const result = await db.query(query, params);

    return success(res, {
      clinics: result.rows
    }, 'Nearby clinics retrieved');

  } catch (err) {
    next(err);
  }
});

// GET /api/clinics/:id - Get clinic details
router.get('/:id', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;

    const clinicResult = await db.query(
      `SELECT c.*, to_jsonb(u)->'preferences'->'social_links' AS social_links FROM medorbit.clinics c LEFT JOIN medorbit.users u ON u.id=c.owner_user_id WHERE c.id = $1 AND c.is_active = true AND c.approval_status = 'approved'`,
      [id]
    );

    if (clinicResult.rows.length === 0) {
      return error(res, 'Clinic not found', 404, 'NOT_FOUND');
    }

    const clinic = clinicResult.rows[0];

    // Doctors in this clinic
    const doctorsResult = await db.query(
      `SELECT
        d.id, d.years_of_experience, d.consultation_fee,
        d.average_rating, d.is_accepting_patients,
        p.first_name_ar, p.first_name_en, p.last_name_ar, p.last_name_en,
        p.profile_image_url,
        s.name_ar as specialty_ar, s.name_en as specialty_en
      FROM medorbit.doctor_clinic_assignments dca
      JOIN medorbit.doctors d ON d.id = dca.doctor_id
      JOIN medorbit.users u ON u.id = d.user_id
      LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
      WHERE dca.clinic_id = $1 AND dca.is_active = true AND u.is_active = true`,
      [id]
    );

    return success(res, {
      clinic,
      doctors: doctorsResult.rows
    }, 'Clinic details retrieved');

  } catch (err) {
    next(err);
  }
});

// POST /api/clinics - Create clinic (admin only)
router.post(
  "/",
  authenticate,
  authorizeAdmin,
  async (req, res, next) => {
    let client;
    try {
      const {
        name_ar, name_en, address_ar, address_en, city, region,
        latitude, longitude, phone, email, website, type
      } = req.body;

      client = await db.getClient();
      await client.query('BEGIN');

      const created = await client.query(
        `INSERT INTO medorbit.clinics(
          name_ar, name_en, address_ar, address_en, city, region,
          latitude, longitude, phone, email, website, type
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
        RETURNING id, name_ar, name_en, type`,
        [name_ar, name_en, address_ar, address_en, city, region,
          latitude, longitude, phone, email, website, type]
      );
      await createAudit({
        user_id: req.user.sub,
        user_role: req.user.role,
        action: 'CLINIC_CREATED',
        entity_type: 'CLINIC',
        entity_id: created.rows[0].id,
        new_values: created.rows[0],
      }, client);
      await client.query('COMMIT');

      return success(res, null, "Clinic created successfully");
    } catch (err) {
      if (client) await client.query('ROLLBACK').catch(() => {});
      next(err);
    } finally {
      client?.release();
    }
  }
);

// PUT /api/clinics/:id - Update clinic (admin only)
router.put(
  "/:id",
  authenticate,
  authorizeAdmin,
  async (req, res, next) => {
    let client;
    try {
      const { name_ar, name_en, phone } = req.body;

      client = await db.getClient();
      await client.query('BEGIN');
      const existing = await client.query(
        `SELECT id, name_ar, name_en, phone
         FROM medorbit.clinics
         WHERE id = $1 AND is_active = true
         FOR UPDATE`,
        [req.params.id]
      );
      if (existing.rowCount === 0) {
        await client.query('ROLLBACK');
        return error(res, "Clinic not found", 404, "NOT_FOUND");
      }

      const result = await client.query(
        `UPDATE medorbit.clinics
         SET name_ar = COALESCE($1, name_ar),
             name_en = COALESCE($2, name_en),
             phone = COALESCE($3, phone)
         WHERE id = $4 AND is_active = true
         RETURNING id, name_ar, name_en, phone`,
        [name_ar, name_en, phone, req.params.id]
      );
      await createAudit({
        user_id: req.user.sub,
        user_role: req.user.role,
        action: 'CLINIC_UPDATED',
        entity_type: 'CLINIC',
        entity_id: result.rows[0].id,
        old_values: existing.rows[0],
        new_values: result.rows[0],
      }, client);
      await client.query('COMMIT');

      return success(res, null, "Clinic updated");
    } catch (err) {
      if (client) await client.query('ROLLBACK').catch(() => {});
      next(err);
    } finally {
      client?.release();
    }
  }
);

// DELETE /api/clinics/:id - Soft-delete clinic (admin only)
router.delete(
  "/:id",
  authenticate,
  authorizeAdmin,
  async (req, res, next) => {
    let client;
    try {
      client = await db.getClient();
      await client.query('BEGIN');
      const existing = await client.query(
        `SELECT id, name_ar, name_en, type, is_active
         FROM medorbit.clinics
         WHERE id = $1 AND is_active = true
         FOR UPDATE`,
        [req.params.id]
      );
      if (existing.rowCount === 0) {
        await client.query('ROLLBACK');
        return error(res, "Clinic not found", 404, "NOT_FOUND");
      }

      const result = await client.query(
        `UPDATE medorbit.clinics
         SET is_active = false
         WHERE id = $1 AND is_active = true
         RETURNING id, name_ar, name_en, type, is_active`,
        [req.params.id]
      );
      await createAudit({
        user_id: req.user.sub,
        user_role: req.user.role,
        action: 'CLINIC_DEACTIVATED',
        entity_type: 'CLINIC',
        entity_id: result.rows[0].id,
        old_values: existing.rows[0],
        new_values: result.rows[0],
      }, client);
      await client.query('COMMIT');

      return success(res, null, "Clinic deleted");
    } catch (err) {
      if (client) await client.query('ROLLBACK').catch(() => {});
      next(err);
    } finally {
      client?.release();
    }
  }
);

// POST /api/clinics/:id/assign-doctor - Admin only
router.post(
  "/:id/assign-doctor",
  authenticate,
  authorizeAdmin,
  async (req, res, next) => {
    let client;
    try {
      const clinicId = req.params.id;
      const { doctorId, isPrimary = false, consultationFeeOverride = null } = req.body;

      if (!doctorId) {
        return error(res, "Doctor id is required", 400, "VALIDATION_ERROR");
      }

      client = await db.getClient();
      await client.query('BEGIN');
      const clinic = await client.query(
        `SELECT id FROM medorbit.clinics WHERE id = $1 AND is_active = true`,
        [clinicId]
      );
      if (clinic.rows.length === 0) {
        await client.query('ROLLBACK');
        return error(res, "Clinic not found", 404, "NOT_FOUND");
      }

      const doctor = await client.query(
        `SELECT id FROM medorbit.doctors WHERE id = $1`,
        [doctorId]
      );
      if (doctor.rows.length === 0) {
        await client.query('ROLLBACK');
        return error(res, "Doctor not found", 404, "NOT_FOUND");
      }

      const assignment = await client.query(
        `INSERT INTO medorbit.doctor_clinic_assignments
           (doctor_id, clinic_id, is_primary, consultation_fee_override, is_active)
         VALUES ($1,$2,$3,$4,true)
         ON CONFLICT (doctor_id, clinic_id)
         DO UPDATE SET
           is_active = true,
           is_primary = $3,
           consultation_fee_override = $4
         RETURNING doctor_id, clinic_id, is_primary, consultation_fee_override, is_active`,
        [doctorId, clinicId, isPrimary, consultationFeeOverride]
      );
      await createAudit({
        user_id: req.user.sub,
        user_role: req.user.role,
        action: 'CLINIC_DOCTOR_ASSIGNED',
        entity_type: 'CLINIC_DOCTOR_ASSIGNMENT',
        entity_id: null,
        new_values: assignment.rows[0],
      }, client);
      await client.query('COMMIT');

      return success(res, null, "Doctor assigned successfully");
    } catch (err) {
      if (client) await client.query('ROLLBACK').catch(() => {});
      next(err);
    } finally {
      client?.release();
    }
  }
);

// DELETE /api/clinics/:id/remove-doctor/:doctorId
router.delete(
  "/:id/remove-doctor/:doctorId",
  authenticate,
  authorizeAdmin,
  async (req, res, next) => {
    let client;
    try {
      client = await db.getClient();
      await client.query('BEGIN');
      const existing = await client.query(
        `SELECT doctor_id, clinic_id, is_primary, consultation_fee_override, is_active
         FROM medorbit.doctor_clinic_assignments
         WHERE clinic_id = $1 AND doctor_id = $2 AND is_active = true
         FOR UPDATE`,
        [req.params.id, req.params.doctorId]
      );
      if (existing.rowCount === 0) {
        await client.query('ROLLBACK');
        return error(res, "Active doctor assignment not found", 404, "NOT_FOUND");
      }

      const removed = await client.query(
        `UPDATE medorbit.doctor_clinic_assignments
         SET is_active = false
         WHERE clinic_id = $1 AND doctor_id = $2 AND is_active = true
         RETURNING doctor_id, clinic_id, is_primary, consultation_fee_override, is_active`,
        [req.params.id, req.params.doctorId]
      );
      await createAudit({
        user_id: req.user.sub,
        user_role: req.user.role,
        action: 'CLINIC_DOCTOR_REMOVED',
        entity_type: 'CLINIC_DOCTOR_ASSIGNMENT',
        old_values: existing.rows[0],
        new_values: removed.rows[0],
      }, client);
      await client.query('COMMIT');

      return success(res, null, "Doctor removed from clinic");
    } catch (err) {
      if (client) await client.query('ROLLBACK').catch(() => {});
      next(err);
    } finally {
      client?.release();
    }
  }
);

module.exports = router;
