const db = require('../config/database');

/**
 * Medical Repository
 * Queries for medications, medical records, and healthcare-related data.
 */
class MedicalRepository {

    // ==================== MEDICATIONS ====================

    async findMedicationByName(name) {
        const result = await db.query(
            `SELECT id, name_ar, name_en, generic_name, drug_class, 
                    active_ingredients, contraindications, side_effects, known_interactions
             FROM medorbit.medications
             WHERE is_active = true
               AND (name_en ILIKE $1 OR name_ar ILIKE $1 OR generic_name ILIKE $1)
             LIMIT 1`,
            [`%${name}%`]
        );
        return result.rows[0] || null;
    }

    async findMedicationsByNames(names) {
        const result = await db.query(
            `SELECT id, name_en, known_interactions
             FROM medorbit.medications
             WHERE LOWER(name_en) = ANY($1)`,
            [names.map(n => n.toLowerCase())]
        );
        return result.rows;
    }

    async searchMedications(searchTerm, limit = 10) {
        const result = await db.query(
            `SELECT id, name_ar, name_en, generic_name, drug_class
             FROM medorbit.medications
             WHERE is_active = true
               AND (name_en ILIKE $1 OR name_ar ILIKE $1 OR generic_name ILIKE $1)
             LIMIT $2`,
            [`%${searchTerm}%`, limit]
        );
        return result.rows;
    }

    // ==================== MEDICAL RECORDS ====================

    async findLatestRecordByPatientId(patientId) {
        const result = await db.query(
            `SELECT diagnosis, symptoms, treatment_plan, created_at
             FROM medorbit.medical_records
             WHERE patient_id = $1
             ORDER BY created_at DESC
             LIMIT 1`,
            [patientId]
        );
        return result.rows[0] || null;
    }

    async findRecordsByPatientId(patientId, { limit = 10, offset = 0 }) {
        const result = await db.query(
            `SELECT id, record_number, record_type, chief_complaint, diagnosis,
                    treatment_plan, vitals, created_at
             FROM medorbit.medical_records
             WHERE patient_id = $1 AND is_draft = false
             ORDER BY created_at DESC
             LIMIT $2 OFFSET $3`,
            [patientId, limit, offset]
        );
        return result.rows;
    }

    // ==================== DOCTOR REVIEWS ====================

    async findReviewsByDoctorId(doctorId, limit = 10) {
        const result = await db.query(
            `SELECT r.id, r.rating, r.review_text_ar, r.review_text_en,
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

    async findAllSpecialties() {
        const result = await db.query(
            `SELECT id, name_ar, name_en, description_ar, description_en, icon
             FROM medorbit.specialties
             WHERE is_active = true
             ORDER BY name_en`
        );
        return result.rows;
    }

    async findSpecialtyById(id) {
        const result = await db.query(
            `SELECT id, name_ar, name_en, description_ar, description_en, icon
             FROM medorbit.specialties
             WHERE id = $1 AND is_active = true`,
            [id]
        );
        return result.rows[0] || null;
    }
}

module.exports = new MedicalRepository();