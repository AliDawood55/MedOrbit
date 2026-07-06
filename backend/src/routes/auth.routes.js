const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/database');
const { success, error } = require('../utils/response');

const router = express.Router();

// POST /api/auth/register
router.post('/register', async (req, res, next) => {
  try {
    const { email, password, role, firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, gender } = req.body;

    // Validation
    if (!email || !password || !role || !firstNameAr || !lastNameAr || !firstNameEn || !lastNameEn) {
      return error(res, 'Missing required fields', 400, 'VALIDATION_ERROR');
    }

    if (!['patient', 'doctor', 'admin'].includes(role)) {
      return error(res, 'Invalid role', 400, 'VALIDATION_ERROR');
    }

    // Check if email exists
    const existing = await db.query('SELECT id FROM medorbit.users WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return error(res, 'Email already registered', 409, 'DUPLICATE_ENTRY');
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS) || 12);

    // Insert user
    const userResult = await db.query(
      `INSERT INTO medorbit.users (email, password_hash, role, email_verified, preferred_language)
       VALUES ($1, $2, $3, true, 'ar') RETURNING id, email, role, created_at`,
      [email, hashedPassword, role]
    );
    const user = userResult.rows[0];

    // Insert profile
    await db.query(
      `INSERT INTO medorbit.user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, gender)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [user.id, firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone || null, gender || null]
    );

    // Insert role-specific data
    if (role === 'patient') {
      await db.query(
        `INSERT INTO medorbit.patients (user_id) VALUES ($1)`,
        [user.id]
      );
    } else if (role === 'doctor') {
      await db.query(
        `INSERT INTO medorbit.doctors (user_id) VALUES ($1)`,
        [user.id]
      );
    }

    // Generate tokens
    const accessToken = jwt.sign(
      { sub: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m' }
    );

    const refreshToken = jwt.sign(
      { sub: user.id, type: 'refresh' },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d' }
    );

    return success(res, {
      user: {
        id: user.id,
        email: user.email,
        role: user.role
      },
      accessToken,
      refreshToken
    }, 'Registration successful', 201);

  } catch (err) {
    next(err);
  }
});

// POST /api/auth/login
router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return error(res, 'Email and password required', 400, 'VALIDATION_ERROR');
    }

    // Find user
    const result = await db.query(
      `SELECT u.id, u.email, u.password_hash, u.role, u.is_active, u.failed_login_attempts, u.locked_until,
              p.first_name_ar, p.last_name_en
       FROM medorbit.users u
       LEFT JOIN medorbit.user_profiles p ON p.user_id = u.id
       WHERE u.email = $1 AND u.deleted_at IS NULL`,
      [email]
    );

    if (result.rows.length === 0) {
      return error(res, 'Invalid credentials', 401, 'INVALID_CREDENTIALS');
    }

    const user = result.rows[0];

    // Check if locked
    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      return error(res, 'Account locked. Try again later.', 423, 'ACCOUNT_LOCKED');
    }

    // Check active
    if (!user.is_active) {
      return error(res, 'Account deactivated', 403, 'ACCOUNT_INACTIVE');
    }

    // Verify password
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      // Increment failed attempts
      await db.query(
        `UPDATE medorbit.users 
         SET failed_login_attempts = failed_login_attempts + 1,
             locked_until = CASE WHEN failed_login_attempts >= 4 THEN NOW() + INTERVAL '30 minutes' ELSE NULL END
         WHERE id = $1`,
        [user.id]
      );
      return error(res, 'Invalid credentials', 401, 'INVALID_CREDENTIALS');
    }

    // Reset failed attempts
    await db.query(
      `UPDATE medorbit.users SET failed_login_attempts = 0, locked_until = NULL WHERE id = $1`,
      [user.id]
    );

    // Generate tokens
    const accessToken = jwt.sign(
      { sub: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m' }
    );

    const refreshToken = jwt.sign(
      { sub: user.id, type: 'refresh' },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d' }
    );

    // Store refresh token
    await db.query(
      `INSERT INTO medorbit.user_sessions (user_id, refresh_token, ip_address, user_agent, expires_at)
       VALUES ($1, $2, $3, $4, NOW() + INTERVAL '7 days')`,
      [user.id, refreshToken, req.ip, req.headers['user-agent'] || null]
    );

    return success(res, {
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        name: user.first_name_ar || user.last_name_en
      },
      accessToken,
      refreshToken
    }, 'Login successful');

  } catch (err) {
    next(err);
  }
});

// POST /api/auth/refresh
router.post('/refresh', async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    
    if (!refreshToken) {
      return error(res, 'Refresh token required', 401, 'UNAUTHORIZED');
    }

    const decoded = jwt.verify(refreshToken, process.env.JWT_SECRET);
    
    if (decoded.type !== 'refresh') {
      return error(res, 'Invalid token type', 401, 'INVALID_TOKEN');
    }

    // Check if token exists in DB
    const session = await db.query(
      `SELECT s.*, u.email, u.role 
       FROM medorbit.user_sessions s
       JOIN medorbit.users u ON u.id = s.user_id
       WHERE s.refresh_token = $1 AND s.expires_at > NOW()`,
      [refreshToken]
    );

    if (session.rows.length === 0) {
      return error(res, 'Invalid or expired refresh token', 401, 'INVALID_TOKEN');
    }

    const user = session.rows[0];

    const newAccessToken = jwt.sign(
      { sub: user.user_id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m' }
    );

    return success(res, { accessToken: newAccessToken }, 'Token refreshed');

  } catch (err) {
    next(err);
  }
});

module.exports = router;