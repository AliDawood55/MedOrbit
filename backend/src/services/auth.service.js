// src/services/auth.service.js
// Hardened authentication service with email verification, password policy, session security

const db = require("../config/database");
const { hashPassword, comparePassword } = require("../utils/password");
const { generateAccessToken, generateRefreshToken, verifyRefreshToken } = require("../utils/jwt");
const { generateToken, generateOtp, hashToken, hashOtp, hashRefreshToken } = require("../utils/token");
const { validatePassword, normalizeEmail, sanitize } = require("../utils/validation");
const { queueEmail } = require("./email.service");
const { verifyEmailTemplate, resetPasswordTemplate, welcomeTemplate } = require("../utils/emailTemplates");
const { OAuth2Client } = require("google-auth-library");
const env = require("../config/env");

const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost:8080/public';
const OTP_EXPIRY_MINUTES = 10;

const googleClient = new OAuth2Client(env.google.clientId);

async function issueSession(queryable, user, req = {}) {
    const authorizationVersion = user.authorization_version;
    const accessToken = generateAccessToken({
        sub: user.id,
        email: user.email,
        role: user.role,
        authorizationVersion,
    });
    const refreshToken = generateRefreshToken({
        sub: user.id,
        authorizationVersion,
    });
    const decodedRefresh = verifyRefreshToken(refreshToken);
    if (!decodedRefresh) throw authError("Unable to create session", 500, "INTERNAL_ERROR");

    await queryable.query(
        `INSERT INTO medorbit.user_sessions
         (user_id, refresh_token_hash, ip_address, user_agent, platform, device_name, expires_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [
            user.id,
            hashRefreshToken(refreshToken),
            req.ip || null,
            req.headers?.["user-agent"] || null,
            req.body?.platform || "web",
            req.body?.deviceName || null,
            new Date(decodedRefresh.exp * 1000),
        ]
    );

    return { accessToken, refreshToken };
}

function authError(message, statusCode, code) {
    const err = new Error(message);
    err.statusCode = statusCode;
    err.code = code;
    return err;
}

function buildVerificationUrl(token) {
    const base = FRONTEND_URL.replace(/\/+$/, '');
    const page = /\.html?$/i.test(base) ? base : `${base}/verify-email.html`;
    const separator = page.includes('?') ? '&' : '?';
    return `${page}${separator}token=${encodeURIComponent(token)}`;
}

async function createVerificationPair(client, userId, email) {
    const linkToken = generateToken();

    await client.query(
        `INSERT INTO medorbit.email_verification_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, NOW() + INTERVAL '24 hours')`,
        [userId, hashToken(linkToken)]
    );

    for (let attempt = 0; attempt < 5; attempt += 1) {
        const otp = generateOtp();
        const inserted = await client.query(
            `INSERT INTO medorbit.email_verification_tokens (user_id, token_hash, expires_at)
             VALUES ($1, $2, NOW() + ($3 * INTERVAL '1 minute'))
             ON CONFLICT (token_hash) DO NOTHING
             RETURNING id`,
            [userId, hashOtp(otp, email, env.jwt.secret), OTP_EXPIRY_MINUTES]
        );
        if (inserted.rows.length > 0) {
            return { linkToken, otp };
        }
    }

    throw authError("Unable to generate verification code", 500, "INTERNAL_ERROR");
}

async function queueVerificationEmail(client, email, userId) {
    const { linkToken, otp } = await createVerificationPair(client, userId, email);
    const verifyUrl = buildVerificationUrl(linkToken);
    const { html, text } = verifyEmailTemplate(verifyUrl, otp);
    await queueEmail(email, 'Verify your MedOrbit account', html, text, client);
}

/**
 * Register new user
 * - Validates password strength
 * - Creates user with email_verified=false
 * - Sends verification email (not console.log)
 */
async function register(userData) {
    const { email, password, role, firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, gender } = userData;

    if (role != null && role !== "patient") {
        throw authError("Public registration only supports patient accounts", 400, "INVALID_ROLE");
    }

    // Validate password strength
    const pwCheck = validatePassword(password);
    if (!pwCheck.valid) {
        const err = new Error(pwCheck.errors.join('; '));
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        throw err;
    }

    const normalizedEmail = normalizeEmail(email);
    const passwordHash = await hashPassword(password);
    const client = await db.getClient();

    try {
        await client.query('BEGIN');

        const existing = await client.query(
            `SELECT id FROM medorbit.users WHERE email=$1`,
            [normalizedEmail]
        );

        if (existing.rows.length > 0) {
            throw authError("Email already registered", 400, "VALIDATION_ERROR");
        }

        const userResult = await client.query(
            `INSERT INTO medorbit.users (email, password_hash, role, email_verified, preferred_language)
             VALUES ($1,$2,'patient',false,'ar')
             RETURNING id,email,role`,
            [normalizedEmail, passwordHash]
        );

        const user = userResult.rows[0];

        await client.query(
            `INSERT INTO medorbit.user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, gender)
             VALUES ($1,$2,$3,$4,$5,$6,$7)`,
            [user.id, sanitize(firstNameAr), sanitize(lastNameAr), sanitize(firstNameEn), sanitize(lastNameEn), phone || null, gender || null]
        );

        await client.query(`INSERT INTO medorbit.patients (user_id) VALUES($1)`, [user.id]);

        await queueVerificationEmail(client, normalizedEmail, user.id);

        const welcomeName = firstNameEn || firstNameAr || 'User';
        const welcome = welcomeTemplate(welcomeName);
        await queueEmail(normalizedEmail, 'Welcome to MedOrbit!', welcome.html, welcome.text, client);

        await client.query('COMMIT');
        return user;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
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
                u.failed_login_attempts, u.locked_until, u.authorization_version,
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

    // Only reveal verification state after the password has been validated.
    if (!user.email_verified) {
        const err = new Error("Please verify your email before logging in");
        err.statusCode = 400;
        err.code = "EMAIL_NOT_VERIFIED";
        throw err;
    }

    // Reset failed attempts on success
    await db.query(
        `UPDATE medorbit.users SET failed_login_attempts=0, locked_until=NULL WHERE id=$1`,
        [user.id]
    );

    const { accessToken, refreshToken } = await issueSession(db, user, req);

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
    if (!googleId) {
        throw authError("Invalid Google sign-in token", 401, "UNAUTHORIZED");
    }
    const normalizedEmail = normalizeEmail(payload.email);

    const [googleMatch, emailMatch] = await Promise.all([
        db.query(
        `SELECT id, email, role, is_active, deleted_at, email_verified,
                google_id, authorization_version
         FROM medorbit.users
         WHERE google_id=$1`,
        [googleId]
        ),
        db.query(
        `SELECT id, email, role, is_active, deleted_at, email_verified,
                google_id, authorization_version
         FROM medorbit.users
         WHERE email=$1`,
        [normalizedEmail]
        ),
    ]);

    if (googleMatch.rows.length > 1 || emailMatch.rows.length > 1 ||
        (googleMatch.rows[0] && emailMatch.rows[0] && googleMatch.rows[0].id !== emailMatch.rows[0].id)) {
        throw authError("Google identity conflicts with an existing account", 409, "GOOGLE_IDENTITY_CONFLICT");
    }

    const result = { rows: googleMatch.rows.length ? googleMatch.rows : emailMatch.rows };

    let user;

    if (result.rows.length > 0) {
        user = result.rows[0];

        if (!user.is_active || user.deleted_at) {
            const err = new Error("Invalid credentials");
            err.statusCode = 401;
            err.code = "UNAUTHORIZED";
            throw err;
        }

        if (user.google_id && user.google_id !== googleId) {
            throw authError("Google identity does not match the linked account", 409, "GOOGLE_IDENTITY_MISMATCH");
        }

        // Existing email/password account signing in with the same Gmail
        // for the first time — link rather than create a duplicate.
        if (!user.google_id) {
            const linked = await db.query(
                `UPDATE medorbit.users
                 SET google_id=$1,
                     email_verified=true,
                     authorization_version=authorization_version+1,
                     updated_at=NOW()
                 WHERE id=$2 AND google_id IS NULL
                 RETURNING id, email, role, is_active, deleted_at, email_verified,
                           google_id, authorization_version`,
                [googleId, user.id]
            );
            if (linked.rows.length !== 1) {
                throw authError("Google identity does not match the linked account", 409, "GOOGLE_IDENTITY_MISMATCH");
            }
            user = linked.rows[0];
            await db.query(
                `UPDATE medorbit.user_sessions
                 SET revoked_at=NOW()
                 WHERE user_id=$1 AND revoked_at IS NULL`,
                [user.id]
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
             RETURNING id, email, role, is_active, deleted_at, email_verified,
                       google_id, authorization_version`,
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

    const { accessToken, refreshToken } = await issueSession(db, user, req);

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
    if (!decoded) throw authError("Invalid refresh token", 400, "INVALID_TOKEN");

    const tokenHash = hashRefreshToken(refreshToken);
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const session = await client.query(
            `SELECT s.id AS session_id, s.user_id, u.email, u.role, u.is_active,
                    u.deleted_at, u.email_verified, u.authorization_version
             FROM medorbit.user_sessions s
             JOIN medorbit.users u ON u.id=s.user_id
             WHERE s.refresh_token_hash=$1
               AND s.expires_at > NOW()
               AND s.revoked_at IS NULL
             FOR UPDATE`,
            [tokenHash]
        );

        if (session.rows.length !== 1) {
            throw authError("Invalid or expired refresh token", 400, "INVALID_TOKEN");
        }

        const user = session.rows[0];
        if (decoded.sub !== user.user_id ||
            decoded.authorizationVersion !== user.authorization_version ||
            !user.is_active || user.deleted_at || !user.email_verified) {
            throw authError("Invalid or expired refresh token", 400, "INVALID_TOKEN");
        }

        await client.query(
            `UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE id=$1`,
            [user.session_id]
        );

        const sessionUser = {
            id: user.user_id,
            email: user.email,
            role: user.role,
            authorization_version: user.authorization_version,
        };
        const tokens = await issueSession(client, sessionUser);
        await client.query('COMMIT');
        return tokens;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Logout user — revokes session
 */
async function logout(refreshToken) {
    if (!verifyRefreshToken(refreshToken)) return;
    await db.query(
        `UPDATE medorbit.user_sessions
         SET revoked_at=NOW()
         WHERE refresh_token_hash=$1 AND revoked_at IS NULL`,
        [hashRefreshToken(refreshToken)]
    );
}

/**
 * Change password
 * - Validates current password
 * - Validates new password strength
 * - Revokes all sessions
 */
async function changePassword(userId, currentPassword, newPassword) {
    const pwCheck = validatePassword(newPassword);
    if (!pwCheck.valid) {
        throw authError(pwCheck.errors.join('; '), 400, "VALIDATION_ERROR");
    }

    const newHash = await hashPassword(newPassword);
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const result = await client.query(
            `SELECT password_hash
             FROM medorbit.users
             WHERE id=$1 AND is_active=true AND deleted_at IS NULL
             FOR UPDATE`,
            [userId]
        );
        if (result.rows.length !== 1) throw authError("Invalid credentials", 401, "UNAUTHORIZED");

        const valid = await comparePassword(currentPassword, result.rows[0].password_hash);
        if (!valid) throw authError("Current password is incorrect", 400, "INVALID_CREDENTIALS");

        await client.query(
            `UPDATE medorbit.users
             SET password_hash=$1,
                 authorization_version=authorization_version+1,
                 updated_at=NOW()
             WHERE id=$2`,
            [newHash, userId]
        );
        await client.query(
            `UPDATE medorbit.user_sessions
             SET revoked_at=NOW()
             WHERE user_id=$1 AND revoked_at IS NULL`,
            [userId]
        );
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
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

        await client.query(
            `UPDATE medorbit.users
             SET password_hash=$1,
                 authorization_version=authorization_version+1,
                 updated_at=NOW()
             WHERE id=$2`,
            [passwordHash, reset.user_id]
        );
        await client.query(`UPDATE medorbit.password_reset_tokens SET used_at=NOW() WHERE id=$1`, [reset.id]);

        // Revoke all sessions
        await client.query(
            `UPDATE medorbit.user_sessions
             SET revoked_at=NOW()
             WHERE user_id=$1 AND revoked_at IS NULL`,
            [reset.user_id]
        );

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
async function verifyEmail(token, email = null) {
    const value = typeof token === 'string' ? token.trim() : '';
    if (!value) {
        throw authError("Verification token is required", 400, "VALIDATION_ERROR");
    }

    const isOtp = /^\d{6}$/.test(value);
    const normalizedEmail = normalizeEmail(email);
    if (isOtp && !normalizedEmail) {
        throw authError("Email is required for verification codes", 400, "VALIDATION_ERROR");
    }

    const client = await db.getClient();
    try {
        await client.query('BEGIN');

        const result = await client.query(
            `SELECT id, user_id, expires_at, verified_at
             FROM medorbit.email_verification_tokens
             WHERE token_hash=$1
             FOR UPDATE`,
            [isOtp ? hashOtp(value, normalizedEmail, env.jwt.secret) : hashToken(value)]
        );

        if (result.rows.length === 0) {
            throw authError("Invalid verification token", 400, "INVALID_VERIFICATION_TOKEN");
        }

        const verification = result.rows[0];
        if (verification.verified_at) {
            throw authError("Verification token has already been used", 409, "VERIFICATION_TOKEN_USED");
        }
        if (new Date(verification.expires_at).getTime() <= Date.now()) {
            throw authError("Verification token has expired", 410, "VERIFICATION_TOKEN_EXPIRED");
        }

        await client.query(
            `UPDATE medorbit.users SET email_verified=true, updated_at=NOW() WHERE id=$1`,
            [verification.user_id]
        );

        await client.query(
            `UPDATE medorbit.email_verification_tokens
             SET verified_at=NOW()
             WHERE user_id=$1 AND verified_at IS NULL`,
            [verification.user_id]
        );

        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Resend verification email
 * - Invalidates old token, generates new one
 * - Does NOT reveal if email exists
 */
async function resendVerification(email) {
    const normalizedEmail = normalizeEmail(email);
    const client = await db.getClient();

    try {
        await client.query('BEGIN');

        const result = await client.query(
            `SELECT id, email_verified
             FROM medorbit.users
             WHERE email=$1 AND deleted_at IS NULL
             FOR UPDATE`,
            [normalizedEmail]
        );

        if (result.rows.length === 0 || result.rows[0].email_verified) {
            await client.query('COMMIT');
            return;
        }

        const user = result.rows[0];
        await client.query(
            `UPDATE medorbit.email_verification_tokens
             SET verified_at=NOW()
             WHERE user_id=$1 AND verified_at IS NULL`,
            [user.id]
        );

        await queueVerificationEmail(client, normalizedEmail, user.id);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = {
    register, login, googleLogin, refresh, logout, changePassword,
    forgotPassword, resetPassword, verifyEmail, resendVerification
};
