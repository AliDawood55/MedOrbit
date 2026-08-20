const crypto = require('crypto');
const db = require('../config/database');
const { createAudit } = require('./audit.service');

const INVITATION_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function normalizeEmail(value) {
    const email = String(value || '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        const err = new Error('A valid email is required');
        err.statusCode = 400;
        err.code = 'VALIDATION_ERROR';
        throw err;
    }
    return email;
}

function hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
}

function invitationDto(row) {
    return {
        id: row.id,
        email: row.email,
        status: row.status,
        expires_at: row.expires_at,
        accepted_at: row.accepted_at,
        accepted_by_user_id: row.accepted_by_user_id,
        revoked_at: row.revoked_at,
        revoked_by_user_id: row.revoked_by_user_id,
        invited_by_user_id: row.invited_by_user_id,
        created_at: row.created_at,
        updated_at: row.updated_at,
    };
}

async function createInvitation({ email, actor }, queryable = db) {
    const client = queryable === db ? await db.getClient() : queryable;
    try {
        await client.query('BEGIN');
        const normalizedEmail = normalizeEmail(email);
        await client.query(
            `UPDATE medorbit.admin_invitations
             SET status='expired', updated_at=NOW()
             WHERE email=$1 AND status='pending' AND expires_at <= NOW()`,
            [normalizedEmail]
        );
        const target = await client.query(
            `SELECT id, role FROM medorbit.users WHERE lower(email)=lower($1) FOR UPDATE`,
            [normalizedEmail]
        );
        if (target.rows.length > 1) throw new Error('Ambiguous account state');
        if (target.rows[0]?.role === 'super_admin') {
            const err = new Error('A super admin cannot be invited as an ordinary admin'); err.statusCode = 409; err.code = 'INVALID_TARGET'; throw err;
        }
        if (target.rows[0]?.role === 'admin') {
            const err = new Error('This account is already an admin'); err.statusCode = 409; err.code = 'INVALID_TARGET'; throw err;
        }
        const existing = await client.query(
            `SELECT id FROM medorbit.admin_invitations WHERE email=$1 AND status='pending' FOR UPDATE`,
            [normalizedEmail]
        );
        if (existing.rows.length) {
            const err = new Error('An active invitation already exists for this email'); err.statusCode = 409; err.code = 'INVITATION_EXISTS'; throw err;
        }
        const token = crypto.randomBytes(32).toString('base64url');
        const expiresAt = new Date(Date.now() + INVITATION_TTL_MS);
        const result = await client.query(
            `INSERT INTO medorbit.admin_invitations (email, token_hash, invited_by_user_id, expires_at)
             VALUES ($1,$2,$3,$4) RETURNING *`,
            [normalizedEmail, hashToken(token), actor.id, expiresAt]
        );
        await createAudit({ user_id: actor.id, user_role: actor.role, action: 'ADMIN_INVITATION_CREATED', entity_type: 'ADMIN_INVITATION', entity_id: result.rows[0].id, new_values: invitationDto(result.rows[0]) }, client);
        await client.query('COMMIT');
        return { invitation: invitationDto(result.rows[0]), token };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        if (queryable === db) client.release();
    }
}

async function acceptInvitation({ token, user }) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const tokenHash = hashToken(String(token || ''));
        const result = await client.query(`SELECT * FROM medorbit.admin_invitations WHERE token_hash=$1 FOR UPDATE`, [tokenHash]);
        if (result.rows.length !== 1) { const err = new Error('Invitation not found'); err.statusCode = 400; err.code = 'INVALID_INVITATION'; throw err; }
        const invitation = result.rows[0];
        if (invitation.status !== 'pending') { const err = new Error('Invitation is no longer available'); err.statusCode = 409; err.code = 'INVITATION_UNAVAILABLE'; throw err; }
        if (new Date(invitation.expires_at) <= new Date()) {
            await client.query(`UPDATE medorbit.admin_invitations SET status='expired', updated_at=NOW() WHERE id=$1`, [invitation.id]);
            await client.query('COMMIT');
            const err = new Error('Invitation has expired'); err.statusCode = 410; err.code = 'INVITATION_EXPIRED'; throw err;
        }
        const account = await client.query(`SELECT id,email,role,is_active,email_verified,deleted_at FROM medorbit.users WHERE id=$1 FOR UPDATE`, [user.sub]);
        const target = account.rows[0];
        if (!target || !target.is_active || target.deleted_at || !target.email_verified || target.email.toLowerCase() !== invitation.email) {
            const err = new Error('Invitation cannot be accepted by this account'); err.statusCode = 403; err.code = 'INVITATION_ACCOUNT_MISMATCH'; throw err;
        }
        if (target.role === 'super_admin' || target.role === 'admin') { const err = new Error('Invitation is not applicable to this account'); err.statusCode = 409; err.code = 'INVALID_TARGET'; throw err; }
        const updated = await client.query(`UPDATE medorbit.users SET role='admin', updated_at=NOW() WHERE id=$1 RETURNING id,email,role,authorization_version`, [target.id]);
        const accepted = await client.query(
            `UPDATE medorbit.admin_invitations SET status='accepted', accepted_at=NOW(), accepted_by_user_id=$1, updated_at=NOW() WHERE id=$2 RETURNING *`,
            [target.id, invitation.id]
        );
        await createAudit({ user_id: target.id, user_role: 'admin', action: 'ADMIN_INVITATION_ACCEPTED', entity_type: 'ADMIN_INVITATION', entity_id: invitation.id, old_values: invitationDto(invitation), new_values: invitationDto(accepted.rows[0]) }, client);
        await client.query('COMMIT');
        return { invitation: invitationDto(accepted.rows[0]), user: updated.rows[0] };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally { client.release(); }
}

async function listInvitations() {
    const result = await db.query(`SELECT * FROM medorbit.admin_invitations ORDER BY created_at DESC`);
    return result.rows.map(invitationDto);
}

async function revokeInvitation({ id, actor }) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const old = await client.query(`SELECT * FROM medorbit.admin_invitations WHERE id=$1 FOR UPDATE`, [id]);
        if (old.rows.length !== 1 || old.rows[0].status !== 'pending') { const err = new Error('Pending invitation not found'); err.statusCode = 404; err.code = 'NOT_FOUND'; throw err; }
        const updated = await client.query(`UPDATE medorbit.admin_invitations SET status='revoked', revoked_at=NOW(), revoked_by_user_id=$1, updated_at=NOW() WHERE id=$2 RETURNING *`, [actor.id, id]);
        await createAudit({ user_id: actor.id, user_role: actor.role, action: 'ADMIN_INVITATION_REVOKED', entity_type: 'ADMIN_INVITATION', entity_id: id, old_values: invitationDto(old.rows[0]), new_values: invitationDto(updated.rows[0]) }, client);
        await client.query('COMMIT');
        return invitationDto(updated.rows[0]);
    } catch (err) { await client.query('ROLLBACK').catch(() => {}); throw err; } finally { client.release(); }
}

module.exports = { INVITATION_TTL_MS, normalizeEmail, hashToken, invitationDto, createInvitation, acceptInvitation, listInvitations, revokeInvitation };
