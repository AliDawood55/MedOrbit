const db = require('../config/database');
const { hasActiveCareRelationship } = require('./careRelationship.service');

async function resolvePatientForUser(userId, queryable = db) {
    const result = await queryable.query(
        'SELECT id FROM medorbit.patients WHERE user_id=$1',
        [userId]
    );
    return result.rows[0] || null;
}

async function resolveDoctorForUser(userId, queryable = db) {
    const result = await queryable.query(
        'SELECT id FROM medorbit.doctors WHERE user_id=$1',
        [userId]
    );
    return result.rows[0] || null;
}

async function findAuthorizedMedicalRecord(recordId, user, { mutation = false } = {}, queryable = db) {
    if (user.role === 'patient') {
        if (mutation) return null;
        const patient = await resolvePatientForUser(user.sub, queryable);
        if (!patient) return null;
        const result = await queryable.query(
            `SELECT * FROM medorbit.medical_records
             WHERE id=$1 AND patient_id=$2 AND is_draft=false`,
            [recordId, patient.id]
        );
        return result.rows[0] || null;
    }

    if (user.role === 'doctor') {
        const doctor = await resolveDoctorForUser(user.sub, queryable);
        if (!doctor) return null;
        const result = await queryable.query(
            mutation
                ? `SELECT * FROM medorbit.medical_records
                   WHERE id=$1 AND doctor_id=$2`
                : `SELECT mr.*
                   FROM medorbit.medical_records mr
                   WHERE mr.id=$1
                     AND (
                       mr.doctor_id=$2 OR EXISTS (
                         SELECT 1 FROM medorbit.doctor_patient_relationships r
                         WHERE r.doctor_id=$2 AND r.patient_id=mr.patient_id
                           AND r.status='active'
                       )
                     )`,
            [recordId, doctor.id]
        );
        return result.rows[0] || null;
    }

    return null;
}

async function findAuthorizedPrescription(prescriptionId, user, queryable = db) {
    if (user.role === 'patient') {
        const patient = await resolvePatientForUser(user.sub, queryable);
        if (!patient) return null;
        const result = await queryable.query(
            'SELECT * FROM medorbit.prescriptions WHERE id=$1 AND patient_id=$2',
            [prescriptionId, patient.id]
        );
        return result.rows[0] || null;
    }

    if (user.role === 'doctor') {
        const doctor = await resolveDoctorForUser(user.sub, queryable);
        if (!doctor) return null;
        const result = await queryable.query(
            `SELECT p.*
             FROM medorbit.prescriptions p
             WHERE p.id=$1
               AND (
                 p.doctor_id=$2 OR EXISTS (
                   SELECT 1 FROM medorbit.doctor_patient_relationships r
                   WHERE r.doctor_id=$2 AND r.patient_id=p.patient_id
                     AND r.status='active'
                 )
               )`,
            [prescriptionId, doctor.id]
        );
        return result.rows[0] || null;
    }

    return null;
}

async function findAssignedAppointment(appointmentId, userId, queryable = db) {
    const doctor = await resolveDoctorForUser(userId, queryable);
    if (!doctor) return null;
    const result = await queryable.query(
        `SELECT * FROM medorbit.appointments
         WHERE id=$1 AND doctor_id=$2`,
        [appointmentId, doctor.id]
    );
    return result.rows[0] || null;
}

module.exports = {
    resolvePatientForUser,
    resolveDoctorForUser,
    hasActiveCareRelationship,
    findAuthorizedMedicalRecord,
    findAuthorizedPrescription,
    findAssignedAppointment,
};
