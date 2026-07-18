const express = require('express');
const db = require('../config/database');
const { success, error } = require('../utils/response');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();

// GET /api/doctors - List all doctors with filters
router.get('/', async (req, res, next) => {
  try {
    const { specialty, region, minRating, search, page = 1, limit = 10 } = req.query;

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
      FROM public.doctors d
      JOIN public.users u ON u.id = d.user_id
      LEFT JOIN public.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN public.specialties s ON s.id = d.specialty_id
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
      FROM public.doctors d
      JOIN public.users u ON u.id = d.user_id
      LEFT JOIN public.user_profiles p ON p.user_id = d.user_id
      LEFT JOIN public.specialties s ON s.id = d.specialty_id
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
      FROM public.doctor_clinic_assignments dca
      JOIN public.clinics c ON c.id = dca.clinic_id
      WHERE dca.doctor_id = $1 AND dca.is_active = true AND c.is_active = true`,
      [id]
    );

    // Availability
    const availabilityResult = await db.query(
      `SELECT 
        id, clinic_id, day_of_week, specific_date,
        start_time, end_time, slot_duration, is_telemedicine
      FROM public.doctor_availability
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
      FROM public.doctor_reviews r
      JOIN public.patients pt ON pt.id = r.patient_id
      LEFT JOIN public.user_profiles p ON p.user_id = pt.user_id
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
      FROM public.doctor_availability
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
        'SELECT user_id FROM public.doctors WHERE id = $1',
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
      `UPDATE public.doctors
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

// GET doctor clinics

router.get(
  "/:id/clinics",
  async (req, res, next) => {

    try {

      const result = await db.query(
        `
        SELECT

        c.id,
        c.name_ar,
        c.name_en,
        c.address_ar,
        c.address_en,
        c.city,
        c.phone,

        dca.is_primary,
        dca.consultation_fee_override

        FROM public.doctor_clinic_assignments dca

        JOIN public.clinics c

        ON c.id=dca.clinic_id

        WHERE dca.doctor_id=$1

        AND dca.is_active=true

        AND c.is_active=true

        `,
        [
          req.params.id
        ]
      );


      return success(
        res,
        result.rows,
        "Doctor clinics retrieved"
      );


    }
    catch (err) {

      next(err);

    }

  });

module.exports = router;