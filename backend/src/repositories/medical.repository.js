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

    // Doctor name joined the same way findReviewsByDoctorId already does it
    // in this file (doctors -> user_profiles via user_id). clinical_notes/
    // doctor_notes are deliberately excluded because they are doctor-internal;
    // diagnosis/chief_complaint/treatment_plan are patient-facing only after
    // publication (is_draft=false).
    async findRecordsByPatientId(patientId, { limit = 10, offset = 0 }) {
        const result = await db.query(
            `SELECT
                 mr.id, mr.record_number, mr.record_type, mr.chief_complaint,
                 mr.diagnosis, mr.treatment_plan, mr.vitals, mr.created_at,
                 up.first_name_ar AS doctor_first_name_ar, up.first_name_en AS doctor_first_name_en,
                 up.last_name_ar AS doctor_last_name_ar, up.last_name_en AS doctor_last_name_en
             FROM medorbit.medical_records mr
             LEFT JOIN medorbit.doctors d ON d.id = mr.doctor_id
             LEFT JOIN medorbit.user_profiles up ON up.user_id = d.user_id
             WHERE mr.patient_id = $1 AND mr.is_draft = false
             ORDER BY mr.created_at DESC
             LIMIT $2 OFFSET $3`,
            [patientId, limit, offset]
        );
        return result.rows;
    }

    // Single-record fetch for a patient's own "my records" detail view.
    // Same column subset and is_draft filter as findRecordsByPatientId, PLUS
    // the patient_id match in the WHERE clause itself is the ownership
    // check: a record that exists but belongs to someone else returns no
    // row here, same as "not found", rather than ever being fetched and then
    // checked.
    async findRecordByIdForPatient(id, patientId) {
        const result = await db.query(
            `SELECT
                 mr.id, mr.record_number, mr.record_type, mr.chief_complaint,
                 mr.diagnosis, mr.treatment_plan, mr.vitals, mr.created_at,
                 up.first_name_ar AS doctor_first_name_ar, up.first_name_en AS doctor_first_name_en,
                 up.last_name_ar AS doctor_last_name_ar, up.last_name_en AS doctor_last_name_en
             FROM medorbit.medical_records mr
             LEFT JOIN medorbit.doctors d ON d.id = mr.doctor_id
             LEFT JOIN medorbit.user_profiles up ON up.user_id = d.user_id
             WHERE mr.id = $1 AND mr.patient_id = $2 AND mr.is_draft = false`,
            [id, patientId]
        );
        return result.rows[0] || null;
    }

    // ==================== APPOINTMENTS (patient-facing) ====================

    // Doctor name + specialty joined the same way findReviewsByDoctorId does
    // it in this file. Used only by the combined "my records" timeline
    // (GET /api/patients/me/records) — the plain GET /appointments route
    // returns raw rows without this join and stays as-is for its own callers.
    async findAppointmentsByPatientId(patientId, { limit = 20, offset = 0 } = {}) {
        const result = await db.query(
            `SELECT
                 a.id, a.appointment_number, a.scheduled_date, a.start_time, a.status,
                 a.appointment_type, a.reason_for_visit,
                 up.first_name_ar AS doctor_first_name_ar, up.first_name_en AS doctor_first_name_en,
                 up.last_name_ar AS doctor_last_name_ar, up.last_name_en AS doctor_last_name_en,
                 s.name_ar AS specialty_ar, s.name_en AS specialty_en
             FROM medorbit.appointments a
             LEFT JOIN medorbit.doctors d ON d.id = a.doctor_id
             LEFT JOIN medorbit.user_profiles up ON up.user_id = d.user_id
             LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
             WHERE a.patient_id = $1
             ORDER BY a.scheduled_date DESC, a.start_time DESC
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
