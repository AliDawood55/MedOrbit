const express = require('express');

const router = express.Router();
const db = require('../config/database');
const { authenticate, authorize } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const { generatePrescriptionPDF } = require('../services/prescription.service');
const { createAudit } = require('../services/audit.service');
const medicalService = require('../services/chatbot/medical.service');
const {
    resolveDoctorForUser,
    hasActiveCareRelationship,
    findAuthorizedPrescription,
} = require('../services/clinicalAuthorization.service');

async function loadPrescriptionItems(prescriptionId, queryable = db) {
    const result = await queryable.query(
        `SELECT id, prescription_id, medication_name_ar, medication_name_en,
                dosage, frequency, duration, quantity, instructions,
                refills_allowed, refills_used, is_active, created_at
         FROM medorbit.prescription_items
         WHERE prescription_id=$1`,
        [prescriptionId]
    );
    return result.rows;
}

async function requirePrescriptionRead(req, res, next) {
    try {
        const prescription = await findAuthorizedPrescription(req.params.id, req.user);
        if (!prescription) return error(res, 'Prescription not found', 404, 'NOT_FOUND');
        req.prescription = prescription;
        return next();
    } catch (err) {
        return next(err);
    }
}

router.post('/', authenticate, authorize('doctor'), async (req, res, next) => {
    let client;
    try {
        client = await db.getClient();
        const {
            patient_id,
            appointment_id,
            valid_until,
            diagnosis,
            instructions,
            doctor_notes,
            items,
        } = req.body;

        if (!appointment_id || !patient_id || !Array.isArray(items) || items.length === 0) {
            return error(res, 'appointment_id, patient_id and items are required', 400, 'VALIDATION_ERROR');
        }

        // Advisory only: AI must not block, edit, or silently replace a
        // clinician's prescription.  An outage is reported explicitly in the
        // response after the prescription has been saved.
        const safetyCheck = await medicalService.checkPrescriptionInteractions(items, req.user.sub);

        await client.query('BEGIN');
        const doctor = await resolveDoctorForUser(req.user.sub, client);
        if (!doctor) {
            await client.query('ROLLBACK');
            return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        }

        const appointment = await client.query(
            `SELECT id FROM medorbit.appointments
             WHERE id=$1 AND doctor_id=$2 AND patient_id=$3`,
            [appointment_id, doctor.id, patient_id]
        );
        if (!appointment.rows.length) {
            await client.query('ROLLBACK');
            return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        }
        if (!await hasActiveCareRelationship(doctor.id, patient_id, client)) {
            await client.query('ROLLBACK');
            return error(res, 'Patient not found', 404, 'NOT_FOUND');
        }

        const result = await client.query(
            `INSERT INTO medorbit.prescriptions
               (prescription_number, patient_id, doctor_id, appointment_id,
                prescription_date, valid_until, status, diagnosis, instructions, doctor_notes)
             VALUES ('RX-'||floor(random()*1000000)::text,$1,$2,$3,CURRENT_DATE,$4,'active',$5,$6,$7)
             RETURNING *`,
            [patient_id, doctor.id, appointment_id, valid_until, diagnosis, instructions, doctor_notes]
        );
        const prescription = result.rows[0];

        for (const item of items) {
            await client.query(
                `INSERT INTO medorbit.prescription_items
                   (prescription_id, medication_name_ar, medication_name_en,
                    dosage, frequency, duration, quantity, instructions)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
                [prescription.id, item.medication_name_ar, item.medication_name_en,
                    item.dosage, item.frequency, item.duration, item.quantity, item.instructions]
            );
        }

        await createAudit({ user_id: req.user.sub, user_role: req.user.role, action: 'PRESCRIPTION_CREATED', entity_type: 'PRESCRIPTION', entity_id: prescription.id, new_values: { id: prescription.id, patient_id: prescription.patient_id, doctor_id: prescription.doctor_id, appointment_id: prescription.appointment_id, status: prescription.status, item_count: items.length } }, client);
        if (safetyCheck.status === 'warning') {
            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'PRESCRIPTION_SAFETY_WARNING_REPORTED',
                entity_type: 'PRESCRIPTION',
                entity_id: prescription.id,
                // Keep the audit useful without duplicating medication names,
                // interaction prose, or other clinical content into audit logs.
                new_values: {
                    prescription_safe: safetyCheck.prescription_safe,
                    warning_count: safetyCheck.warnings.length,
                    interaction_count: safetyCheck.interactions.length,
                },
            }, client);
        }

        await client.query('COMMIT');
        return success(res, { ...prescription, safety_check: safetyCheck }, 'Prescription created', 201);
    } catch (err) {
        if (client) await client.query('ROLLBACK').catch(() => {});
        return next(err);
    } finally {
        client?.release();
    }
});

router.get('/:id', authenticate, requirePrescriptionRead, async (req, res, next) => {
    try {
        const items = await loadPrescriptionItems(req.params.id);
        return success(res, { prescription: req.prescription, items }, 'Prescription retrieved');
    } catch (err) {
        return next(err);
    }
});

router.get('/:id/pdf', authenticate, requirePrescriptionRead, async (req, res, next) => {
    try {
        const items = await loadPrescriptionItems(req.params.id);
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', 'attachment; filename=prescription.pdf');
        const pdf = generatePrescriptionPDF(req.prescription, items);
        return pdf.pipe(res);
    } catch (err) {
        return next(err);
    }
});

module.exports = router;
