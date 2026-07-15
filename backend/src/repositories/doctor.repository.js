const db = require('../config/database');

/**
 * Doctor Repository
 * All SQL queries related to doctors, their specialties, availability, and reviews.
 */
class DoctorRepository {

    // ==================== LIST WITH FILTERS ====================

    async findAll({ specialty, region, minRating, search, page = 1, limit = 10 }) {
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

        // Count
        const countResult = await db.query(
            `SELECT COUNT(*) FROM (${query}) as count_query`,
            params
        );
        const total = parseInt(countResult.rows[0].count);

        query += ` ORDER BY d.average_rating DESC, d.total_ratings DESC`;
        query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
        params.push(parseInt(limit), (parseInt(page) - 1) * parseInt(limit));

        const result = await db.query(query, params);

        return {
            doctors: result.rows,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        };
    }

    // ==================== BY ID ====================

    async findById(id) {
        const result = await db.query(
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
        return result.rows[0] || null;
    }

    async findByUserId(userId) {
        const result = await db.query(
            'SELECT user_id FROM medorbit.doctors WHERE id = $1',
            [userId]
        );
        return result.rows[0] || null;
    }

    // ==================== UPDATE ====================

    async update(id, fields) {
        const {
            yearsOfExperience, consultationFee, consultationDuration,
            education, certifications, professionalBioAr, professionalBioEn,
            isAcceptingPatients, specialtyId
        } = fields;

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
    }

    // ==================== CLINICS ====================

    async findClinicsByDoctorId(doctorId) {
        const result = await db.query(
            `SELECT 
                c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
                c.city, c.region, c.latitude, c.longitude, c.phone,
                dca.consultation_fee_override, dca.is_primary
            FROM medorbit.doctor_clinic_assignments dca
            JOIN medorbit.clinics c ON c.id = dca.clinic_id
            WHERE dca.doctor_id = $1 AND dca.is_active = true AND c.is_active = true`,
            [doctorId]
        );
        return result.rows;
    }

    // ==================== AVAILABILITY ====================

    async findAvailability(doctorId, date) {
        let query = `
            SELECT 
                id, clinic_id, day_of_week, specific_date,
                start_time, end_time, slot_duration, is_telemedicine
            FROM medorbit.doctor_availability
            WHERE doctor_id = $1 AND is_active = true
        `;

        const params = [doctorId];

        if (date) {
            query += ` AND (specific_date = $2 OR (specific_date IS NULL AND day_of_week = EXTRACT(DOW FROM $2::date)))`;
            params.push(date);
        }

        query += ` ORDER BY day_of_week, start_time`;

        const result = await db.query(query, params);
        return result.rows;
    }

    // ==================== REVIEWS ====================

    async findReviewsByDoctorId(doctorId, limit = 10) {
        const result = await db.query(
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
            LIMIT $2`,
            [doctorId, limit]
        );
        return result.rows;
    }

    // ==================== SPECIALTIES ====================

    async findSpecialtyByName(name) {
        const result = await db.query(
            `SELECT id, name_ar, name_en, description_ar, description_en
             FROM medorbit.specialties
             WHERE is_active = true AND (name_en ILIKE $1 OR name_ar ILIKE $1)
             LIMIT 1`,
            [`%${name}%`]
        );
        return result.rows[0] || null;
    }

    async findAllSpecialties() {
        const result = await db.query(
            `SELECT id, name_ar, name_en, description_ar, description_en, icon
             FROM medorbit.specialties
             WHERE is_active = true
             ORDER BY name_en`
        );
        return result.rows;
    }

    // ==================== FIND DOCTORS BY SPECIALTY ====================

    async findBySpecialty(specialtyName, { limit = 10, page = 1 }) {
        let query = `
            SELECT 
                d.id, d.average_rating, d.consultation_fee, d.years_of_experience,
                d.is_accepting_patients,
                p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
                p.profile_image_url,
                s.name_ar as specialty_ar, s.name_en as specialty_en
            FROM medorbit.doctors d
            JOIN medorbit.users u ON u.id = d.user_id
            LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
            JOIN medorbit.specialties s ON s.id = d.specialty_id
            WHERE u.is_active = true AND u.deleted_at IS NULL
              AND d.is_accepting_patients = true
              AND (s.name_en ILIKE $1 OR s.name_ar ILIKE $1)
            ORDER BY d.average_rating DESC
            LIMIT $2 OFFSET $3
        `;

        const result = await db.query(query, [`%${specialtyName}%`, limit, (page - 1) * limit]);
        return result.rows;
    }
}

module.exports = new DoctorRepository();