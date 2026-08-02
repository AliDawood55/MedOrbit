// src/routes/doctor.routes.js
const express = require('express');
const db = require('../config/database');
const { success, error } = require('../utils/response');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();

// Shared by all doctor<->patient routes below.
async function resolveDoctorId(userId) {
  const result = await db.query('SELECT id FROM medorbit.doctors WHERE user_id = $1', [userId]);
  return result.rows[0]?.id || null;
}

// A doctor may only act on a patient they have (or had) at least one
// appointment with — there's no dedicated relationship table. Returns a
// boolean rather than throwing so callers can turn a "no" into a 404 (not
// 403), so a doctor probing random patient ids can't tell real ids from
// fake ones — see the isolation note in patient-detail.js.
async function verifyDoctorPatientRelationship(doctorId, patientId) {
  const result = await db.query(
    'SELECT 1 FROM medorbit.appointments WHERE doctor_id = $1 AND patient_id = $2 LIMIT 1',
    [doctorId, patientId]
  );
  return result.rows.length > 0;
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
         MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) AS next_appointment_date,
         MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date < CURRENT_DATE OR a.status = 'completed') AS last_appointment_date,
         COUNT(*) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) > 0 AS has_upcoming
       FROM medorbit.patients p
       JOIN medorbit.users u ON u.id = p.user_id
       LEFT JOIN medorbit.user_profiles pr ON pr.user_id = u.id
       JOIN medorbit.appointments a ON a.patient_id = p.id
       WHERE a.doctor_id = $1${searchClause}
       GROUP BY p.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en, pr.phone, pr.profile_image_url
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
      `SELECT p.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
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

// GET /api/doctors/me/posts - Doctor's own posts, every status (draft +
// published). doctorId resolved server-side from the JWT — see
// resolveDoctorId above.
router.get('/me/posts', authenticate, authorize('doctor'), async (req, res, next) => {
  try {
    const doctorId = await resolveDoctorId(req.user.sub);
    if (!doctorId) return error(res, 'Doctor profile not found', 404, 'NOT_FOUND');

    const result = await db.query(
      `SELECT id, title_ar, title_en, category, body, is_published, created_at, updated_at
       FROM medorbit.doctor_posts
       WHERE doctor_id = $1
       ORDER BY created_at DESC`,
      [doctorId]
    );

    return success(res, result.rows, 'Posts retrieved');
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

    const { titleAr, titleEn, category, body, isPublished } = req.body;

    if (!titleAr && !titleEn) {
      return error(res, 'titleAr or titleEn is required', 400, 'VALIDATION_ERROR');
    }
    if (!body) {
      return error(res, 'body is required', 400, 'VALIDATION_ERROR');
    }

    const result = await db.query(
      `INSERT INTO medorbit.doctor_posts (doctor_id, title_ar, title_en, category, body, is_published)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, title_ar, title_en, category, body, is_published, created_at, updated_at`,
      [doctorId, titleAr || null, titleEn || null, category || 'health_tip', body, !!isPublished]
    );

    return success(res, result.rows[0], 'Post created', 201);
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

    const { titleAr, titleEn, category, body, isPublished } = req.body;

    const result = await db.query(
      `UPDATE medorbit.doctor_posts
       SET title_ar = COALESCE($1, title_ar),
           title_en = COALESCE($2, title_en),
           category = COALESCE($3, category),
           body = COALESCE($4, body),
           is_published = COALESCE($5, is_published)
       WHERE id = $6 AND doctor_id = $7
       RETURNING id, title_ar, title_en, category, body, is_published, created_at, updated_at`,
      [titleAr || null, titleEn || null, category || null, body || null, typeof isPublished === 'boolean' ? isPublished : null, req.params.postId, doctorId]
    );

    if (result.rows.length === 0) return error(res, 'Post not found', 404, 'NOT_FOUND');

    return success(res, result.rows[0], 'Post updated');
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
      `DELETE FROM medorbit.doctor_posts WHERE id = $1 AND doctor_id = $2 RETURNING id`,
      [req.params.postId, doctorId]
    );

    if (result.rows.length === 0) return error(res, 'Post not found', 404, 'NOT_FOUND');

    return success(res, null, 'Post deleted');
  } catch (err) {
    next(err);
  }
});

// GET /api/doctors - List all doctors with filters
router.get('/', async (req, res, next) => {
  try {
    const { specialty, region, minRating, minFee, maxFee, search, page = 1, limit = 10 } = req.query;

    let query = `
      SELECT
        d.id, d.user_id, d.medical_license_number, d.years_of_experience,
        d.consultation_fee, d.consultation_duration, d.average_rating, d.total_ratings,
        d.is_accepting_patients, d.education, d.certifications,
        d.professional_bio_ar, d.professional_bio_en,
        u.email,
        p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
        p.phone, p.profile_image_url,
        s.name_ar as specialty_ar, s.name_en as specialty_en,
        s.icon as specialty_icon
      FROM medorbit.doctors d
      JOIN medorbit.users u ON u.id = d.user_id
      LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
      WHERE u.is_active = true AND u.deleted_at IS NULL
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
        p.last_name_en ILIKE $${paramIndex}
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
    params.push(parseInt(limit), (parseInt(page) - 1) * parseInt(limit));

    const result = await db.query(query, params);

    return success(res, {
      doctors: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        totalPages: Math.ceil(total / parseInt(limit))
      }
    }, 'Doctors retrieved successfully');

  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id - Get doctor details
router.get('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;

    // Doctor details
    const doctorResult = await db.query(
      `SELECT
        d.id, d.user_id, d.medical_license_number, d.years_of_experience,
        d.consultation_fee, d.consultation_duration, d.average_rating, d.total_ratings,
        d.is_accepting_patients, d.education, d.certifications,
        d.professional_bio_ar, d.professional_bio_en,
        u.email, u.created_at,
        p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
        p.phone, p.profile_image_url, p.address, p.city,
        s.name_ar as specialty_ar, s.name_en as specialty_en,
        s.description_ar, s.description_en, s.icon as specialty_icon
      FROM medorbit.doctors d
      JOIN medorbit.users u ON u.id = d.user_id
      LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
      WHERE d.id = $1 AND u.is_active = true AND u.deleted_at IS NULL`,
      [id]
    );

    if (doctorResult.rows.length === 0) {
      return error(res, 'Doctor not found', 404, 'NOT_FOUND');
    }

    const doctor = doctorResult.rows[0];

    // Clinics
    const clinicsResult = await db.query(
      `SELECT
        c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
        c.city, c.region, c.latitude, c.longitude, c.phone,
        dca.consultation_fee_override, dca.is_primary
      FROM medorbit.doctor_clinic_assignments dca
      JOIN medorbit.clinics c ON c.id = dca.clinic_id
      WHERE dca.doctor_id = $1 AND dca.is_active = true AND c.is_active = true`,
      [id]
    );

    // Availability
    const availabilityResult = await db.query(
      `SELECT
        id, clinic_id, day_of_week, specific_date,
        start_time, end_time, slot_duration, is_telemedicine
      FROM medorbit.doctor_availability
      WHERE doctor_id = $1 AND is_active = true
      ORDER BY day_of_week, start_time`,
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
      clinics: clinicsResult.rows,
      availability: availabilityResult.rows,
      reviews: reviewsResult.rows
    }, 'Doctor details retrieved');

  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id/availability - Get available slots
router.get('/:id/availability', async (req, res, next) => {
  try {
    const { id } = req.params;
    const { date } = req.query; // optional: specific date

    let query = `
      SELECT
        id, clinic_id, day_of_week, specific_date,
        start_time, end_time, slot_duration, is_telemedicine
      FROM medorbit.doctor_availability
      WHERE doctor_id = $1 AND is_active = true
    `;

    const params = [id];

    if (date) {
      query += ` AND (specific_date = $2 OR (specific_date IS NULL AND day_of_week = EXTRACT(DOW FROM $2::date)))`;
      params.push(date);
    }

    query += ` ORDER BY day_of_week, start_time`;

    const result = await db.query(query, params);

    return success(res, {
      slots: result.rows
    }, 'Availability retrieved');

  } catch (err) {
    next(err);
  }
});

// PUT /api/doctors/:id - Update doctor profile (Doctor only)
router.put('/:id', authenticate, authorize('doctor', 'admin'), async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = req.user.sub;

    // Check ownership (unless admin)
    if (req.user.role !== 'admin') {
      const doctorCheck = await db.query(
        'SELECT user_id FROM medorbit.doctors WHERE id = $1',
        [id]
      );
      if (doctorCheck.rows.length === 0 || doctorCheck.rows[0].user_id !== userId) {
        return error(res, 'Unauthorized', 403, 'FORBIDDEN');
      }
    }

    const {
      yearsOfExperience, consultationFee, consultationDuration,
      education, certifications, professionalBioAr, professionalBioEn,
      isAcceptingPatients, specialtyId
    } = req.body;

    await db.query(
      `UPDATE medorbit.doctors
       SET years_of_experience = COALESCE($1, years_of_experience),
           consultation_fee = COALESCE($2, consultation_fee),
           consultation_duration = COALESCE($3, consultation_duration),
           education = COALESCE($4, education),
           certifications = COALESCE($5, certifications),
           professional_bio_ar = COALESCE($6, professional_bio_ar),
           professional_bio_en = COALESCE($7, professional_bio_en),
           is_accepting_patients = COALESCE($8, is_accepting_patients),
           specialty_id = COALESCE($9, specialty_id)
       WHERE id = $10`,
      [yearsOfExperience, consultationFee, consultationDuration,
        education, certifications, professionalBioAr, professionalBioEn,
        isAcceptingPatients, specialtyId, id]
    );

    return success(res, null, 'Doctor profile updated');

  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id/clinics - Clinics this doctor is assigned to
router.get('/:id/clinics', async (req, res, next) => {
  try {
    const result = await db.query(
      `SELECT
        c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
        c.city, c.phone,
        dca.is_primary, dca.consultation_fee_override
      FROM medorbit.doctor_clinic_assignments dca
      JOIN medorbit.clinics c ON c.id = dca.clinic_id
      WHERE dca.doctor_id = $1 AND dca.is_active = true AND c.is_active = true`,
      [req.params.id]
    );

    return success(res, result.rows, "Doctor clinics retrieved");
  } catch (err) {
    next(err);
  }
});

// GET /api/doctors/:id/posts - Public read of a doctor's PUBLISHED posts
// only (doctor.html's Posts tab). Drafts never leave the doctor's own
// GET /me/posts above.
router.get('/:id/posts', async (req, res, next) => {
  try {
    const result = await db.query(
      `SELECT id, title_ar, title_en, category, body, created_at
       FROM medorbit.doctor_posts
       WHERE doctor_id = $1 AND is_published = true
       ORDER BY created_at DESC`,
      [req.params.id]
    );

    return success(res, result.rows, "Doctor posts retrieved");
  } catch (err) {
    next(err);
  }
});

// POST /api/doctors/:id/availability - Create availability slot
router.post(
  '/:id/availability',
  authenticate,
  authorize('doctor', 'admin'),
  async (req, res, next) => {
    try {
      const doctorId = req.params.id;
      const {
        clinic_id, day_of_week, specific_date,
        start_time, end_time, slot_duration, is_telemedicine
      } = req.body;

      const result = await db.query(
        `INSERT INTO medorbit.doctor_availability
          (doctor_id, clinic_id, day_of_week, specific_date, start_time, end_time, slot_duration, is_telemedicine)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING *`,
        [doctorId, clinic_id || null, day_of_week, specific_date || null,
          start_time, end_time, slot_duration || 30, is_telemedicine || false]
      );

      return success(res, result.rows[0], "Availability created");
    } catch (err) {
      next(err);
    }
  }
);

// PUT /api/doctors/:id/availability/:slotId - Update availability slot
router.put(
  '/:id/availability/:slotId',
  authenticate,
  authorize('doctor', 'admin'),
  async (req, res, next) => {
    try {
      const { start_time, end_time, slot_duration, is_telemedicine, clinic_id } = req.body;

      const result = await db.query(
        `UPDATE medorbit.doctor_availability
         SET start_time = COALESCE($1, start_time),
             end_time = COALESCE($2, end_time),
             slot_duration = COALESCE($3, slot_duration),
             is_telemedicine = COALESCE($4, is_telemedicine),
             clinic_id = COALESCE($5, clinic_id)
         WHERE id = $6 AND doctor_id = $7
         RETURNING *`,
        [start_time, end_time, slot_duration, is_telemedicine, clinic_id,
          req.params.slotId, req.params.id]
      );

      if (result.rows.length === 0) {
        return error(res, "Availability not found", 404, "NOT_FOUND");
      }

      return success(res, result.rows[0], "Availability updated");
    } catch (err) {
      next(err);
    }
  }
);

// DELETE /api/doctors/:id/availability/:slotId - Deactivate availability slot
router.delete(
  '/:id/availability/:slotId',
  authenticate,
  authorize('doctor', 'admin'),
  async (req, res, next) => {
    try {
      await db.query(
        `UPDATE medorbit.doctor_availability
         SET is_active = false
         WHERE id = $1 AND doctor_id = $2`,
        [req.params.slotId, req.params.id]
      );

      return success(res, null, "Availability deleted");
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
