const db = require('../config/database');

class MessagingPolicyError extends Error {
    constructor(message, status = 403, code = 'MESSAGING_FORBIDDEN') {
        super(message);
        this.status = status;
        this.code = code;
    }
}

async function resolveMessagingActor(userId, role, queryable = db) {
    if (role === 'patient') {
        const result = await queryable.query(
            `SELECT p.id AS patient_id,u.id AS user_id,u.role
             FROM medorbit.users u
             JOIN medorbit.patients p ON p.user_id=u.id
             WHERE u.id=$1 AND u.role='patient' AND u.is_active=true
               AND u.email_verified=true AND u.deleted_at IS NULL`,
            [userId]
        );
        if (result.rows[0]) return { ...result.rows[0], kind: 'patient' };
    }

    if (role === 'doctor') {
        const result = await queryable.query(
            `SELECT d.id AS doctor_id,u.id AS user_id,u.role
             FROM medorbit.users u
             JOIN medorbit.doctors d ON d.user_id=u.id
             WHERE u.id=$1 AND u.role='doctor' AND u.is_active=true
               AND u.email_verified=true AND u.deleted_at IS NULL
               AND d.approval_status='approved'`,
            [userId]
        );
        if (result.rows[0]) return { ...result.rows[0], kind: 'doctor' };
    }

    if (role === 'clinic') {
        const result = await queryable.query(
            `SELECT c.id AS clinic_id,u.id AS user_id,u.role
             FROM medorbit.users u
             JOIN medorbit.clinics c ON c.owner_user_id=u.id
             WHERE u.id=$1 AND u.role='clinic' AND u.is_active=true
               AND u.email_verified=true AND u.deleted_at IS NULL
               AND c.is_active=true AND c.approval_status='approved'`,
            [userId]
        );
        if (result.rows[0]) return { ...result.rows[0], kind: 'clinic' };
    }

    throw new MessagingPolicyError('Messaging is available only to eligible patients, approved doctors, and verified clinics');
}

async function resolveCounterpart(actor, counterpartId, queryable = db) {
    if (actor.kind === 'patient') {
        const result = await queryable.query(
            `SELECT d.id AS doctor_id,u.id AS user_id,'doctor'::text AS kind
             FROM medorbit.doctors d
             JOIN medorbit.users u ON u.id=d.user_id
             WHERE d.id=$1 AND u.role='doctor' AND u.is_active=true
               AND u.email_verified=true AND u.deleted_at IS NULL
               AND d.approval_status='approved'`,
            [counterpartId]
        );
        if (result.rows[0]) return result.rows[0];
        const clinic = await queryable.query(
            `SELECT c.id AS clinic_id,u.id AS user_id,'clinic'::text AS kind
             FROM medorbit.clinics c JOIN medorbit.users u ON u.id=c.owner_user_id
             WHERE c.id=$1 AND c.is_active=true AND c.approval_status='approved'
               AND u.is_active=true AND u.email_verified=true AND u.deleted_at IS NULL`,
            [counterpartId]
        );
        if (clinic.rows[0]) return clinic.rows[0];
        throw new MessagingPolicyError('Eligible doctor not found', 404, 'NOT_FOUND');
    }

    const doctor = await queryable.query(
        `SELECT d.id AS doctor_id,u.id AS user_id,'doctor'::text AS kind
         FROM medorbit.doctors d
         JOIN medorbit.users u ON u.id=d.user_id
         WHERE d.id=$1 AND u.id<>$2 AND u.role='doctor' AND u.is_active=true
           AND u.email_verified=true AND u.deleted_at IS NULL
           AND d.approval_status='approved'`,
        [counterpartId, actor.user_id]
    );
    if (doctor.rows[0]) return doctor.rows[0];

    const patient = await queryable.query(
        `SELECT p.id AS patient_id,u.id AS user_id,'patient'::text AS kind,
                up.allow_doctor_messages
         FROM medorbit.patients p
         JOIN medorbit.users u ON u.id=p.user_id
         JOIN medorbit.user_profiles up ON up.user_id=u.id
         WHERE (p.id=$1 OR up.public_profile_id=$1)
           AND u.role='patient' AND u.is_active=true
           AND u.email_verified=true AND u.deleted_at IS NULL`,
        [counterpartId]
    );
    if (patient.rows[0]) return patient.rows[0];

    const clinic = await queryable.query(
        `SELECT c.id AS clinic_id,u.id AS user_id,'clinic'::text AS kind
         FROM medorbit.clinics c JOIN medorbit.users u ON u.id=c.owner_user_id
         WHERE c.id=$1 AND u.id<>$2 AND c.is_active=true AND c.approval_status='approved'
           AND u.is_active=true AND u.email_verified=true AND u.deleted_at IS NULL`,
        [counterpartId, actor.user_id]
    );
    if (clinic.rows[0]) return clinic.rows[0];

    throw new MessagingPolicyError('Eligible recipient not found', 404, 'NOT_FOUND');
}

async function findActiveRelationship(actor, counterpart, queryable = db) {
    if (actor.kind === 'clinic' || counterpart.kind === 'clinic') return null;
    if (actor.kind === counterpart.kind) return null;
    const doctorId = actor.kind === 'doctor' ? actor.doctor_id : counterpart.doctor_id;
    const patientId = actor.kind === 'patient' ? actor.patient_id : counterpart.patient_id;
    const result = await queryable.query(
        `SELECT id FROM medorbit.doctor_patient_relationships
         WHERE doctor_id=$1 AND patient_id=$2 AND status='active'
         ORDER BY started_at DESC,id DESC LIMIT 1`,
        [doctorId, patientId]
    );
    return result.rows[0] || null;
}

async function findEligibleRelationship(actor, counterpartId, queryable = db) {
    const counterpart = await resolveCounterpart(actor, counterpartId, queryable);
    const relationship = await findActiveRelationship(actor, counterpart, queryable);
    if (!relationship) {
        throw new MessagingPolicyError('Eligible care relationship not found', 404, 'NOT_FOUND');
    }
    return {
        ...relationship,
        doctor_user_id: actor.kind === 'doctor' ? actor.user_id : counterpart.user_id,
        patient_user_id: actor.kind === 'patient' ? actor.user_id : counterpart.user_id,
    };
}

async function getConversationAccess(
    conversationId,
    userId,
    { requireActiveEligibility = false } = {},
    queryable = db
) {
    const result = await queryable.query(
        `SELECT c.id,c.status,c.relationship_id,c.conversation_type,
                c.initiated_by_user_id,c.request_status,c.declined_at,
                m.member_role,m.left_at,
                NOT EXISTS (
                  SELECT 1
                  FROM medorbit.conversation_members cm
                  JOIN medorbit.users cu ON cu.id=cm.user_id
                  LEFT JOIN medorbit.doctors cd
                    ON cd.user_id=cu.id AND cm.member_role='doctor'
                  LEFT JOIN medorbit.clinics cc
                    ON cc.owner_user_id=cu.id AND cm.member_role='clinic'
                  WHERE cm.conversation_id=c.id AND cm.left_at IS NULL
                    AND (cu.is_active=false OR cu.deleted_at IS NOT NULL
                         OR (cm.member_role='doctor' AND
                             (cu.role<>'doctor' OR cd.approval_status IS DISTINCT FROM 'approved'))
                         OR (cm.member_role='clinic' AND
                             (cu.role<>'clinic' OR cc.id IS NULL OR cc.is_active=false
                              OR cc.approval_status<>'approved')))
                ) AS participants_eligible
         FROM medorbit.direct_conversations c
         JOIN medorbit.conversation_members m
           ON m.conversation_id=c.id AND m.user_id=$2
         WHERE c.id=$1`,
        [conversationId, userId]
    );
    const access = result.rows[0];
    if (!access || access.left_at) {
        throw new MessagingPolicyError('Conversation not found', 404, 'NOT_FOUND');
    }
    if (requireActiveEligibility && (
        access.status !== 'active' || access.request_status !== 'accepted' || !access.participants_eligible
    )) {
        throw new MessagingPolicyError('Conversation is not available for messaging');
    }
    return access;
}

module.exports = {
    MessagingPolicyError,
    resolveMessagingActor,
    resolveCounterpart,
    findActiveRelationship,
    findEligibleRelationship,
    getConversationAccess,
};
