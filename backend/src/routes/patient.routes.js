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
const { hasActiveCareRelationship } = require('../services/careRelationship.service');
const { boundedText } = require('../utils/profileFields');


// Every handler below resolves the caller's own medorbit.patients.id from
// req.user.sub (the JWT subject, a users.id) server-side — never from a
// client-supplied id — same pattern already used correctly in
// appointment.routes.js's POST /. The legacy generic clinical routes now use
// the same server-resolved ownership model rather than trusting resource IDs.
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
// GET /api/patients/me/records
// =======================================
// Combined history timeline for my-records.html — interleaves the patient's
// own appointments, medical records (diagnoses) and prescriptions into one
// date-sorted list. Reuses the same ownership-scoped queries/services the
// dedicated endpoints above and below already use; nothing new is read from
// the DB, this just merges them chronologically for the timeline UI.

router.get(
    "/me/records",
    authenticate,
    authorize("patient"),

    async (req, res, next) => {

        try {

            const patientId = await resolvePatientId(req.user.sub);

            if (!patientId) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }

            const limit = Math.min(Number(req.query.limit) || 50, 200);

            const [appointments, records, prescriptions] = await Promise.all([
                medicalRepository.findAppointmentsByPatientId(patientId, { limit }),
                medicalRepository.findRecordsByPatientId(patientId, { limit }),
                prescriptionService.findByPatientId(patientId, { limit })
            ]);

            const timeline = [
                ...appointments.map((a) => ({ ...a, entry_type: "appointment", entry_date: a.scheduled_date })),
                ...records.map((r) => ({ ...r, entry_type: "record", entry_date: r.created_at })),
                ...prescriptions.map((p) => ({ ...p, entry_type: "prescription", entry_date: p.prescription_date }))
            ].sort((a, b) => new Date(b.entry_date) - new Date(a.entry_date));

            return success(res, { timeline }, "Patient history retrieved");

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
    return hasActiveCareRelationship(doctorId, patientId);
}

// =======================================
// Privacy-safe social patient profile
// =======================================

router.get(
    "/me/profile",
    authenticate,
    authorize("patient"),
    async (req, res, next) => {
        try {
            const result = await db.query(
                `SELECT up.public_profile_id AS id,up.first_name_ar,up.last_name_ar,
                        up.first_name_en,up.last_name_en,up.profile_image_url AS avatar_url,
                        up.social_bio AS bio,up.city,up.allow_doctor_messages,
                        u.preferred_language,u.created_at AS member_since
                 FROM medorbit.users u
                 JOIN medorbit.user_profiles up ON up.user_id=u.id
                 JOIN medorbit.patients p ON p.user_id=u.id
                 WHERE u.id=$1 AND u.role='patient' AND u.is_active=true
                   AND u.deleted_at IS NULL`,
                [req.user.sub]
            );
            if (!result.rows[0]) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }
            return success(res, result.rows[0], "Patient social profile retrieved");
        } catch (err) {
            return next(err);
        }
    }
);

router.put(
    "/me/profile",
    authenticate,
    authorize("patient"),
    async (req, res, next) => {
        try {
            const bio = boundedText(req.body, ['bio', 'social_bio'], 'Bio', 500);
            const city = boundedText(req.body, ['city'], 'City', 80);
            const privacyProvided = Object.prototype.hasOwnProperty.call(req.body, 'allowDoctorMessages')
                || Object.prototype.hasOwnProperty.call(req.body, 'allow_doctor_messages');
            const privacy = req.body.allowDoctorMessages ?? req.body.allow_doctor_messages;
            if (privacyProvided && typeof privacy !== 'boolean') {
                return error(res, 'Privacy preference must be boolean', 400, 'VALIDATION_ERROR');
            }

            const result = await db.query(
                `UPDATE medorbit.user_profiles up
                 SET social_bio=CASE WHEN $1 THEN $2 ELSE social_bio END,
                     city=CASE WHEN $3 THEN $4 ELSE city END,
                     allow_doctor_messages=CASE WHEN $5 THEN $6 ELSE allow_doctor_messages END,
                     updated_at=NOW()
                 FROM medorbit.users u,medorbit.patients p
                 WHERE up.user_id=$7 AND u.id=up.user_id AND p.user_id=u.id
                   AND u.role='patient' AND u.is_active=true AND u.deleted_at IS NULL
                 RETURNING up.public_profile_id AS id,up.first_name_ar,up.last_name_ar,
                           up.first_name_en,up.last_name_en,
                           up.profile_image_url AS avatar_url,up.social_bio AS bio,
                           up.city,up.allow_doctor_messages,u.preferred_language,
                           u.created_at AS member_since`,
                [bio.provided, bio.value, city.provided, city.value,
                    privacyProvided, privacy, req.user.sub]
            );
            if (!result.rows[0]) {
                return error(res, "Patient profile not found", 404, "NOT_FOUND");
            }
            return success(res, result.rows[0], "Patient social profile updated");
        } catch (err) {
            return next(err);
        }
    }
);

// Approved doctors may discover only patients who opted in. The public profile
// UUID is intentionally separate from the clinical patients.id.
router.get(
    "/discover",
    authenticate,
    authorize("doctor"),
    async (req, res, next) => {
        try {
            const search = typeof req.query.search === 'string' ? req.query.search.trim() : '';
            if (search.length > 80) {
                return error(res, 'Search is too long', 400, 'VALIDATION_ERROR');
            }
            const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 30);
            const result = await db.query(
                `SELECT up.public_profile_id AS id,up.first_name_ar,up.last_name_ar,
                        up.first_name_en,up.last_name_en,
                        up.profile_image_url AS avatar_url,up.social_bio AS bio,up.city
                 FROM medorbit.users u
                 JOIN medorbit.user_profiles up ON up.user_id=u.id
                 JOIN medorbit.patients p ON p.user_id=u.id
                 WHERE u.role='patient' AND u.is_active=true AND u.email_verified=true
                   AND u.deleted_at IS NULL AND up.allow_doctor_messages=true
                   AND ($1='' OR up.first_name_ar ILIKE '%'||$1||'%'
                        OR up.last_name_ar ILIKE '%'||$1||'%'
                        OR up.first_name_en ILIKE '%'||$1||'%'
                        OR up.last_name_en ILIKE '%'||$1||'%'
                        OR up.city ILIKE '%'||$1||'%')
                 ORDER BY up.first_name_en,up.last_name_en,up.public_profile_id
                 LIMIT $2`,
                [search, limit]
            );
            return success(res, { items: result.rows, limit }, "Discoverable patient profiles retrieved");
        } catch (err) {
            return next(err);
        }
    }
);


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
                     r.started_at AS relationship_started_at, r.source AS relationship_source,
                     MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) AS next_appointment_date,
                     MAX(a.scheduled_date) FILTER (WHERE a.scheduled_date < CURRENT_DATE OR a.status = 'completed') AS last_appointment_date,
                     COUNT(*) FILTER (WHERE a.scheduled_date >= CURRENT_DATE AND a.status NOT IN ('cancelled', 'no_show')) > 0 AS has_upcoming
                 FROM medorbit.doctors d
                 JOIN medorbit.users u ON u.id = d.user_id
                 LEFT JOIN medorbit.user_profiles pr ON pr.user_id = u.id
                 LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
                 JOIN medorbit.doctor_patient_relationships r
                   ON r.doctor_id=d.id AND r.patient_id=$1 AND r.status='active'
                 LEFT JOIN medorbit.appointments a ON a.doctor_id=d.id AND a.patient_id=$1
                 WHERE u.is_active=true AND u.deleted_at IS NULL
                   AND d.approval_status='approved'
                 GROUP BY d.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
                          pr.phone, pr.profile_image_url, s.name_ar, s.name_en, d.consultation_fee, d.average_rating,
                          r.started_at, r.source
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
