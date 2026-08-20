const db = require('../config/database');
const { createAudit } = require('./audit.service');
const { enqueueOutboxEvent } = require('./outbox.service');

const QUALIFYING_APPOINTMENT_STATUSES = Object.freeze([
    'scheduled', 'confirmed', 'in_progress', 'completed',
]);

async function hasActiveCareRelationship(doctorId, patientId, queryable = db) {
    const result = await queryable.query(
        `SELECT 1 FROM medorbit.doctor_patient_relationships
         WHERE doctor_id=$1 AND patient_id=$2 AND status='active'
         LIMIT 1`,
        [doctorId, patientId]
    );
    return result.rows.length === 1;
}

async function hasLegacyAppointmentRelationship(doctorId, patientId, queryable = db) {
    const result = await queryable.query(
        `SELECT 1 FROM medorbit.appointments
         WHERE doctor_id=$1 AND patient_id=$2
           AND status=ANY($3::varchar[])
         LIMIT 1`,
        [doctorId, patientId, QUALIFYING_APPOINTMENT_STATUSES]
    );
    return result.rows.length === 1;
}

async function compareLegacyRelationship(doctorId, patientId, queryable = db) {
    const [legacy, current] = await Promise.all([
        hasLegacyAppointmentRelationship(doctorId, patientId, queryable),
        hasActiveCareRelationship(doctorId, patientId, queryable),
    ]);
    return { legacy, current, matches: legacy === current };
}

async function ensureActiveCareRelationship({
    doctorId,
    patientId,
    source = 'appointment',
    sourceReferenceId = null,
    actorUserId = null,
    actorRole = null,
    startedAt = null,
}, queryable = db) {
    const result = await queryable.query(
        `INSERT INTO medorbit.doctor_patient_relationships
           (doctor_id, patient_id, status, source, source_reference_id,
            started_at, created_by_user_id)
         VALUES ($1,$2,'active',$3,$4,COALESCE($5,NOW()),$6)
         ON CONFLICT (doctor_id, patient_id) WHERE status='active'
         DO NOTHING
         RETURNING *`,
        [doctorId, patientId, source, sourceReferenceId, startedAt, actorUserId]
    );

    if (result.rows[0]) {
        await createAudit({
            user_id: actorUserId,
            user_role: actorRole,
            action: 'CARE_RELATIONSHIP_CREATED',
            entity_type: 'CARE_RELATIONSHIP',
            entity_id: result.rows[0].id,
            new_values: {
                doctor_id: doctorId,
                patient_id: patientId,
                source,
                source_reference_id: sourceReferenceId,
            },
        }, queryable);
        await enqueueOutboxEvent(queryable, {
            aggregateType: 'care_relationship', aggregateId: result.rows[0].id,
            eventType: 'care.relationship.created',
            payload: { relationshipId: result.rows[0].id, doctorId, patientId, source, sourceReferenceId },
        });
        return { relationship: result.rows[0], created: true };
    }

    const existing = await queryable.query(
        `SELECT * FROM medorbit.doctor_patient_relationships
         WHERE doctor_id=$1 AND patient_id=$2 AND status='active'`,
        [doctorId, patientId]
    );
    return { relationship: existing.rows[0], created: false };
}

async function closeRelationship({
    relationshipId,
    doctorId = null,
    status,
    actorUserId,
    actorRole,
    reason,
}, queryable = db) {
    if (!['ended', 'revoked'].includes(status)) throw new Error('Invalid relationship close status');
    const params = [relationshipId, status, actorUserId, reason || null];
    let ownership = '';
    if (doctorId) {
        params.push(doctorId);
        ownership = ' AND doctor_id=$5';
    }
    const result = await queryable.query(
        `UPDATE medorbit.doctor_patient_relationships
         SET status=$2, ended_at=NOW(), ended_by_user_id=$3,
             end_reason=$4, updated_at=NOW()
         WHERE id=$1 AND status='active'${ownership}
         RETURNING *`,
        params
    );
    if (!result.rows[0]) return null;
    await createAudit({
        user_id: actorUserId,
        user_role: actorRole,
        action: status === 'revoked' ? 'CARE_RELATIONSHIP_REVOKED' : 'CARE_RELATIONSHIP_ENDED',
        entity_type: 'CARE_RELATIONSHIP',
        entity_id: relationshipId,
        old_values: { status: 'active' },
        new_values: {
            status,
            doctor_id: result.rows[0].doctor_id,
            patient_id: result.rows[0].patient_id,
            reason: reason || null,
        },
    }, queryable);
    return result.rows[0];
}

module.exports = {
    QUALIFYING_APPOINTMENT_STATUSES,
    hasActiveCareRelationship,
    hasLegacyAppointmentRelationship,
    compareLegacyRelationship,
    ensureActiveCareRelationship,
    closeRelationship,
};
