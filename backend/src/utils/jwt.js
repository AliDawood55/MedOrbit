const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const env = require('../config/env');

const verificationOptions = {
    algorithms: [env.jwt.algorithm],
    issuer: env.jwt.issuer,
    audience: env.jwt.audience,
};

function sign(payload, expiresIn) {
    return jwt.sign(payload, env.jwt.secret, {
        algorithm: env.jwt.algorithm,
        issuer: env.jwt.issuer,
        audience: env.jwt.audience,
        expiresIn,
    });
}

function generateAccessToken(payload) {
    return sign({ ...payload, type: 'access' }, env.jwt.accessExpiresIn);
}

function generateRefreshToken(payload) {
    return sign({
        ...payload,
        type: 'refresh',
        jti: crypto.randomUUID(),
    }, env.jwt.refreshExpiresIn);
}

function verifyTypedToken(token, expectedType) {
    try {
        const decoded = jwt.verify(token, env.jwt.secret, verificationOptions);
        return decoded.type === expectedType ? decoded : null;
    } catch {
        return null;
    }
}

function verifyAccessToken(token) {
    return verifyTypedToken(token, 'access');
}

function verifyRefreshToken(token) {
    return verifyTypedToken(token, 'refresh');
}

module.exports = {
    generateAccessToken,
    generateRefreshToken,
    verifyAccessToken,
    verifyRefreshToken,
};
