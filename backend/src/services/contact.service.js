const db = require('../config/database');
const { createAudit } = require('./audit.service');

class ContactValidationError extends Error {
    constructor(message, statusCode = 400, code = 'VALIDATION_ERROR') {
        super(message);
        this.statusCode = statusCode;
        this.code = code;
    }
}

function text(value, label, maxLength) {
    if (typeof value !== 'string') throw new ContactValidationError(`${label} is required`);
    const normalized = value.trim();
    if (!normalized) throw new ContactValidationError(`${label} is required`);
    if (normalized.length > maxLength) {
        throw new ContactValidationError(`${label} must not exceed ${maxLength} characters`);
    }
    return normalized;
}

function email(value) {
    const normalized = text(value, 'Email', 320).toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
        throw new ContactValidationError('A valid email is required');
    }
    return normalized;
}

async function submitContact({ userId = null, role = null, body }) {
    const subject = text(body.subject, 'Subject', 160);
    const message = text(body.message, 'Message', 4000);
    let senderName;
    let senderEmail;

    if (userId) {
        const identity = await db.query(
            `SELECT u.email,
                    COALESCE(NULLIF(trim(concat_ws(' ',p.first_name_en,p.last_name_en)),''),
                             NULLIF(trim(concat_ws(' ',p.first_name_ar,p.last_name_ar)),''),
                             'MedOrbit user') AS display_name
             FROM medorbit.users u
             LEFT JOIN medorbit.user_profiles p ON p.user_id=u.id
             WHERE u.id=$1 AND u.is_active=true AND u.deleted_at IS NULL`,
            [userId]
        );
        if (!identity.rows[0]) throw new ContactValidationError('User not found', 404, 'NOT_FOUND');
        senderName = identity.rows[0].display_name;
        senderEmail = identity.rows[0].email;
    } else {
        senderName = text(body.name ?? body.sender_name, 'Name', 120);
        senderEmail = email(body.email ?? body.sender_email);
    }

    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const inserted = await client.query(
            `INSERT INTO medorbit.contact_messages
               (user_id,sender_name,sender_email,subject,message)
             VALUES($1,$2,$3,$4,$5)
             RETURNING id,status,created_at`,
            [userId, senderName, senderEmail, subject, message]
        );
        const contact = inserted.rows[0];
        await client.query(
            `INSERT INTO medorbit.notifications
               (user_id,title_ar,title_en,message_ar,message_en,
                notification_type,reference_id,reference_type,channel)
             SELECT u.id,'رسالة تواصل جديدة','New contact message',
                    'وصلت رسالة جديدة إلى صندوق رسائل التواصل.',
                    'A new message arrived in the Contact inbox.',
                    'NEW_CONTACT_MESSAGE',$1,'CONTACT_MESSAGE','in_app'
             FROM medorbit.users u
             WHERE u.role IN ('admin','super_admin') AND u.is_active=true
               AND u.email_verified=true AND u.deleted_at IS NULL`,
            [contact.id]
        );
        await createAudit({
            user_id: userId,
            user_role: role || 'guest',
            action: 'CONTACT_MESSAGE_SUBMITTED',
            entity_type: 'CONTACT_MESSAGE',
            entity_id: contact.id,
            new_values: { status: contact.status, authenticated: Boolean(userId) },
        }, client);
        await client.query('COMMIT');
        return contact;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function listContacts({ status, limit = 30, offset = 0 }) {
    const safeLimit = Math.min(Math.max(Number(limit) || 30, 1), 100);
    const safeOffset = Math.max(Number(offset) || 0, 0);
    const values = [];
    let filter = '';
    if (status) {
        if (!['new', 'read', 'resolved'].includes(status)) {
            throw new ContactValidationError('Invalid contact status');
        }
        values.push(status);
        filter = `WHERE c.status=$${values.length}`;
    }
    values.push(safeLimit, safeOffset);
    const result = await db.query(
        `SELECT c.id,c.user_id IS NOT NULL AS authenticated,c.sender_name,c.sender_email,
                c.subject,c.status,c.created_at,c.updated_at,c.read_at,c.resolved_at
         FROM medorbit.contact_messages c
         ${filter}
         ORDER BY CASE c.status WHEN 'new' THEN 0 WHEN 'read' THEN 1 ELSE 2 END,
                  c.created_at DESC,c.id DESC
         LIMIT $${values.length - 1} OFFSET $${values.length}`,
        values
    );
    return { items: result.rows, limit: safeLimit, offset: safeOffset };
}

async function getContact(id) {
    const result = await db.query(
        `SELECT id,user_id IS NOT NULL AS authenticated,sender_name,sender_email,
                subject,message,status,created_at,updated_at,read_at,resolved_at,resolved_by
         FROM medorbit.contact_messages WHERE id=$1`,
        [id]
    );
    if (!result.rows[0]) throw new ContactValidationError('Contact message not found', 404, 'NOT_FOUND');
    return result.rows[0];
}

async function updateContact(id, actor, action) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const result = await client.query(
            action === 'read'
                ? `UPDATE medorbit.contact_messages
                   SET status=CASE WHEN status='new' THEN 'read' ELSE status END,
                       read_at=COALESCE(read_at,NOW()),updated_at=NOW()
                   WHERE id=$1
                   RETURNING id,status,read_at,resolved_at,resolved_by`
                : `UPDATE medorbit.contact_messages
                   SET status='resolved',read_at=COALESCE(read_at,NOW()),
                       resolved_at=COALESCE(resolved_at,NOW()),resolved_by=$2,updated_at=NOW()
                   WHERE id=$1
                   RETURNING id,status,read_at,resolved_at,resolved_by`,
            action === 'read' ? [id] : [id, actor.sub]
        );
        if (!result.rows[0]) {
            throw new ContactValidationError('Contact message not found', 404, 'NOT_FOUND');
        }
        await createAudit({
            user_id: actor.sub,
            user_role: actor.role,
            action: action === 'read' ? 'CONTACT_MESSAGE_READ' : 'CONTACT_MESSAGE_RESOLVED',
            entity_type: 'CONTACT_MESSAGE',
            entity_id: id,
            new_values: { status: result.rows[0].status },
        }, client);
        await client.query('COMMIT');
        return result.rows[0];
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = {
    ContactValidationError,
    submitContact,
    listContacts,
    getContact,
    updateContact,
};
