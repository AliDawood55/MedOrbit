const crypto = require('crypto');

function getInternalToken() {
    if (process.env.AI_INTERNAL_TOKEN) return process.env.AI_INTERNAL_TOKEN;
    if (!process.env.JWT_SECRET) return null;
    return crypto
        .createHash('sha256')
        .update(`medorbit-ai-internal:${process.env.JWT_SECRET}`)
        .digest('hex');
}

function internalIdentityHeaders({ userId, recordId } = {}) {
    const token = getInternalToken();
    if (!token) throw new Error('AI internal credential is not configured');
    return {
        'X-MedOrbit-Internal-Token': token,
        ...(userId ? { 'X-MedOrbit-User-Id': userId } : {}),
        ...(recordId ? { 'X-MedOrbit-Record-Id': recordId } : {}),
    };
}

module.exports = { getInternalToken, internalIdentityHeaders };
