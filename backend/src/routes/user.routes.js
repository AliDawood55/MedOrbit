const express = require('express');
const db = require('../config/database');
const { success, error } = require('../utils/response');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// GET /api/users/me
router.get('/me', authenticate, async (req, res, next) => {
  try {
    const userId = req.user.sub;

    const result = await db.query(
      `SELECT u.id, u.email, u.role, u.preferred_language, u.is_active, u.email_verified,
              p.first_name_ar, p.last_name_ar, p.first_name_en, p.last_name_en,
              p.phone, p.date_of_birth, p.gender, p.profile_image_url, p.address, p.city
       FROM public.users u
       LEFT JOIN public.user_profiles p ON p.user_id = u.id
       WHERE u.id = $1 AND u.deleted_at IS NULL`,
      [userId]
    );

    if (result.rows.length === 0) {
      return error(res, 'User not found', 404, 'NOT_FOUND');
    }

    return success(res, result.rows[0], 'Profile retrieved');

  } catch (err) {
    next(err);
  }
});

// PUT /api/users/me
router.put('/me', authenticate, async (req, res, next) => {
  try {
    const userId = req.user.sub;
    const { firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, dateOfBirth, gender, address, preferredLanguage } = req.body;

    await db.query(
      `UPDATE public.user_profiles
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

    if (preferredLanguage) {
      await db.query(
        `UPDATE public.users SET preferred_language = $1 WHERE id = $2`,
        [preferredLanguage, userId]
      );
    }

    return success(res, null, 'Profile updated');

  } catch (err) {
    next(err);
  }
});

module.exports = router;