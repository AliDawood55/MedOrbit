const express = require('express');

const db = require('../config/database');
const { authenticate, authorize } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const { findAssignedAppointment } = require('../services/clinicalAuthorization.service');
const { ensureActiveCareRelationship } = require('../services/careRelationship.service');
const { notifyAppointmentTransition } = require('../services/notification.service');
const scheduling = require('../services/scheduling.service');

const router = express.Router();

// Historical meeting_link values remain in PostgreSQL for record integrity,
// but human calling is no longer an active client capability.
function appointmentDto(row) {
    if (!row) return row;
    const { meeting_link: _historicalMeetingLink, ...safe } = row;
    return safe;
}

// Server-generated bookable slots. The array shape remains compatible with
// existing web/mobile clients, but each row is now one exact slot after
// weekly rules, date overrides, blocks, past time, and bookings are removed.
// Availability is account-only, not patient-only: patients use it to book and
// doctors use the same generated view to verify their published schedules.
// Booking itself remains restricted to patients below.
router.get('/available-slots', authenticate, async (req, res, next) => {
    try {
        const { doctor_id, clinic_id, date } = req.query;
        if (!doctor_id || !date) {
            return error(res, 'doctor_id and date are required', 400, 'VALIDATION_ERROR');
        }
        const slots = await scheduling.listBookableSlots({ doctorId: doctor_id, clinicId: clinic_id, date });
        return success(res, slots, 'Available slots retrieved');
    } catch (err) {
        return next(err);
    }
});

// Booking is revalidated inside a serialized transaction. Client-supplied
// duration/end/type must exactly match a currently generated server slot.
router.post('/', authenticate, authorize('patient'), async (req, res, next) => {
    try {
        const appointment = await scheduling.bookAppointment(req.user.sub, req.body);
        return success(res, appointmentDto(appointment), 'Appointment booked', 201);
    } catch (err) {
        return next(err);
    }
});

// Patient appointment history. Doctor schedule views use
// GET /api/doctors/me/schedule and receive only appropriate patient identity.
router.get('/', authenticate, authorize('patient'), async (req, res, next) => {
    try {
        const patient = await db.query(
            'SELECT id FROM medorbit.patients WHERE user_id=$1',
            [req.user.sub]
        );
        if (!patient.rows[0]) return error(res, 'Patient profile not found', 404, 'NOT_FOUND');
        const result = await db.query(
            `SELECT * FROM medorbit.appointments
             WHERE patient_id=$1
             ORDER BY scheduled_date DESC,start_time DESC,id DESC`,
            [patient.rows[0].id]
        );
        return success(res, result.rows.map(appointmentDto), 'Appointments retrieved');
    } catch (err) {
        return next(err);
    }
});

router.get('/:id', authenticate, authorize('patient'), async (req, res, next) => {
    try {
        const patient = await db.query(
            'SELECT id FROM medorbit.patients WHERE user_id=$1',
            [req.user.sub]
        );
        if (!patient.rows[0]) return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        const result = await db.query(
            'SELECT * FROM medorbit.appointments WHERE id=$1 AND patient_id=$2',
            [req.params.id, patient.rows[0].id]
        );
        if (!result.rows[0]) return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        return success(res, appointmentDto(result.rows[0]), 'Appointment retrieved');
    } catch (err) {
        return next(err);
    }
});

router.put('/:id/cancel', authenticate, async (req, res, next) => {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const reason = req.body?.reason == null ? null : String(req.body.reason).trim().slice(0, 1000);
        let result;
        let transition;
        if (req.user.role === 'patient') {
            const patient = await client.query(
                'SELECT id FROM medorbit.patients WHERE user_id=$1',
                [req.user.sub]
            );
            if (patient.rows[0]) {
                result = await client.query(
                    `UPDATE medorbit.appointments
                     SET status='cancelled',cancelled_at=NOW(),cancelled_by=$3,
                         cancellation_reason=$4,updated_at=NOW()
                     WHERE id=$1 AND patient_id=$2 AND status IN ('scheduled','confirmed')
                     RETURNING *`,
                    [req.params.id, patient.rows[0].id, req.user.sub, reason]
                );
                transition = 'cancelled_by_patient';
            }
        } else if (req.user.role === 'doctor') {
            const appointment = await findAssignedAppointment(req.params.id, req.user.sub, client);
            if (appointment) {
                result = await client.query(
                    `UPDATE medorbit.appointments
                     SET status='cancelled',cancelled_at=NOW(),cancelled_by=$3,
                         cancellation_reason=$4,updated_at=NOW()
                     WHERE id=$1 AND doctor_id=$2 AND status IN ('scheduled','confirmed')
                     RETURNING *`,
                    [req.params.id, appointment.doctor_id, req.user.sub, reason]
                );
                transition = 'cancelled_by_doctor';
            }
        } else {
            await client.query('ROLLBACK');
            return error(res, 'Only appointment participants may cancel appointments', 403, 'FORBIDDEN');
        }
        if (!result?.rows[0]) {
            await client.query('ROLLBACK');
            return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        }
        await client.query(
            `INSERT INTO medorbit.appointment_status_history
               (appointment_id,new_status,changed_by)
             VALUES($1,'cancelled',$2)`,
            [req.params.id, req.user.sub]
        );
        await notifyAppointmentTransition(client, req.params.id, transition);
        await client.query('COMMIT');
        return success(res, appointmentDto(result.rows[0]), 'Appointment cancelled');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => { });
        return next(err);
    } finally {
        client.release();
    }
});

async function updateDoctorAppointmentStatus(req, res, next, targetStatus, allowedStatuses) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const appointment = await findAssignedAppointment(req.params.id, req.user.sub, client);
        if (!appointment) {
            await client.query('ROLLBACK');
            return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        }
        const result = await client.query(
            `UPDATE medorbit.appointments
             SET status=$1,updated_at=NOW()
             WHERE id=$2 AND doctor_id=$3 AND status=ANY($4::varchar[])
             RETURNING *`,
            [targetStatus, req.params.id, appointment.doctor_id, allowedStatuses]
        );
        if (!result.rows[0]) {
            await client.query('ROLLBACK');
            return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        }
        await client.query(
            `INSERT INTO medorbit.appointment_status_history
               (appointment_id,new_status,changed_by)
             VALUES($1,$2,$3)`,
            [req.params.id, targetStatus, req.user.sub]
        );
        if (targetStatus === 'confirmed') {
            await notifyAppointmentTransition(client, req.params.id, 'confirmed');
        }
        await ensureActiveCareRelationship({
            doctorId: appointment.doctor_id,
            patientId: appointment.patient_id,
            source: appointment.appointment_type === 'telemedicine' ? 'telemedicine' : 'appointment',
            sourceReferenceId: appointment.id,
            actorUserId: req.user.sub,
            actorRole: req.user.role,
        }, client);
        await client.query('COMMIT');
        return success(res, appointmentDto(result.rows[0]), `Appointment ${targetStatus}`);
    } catch (err) {
        await client.query('ROLLBACK').catch(() => { });
        return next(err);
    } finally {
        client.release();
    }
}

router.put('/:id/confirm', authenticate, authorize('doctor'), (req, res, next) => (
    updateDoctorAppointmentStatus(req, res, next, 'confirmed', ['scheduled', 'confirmed'])
));

router.put('/:id/complete', authenticate, authorize('doctor'), (req, res, next) => (
    updateDoctorAppointmentStatus(req, res, next, 'completed', ['confirmed', 'in_progress', 'completed'])
));

module.exports = router;
