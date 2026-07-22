// src/services/auth.service.js
// Hardened authentication service with email verification, password policy, session security

const db = require("../config/database");
const { hashPassword, comparePassword } = require("../utils/password");
const { generateAccessToken, generateRefreshToken, verifyRefreshToken } = require("../utils/jwt");
const { generateToken, hashToken } = require("../utils/token");
const { validatePassword, normalizeEmail, sanitize } = require("../utils/validation");
const { queueEmail } = require("./email.service");
const { verifyEmailTemplate, resetPasswordTemplate, welcomeTemplate } = require("../utils/emailTemplates");
const { OAuth2Client } = require("google-auth-library");
const env = require("../config/env");

const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost:8080/public';

const googleClient = new OAuth2Client(env.google.clientId);

/**
 * Register new user
 * - Validates password strength
 * - Creates user with email_verified=false
 * - Sends verification email (not console.log)
 */
async function register(userData) {
    const { email, password, role, firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, gender } = userData;

    // Validate password strength
    const pwCheck = validatePassword(password);
    if (!pwCheck.valid) {
        const err = new Error(pwCheck.errors.join('; '));
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        throw err;
    }

    const normalizedEmail = normalizeEmail(email);

    const existing = await db.query(
        `SELECT id FROM medorbit.users WHERE email=$1`,
        [normalizedEmail]
    );

    if (existing.rows.length > 0) {
        const err = new Error("Email already registered");
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        throw err;
    }

    const passwordHash = await hashPassword(password);

    const userResult = await db.query(
        `INSERT INTO medorbit.users (email, password_hash, role, email_verified, preferred_language)
         VALUES ($1,$2,$3,false,'ar')
         RETURNING id,email,role`,
        [normalizedEmail, passwordHash, role]
    );

    const user = userResult.rows[0];

    await db.query(
        `INSERT INTO medorbit.user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, gender)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [user.id, sanitize(firstNameAr), sanitize(lastNameAr), sanitize(firstNameEn), sanitize(lastNameEn), phone || null, gender || null]
    );

    if (role === "patient") {
        await db.query(`INSERT INTO medorbit.patients (user_id) VALUES($1)`, [user.id]);
    }
    if (role === "doctor") {
        await db.query(`INSERT INTO medorbit.doctors (user_id) VALUES($1)`, [user.id]);
    }

    // Generate verification token and send email
    const token = generateToken();
    const tokenHash = hashToken(token);

    // Invalidate any existing tokens for this user
    await db.query(
        `UPDATE medorbit.email_verification_tokens SET verified_at = NOW() WHERE user_id = $1 AND verified_at IS NULL`,
        [user.id]
    );

    await db.query(
        `INSERT INTO medorbit.email_verification_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, NOW()+INTERVAL '24 hours')`,
        [user.id, tokenHash]
    );

    const verifyUrl = `${FRONTEND_URL}?verify=${token}`;
    const { html, text } = verifyEmailTemplate(verifyUrl);

    try {
        await queueEmail(normalizedEmail, 'Verify your MedOrbit account', html, text);
    } catch (err) {
        console.warn(`Failed to queue verification email: ${err.message}`);
    }

    // Send welcome email
    const welcomeName = firstNameEn || firstNameAr || 'User';
    const welcome = welcomeTemplate(welcomeName);
    try {
        await queueEmail(normalizedEmail, 'Welcome to MedOrbit!', welcome.html, welcome.text);
    } catch (err) {
        console.warn(`Failed to queue welcome email: ${err.message}`);
    }

    return user;
}

/**
 * Login user
 * - Blocks unverified accounts
 * - Account lockout after 5 failures
 * - Generic error messages
 */
async function login(email, password, req) {
    const normalizedEmail = normalizeEmail(email);

    const result = await db.query(
        `SELECT u.id, u.email, u.password_hash, u.role, u.is_active, u.email_verified,
                u.failed_login_attempts, u.locked_until,
                p.first_name_ar, p.last_name_en
         FROM medorbit.users u
         LEFT JOIN medorbit.user_profiles p ON p.user_id=u.id
         WHERE u.email=$1 AND u.deleted_at IS NULL`,
        [normalizedEmail]
    );

    if (result.rows.length === 0) {
       const err = new Error("Invalid credentials");
       err.statusCode = 400;
       err.code = "INVALID_CREDENTIALS";
       throw err;
    }

    const user = result.rows[0];

    // Check account lockout
    if (user.locked_until && new Date(user.locked_until) > new Date()) {
        const err = new Error("Invalid credentials");
        err.statusCode = 401;
        err.code = "UNAUTHORIZED";
        throw err;
    }

    if (!user.is_active) {
        const err = new Error("Invalid credentials");
        err.statusCode = 401;
        err.code = "UNAUTHORIZED";
        throw err;
    }

    // Block unverified accounts
    if (!user.email_verified) {
        const err = new Error("Please verify your email before logging in");
        err.statusCode = 400;
        err.code = "EMAIL_NOT_VERIFIED";
        throw err;
    }

    const validPassword = await comparePassword(password, user.password_hash);

    if (!validPassword) {
        // Increment failed attempts, lock after 5
        await db.query(
            `UPDATE medorbit.users
             SET failed_login_attempts = failed_login_attempts + 1,
                 locked_until = CASE WHEN failed_login_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE locked_until END
             WHERE id=$1`,
            [user.id]
        );
        const err = new Error("Invalid credentials");
        err.statusCode = 400;
        err.code = "INVALID_CREDENTIALS";
        throw err;
    }

    // Reset failed attempts on success
    await db.query(
        `UPDATE medorbit.users SET failed_login_attempts=0, locked_until=NULL WHERE id=$1`,
        [user.id]
    );

    const accessToken = generateAccessToken({
        sub: user.id,
        email: user.email,
        role: user.role
    });

    const refreshToken = generateRefreshToken({
        sub: user.id,
        type: "refresh"
    });

    // Decode refresh token to extract jti
    const decodedRefresh = verifyRefreshToken(refreshToken);

    await db.query(
        `INSERT INTO medorbit.user_sessions (user_id, refresh_token, ip_address, user_agent, platform, device_name, expires_at)
         VALUES ($1,$2,$3,$4,$5,$6, NOW()+INTERVAL '7 days')`,
        [user.id, refreshToken, req.ip, req.headers["user-agent"] || null,
         req.body.platform || "web", req.body.deviceName || null]
    );

    return {
        user: {
            id: user.id,
            email: user.email,
            role: user.role,
            name: user.first_name_ar || user.last_name_en
        },
        accessToken,
        refreshToken
    };
}

/**
 * Google Sign-In
 * - Verifies the ID token server-side (signature, audience, issuer, expiry)
 *   via google-auth-library — never trusts the client's decoded payload.
 * - Existing email match -> links google_id to that account and logs in.
 * - No match -> creates a new patient account (email already verified by
 *   Google, no local password).
 * - Issues the exact same access+refresh pair as password login, through
 *   the same user_sessions insert, so every other piece of the auth system
 *   (refresh, revocation, middleware) needs no special-casing for how the
 *   session originated.
 */
async function googleLogin(idToken, req) {
    if (!idToken) {
        const err = new Error("Google ID token required");
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        throw err;
    }

    let payload;
    try {
        const ticket = await googleClient.verifyIdToken({
            idToken,
            audience: env.google.clientId
        });
        payload = ticket.getPayload();
    } catch (err) {
        const e = new Error("Invalid Google sign-in token");
        e.statusCode = 401;
        e.code = "UNAUTHORIZED";
        throw e;
    }

    if (!payload || !payload.email || !payload.email_verified) {
        const err = new Error("Google account email is not verified");
        err.statusCode = 401;
        err.code = "UNAUTHORIZED";
        throw err;
    }

    const googleId = payload.sub;
    const normalizedEmail = normalizeEmail(payload.email);

    let result = await db.query(
        `SELECT id, email, role, is_active, google_id
         FROM medorbit.users
         WHERE (google_id=$1 OR email=$2) AND deleted_at IS NULL`,
        [googleId, normalizedEmail]
    );

    let user;

    if (result.rows.length > 0) {
        user = result.rows[0];

        if (!user.is_active) {
            const err = new Error("Invalid credentials");
            err.statusCode = 401;
            err.code = "UNAUTHORIZED";
            throw err;
        }

        // Existing email/password account signing in with the same Gmail
        // for the first time — link rather than create a duplicate.
        if (!user.google_id) {
            await db.query(
                `UPDATE medorbit.users SET google_id=$1, email_verified=true, updated_at=NOW() WHERE id=$2`,
                [googleId, user.id]
            );
        }
    } else {
        // New account. user_profiles.first_name_*/last_name_* are NOT NULL
        // and Google gives us no Arabic variant, so the Latin name from the
        // token is reused for both — real data in the wrong-script column,
        // not a fabricated placeholder.
        const givenName = sanitize(payload.given_name || '') || (payload.name ? payload.name.split(' ')[0] : '') || 'Google';
        const familyName = sanitize(payload.family_name || '') || (payload.name ? payload.name.split(' ').slice(1).join(' ') : '') || 'User';

        const userResult = await db.query(
            `INSERT INTO medorbit.users (email, password_hash, role, email_verified, google_id, preferred_language)
             VALUES ($1, NULL, 'patient', true, $2, 'ar')
             RETURNING id, email, role, is_active, google_id`,
            [normalizedEmail, googleId]
        );
        user = userResult.rows[0];

        await db.query(
            `INSERT INTO medorbit.user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, profile_image_url)
             VALUES ($1, $2, $3, $2, $3, $4)`,
            [user.id, givenName, familyName, payload.picture || null]
        );

        await db.query(`INSERT INTO medorbit.patients (user_id) VALUES($1)`, [user.id]);
    }

    const accessToken = generateAccessToken({
        sub: user.id,
        email: user.email,
        role: user.role
    });

    const refreshToken = generateRefreshToken({
        sub: user.id,
        type: "refresh"
    });

    await db.query(
        `INSERT INTO medorbit.user_sessions (user_id, refresh_token, ip_address, user_agent, platform, device_name, expires_at)
         VALUES ($1,$2,$3,$4,$5,$6, NOW()+INTERVAL '7 days')`,
        [user.id, refreshToken, req.ip, req.headers["user-agent"] || null,
         req.body.platform || "web", req.body.deviceName || null]
    );

    return {
        user: {
            id: user.id,
            email: user.email,
            role: user.role,
            name: payload.name || payload.given_name || user.email
        },
        accessToken,
        refreshToken
    };
}

/**
 * Refresh access token
 * - Validates session exists and not revoked
 * - Rotates refresh token (revokes old, issues new)
 */
async function refresh(refreshToken) {
    const decoded = verifyRefreshToken(refreshToken);
    if (!decoded || decoded.type !== "refresh") {
        const err = new Error("Invalid refresh token");
        err.statusCode = 400;
        err.code = "INVALID_TOKEN";
        throw err;
    }

    const session = await db.query(
        `SELECT s.user_id, u.email, u.role
         FROM medorbit.user_sessions s
         JOIN medorbit.users u ON u.id=s.user_id
         WHERE s.refresh_token=$1 AND s.expires_at > NOW() AND s.revoked_at IS NULL`,
        [refreshToken]
    );

    if (session.rows.length === 0) {
        const err = new Error("Expired refresh token");
        err.statusCode = 400;
        err.code = "INVALID_TOKEN";
        throw err;
    }

    const user = session.rows[0];

    // Revoke old refresh token (rotation)
    await db.query(
        `UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE refresh_token=$1`,
        [refreshToken]
    );

    // Issue new refresh token
    const newRefreshToken = generateRefreshToken({
        sub: user.user_id,
        type: "refresh"
    });

    // Create new session
    await db.query(
        `INSERT INTO medorbit.user_sessions (user_id, refresh_token, expires_at)
         VALUES ($1, $2, NOW()+INTERVAL '7 days')`,
        [user.user_id, newRefreshToken]
    );

    const accessToken = generateAccessToken({
        sub: user.user_id,
        email: user.email,
        role: user.role
    });

    return { accessToken, refreshToken: newRefreshToken };
}

/**
 * Logout user — revokes session
 */
async function logout(refreshToken) {
    await db.query(
        `UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE refresh_token=$1`,
        [refreshToken]
    );
}

/**
 * Change password
 * - Validates current password
 * - Validates new password strength
 * - Revokes all sessions
 */
async function changePassword(userId, currentPassword, newPassword) {
    const result = await db.query(
        `SELECT password_hash FROM medorbit.users WHERE id=$1`,
        [userId]
    );

    if (result.rows.length === 0) {
        const err = new Error("Invalid credentials");
        err.statusCode = 401;
        err.code = "UNAUTHORIZED";
        throw err;
    }

    const valid = await comparePassword(currentPassword, result.rows[0].password_hash);
    if (!valid) {
        const err = new Error("Current password is incorrect");
        err.statusCode = 400;
        err.code = "INVALID_CREDENTIALS";
        throw err;
    }

    // Validate new password strength
    const pwCheck = validatePassword(newPassword);
    if (!pwCheck.valid) {
        const err = new Error(pwCheck.errors.join('; '));
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        throw err;
    }

    const newHash = await hashPassword(newPassword);

    await db.query(
        `UPDATE medorbit.users SET password_hash=$1, updated_at=NOW() WHERE id=$2`,
        [newHash, userId]
    );

    // Revoke all sessions
    await db.query(
        `UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE user_id=$1`,
        [userId]
    );
}

/**
 * Forgot password
 * - Generates token, sends email with reset link
 * - Does NOT reveal if email exists (prevents enumeration)
 */
async function forgotPassword(email) {
    const normalizedEmail = normalizeEmail(email);

    const result = await db.query(
        `SELECT id, email FROM medorbit.users WHERE email=$1 AND deleted_at IS NULL`,
        [normalizedEmail]
    );

    // Always return success — do not reveal if email exists
    if (result.rows.length === 0) {
        return;
    }

    const user = result.rows[0];
    const token = generateToken();
    const tokenHash = hashToken(token);

    // Invalidate old tokens
    await db.query(
        `UPDATE medorbit.password_reset_tokens SET used_at=NOW() WHERE user_id=$1 AND used_at IS NULL`,
        [user.id]
    );

    await db.query(
        `INSERT INTO medorbit.password_reset_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, NOW()+INTERVAL '15 minutes')`,
        [user.id, tokenHash]
    );

    const resetUrl = `${FRONTEND_URL}?reset=${token}`;
    const { html, text } = resetPasswordTemplate(resetUrl);

    try {
        await queueEmail(normalizedEmail, 'Reset your MedOrbit password', html, text);
    } catch (err) {
        console.warn(`Failed to queue password reset email: ${err.message}`);
    }
}

/**
 * Reset password
 * - Validates token, single-use, expired check
 * - Updates password, revokes all sessions
 */
async function resetPassword(token, newPassword) {
    // Validate new password strength
    const pwCheck = validatePassword(newPassword);
    if (!pwCheck.valid) {
        const err = new Error(pwCheck.errors.join('; '));
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        throw err;
    }

    const tokenHash = hashToken(token);

    const result = await db.query(
        `SELECT id, user_id FROM medorbit.password_reset_tokens
         WHERE token_hash=$1 AND expires_at > NOW() AND used_at IS NULL`,
        [tokenHash]
    );

    if (result.rows.length === 0) {
        const err = new Error("Invalid or expired token");
        err.statusCode = 400;
        err.code = "INVALID_TOKEN";
        throw err;
    }

    const reset = result.rows[0];
    const passwordHash = await hashPassword(newPassword);

    // Password update + token consumption + session revocation must be atomic —
    // a failure partway through must not leave the password changed but the
    // token still usable (or vice versa).
    const client = await db.getClient();
    try {
        await client.query('BEGIN');

        await client.query(`UPDATE medorbit.users SET password_hash=$1 WHERE id=$2`, [passwordHash, reset.user_id]);
        await client.query(`UPDATE medorbit.password_reset_tokens SET used_at=NOW() WHERE id=$1`, [reset.id]);

        // Revoke all sessions
        await client.query(`UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE user_id=$1`, [reset.user_id]);

        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Verify email
 * - Validates token, single-use, expired check
 * - Marks user as verified
 */
async function verifyEmail(token) {
    const tokenHash = hashToken(token);

    const result = await db.query(
        `SELECT id, user_id FROM medorbit.email_verification_tokens
         WHERE token_hash=$1 AND expires_at > NOW() AND verified_at IS NULL`,
        [tokenHash]
    );

    if (result.rows.length === 0) {
        throw new Error("Invalid or expired verification token");
    }

    const data = result.rows[0];

    await db.query(
        `UPDATE medorbit.users SET email_verified=true, updated_at=NOW() WHERE id=$1`,
        [data.user_id]
    );

    await db.query(
        `UPDATE medorbit.email_verification_tokens SET verified_at=NOW() WHERE id=$1`,
        [data.id]
    );
}

/**
 * Resend verification email
 * - Invalidates old token, generates new one
 * - Does NOT reveal if email exists
 */
async function resendVerification(email) {
    const normalizedEmail = normalizeEmail(email);

    const result = await db.query(
        `SELECT id FROM medorbit.users WHERE email=$1 AND deleted_at IS NULL`,
        [normalizedEmail]
    );

    if (result.rows.length === 0) {
        return;
    }

    const user = result.rows[0];

    // Check if already verified
    const verifiedCheck = await db.query(
        `SELECT email_verified FROM medorbit.users WHERE id=$1`,
        [user.id]
    );
    if (verifiedCheck.rows[0]?.email_verified) {
        return;
    }

    // Invalidate old tokens
    await db.query(
        `UPDATE medorbit.email_verification_tokens SET verified_at=NOW() WHERE user_id=$1 AND verified_at IS NULL`,
        [user.id]
    );

    const token = generateToken();
    const tokenHash = hashToken(token);

    await db.query(
        `INSERT INTO medorbit.email_verification_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, NOW()+INTERVAL '24 hours')`,
        [user.id, tokenHash]
    );

    const verifyUrl = `${FRONTEND_URL}?verify=${token}`;
    const { html, text } = verifyEmailTemplate(verifyUrl);

    try {
        await queueEmail(normalizedEmail, 'Verify your MedOrbit account', html, text);
    } catch (err) {
        console.warn(`Failed to queue verification email: ${err.message}`);
    }
}

module.exports = {
    register, login, googleLogin, refresh, logout, changePassword,
    forgotPassword, resetPassword, verifyEmail, resendVerification
};