const express = require('express');
const db = require('../config/database');
const { success, error } = require('../utils/response');

const router = express.Router();

// Known facility types — invalid values are ignored rather than erroring.
const VALID_CLINIC_TYPES = new Set([
  'clinic', 'pharmacy', 'hospital', 'laboratory', 'dental', 'radiology', 'emergency'
]);

// GET /api/clinics - List clinics with filters
router.get('/', async (req, res, next) => {
  try {
    const { region, service, insurance, search, type, page = 1, limit = 10 } = req.query;

    let query = `
      SELECT
        c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
        c.city, c.region, c.latitude, c.longitude, c.phone, c.email,
        c.website, c.operating_hours, c.services, c.insurance_accepted,
        c.type, c.logo_url, c.is_active, c.verification_status
      FROM medorbit.clinics c
      WHERE c.is_active = true
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

// GET /api/clinics/nearby - Find nearby clinics
router.get('/nearby', async (req, res, next) => {
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
      WHERE c.is_active = true
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
router.get('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;

    const clinicResult = await db.query(
      `SELECT * FROM medorbit.clinics WHERE id = $1 AND is_active = true`,
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

module.exports = router;