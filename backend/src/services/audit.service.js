const db = require('../config/database');

const SENSITIVE_KEYS = new Set([
    'passwordhash',
    'googleid',
    'refreshtoken',
    'refreshtokenhash',
    'verificationtoken',
    'resettoken',
    'tokenhash',
]);

function normalizedKey(key) {
    return key.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function sanitizeAuditValue(value) {
    if (Array.isArray(value)) return value.map(sanitizeAuditValue);
    if (!value || typeof value !== 'object') return value;

    return Object.fromEntries(
        Object.entries(value)
            .filter(([key]) => !SENSITIVE_KEYS.has(normalizedKey(key)))
            .map(([key, nested]) => [key, sanitizeAuditValue(nested)])
    );
}

async function createAudit({
    user_id = null,
    user_role = null,
    action,
    entity_type = null,
    entity_id = null,
    old_values = null,
    new_values = null,
    ip_address = null,
    user_agent = null,
}, queryable = db) {
    await queryable.query(
        `INSERT INTO medorbit.audit_logs
         (user_id, user_role, action, entity_type, entity_id,
          old_values, new_values, ip_address, user_agent)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [
            user_id,
            user_role,
            action,
            entity_type,
            entity_id,
            sanitizeAuditValue(old_values),
            sanitizeAuditValue(new_values),
            ip_address,
            user_agent,
        ]
    );
}

module.exports = { createAudit, sanitizeAuditValue };
