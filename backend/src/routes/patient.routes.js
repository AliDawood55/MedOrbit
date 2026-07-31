const express = require("express");

const router = express.Router();

const db = require("../config/database");

const {
    authenticate,
    authorize
} = require("../middleware/auth");

const {
    success,
    error
} = require("../utils/response");

const medicalRepository = require("../repositories/medical.repository");
const prescriptionService = require("../services/prescription.service");


// Every handler below resolves the caller's own medorbit.patients.id from
// req.user.sub (the JWT subject, a users.id) server-side — never from a
// client-supplied id — same pattern already used correctly in
// appointment.routes.js's POST /. This is what makes these "my X" routes
// safe to add alongside the existing, unscoped GET /medical-records and
// GET /prescriptions/:id (which remain as-is, used by doctor-facing flows
// elsewhere; patients should never call those directly).
async function resolvePatientId(userId) {
    const result = await db.query(
        `SELECT id FROM medorbit.patients WHERE user_id=$1`,
        [userId]
    );
    return result.rows[0]?.id || null;
}


// =======================================
// GET /api/patients/me/medical-records
// =======================================

router.get(
    "/me/medical-records",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }

            const limit = Math.min(Number(req.query.limit) || 20, 100);
            const offset = Number(req.query.offset) || 0;

            const records = await medicalRepository.findRecordsByPatientId(
                patientId,
                { limit, offset }
            );

            return success(res, records, "Medical records retrieved");

        } catch (err) {
            next(err);
        }
    });


// =======================================
// GET /api/patients/me/medical-records/:id
// =======================================

router.get(
    "/me/medical-records/:id",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Record not found", 404, "NOT_FOUND");
            }

            const record = await medicalRepository.findRecordByIdForPatient(
                req.params.id,
                patientId
            );

            if (!record) {
                return error(res, "Record not found", 404, "NOT_FOUND");
            }

            return success(res, record, "Medical record retrieved");

        } catch (err) {
            next(err);
        }
    });


// =======================================
// GET /api/patients/me/prescriptions
// =======================================

router.get(
    "/me/prescriptions",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }

            const limit = Math.min(Number(req.query.limit) || 20, 100);
            const offset = Number(req.query.offset) || 0;

            const prescriptions = await prescriptionService.findByPatientId(
                patientId,
                { limit, offset }
            );

            return success(res, prescriptions, "Prescriptions retrieved");

        } catch (err) {
            next(err);
        }
    });


// =======================================
// GET /api/patients/me/prescriptions/:id
// =======================================

router.get(
    "/me/prescriptions/:id",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Prescription not found", 404, "NOT_FOUND");
            }

            const result = await prescriptionService.findByIdForPatient(
                req.params.id,
                patientId
            );

            if (!result) {
                return error(res, "Prescription not found", 404, "NOT_FOUND");
            }

            return success(res, result, "Prescription retrieved");

        } catch (err) {
            next(err);
        }
    });


// Shared by /me/doctors/:doctorId/notes below — a patient may only read
// shared notes from a doctor they have (or had) at least one appointment
// with, same relationship rule as doctor.routes.js's
// verifyDoctorPatientRelationship (there's no dedicated relationship
// table either direction).
async function verifyPatientDoctorRelationship(patientId, doctorId) {
    const result = await db.query(
        `SELECT 1 FROM medorbit.appointments WHERE patient_id=$1 AND doctor_id=$2 LIMIT 1`,
        [patientId, doctorId]
    );
    return result.rows.length > 0;
}


// =======================================
// GET /api/patients/me/doctors
// =======================================
// Patient-side mirror of doctor.routes.js's GET /me/patients — derived from
// appointment history (no dedicated relationship table).

router.get(
    "/me/doctors",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }

            const result = await db.query(
                `SELECT
                     d.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
                     pr.phone, pr.profile_image_url,
                     s.name_ar AS specialty_ar, s.name_en AS specialty_en,
                     d.consultation_fee, d.average_rating,
                     MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) AS next_appointment_date,
                     MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date < CURRENT_DATE OR a.status = 'completed') AS last_appointment_date,
                     COUNT(*) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) > 0 AS has_upcoming
                 FROM medorbit.doctors d
                 JOIN medorbit.users u ON u.id = d.user_id
                 LEFT JOIN medorbit.user_profiles pr ON pr.user_id = u.id
                 LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
                 JOIN medorbit.appointments a ON a.doctor_id = d.id
                 WHERE a.patient_id = $1
                 GROUP BY d.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
                          pr.phone, pr.profile_image_url, s.name_ar, s.name_en, d.consultation_fee, d.average_rating
                 ORDER BY COALESCE(MAX(a.scheduled_date), '-infinity') DESC`,
                [patientId]
            );

            return success(res, result.rows, "Doctors retrieved");

        } catch (err) {
            next(err);
        }
    });


// =======================================
// GET /api/patients/me/doctors/:doctorId/notes
// =======================================
// "Shared notes" (my-doctor.html) — only rows the doctor explicitly marked
// visible_to_patient=true, and never is_draft=true, never doctor_notes
// (that column stays doctor-internal even for a shared note; see
// medical.repository.js's patient-facing methods for the same convention).
// 404 (not 403) if no appointment relationship exists with this doctor —
// same reasoning as doctor.routes.js's verifyDoctorPatientRelationship.

router.get(
    "/me/doctors/:doctorId/notes",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }

            const { doctorId } = req.params;
            const related = await verifyPatientDoctorRelationship(patientId, doctorId);

            if (!related) {
                return error(res, "Doctor not found", 404, "NOT_FOUND");
            }

            const result = await db.query(
                `SELECT
                     mr.id, mr.record_type, mr.chief_complaint, mr.diagnosis,
                     mr.treatment_plan, mr.clinical_notes, mr.created_at
                 FROM medorbit.medical_records mr
                 WHERE mr.patient_id = $1 AND mr.doctor_id = $2
                   AND mr.visible_to_patient = true AND mr.is_draft = false
                 ORDER BY mr.created_at DESC`,
                [patientId, doctorId]
            );

            return success(res, result.rows, "Shared notes retrieved");

        } catch (err) {
            next(err);
        }
    });


module.exports = router;
