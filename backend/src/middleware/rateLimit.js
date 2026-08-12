const crypto = require('crypto');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');

const env = require('../config/env');
const { verifyAccessToken } = require('../utils/jwt');

const GENERAL_WINDOW_MS = 15 * 60 * 1000;
const AUTHENTICATED_GENERAL_MAX = 300;
const ANONYMOUS_GENERAL_MAX = 100;
const identityCache = Symbol('rateLimitIdentity');

function verifiedAccessSubject(req) {
    if (Object.prototype.hasOwnProperty.call(req, identityCache)) {
        return req[identityCache];
    }

    const header = req.headers?.authorization;
    if (!header?.startsWith('Bearer ')) {
        req[identityCache] = null;
        return null;
    }

    const decoded = verifyAccessToken(header.slice(7));
    req[identityCache] = decoded?.sub || null;
    return req[identityCache];
}

function hashSubject(subject) {
    return crypto
        .createHmac('sha256', env.jwt.secret)
        .update(String(subject))
        .digest('hex');
}

function generalApiKey(req) {
    const subject = verifiedAccessSubject(req);
    if (subject) return `user:${hashSubject(subject)}`;
    return `ip:${ipKeyGenerator(req.ip)}`;
}

function defaultGeneralSkip(req) {
    // Health probes must not consume client capacity. Authentication has its
    // own stricter, IP-based limiters in auth.routes.js.
    return req.path === '/health' || req.path === '/auth' || req.path.startsWith('/auth/');
}

function rateLimitPayload(message = 'Too many requests. Please try again later.') {
    return {
        success: false,
        error: { code: 'RATE_LIMITED', message },
    };
}

function createGeneralApiLimiter(options = {}) {
    const authenticatedMax = options.authenticatedMax ?? AUTHENTICATED_GENERAL_MAX;
    const anonymousMax = options.anonymousMax ?? ANONYMOUS_GENERAL_MAX;

    return rateLimit({
        windowMs: options.windowMs ?? GENERAL_WINDOW_MS,
        limit: (req) => verifiedAccessSubject(req) ? authenticatedMax : anonymousMax,
        keyGenerator: generalApiKey,
        skip: options.skip ?? defaultGeneralSkip,
        standardHeaders: true,
        legacyHeaders: false,
        message: rateLimitPayload(),
    });
}

module.exports = {
    GENERAL_WINDOW_MS,
    AUTHENTICATED_GENERAL_MAX,
    ANONYMOUS_GENERAL_MAX,
    createGeneralApiLimiter,
    generalApiKey,
    rateLimitPayload,
    verifiedAccessSubject,
};
