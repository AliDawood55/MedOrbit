// src/utils/validation.js
// Input validation utilities for auth endpoints

/**
 * Validate password strength
 * Rules: min 8 chars, uppercase, lowercase, number, special char
 */
function validatePassword(password) {
    const errors = [];

    if (!password || password.length < 8) {
        errors.push('Password must be at least 8 characters');
    }
    if (!/[A-Z]/.test(password)) {
        errors.push('Password must contain an uppercase letter');
    }
    if (!/[a-z]/.test(password)) {
        errors.push('Password must contain a lowercase letter');
    }
    if (!/[0-9]/.test(password)) {
        errors.push('Password must contain a number');
    }
    if (!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(password)) {
        errors.push('Password must contain a special character');
    }

    return {
        valid: errors.length === 0,
        errors
    };
}

/**
 * Validate email format
 */
function validateEmail(email) {
    if (!email || typeof email !== 'string') {
        return false;
    }
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email.trim().toLowerCase());
}

/**
 * Normalize email: lowercase + trim
 */
function normalizeEmail(email) {
    if (!email) return '';
    return email.trim().toLowerCase();
}

/**
 * Sanitize string: trim, strip HTML tags
 */
function sanitize(str) {
    if (!str || typeof str !== 'string') return '';
    return str.trim().replace(/<[^>]*>/g, '');
}

/**
 * Validate required fields exist
 */
function requireFields(body, fields) {
    const missing = [];
    for (const field of fields) {
        const value = body[field];
        if (value === undefined || value === null || (typeof value === 'string' && value.trim() === '')) {
            missing.push(field);
        }
    }
    return missing;
}

module.exports = {
    validatePassword,
    validateEmail,
    normalizeEmail,
    sanitize,
    requireFields
};