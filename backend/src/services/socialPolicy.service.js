const db = require('../config/database');

async function resolveApprovedDoctorForUser(userId, queryable = db) {
    const result = await queryable.query(
        `SELECT d.id,d.user_id,d.approval_status
         FROM medorbit.doctors d
         JOIN medorbit.users u ON u.id=d.user_id
         WHERE d.user_id=$1 AND u.role='doctor' AND u.is_active=true
           AND u.deleted_at IS NULL AND d.approval_status='approved'`,
        [userId]
    );
    return result.rows[0] || null;
}

async function findManageablePost(postId, userId, queryable = db) {
    const result = await queryable.query(
        `SELECT p.* FROM medorbit.doctor_posts p
         JOIN medorbit.doctors d ON d.id=p.doctor_id
         WHERE p.id=$1 AND d.user_id=$2 AND p.deleted_at IS NULL`,
        [postId,userId]
    );
    return result.rows[0] || null;
}

async function findEligiblePost(postId, queryable = db) {
    const result = await queryable.query(
        `SELECT p.* FROM medorbit.doctor_posts p
         JOIN medorbit.doctors d ON d.id=p.doctor_id
         JOIN medorbit.users u ON u.id=d.user_id
         WHERE p.id=$1 AND p.status='published' AND p.moderation_status='approved'
           AND p.deleted_at IS NULL AND d.approval_status='approved'
           AND u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL`,
        [postId]
    );
    return result.rows[0] || null;
}

async function findFollowableDoctor(doctorId, queryable = db) {
    const result = await queryable.query(
        `SELECT d.id FROM medorbit.doctors d JOIN medorbit.users u ON u.id=d.user_id
         WHERE d.id=$1 AND d.approval_status='approved'
           AND u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL`,
        [doctorId]
    );
    return result.rows[0] || null;
}

module.exports = { resolveApprovedDoctorForUser, findManageablePost, findEligiblePost, findFollowableDoctor };
