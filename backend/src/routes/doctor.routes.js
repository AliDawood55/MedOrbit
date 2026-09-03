// src/routes/doctor.routes.js
const express = require('express');
const db = require('../config/database');
const { success, error } = require('../utils/response');
const { authenticate, authorize } = require('../middleware/auth');
const { getRankedDoctors } = require('../services/recommendation.service');
const {
  resolveBilingualUserContent,
  withCanonicalContent
} = require('../utils/bilingualUserContent');
const {
  resolveDoctorForUser: resolveCurrentDoctor
} = require('../services/clinicalAuthorization.service');
const {
  hasActiveCareRelationship,
  closeRelationship
} = require('../services/careRelationship.service');
const {
  boundedText,
  boundedTags,
  boundedInteger
} = require('../utils/profileFields');
const scheduling = require('../services/scheduling.service');
const { createAudit } = require('../services/audit.service');

const router = express.Router();

// Shared by all doctor<->patient routes below.
async function resolveDoctorId(userId) {
  const result = await db.query('SELECT id FROM medorbit.doctors WHERE user_id = $1', [userId]);
  return result.rows[0]?.id || null;
}

// A clinic can only become a doctor's workplace after the doctor accepts its
// invitation. These endpoints deliberately resolve the doctor from the JWT.
router.get('/me/clinic-invitations', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    const result = await db.query(`SELECT i.id,i.status,i.message,i.created_at,c.id AS clinic_id,c.name_ar,c.name_en,c.city,c.address_ar,c.address_en FROM medorbit.clinic_doctor_invitations i JOIN medorbit.clinics c ON c.id=i.clinic_id WHERE i.doctor_id=$1 ORDER BY i.created_at DESC`, [doctorId]);
    return success(res, result.rows, 'Clinic invitations retrieved');
  } catch (err) { return next(err); }
});

router.post('/me/clinic-invitations/:id/respond', authenticate, authorize('doctor'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    if (typeof req.body?.accepted !== 'boolean') return error(res, 'accepted must be true or false', 400, 'VALIDATION_ERROR');
    await client.query('BEGIN');
    const doctorId = await resolveDoctorId(req.user.sub);
    const invitation = (await client.query(`SELECT i.*,c.owner_user_id,c.name_ar,c.name_en FROM medorbit.clinic_doctor_invitations i JOIN medorbit.clinics c ON c.id=i.clinic_id WHERE i.id=$1 AND i.doctor_id=$2 FOR UPDATE`, [req.params.id, doctorId])).rows[0];
    if (!invitation || invitation.status !== 'pending') { const err = new Error('Pending clinic invitation not found'); err.statusCode = 404; err.code = 'NOT_FOUND'; throw err; }
    const status = req.body.accepted ? 'accepted' : 'declined';
    const row = (await client.query(`UPDATE medorbit.clinic_doctor_invitations SET status=$1,responded_at=NOW(),updated_at=NOW() WHERE id=$2 RETURNING *`, [status, invitation.id])).rows[0];
    if (req.body.accepted) {
      await client.query(`INSERT INTO medorbit.doctor_clinic_assignments(doctor_id,clinic_id,is_active,joined_at,ended_at,source,invitation_id) VALUES($1,$2,true,NOW(),NULL,'clinic_invitation',$3) ON CONFLICT(doctor_id,clinic_id) DO UPDATE SET is_active=true,joined_at=NOW(),ended_at=NULL,source='clinic_invitation',invitation_id=EXCLUDED.invitation_id`, [doctorId, invitation.clinic_id, invitation.id]);
    }
    await client.query(`INSERT INTO medorbit.notifications(user_id,notification_type,title_en,title_ar,message_en,message_ar,reference_id,reference_type,channel) VALUES($1,$2,'Clinic invitation response','رد على دعوة المنشأة الصحية',$3,$4,$5,'CLINIC_DOCTOR_INVITATION','in_app')`, [invitation.owner_user_id, req.body.accepted ? 'CLINIC_DOCTOR_INVITATION_ACCEPTED' : 'CLINIC_DOCTOR_INVITATION_DECLINED', req.body.accepted ? 'A doctor accepted your clinic invitation.' : 'A doctor declined your clinic invitation.', req.body.accepted ? 'قبل الطبيب دعوة منشأتك الصحية.' : 'رفض الطبيب دعوة منشأتك الصحية.', invitation.id]);
    await createAudit({ user_id:req.user.sub,user_role:req.user.role,action:req.body.accepted?'DOCTOR_ACCEPTED_CLINIC_INVITATION':'DOCTOR_DECLINED_CLINIC_INVITATION',entity_type:'CLINIC_DOCTOR_INVITATION',entity_id:invitation.id,new_values:row }, client);
    await client.query('COMMIT'); return success(res, row, req.body.accepted ? 'Clinic invitation accepted' : 'Clinic invitation declined');
  } catch (err) { await client.query('ROLLBACK').catch(() => {}); return next(err); } finally { client.release(); }
});

// One authoritative assignment query for both public doctor projections.
// Keep the compact /:id/clinics endpoint for client compatibility, but derive
// it from the same data as the doctor-detail response so its eligibility rules
// cannot drift from the profile view.
async function findActiveClinicsByDoctorId(doctorId) {
  const result = await db.query(
    `SELECT
      c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
      c.city, c.region, c.latitude, c.longitude, c.phone,
      dca.consultation_fee_override, dca.is_primary
    FROM medorbit.doctor_clinic_assignments dca
    JOIN medorbit.clinics c ON c.id = dca.clinic_id
    WHERE dca.doctor_id = $1 AND dca.is_active = true AND c.is_active = true
      AND c.approval_status = 'approved'`,
    [doctorId]
  );
  return result.rows;
}

// A doctor may only act on a patient they have (or had) at least one
// appointment with — there's no dedicated relationship table. Returns a
// boolean rather than throwing so callers can turn a "no" into a 404 (not
// 403), so a doctor probing random patient ids can't tell real ids from
// fake ones — see the isolation note in patient-detail.js.
async function verifyDoctorPatientRelationship(doctorId, patientId) {
  return hasActiveCareRelationship(doctorId, patientId);
}

// GET /api/doctors/me/patients - Doctor's own patient list, derived from
// appointment history (no dedicated doctor<->patient relationship table
// exists). doctorId is resolved server-side from the JWT (req.user.sub),
// never accepted from the client — see the isolation note in my-patients.js.
// Supports ?search= against the patient's name, matching what
// my-patients.html's search box already sends.
router.get('/me/patients', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const { search } = req.query;
    const params = [doctorId];
    let searchClause = '';
    if (search) {
      params.push(`%${search}%`);
      searchClause = ` AND (pr.first_name_ar ILIKE $2 OR pr.first_name_en ILIKE $2 OR pr.last_name_ar ILIKE $2 OR pr.last_name_en ILIKE $2)`;
    }

    const result = await db.query(
      `SELECT
         p.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
         pr.phone, pr.profile_image_url,
         r.started_at AS relationship_started_at, r.source AS relationship_source,
         MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) AS next_appointment_date,
         MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date < CURRENT_DATE OR a.status = 'completed') AS last_appointment_date,
         COUNT(*) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) > 0 AS has_upcoming
       FROM medorbit.patients p
       JOIN medorbit.users u ON u.id = p.user_id
       LEFT JOIN medorbit.user_profiles pr ON pr.user_id = u.id
       JOIN medorbit.doctor_patient_relationships r
         ON r.patient_id=p.id AND r.doctor_id=$1 AND r.status='active'
       LEFT JOIN medorbit.appointments a ON a.patient_id=p.id AND a.doctor_id=$1
       WHERE true${searchClause}
       GROUP BY p.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
                pr.phone, pr.profile_image_url, r.started_at, r.source
       ORDER BY COALESCE(MAX(a.scheduled_date), '-infinity') DESC`,
      params
    );

    return success(res, result.rows, 'Patients retrieved');
  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/me/patients/:patientId - Single patient file, as seen by
// their doctor: profile + this doctor's appointment history + session notes
// + prescriptions for this patient. The relationship check runs BEFORE any
// of that is queried and returns 404 (not 403) on failure — see
// verifyDoctorPatientRelationship above and the isolation note in
// patient-detail.js. Notes/prescriptions are always filtered by BOTH
// doctor_id AND patient_id, so a doctor never sees another doctor's notes
// about the same patient.
router.get('/me/patients/:patientId', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const { patientId } = req.params;
    const related = await verifyDoctorPatientRelationship(doctorId, patientId);
    if (!related) return error(res, 'Patient not found', 404, 'NOT_FOUND');

    const patientResult = await db.query(
      `SELECT p.id, u.id AS user_id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
              pr.phone, pr.profile_image_url, pr.date_of_birth, pr.gender
       FROM medorbit.patients p
       JOIN medorbit.users u ON u.id = p.user_id
       LEFT JOIN medorbit.user_profiles pr ON pr.user_id = u.id
       WHERE p.id = $1`,
      [patientId]
    );

    const appointmentsResult = await db.query(
      `SELECT id, appointment_number, scheduled_date, start_time, end_time,
              appointment_type, status, reason_for_visit
       FROM medorbit.appointments
       WHERE doctor_id = $1 AND patient_id = $2
       ORDER BY scheduled_date DESC, start_time DESC`,
      [doctorId, patientId]
    );

    const notesResult = await db.query(
      `SELECT id, record_number, record_type, chief_complaint, diagnosis,
              treatment_plan, clinical_notes, doctor_notes, is_draft, visible_to_patient, created_at
       FROM medorbit.medical_records
       WHERE doctor_id = $1 AND patient_id = $2
       ORDER BY created_at DESC`,
      [doctorId, patientId]
    );

    const prescriptionsResult = await db.query(
      `SELECT id, prescription_number, prescription_date, valid_until, status, diagnosis, instructions
       FROM medorbit.prescriptions
       WHERE doctor_id = $1 AND patient_id = $2
       ORDER BY prescription_date DESC`,
      [doctorId, patientId]
    );

    return success(res, {
      patient: patientResult.rows[0],
      appointments: appointmentsResult.rows,
      notes: notesResult.rows,
      prescriptions: prescriptionsResult.rows
    }, 'Patient detail retrieved');
  } catch (err) {
    next(err);
  }
});

// POST /api/doctors/me/patients/:patientId/notes - Add a session note,
// stored as a medorbit.medical_records row. patient_id/doctor_id are always
// forced server-side (doctor_id from the JWT via resolveDoctorId, patient_id
// from the URL only after the relationship check passes) — never taken from
// the request body.
router.post('/me/patients/:patientId/notes', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const { patientId } = req.params;
    const related = await verifyDoctorPatientRelationship(doctorId, patientId);
    if (!related) return error(res, 'Patient not found', 404, 'NOT_FOUND');

    const { record_type, chief_complaint, diagnosis, clinical_notes, is_draft, visible_to_patient } = req.body;

    const result = await db.query(
      `INSERT INTO medorbit.medical_records
         (patient_id, doctor_id, record_type, chief_complaint, diagnosis, clinical_notes, is_draft, visible_to_patient)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id, record_number, record_type, chief_complaint, diagnosis, clinical_notes, is_draft, visible_to_patient, created_at`,
      [patientId, doctorId, record_type || 'consultation', chief_complaint || null, diagnosis || null, clinical_notes || null, !!is_draft, !!visible_to_patient]
    );

    return success(res, result.rows[0], 'Note saved', 201);
  } catch (err) {
    next(err);
  }
});

router.post('/me/patients/:patientId/relationship/end', authenticate, authorize('doctor'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const doctor = await resolveCurrentDoctor(req.user.sub, client);
    const current = doctor && await client.query(
      `SELECT id FROM medorbit.doctor_patient_relationships
       WHERE doctor_id=$1 AND patient_id=$2 AND status='active'
       FOR UPDATE`,
      [doctor.id, req.params.patientId]
    );
    if (!current?.rows[0]) {
      await client.query('ROLLBACK');
      return error(res, 'Relationship not found', 404, 'NOT_FOUND');
    }
    const relationship = await closeRelationship({
      relationshipId: current.rows[0].id,
      doctorId: doctor.id,
      status: 'ended',
      actorUserId: req.user.sub,
      actorRole: req.user.role,
      reason: req.body.reason,
    }, client);
    await client.query('COMMIT');
    return success(res, {
      id: relationship.id,
      status: relationship.status,
      ended_at: relationship.ended_at,
      end_reason: relationship.end_reason,
    }, 'Care relationship ended');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    return next(err);
  } finally {
    client.release();
  }
});

// GET /api/doctors/me/posts - Doctor's own posts, every status (draft +
// published). doctorId resolved server-side from the JWT — see
// resolveDoctorId above.
router.get('/me/posts', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const result = await db.query(
      `SELECT p.id,p.title_ar,p.title_en,p.category,p.body,p.is_published,p.status,
              p.moderation_status,p.published_at,p.created_at,p.updated_at,
              (SELECT count(*)::int FROM medorbit.post_likes l WHERE l.post_id=p.id) like_count,
              (SELECT count(*)::int FROM medorbit.post_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.moderation_status='approved') comment_count
       FROM medorbit.doctor_posts p
       WHERE p.doctor_id = $1 AND p.deleted_at IS NULL
       ORDER BY created_at DESC`,
      [doctorId]
    );

    return success(
      res,
      result.rows.map((post) => withCanonicalContent(post, 'title', 'title_ar', 'title_en')),
      'Posts retrieved'
    );
  } catch (err) {
    next(err);
  }
});

// POST /api/doctors/me/posts - Create a post. doctor_id always forced
// server-side, never taken from the request body.
router.post('/me/posts', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const { category, body, isPublished } = req.body;
    const title = resolveBilingualUserContent(req.body, {
      canonicalKey: 'title',
      legacyArKeys: ['titleAr', 'title_ar'],
      legacyEnKeys: ['titleEn', 'title_en'],
      label: 'Title',
      maxLength: 150,
      required: true
    });

    const cleanBody=String(body || '').trim();
    if (!cleanBody || cleanBody.length>10000) {
      return error(res, 'body is required', 400, 'VALIDATION_ERROR');
    }
    if (!['health_tip','announcement','clinic_news','article'].includes(category || 'health_tip')) return error(res,'Invalid category',400,'VALIDATION_ERROR');
    const postStatus=isPublished ? 'published' : 'draft';
    const moderationStatus=isPublished ? 'approved' : 'pending';

    const result = await db.query(
      `INSERT INTO medorbit.doctor_posts
         (doctor_id,title_ar,title_en,category,body,is_published,status,moderation_status,published_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,CASE WHEN $6 THEN NOW() ELSE NULL END)
       RETURNING id,title_ar,title_en,category,body,is_published,status,moderation_status,published_at,created_at,updated_at`,
      [doctorId,title.ar,title.en,category || 'health_tip',cleanBody,!!isPublished,postStatus,moderationStatus]
    );

    return success(res, withCanonicalContent(result.rows[0], 'title', 'title_ar', 'title_en'), 'Post created', 201);
  } catch (err) {
    next(err);
  }
});

// PUT /api/doctors/me/posts/:postId - Edit a post. The id + doctor_id match
// in the WHERE clause IS the ownership check — a post belonging to another
// doctor returns 404 here, same as one that doesn't exist.
router.put('/me/posts/:postId', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const { category, body, isPublished } = req.body;
    const title = resolveBilingualUserContent(req.body, {
      canonicalKey: 'title',
      legacyArKeys: ['titleAr', 'title_ar'],
      legacyEnKeys: ['titleEn', 'title_en'],
      label: 'Title',
      maxLength: 150
    });
    if (title.source === 'canonical' && !title.canonical) {
      return error(res, 'Title is required', 400, 'VALIDATION_ERROR');
    }
    if (body !== undefined && (!String(body).trim() || String(body).trim().length>10000)) return error(res,'Invalid post body',400,'VALIDATION_ERROR');
    if (category !== undefined && !['health_tip','announcement','clinic_news','article'].includes(category)) return error(res,'Invalid category',400,'VALIDATION_ERROR');
    const current=await db.query(`SELECT moderation_status FROM medorbit.doctor_posts WHERE id=$1 AND doctor_id=$2 AND deleted_at IS NULL`,[req.params.postId,doctorId]);
    if(!current.rows[0]) return error(res,'Post not found',404,'NOT_FOUND');
    if(isPublished===true && ['hidden','rejected'].includes(current.rows[0].moderation_status)) return error(res,'Post is restricted by moderation',403,'CONTENT_MODERATED');

    const result = await db.query(
      `UPDATE medorbit.doctor_posts
       SET title_ar = CASE WHEN $1::boolean THEN $2 ELSE title_ar END,
           title_en = CASE WHEN $3::boolean THEN $4 ELSE title_en END,
           category = COALESCE($5, category),
           body = COALESCE($6, body),
           is_published = COALESCE($7, is_published),
           status = CASE WHEN $7::boolean IS NULL THEN status WHEN $7 THEN 'published' ELSE 'draft' END,
           moderation_status = CASE WHEN $7=true AND moderation_status='pending' THEN 'approved' ELSE moderation_status END,
           published_at = CASE WHEN $7=true THEN COALESCE(published_at,NOW()) WHEN $7=false THEN NULL ELSE published_at END,
           updated_at=NOW()
       WHERE id = $8 AND doctor_id = $9 AND deleted_at IS NULL
       RETURNING id,title_ar,title_en,category,body,is_published,status,moderation_status,published_at,created_at,updated_at`,
      [
        title.arProvided,title.ar,title.enProvided,title.en,
        category || null,body === undefined ? null : String(body).trim(),
        typeof isPublished === 'boolean' ? isPublished : null,
        req.params.postId,doctorId
      ]
    );

    if (result.rows.length === 0) return error(res, 'Post not found', 404, 'NOT_FOUND');

    return success(res, withCanonicalContent(result.rows[0], 'title', 'title_ar', 'title_en'), 'Post updated');
  } catch (err) {
    next(err);
  }
});

// DELETE /api/doctors/me/posts/:postId - Same ownership check as PUT above.
router.delete('/me/posts/:postId', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const result = await db.query(
      `UPDATE medorbit.doctor_posts SET deleted_at=NOW(),updated_at=NOW()
       WHERE id=$1 AND doctor_id=$2 AND deleted_at IS NULL RETURNING id`,
      [req.params.postId, doctorId]
    );

    if (result.rows.length === 0) return error(res, 'Post not found', 404, 'NOT_FOUND');

    return success(res, null, 'Post deleted');
  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/me/profile - approved doctor's editable professional data.
router.get('/me/profile', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const result = await db.query(
      `SELECT d.id,d.medical_license_number,d.approval_status,
              d.sub_specialty,d.years_of_experience,d.consultation_fee,
              d.consultation_duration,d.education,d.certifications,
              d.professional_bio_ar,d.professional_bio_en,d.professional_headline,
              d.areas_of_expertise,d.professional_interests,d.languages_spoken,
              d.is_accepting_patients,d.specialty_id,p.city,p.profile_image_url,
              s.name_ar AS specialty_ar,s.name_en AS specialty_en
       FROM medorbit.doctors d
       JOIN medorbit.users u ON u.id=d.user_id
       LEFT JOIN medorbit.user_profiles p ON p.user_id=d.user_id
       LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id
       WHERE d.user_id=$1 AND u.role='doctor' AND u.is_active=true
         AND u.deleted_at IS NULL AND d.approval_status='approved'`,
      [req.user.sub]
    );
    if (!result.rows[0]) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');
    return success(res, withCanonicalContent(
      result.rows[0],
      'professional_bio',
      'professional_bio_ar',
      'professional_bio_en'
    ), 'Professional profile retrieved');
  } catch (err) {
    return next(err);
  }
});

// PUT /api/doctors/me/profile - one canonical input per semantic concept.
router.put('/me/profile', authenticate, authorize('doctor'), async (req, res, next) => {
  const client = await db.getClient();
  try {
    const protectedFields = [
      'medical_license_number','medicalLicenseNumber','specialty_id','specialtyId',
      'approval_status','approvalStatus','authorization_version','authorizationVersion',
      'role','user_id','userId'
    ];
    if (protectedFields.some((key) => Object.prototype.hasOwnProperty.call(req.body, key))) {
      return error(res, 'Verified credential and security fields are read-only', 400, 'PROTECTED_FIELD');
    }
    await client.query('BEGIN');
    const doctor = await client.query(
      `SELECT id FROM medorbit.doctors WHERE user_id=$1 AND approval_status='approved'`,
      [req.user.sub]
    );
    if (!doctor.rows[0]) {
      await client.query('ROLLBACK');
      return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');
    }

    const bioPayload = { ...req.body };
    if (!Object.prototype.hasOwnProperty.call(bioPayload, 'bio')) {
      if (Object.prototype.hasOwnProperty.call(bioPayload, 'professionalBio')) {
        bioPayload.bio = bioPayload.professionalBio;
      } else if (Object.prototype.hasOwnProperty.call(bioPayload, 'professional_bio')) {
        bioPayload.bio = bioPayload.professional_bio;
      }
    }
    const professionalBio = resolveBilingualUserContent(bioPayload, {
      canonicalKey: 'bio',
      legacyArKeys: ['professionalBioAr', 'professional_bio_ar'],
      legacyEnKeys: ['professionalBioEn', 'professional_bio_en'],
      label: 'Professional bio'
    });
    if ((professionalBio.arProvided && professionalBio.ar?.length > 3000)
        || (professionalBio.enProvided && professionalBio.en?.length > 3000)) {
      await client.query('ROLLBACK');
      return error(res, 'Professional bio must not exceed 3000 characters', 400, 'VALIDATION_ERROR');
    }

    const headline = boundedText(req.body, ['professionalHeadline', 'professional_headline'], 'Professional headline', 160);
    const subSpecialty = boundedText(req.body, ['subSpecialty', 'sub_specialty'], 'Sub-specialty', 160);
    const expertise = boundedTags(req.body, ['areasOfExpertise', 'areas_of_expertise'], 'Areas of expertise', 12);
    const interests = boundedTags(req.body, ['professionalInterests', 'professional_interests'], 'Professional interests', 10);
    const languages = boundedTags(req.body, ['languagesSpoken', 'languages_spoken'], 'Languages spoken', 10);
    const education = boundedTags(req.body, ['education'], 'Education', 20, 160);
    const certifications = boundedTags(req.body, ['certifications'], 'Certifications', 20, 160);
    const experience = boundedInteger(req.body, ['yearsOfExperience', 'years_of_experience'], 'Years of experience', 0, 80);
    const city = boundedText(req.body, ['city'], 'City', 80);
    const feeProvided = Object.prototype.hasOwnProperty.call(req.body, 'consultationFee')
      || Object.prototype.hasOwnProperty.call(req.body, 'consultation_fee');
    const fee = feeProvided ? Number(req.body.consultationFee ?? req.body.consultation_fee) : null;
    if (feeProvided && (!Number.isFinite(fee) || fee < 0 || fee > 100000 || Math.round(fee * 100) !== fee * 100)) {
      await client.query('ROLLBACK');
      return error(res, 'Consultation fee must be between 0 and 100000 with at most two decimals', 400, 'VALIDATION_ERROR');
    }
    const durationProvided = Object.prototype.hasOwnProperty.call(req.body, 'consultationDuration')
      || Object.prototype.hasOwnProperty.call(req.body, 'consultation_duration');
    const duration = durationProvided ? Number(req.body.consultationDuration ?? req.body.consultation_duration) : null;
    if (durationProvided && !scheduling.ALLOWED_DURATIONS.has(duration)) {
      await client.query('ROLLBACK');
      return error(res, 'Consultation duration must be 15, 20, 30, 45, or 60 minutes', 400, 'VALIDATION_ERROR');
    }
    const acceptingProvided = Object.prototype.hasOwnProperty.call(req.body, 'isAcceptingPatients')
      || Object.prototype.hasOwnProperty.call(req.body, 'is_accepting_patients');
    const accepting = req.body.isAcceptingPatients ?? req.body.is_accepting_patients;
    if (acceptingProvided && typeof accepting !== 'boolean') {
      await client.query('ROLLBACK');
      return error(res, 'Accepting-patients state must be boolean', 400, 'VALIDATION_ERROR');
    }

    await client.query(
      `UPDATE medorbit.doctors
       SET professional_headline=CASE WHEN $1 THEN $2 ELSE professional_headline END,
           sub_specialty=CASE WHEN $3 THEN $4 ELSE sub_specialty END,
           years_of_experience=CASE WHEN $5 THEN $6 ELSE years_of_experience END,
           areas_of_expertise=CASE WHEN $7 THEN $8::text[] ELSE areas_of_expertise END,
           professional_interests=CASE WHEN $9 THEN $10::text[] ELSE professional_interests END,
           languages_spoken=CASE WHEN $11 THEN $12::text[] ELSE languages_spoken END,
           education=CASE WHEN $13 THEN $14::text[] ELSE education END,
           certifications=CASE WHEN $15 THEN $16::text[] ELSE certifications END,
           professional_bio_ar=CASE WHEN $17 THEN $18 ELSE professional_bio_ar END,
           professional_bio_en=CASE WHEN $19 THEN $20 ELSE professional_bio_en END,
           is_accepting_patients=CASE WHEN $21 THEN $22 ELSE is_accepting_patients END,
           consultation_fee=CASE WHEN $23 THEN $24 ELSE consultation_fee END,
           consultation_duration=CASE WHEN $25 THEN $26 ELSE consultation_duration END,
           updated_at=NOW()
       WHERE id=$27`,
      [
        headline.provided, headline.value,
        subSpecialty.provided, subSpecialty.value,
        experience.provided, experience.value,
        expertise.provided, expertise.value,
        interests.provided, interests.value,
        languages.provided, languages.value,
        education.provided, education.value,
        certifications.provided, certifications.value,
        professionalBio.arProvided, professionalBio.ar,
        professionalBio.enProvided, professionalBio.en,
        acceptingProvided, accepting,
        feeProvided, fee,
        durationProvided, duration,
        doctor.rows[0].id
      ]
    );

    if (city.provided) {
      await client.query(
        `UPDATE medorbit.user_profiles SET city=$1,updated_at=NOW() WHERE user_id=$2`,
        [city.value, req.user.sub]
      );
    }

    const updated = await client.query(
      `SELECT d.id,d.medical_license_number,d.approval_status,d.sub_specialty,
              d.years_of_experience,d.consultation_fee,d.consultation_duration,
              d.education,d.certifications,
              d.professional_bio_ar,d.professional_bio_en,d.professional_headline,
              d.areas_of_expertise,d.professional_interests,d.languages_spoken,
              d.is_accepting_patients,d.specialty_id,p.city,p.profile_image_url,
              s.name_ar AS specialty_ar,s.name_en AS specialty_en
       FROM medorbit.doctors d
       LEFT JOIN medorbit.user_profiles p ON p.user_id=d.user_id
       LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id
       WHERE d.id=$1`,
      [doctor.rows[0].id]
    );
    await client.query('COMMIT');
    return success(res, withCanonicalContent(
      updated.rows[0],
      'professional_bio',
      'professional_bio_ar',
      'professional_bio_en'
    ), 'Professional profile updated');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    return next(err);
  } finally {
    client.release();
  }
});

// Doctor-owned scheduling API. Doctor identity is always resolved from the
// authenticated user; client-supplied doctor identifiers are rejected by the
// service and admins do not impersonate doctors through these routes.
router.get('/me/schedule', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    return success(res, await scheduling.getDoctorSchedule(req.user.sub), 'Doctor schedule retrieved');
  } catch (err) {
    return next(err);
  }
});

router.post('/me/availability', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    return success(
      res,
      await scheduling.createAvailability(req.user.sub, req.body),
      'Availability created',
      201
    );
  } catch (err) {
    return next(err);
  }
});

router.put('/me/availability/:slotId', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    return success(
      res,
      await scheduling.updateAvailability(req.user.sub, req.params.slotId, req.body),
      'Availability updated'
    );
  } catch (err) {
    return next(err);
  }
});

router.delete('/me/availability/:slotId', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    return success(
      res,
      await scheduling.deleteAvailability(req.user.sub, req.params.slotId),
      'Availability deleted'
    );
  } catch (err) {
    return next(err);
  }
});

// GET /api/doctors - List all doctors with filters
router.get('/', authenticate, async (req, res, next) => {
  try {
    const { specialty, region, minRating, minFee, maxFee, search, page = 1, limit = 10 } = req.query;
    const pageNumber=Math.max(Number.parseInt(page,10)||1,1),limitNumber=Math.min(Math.max(Number.parseInt(limit,10)||10,1),50);
    if(req.user && !specialty && !region && !minRating && !minFee && !maxFee && !search){
      const ranked=await getRankedDoctors({userId:req.user.sub,limit:pageNumber*limitNumber});
      const total=Number((await db.query(`SELECT count(*) FROM medorbit.doctors d JOIN medorbit.users u ON u.id=d.user_id
        WHERE u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL AND d.approval_status='approved'`)).rows[0].count);
      return success(res,{doctors:ranked.slice((pageNumber-1)*limitNumber),pagination:{page:pageNumber,limit:limitNumber,total,totalPages:Math.ceil(total/limitNumber)}},'Doctors retrieved successfully');
    }

    let query = `
      SELECT
        d.id, d.medical_license_number, d.years_of_experience,
        d.consultation_fee, d.consultation_duration, d.average_rating, d.total_ratings,
        d.is_accepting_patients, d.education, d.certifications,d.sub_specialty,
        d.professional_headline,d.areas_of_expertise,d.professional_interests,d.languages_spoken,
        d.professional_bio_ar, d.professional_bio_en,
        p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
        p.profile_image_url,p.city,
        (SELECT count(*)::int FROM medorbit.user_follows f WHERE f.doctor_id=d.id) AS follower_count,
        s.name_ar as specialty_ar, s.name_en as specialty_en,
        s.icon as specialty_icon
      FROM medorbit.doctors d
      JOIN medorbit.users u ON u.id = d.user_id
      LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
      WHERE u.is_active = true AND u.deleted_at IS NULL AND d.approval_status = 'approved'
    `;

    const params = [];
    let paramIndex = 1;

    if (specialty) {
      query += ` AND (s.name_en ILIKE $${paramIndex} OR s.name_ar ILIKE $${paramIndex})`;
      params.push(`%${specialty}%`);
      paramIndex++;
    }

    if (region) {
      query += ` AND p.city ILIKE $${paramIndex}`;
      params.push(`%${region}%`);
      paramIndex++;
    }

    if (minRating) {
      query += ` AND d.average_rating >= $${paramIndex}`;
      params.push(parseFloat(minRating));
      paramIndex++;
    }

    if (minFee) {
      query += ` AND d.consultation_fee >= $${paramIndex}`;
      params.push(Number(minFee));
      paramIndex++;
    }

    if (maxFee) {
      query += ` AND d.consultation_fee <= $${paramIndex}`;
      params.push(Number(maxFee));
      paramIndex++;
    }

    if (search) {
      query += ` AND (
        p.first_name_ar ILIKE $${paramIndex} OR
        p.first_name_en ILIKE $${paramIndex} OR
        p.last_name_ar ILIKE $${paramIndex} OR
        p.last_name_en ILIKE $${paramIndex} OR
        d.sub_specialty ILIKE $${paramIndex} OR
        d.professional_headline ILIKE $${paramIndex} OR
        array_to_string(d.areas_of_expertise,' ') ILIKE $${paramIndex}
      )`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    // Count total
    const countResult = await db.query(
      `SELECT COUNT(*) FROM (${query}) as count_query`,
      params
    );
    const total = parseInt(countResult.rows[0].count);

    // Add pagination
    query += ` ORDER BY d.average_rating DESC, d.total_ratings DESC`;
    query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(limitNumber, (pageNumber - 1) * limitNumber);

    const result = await db.query(query, params);

    return success(res, {
      doctors: result.rows,
      pagination: {
        page: pageNumber,
        limit: limitNumber,
        total,
        totalPages: Math.ceil(total / limitNumber)
      }
    }, 'Doctors retrieved successfully');

  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id - Get doctor details
router.get('/:id', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;

    // Doctor details
    const doctorResult = await db.query(
      `SELECT
        d.id, d.user_id, d.medical_license_number, d.years_of_experience,
        d.consultation_fee, d.consultation_duration, d.average_rating, d.total_ratings,
        d.is_accepting_patients, d.education, d.certifications,d.sub_specialty,
        d.professional_headline,d.areas_of_expertise,d.professional_interests,d.languages_spoken,
        d.professional_bio_ar, d.professional_bio_en,
        u.created_at, to_jsonb(u)->'preferences'->'social_links' AS social_links,
        p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
        p.profile_image_url, p.city,
        true AS is_verified,
        (SELECT count(*)::int FROM medorbit.user_follows f WHERE f.doctor_id=d.id) AS follower_count,
        CASE WHEN $2::uuid IS NULL THEN false ELSE EXISTS(
          SELECT 1 FROM medorbit.user_follows f WHERE f.doctor_id=d.id AND f.user_id=$2
        ) END AS is_following,
        s.name_ar as specialty_ar, s.name_en as specialty_en,
        s.description_ar, s.description_en, s.icon as specialty_icon
      FROM medorbit.doctors d
      JOIN medorbit.users u ON u.id = d.user_id
      LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
      WHERE d.id = $1 AND u.is_active = true AND u.deleted_at IS NULL AND d.approval_status = 'approved'`,
      [id, req.user?.sub || null]
    );

    if (doctorResult.rows.length === 0) {
      return error(res, 'Doctor not found', 404, 'NOT_FOUND');
    }

    const doctor = withCanonicalContent(
      doctorResult.rows[0],
      'professional_bio',
      'professional_bio_ar',
      'professional_bio_en'
    );
    doctor.is_owner = Boolean(req.user && doctor.user_id === req.user.sub);
    delete doctor.user_id;

    const clinics = await findActiveClinicsByDoctorId(id);

    // Availability
    const availabilityResult = await db.query(
      `SELECT
        da.id, da.clinic_id, da.day_of_week, da.specific_date,
        da.start_time, da.end_time, da.slot_duration, da.is_telemedicine
      FROM medorbit.doctor_availability da
      JOIN medorbit.doctors d ON d.id=da.doctor_id
      JOIN medorbit.users u ON u.id=d.user_id
      WHERE da.doctor_id = $1 AND da.is_active = true
        AND da.availability_type='available' AND da.day_of_week IS NOT NULL
        AND d.approval_status='approved' AND u.is_active=true AND u.deleted_at IS NULL
      ORDER BY da.day_of_week, da.start_time`,
      [id]
    );

    // Reviews
    const reviewsResult = await db.query(
      `SELECT
        r.id, r.rating, r.review_text_ar, r.review_text_en,
        r.professionalism_rating, r.treatment_rating, r.communication_rating,
        r.created_at,
        p.first_name_ar as patient_first_name_ar,
        p.first_name_en as patient_first_name_en
      FROM medorbit.doctor_reviews r
      JOIN medorbit.patients pt ON pt.id = r.patient_id
      LEFT JOIN medorbit.user_profiles p ON p.user_id = pt.user_id
      WHERE r.doctor_id = $1 AND r.is_visible = true
      ORDER BY r.created_at DESC
      LIMIT 10`,
      [id]
    );

    return success(res, {
      doctor,
      clinics,
      availability: availabilityResult.rows,
      reviews: reviewsResult.rows.map((review) => (
        withCanonicalContent(review, 'review_text', 'review_text_ar', 'review_text_en')
      ))
    }, 'Doctor details retrieved');

  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id/availability - Get available slots
router.get('/:id/availability', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { date } = req.query; // optional: specific date

    let query = `
      SELECT
        da.id, da.clinic_id, da.day_of_week, da.specific_date,
        da.start_time, da.end_time, da.slot_duration, da.is_telemedicine
      FROM medorbit.doctor_availability da
      JOIN medorbit.doctors d ON d.id=da.doctor_id
      JOIN medorbit.users u ON u.id=d.user_id
      WHERE da.doctor_id = $1 AND da.is_active = true
        AND da.availability_type='available'
        AND d.approval_status='approved' AND u.is_active=true AND u.deleted_at IS NULL
    `;

    const params = [id];

    if (date) {
      query += ` AND (da.specific_date = $2 OR (da.specific_date IS NULL AND da.day_of_week = EXTRACT(DOW FROM $2::date)))`;
      params.push(date);
    }

    query += ` ORDER BY da.day_of_week, da.start_time`;

    const result = await db.query(query, params);

    return success(res, {
      slots: result.rows
    }, 'Availability retrieved');

  } catch (err) {
    next(err);
  }
});

// Legacy owner-only profile endpoint retained for compatibility. Verified
// specialty/license state is intentionally not editable here.
router.put('/:id', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = req.user.sub;
    const doctorCheck = await db.query(
      'SELECT user_id FROM medorbit.doctors WHERE id=$1 AND approval_status=\'approved\'',
      [id]
    );
    if (doctorCheck.rows.length === 0 || doctorCheck.rows[0].user_id !== userId) {
      return error(res, 'Unauthorized', 403, 'FORBIDDEN');
    }
    if (['specialtyId','specialty_id','medicalLicenseNumber','medical_license_number',
      'approvalStatus','approval_status'].some((key) => Object.prototype.hasOwnProperty.call(req.body, key))) {
      return error(res, 'Verified credential fields are read-only', 400, 'PROTECTED_FIELD');
    }

    const experience = boundedInteger(req.body, ['yearsOfExperience', 'years_of_experience'], 'Years of experience', 0, 80);
    const education = boundedTags(req.body, ['education'], 'Education', 20, 160);
    const certifications = boundedTags(req.body, ['certifications'], 'Certifications', 20, 160);
    const feeProvided = Object.prototype.hasOwnProperty.call(req.body, 'consultationFee')
      || Object.prototype.hasOwnProperty.call(req.body, 'consultation_fee');
    const fee = feeProvided ? Number(req.body.consultationFee ?? req.body.consultation_fee) : null;
    if (feeProvided && (!Number.isFinite(fee) || fee < 0 || fee > 100000 || Math.round(fee * 100) !== fee * 100)) {
      return error(res, 'Invalid consultation fee', 400, 'VALIDATION_ERROR');
    }
    const durationProvided = Object.prototype.hasOwnProperty.call(req.body, 'consultationDuration')
      || Object.prototype.hasOwnProperty.call(req.body, 'consultation_duration');
    const duration = durationProvided ? Number(req.body.consultationDuration ?? req.body.consultation_duration) : null;
    if (durationProvided && !scheduling.ALLOWED_DURATIONS.has(duration)) {
      return error(res, 'Invalid consultation duration', 400, 'VALIDATION_ERROR');
    }
    const acceptingProvided = Object.prototype.hasOwnProperty.call(req.body, 'isAcceptingPatients')
      || Object.prototype.hasOwnProperty.call(req.body, 'is_accepting_patients');
    const accepting = req.body.isAcceptingPatients ?? req.body.is_accepting_patients;
    if (acceptingProvided && typeof accepting !== 'boolean') {
      return error(res, 'Invalid accepting-patients state', 400, 'VALIDATION_ERROR');
    }
    const professionalBio = resolveBilingualUserContent(req.body, {
      canonicalKey: 'professionalBio',
      legacyArKeys: ['professionalBioAr', 'professional_bio_ar'],
      legacyEnKeys: ['professionalBioEn', 'professional_bio_en'],
      label: 'Professional bio'
    });

    await db.query(
      `UPDATE medorbit.doctors
       SET years_of_experience = CASE WHEN $1 THEN $2 ELSE years_of_experience END,
           consultation_fee = CASE WHEN $3 THEN $4 ELSE consultation_fee END,
           consultation_duration = CASE WHEN $5 THEN $6 ELSE consultation_duration END,
           education = CASE WHEN $7 THEN $8::text[] ELSE education END,
           certifications = CASE WHEN $9 THEN $10::text[] ELSE certifications END,
           professional_bio_ar = CASE WHEN $11 THEN $12 ELSE professional_bio_ar END,
           professional_bio_en = CASE WHEN $13 THEN $14 ELSE professional_bio_en END,
           is_accepting_patients = CASE WHEN $15 THEN $16 ELSE is_accepting_patients END,
           updated_at=NOW()
       WHERE id = $17`,
      [experience.provided, experience.value,
        feeProvided, fee,
        durationProvided, duration,
        education.provided, education.value,
        certifications.provided, certifications.value,
        professionalBio.arProvided, professionalBio.ar,
        professionalBio.enProvided, professionalBio.en,
        acceptingProvided, accepting, id]
    );

    return success(res, null, 'Doctor profile updated');

  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id/clinics - Clinics this doctor is assigned to
router.get('/:id/clinics', authenticate, async (req, res, next) => {
  try {
    const clinics = await findActiveClinicsByDoctorId(req.params.id);
    const compactClinics = clinics.map(({ region, latitude, longitude, ...clinic }) => clinic);
    return success(res, compactClinics, "Doctor clinics retrieved");
  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id/posts - Public read of a doctor's PUBLISHED posts
// only (doctor.html's Posts tab). Drafts never leave the doctor's own
// GET /me/posts above.
router.get('/:id/posts', authenticate, async (req, res, next) => {
  try {
    const result = await db.query(
      `SELECT p.id,p.title_ar,p.title_en,p.category,p.body,p.published_at,p.created_at,
              (SELECT count(*)::int FROM medorbit.post_likes l WHERE l.post_id=p.id) like_count,
              (SELECT count(*)::int FROM medorbit.post_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.moderation_status='approved') comment_count
       FROM medorbit.doctor_posts p
       JOIN medorbit.doctors d ON d.id=p.doctor_id
       JOIN medorbit.users u ON u.id=d.user_id
       WHERE p.doctor_id=$1 AND p.status='published' AND p.moderation_status='approved' AND p.deleted_at IS NULL
         AND d.approval_status='approved' AND u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL
       ORDER BY p.published_at DESC,p.id DESC`,
      [req.params.id]
    );

    return success(
      res,
      result.rows.map((post) => withCanonicalContent(post, 'title', 'title_ar', 'title_en')),
      "Doctor posts retrieved"
    );
  } catch (err) {
    next(err);
  }
});

// POST /api/doctors/:id/availability - Create availability slot
router.post(
  '/:id/availability',
  authenticate,
  authorize('doctor'),
  async (req, res, next) => {
    try {
      const currentDoctor = await resolveCurrentDoctor(req.user.sub);
      if (!currentDoctor || currentDoctor.id !== req.params.id) {
        return error(res, 'Availability not found', 404, 'NOT_FOUND');
      }
      return success(
        res,
        await scheduling.createAvailability(req.user.sub, req.body),
        'Availability created',
        201
      );
    } catch (err) {
      next(err);
    }
  }
);

// PUT /api/doctors/:id/availability/:slotId - Update availability slot
router.put(
  '/:id/availability/:slotId',
  authenticate,
  authorize('doctor'),
  async (req, res, next) => {
    try {
      const currentDoctor = await resolveCurrentDoctor(req.user.sub);
      if (!currentDoctor || currentDoctor.id !== req.params.id) {
        return error(res, 'Availability not found', 404, 'NOT_FOUND');
      }
      return success(
        res,
        await scheduling.updateAvailability(req.user.sub, req.params.slotId, req.body),
        'Availability updated'
      );
    } catch (err) {
      next(err);
    }
  }
);

// DELETE /api/doctors/:id/availability/:slotId - Deactivate availability slot
router.delete(
  '/:id/availability/:slotId',
  authenticate,
  authorize('doctor'),
  async (req, res, next) => {
    try {
      const currentDoctor = await resolveCurrentDoctor(req.user.sub);
      if (!currentDoctor || currentDoctor.id !== req.params.id) {
        return error(res, 'Availability not found', 404, 'NOT_FOUND');
      }
      return success(
        res,
        await scheduling.deleteAvailability(req.user.sub, req.params.slotId),
        'Availability deleted'
      );
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
