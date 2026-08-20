const db = require('../config/database');
const { verifyAccessToken } = require('../utils/jwt');
const { error } = require('../utils/response');

async function resolveAuthorizationContext(decoded) {
    if (!decoded?.sub || !Number.isInteger(decoded.authorizationVersion)) return null;

    const result = await db.query(
        `SELECT id, role, is_active, deleted_at, email_verified, authorization_version
         FROM medorbit.users
         WHERE id=$1`,
        [decoded.sub]
    );

    if (result.rows.length !== 1) return null;
    const user = result.rows[0];
    if (!user.is_active || user.deleted_at || !user.email_verified) return null;
    if (user.authorization_version !== decoded.authorizationVersion) return null;

    return {
        ...decoded,
        sub: user.id,
        role: user.role,
        authorizationVersion: user.authorization_version,
        emailVerified: user.email_verified,
    };
}

async function authenticate(req, res, next) {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return error(res, 'Access token required', 401, 'UNAUTHORIZED');
        }

        const decoded = verifyAccessToken(authHeader.slice(7));
        const context = await resolveAuthorizationContext(decoded);
        if (!context) return error(res, 'Invalid access token', 401, 'UNAUTHORIZED');

        req.user = context;
        return next();
    } catch {
        return error(res, 'Invalid access token', 401, 'UNAUTHORIZED');
    }
}

const authorize = (...roles) => async (req, res, next) => {
    if (!req.user) return error(res, 'Authentication required', 401, 'UNAUTHORIZED');
    if (!roles.includes(req.user.role)) {
        return error(res, 'You do not have permission', 403, 'FORBIDDEN');
    }
    if (req.user.role === 'doctor' && roles.includes('doctor')) {
        const result = await db.query(`SELECT approval_status FROM medorbit.doctors WHERE user_id=$1`, [req.user.sub]);
        if (result.rows.length !== 1 || result.rows[0].approval_status !== 'approved') {
            return error(res, 'Doctor account is not approved for this action', 403, 'DOCTOR_NOT_APPROVED');
        }
    }
    return next();
};

const authorizeAdmin = authorize('admin', 'super_admin');
const authorizeSuperAdmin = authorize('super_admin');

async function authenticateOptional(req, res, next) {
    try {
        const authHeader = req.headers.authorization;
        if (authHeader?.startsWith('Bearer ')) {
            const decoded = verifyAccessToken(authHeader.slice(7));
            const context = await resolveAuthorizationContext(decoded);
            if (context) req.user = context;
        }
    } catch {
        // Optional authentication deliberately degrades to anonymous.
    }
    return next();
}

module.exports = { authenticate, authorize, authorizeAdmin, authorizeSuperAdmin, authenticateOptional, resolveAuthorizationContext };
