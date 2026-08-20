const db = require('../config/database');
const { hashRefreshToken } = require('../utils/token');

/**
 * User Repository
 * All SQL queries related to users, profiles, sessions, and auth.
 * No business logic — only data access.
 */
class UserRepository {

    // ==================== USERS ====================

    async findById(id) {
        const result = await db.query(
            `SELECT u.id, u.email, u.role, u.is_active, u.email_verified, 
                    u.preferred_language, u.created_at, u.failed_login_attempts, u.locked_until,
                    p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
                    p.phone, p.date_of_birth, p.gender, p.profile_image_url, p.address, p.city
             FROM medorbit.users u
             LEFT JOIN medorbit.user_profiles p ON p.user_id = u.id
             WHERE u.id = $1 AND u.deleted_at IS NULL`,
            [id]
        );
        return result.rows[0] || null;
    }

    async findByEmail(email) {
        const result = await db.query(
            `SELECT u.*, p.first_name_ar, p.last_name_en
             FROM medorbit.users u
             LEFT JOIN medorbit.user_profiles p ON p.user_id = u.id
             WHERE u.email = $1 AND u.deleted_at IS NULL`,
            [email]
        );
        return result.rows[0] || null;
    }

    async emailExists(email) {
        const result = await db.query(
            'SELECT id FROM medorbit.users WHERE email = $1',
            [email]
        );
        return result.rows.length > 0;
    }

    async create({ email, passwordHash, role }) {
        const result = await db.query(
            `INSERT INTO medorbit.users (email, password_hash, role, email_verified, preferred_language)
             VALUES ($1, $2, $3, true, 'ar') RETURNING id, email, role, created_at`,
            [email, passwordHash, role]
        );
        return result.rows[0];
    }

    async updateLoginAttempts(userId, failedCount, lockedUntil) {
        if (lockedUntil) {
            await db.query(
                `UPDATE medorbit.users 
                 SET failed_login_attempts = $1, locked_until = $2
                 WHERE id = $3`,
                [failedCount, lockedUntil, userId]
            );
        } else {
            await db.query(
                `UPDATE medorbit.users 
                 SET failed_login_attempts = $1, locked_until = NULL
                 WHERE id = $2`,
                [failedCount, userId]
            );
        }
    }

    async resetLoginAttempts(userId) {
        await db.query(
            `UPDATE medorbit.users SET failed_login_attempts = 0, locked_until = NULL WHERE id = $1`,
            [userId]
        );
    }

    async updateProfile(userId, fields) {
        const {
            firstNameAr, lastNameAr, firstNameEn, lastNameEn,
            phone, dateOfBirth, gender, address
        } = fields;

        await db.query(
            `UPDATE medorbit.user_profiles
             SET first_name_ar = COALESCE($1, first_name_ar),
                 last_name_ar = COALESCE($2, last_name_ar),
                 first_name_en = COALESCE($3, first_name_en),
                 last_name_en = COALESCE($4, last_name_en),
                 phone = COALESCE($5, phone),
                 date_of_birth = COALESCE($6, date_of_birth),
                 gender = COALESCE($7, gender),
                 address = COALESCE($8, address)
             WHERE user_id = $9`,
            [firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, dateOfBirth, gender, address, userId]
        );
    }

    async updateLanguage(userId, language) {
        await db.query(
            `UPDATE medorbit.users SET preferred_language = $1 WHERE id = $2`,
            [language, userId]
        );
    }

    // ==================== PROFILES ====================

    async createProfile({ userId, firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, gender }) {
        await db.query(
            `INSERT INTO medorbit.user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, gender)
             VALUES ($1, $2, $3, $4, $5, $6, $7)`,
            [userId, firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone || null, gender || null]
        );
    }

    // ==================== ROLE-SPECIFIC ====================

    async createPatient(userId) {
        await db.query(
            'INSERT INTO medorbit.patients (user_id) VALUES ($1)',
            [userId]
        );
    }

    async createDoctor(userId) {
        await db.query(
            'INSERT INTO medorbit.doctors (user_id) VALUES ($1)',
            [userId]
        );
    }

    // ==================== SESSIONS ====================

    async createSession({ userId, refreshToken, ipAddress, userAgent }) {
        await db.query(
            `INSERT INTO medorbit.user_sessions (user_id, refresh_token_hash, ip_address, user_agent, expires_at)
             VALUES ($1, $2, $3, $4, NOW() + INTERVAL '7 days')`,
            [userId, hashRefreshToken(refreshToken), ipAddress, userAgent]
        );
    }

    async findSessionByToken(refreshToken) {
        const result = await db.query(
            `SELECT s.*, u.email, u.role 
             FROM medorbit.user_sessions s
             JOIN medorbit.users u ON u.id = s.user_id
             WHERE s.refresh_token_hash = $1 AND s.expires_at > NOW()`,
            [hashRefreshToken(refreshToken)]
        );
        return result.rows[0] || null;
    }
}

module.exports = new UserRepository();
