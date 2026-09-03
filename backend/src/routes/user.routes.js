const express = require("express");

const router = express.Router();

const db = require("../config/database");

const {
  authenticate
} = require("../middleware/auth");


const {
  success,
  error
} = require("../utils/response");

const upload = require("../middleware/avatarUpload");


/*
GET CURRENT USER PROFILE

GET /api/users/me
*/
router.get(
  "/me",
  authenticate,
  async (req, res, next) => {

    try {


      const userId = req.user.sub;


      const result =
        await db.query(
          `
        SELECT

            u.id,
            u.email,
            u.role,
            CASE WHEN u.role = 'clinic' THEN
              CASE WHEN EXISTS (
                SELECT 1 FROM medorbit.clinics c
                WHERE c.owner_user_id=u.id
                  AND c.is_active=true
                  AND c.approval_status='approved'
              ) THEN 'approved'
              ELSE COALESCE((
                SELECT a.status FROM medorbit.clinic_applications a
                WHERE a.user_id=u.id
                ORDER BY a.submitted_at DESC
                LIMIT 1
              ), 'needs_application')
              END
            ELSE NULL END AS clinic_account_status,
            u.preferred_language,
            to_jsonb(u)->'preferences'->'social_links' AS social_links,
            u.created_at,

            p.first_name_ar,
            p.last_name_ar,
            p.first_name_en,
            p.last_name_en,
            p.phone,
            p.gender,
            p.profile_image_url AS avatar_url,
            p.updated_at AS profile_updated_at,
            p.address,
            p.city


        FROM medorbit.users u

        LEFT JOIN medorbit.user_profiles p

        ON p.user_id=u.id


        WHERE u.id=$1

        AND u.deleted_at IS NULL

        `,
          [
            userId
          ]);


      if (result.rows.length === 0) {

        return error(
          res,
          "User not found",
          404,
          "NOT_FOUND"
        );

      }



      return success(
        res,
        result.rows[0],
        "Profile retrieved"
      );



    }

    catch (err) {

      next(err);

    }

  });





/*
UPDATE PROFILE

PUT /api/users/me
*/
router.put(
  "/me",
  authenticate,
  async (req, res, next) => {


    try {


      const userId = req.user.sub;


      const {

        firstNameAr,
        lastNameAr,
        firstNameEn,
        lastNameEn,
        phone,
        gender,
        address,
        city


      } = req.body;



      await db.query(
        `
UPDATE medorbit.user_profiles

SET

first_name_ar=COALESCE($1,first_name_ar),
last_name_ar=COALESCE($2,last_name_ar),
first_name_en=COALESCE($3,first_name_en),
last_name_en=COALESCE($4,last_name_en),
phone=COALESCE($5,phone),
gender=COALESCE($6,gender),
address=COALESCE($7,address),
city=COALESCE($8,city),
updated_at=NOW()


WHERE user_id=$9

`,
        [
          firstNameAr,
          lastNameAr,
          firstNameEn,
          lastNameEn,
          phone,
          gender,
          address,
          city,
          userId
        ]);



      return success(
        res,
        null,
        "Profile updated successfully"
      );



    }

    catch (err) {

      next(err);

    }


  });







/*
GET SAVED PLACES (across all conversations)

GET /api/users/me/saved-places
*/
router.get(
  "/me/saved-places",
  authenticate,
  async (req, res, next) => {

    try {

      const userId = req.user.sub;

      const result = await db.query(
        `
        SELECT
            id,
            conversation_id,
            place_name,
            place_type,
            latitude,
            longitude,
            address,
            phone,
            distance_km,
            rating,
            created_at

        FROM medorbit.saved_places

        WHERE user_id=$1
        AND is_active=true

        ORDER BY created_at DESC
        LIMIT 50
        `,
        [userId]
      );

      return success(
        res,
        { places: result.rows },
        "Saved places retrieved"
      );

    } catch (err) {
      next(err);
    }
  });

/*
UPDATE PREFERENCES

PUT /api/users/me/preferences
*/
router.put(
  "/me/preferences",
  authenticate,
  async (req, res, next) => {


    try {


      const userId = req.user.sub;


      const { language, social_links: socialLinks } = req.body;
      if (socialLinks !== undefined && ['admin', 'super_admin', 'patient'].includes(req.user.role)) {
        return error(res, 'This account type cannot publish social links', 403, 'FORBIDDEN');
      }
      const allowedLinks = req.user.role === 'patient'
        ? ['whatsapp']
        : ['website', 'instagram', 'facebook', 'tiktok', 'linkedin', 'whatsapp', 'x', 'youtube'];
      let safeSocialLinks = null;
      if (socialLinks !== undefined) {
        if (!socialLinks || typeof socialLinks !== 'object' || Array.isArray(socialLinks)) return error(res, 'Invalid social links', 400, 'VALIDATION_ERROR');
        safeSocialLinks = {};
        for (const [key, value] of Object.entries(socialLinks)) {
          if (!allowedLinks.includes(key) || !String(value || '').trim()) continue;
          const link = String(value).trim();
          if (key === 'whatsapp') {
            const number = link.replace(/[^\d]/g, '').replace(/^00/, '');
            if (number.length < 8 || number.length > 15) return error(res, 'WhatsApp must be a valid international phone number', 400, 'VALIDATION_ERROR');
            safeSocialLinks[key] = number;
            continue;
          }
          if (link.length > 500 || !/^https:\/\//i.test(link)) return error(res, 'Social links must use HTTPS URLs', 400, 'VALIDATION_ERROR');
          safeSocialLinks[key] = link;
        }
      }



      const preferenceColumn = await db.query(
        `SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='medorbit' AND table_name='users' AND column_name='preferences') AS present`
      );
      if (socialLinks !== undefined && !preferenceColumn.rows[0].present) {
        return error(res, 'Social links are unavailable until the existing preferences field is enabled', 409, 'FEATURE_UNAVAILABLE');
      }
      const query = preferenceColumn.rows[0].present ? `
UPDATE medorbit.users
SET preferred_language=COALESCE($1,preferred_language),
    preferences=CASE WHEN $2::jsonb IS NULL THEN preferences ELSE jsonb_set(COALESCE(preferences,'{}'::jsonb),'{social_links}',$2::jsonb,true) END,
    updated_at=NOW()
WHERE id=$3
` : `
UPDATE medorbit.users SET preferred_language=COALESCE($1,preferred_language),updated_at=NOW() WHERE id=$3
`;
      await db.query(
        query,
        [
          language, safeSocialLinks === null ? null : JSON.stringify(safeSocialLinks),
          userId
        ]);



      return success(
        res,
        null,
        "Preferences updated"
      );


    }

    catch (err) {

      next(err);

    }


  });









/*
SOFT DELETE ACCOUNT

DELETE /api/users/me
*/
router.delete(
  "/me",
  authenticate,
  async (req, res, next) => {


    try {


      const userId = req.user.sub;


      const client = await db.getClient();
      try {
        await client.query("BEGIN");
        await client.query(
          `UPDATE medorbit.users
           SET deleted_at=NOW(),
               is_active=false,
               authorization_version=authorization_version+1,
               updated_at=NOW()
           WHERE id=$1`,
          [userId]
        );
        await client.query(
          `UPDATE medorbit.user_sessions
           SET revoked_at=NOW()
           WHERE user_id=$1 AND revoked_at IS NULL`,
          [userId]
        );
        await client.query("COMMIT");
      } catch (err) {
        await client.query("ROLLBACK");
        throw err;
      } finally {
        client.release();
      }



      return success(
        res,
        null,
        "Account deleted successfully"
      );


    }

    catch (err) {

      next(err);

    }


  });

router.post(
  "/me/avatar",
  authenticate,
  upload.single("avatar"),

  async (req, res, next) => {


    try {


      const userId = req.user.sub;


      const url =
        `/uploads/avatars/${req.file.filename}`;


      await db.query(
        `
UPDATE medorbit.user_profiles

SET profile_image_url=$1,
updated_at=NOW()

WHERE user_id=$2

`,
        [
          url,
          userId
        ]);



      return success(
        res,
        {
          avatar: url
        },
        "Avatar uploaded"
      );


    }

    catch (err) {

      next(err);

    }

  });



module.exports = router;
