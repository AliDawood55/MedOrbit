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

const upload = require("../middleware/upload");


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
            u.preferred_language,
            u.preferences,
            u.created_at,

            p.first_name_ar,
            p.last_name_ar,
            p.first_name_en,
            p.last_name_en,
            p.phone,
            p.gender,
            p.avatar_url,
            p.address,
            p.city


        FROM public.users u

        LEFT JOIN public.user_profiles p

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
UPDATE public.user_profiles

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
UPDATE PREFERENCES

PUT /api/users/me/preferences
*/
router.put(
  "/me/preferences",
  authenticate,
  async (req, res, next) => {


    try {


      const userId = req.user.sub;


      const {
        language,
        preferences
      } = req.body;



      await db.query(
        `

UPDATE public.users

SET

preferred_language=
COALESCE($1,preferred_language),

preferences=
COALESCE($2,preferences),

updated_at=NOW()


WHERE id=$3

`,
        [
          language,
          preferences,
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


      await db.query(
        `

UPDATE public.users

SET

deleted_at=NOW(),
is_active=false


WHERE id=$1


`,
        [
          userId
        ]);



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
UPDATE public.user_profiles

SET avatar_url=$1,
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