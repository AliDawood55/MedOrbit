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
const {
    resolveBilingualUserContent,
    withCanonicalContent
} = require("../utils/bilingualUserContent");

function isRating(value) {
    return Number.isInteger(value) && value >= 1 && value <= 5;
}




// =====================================================
// POST REVIEW
// POST /api/doctors/:id/reviews
// =====================================================

router.post(
    "/doctors/:id/reviews",

    authenticate,

    async (req, res, next) => {

        try {


            const doctor_id = req.params.id;


            const patient =
                await db.query(
                    `
                SELECT id
                FROM medorbit.patients
                WHERE user_id=$1
                `,
                    [
                        req.user.sub
                    ]
                );


            if (!patient.rows.length) {

                return error(
                    res,
                    "Patient profile not found",
                    404,
                    "PATIENT_NOT_FOUND"
                );

            }


            const patient_id =
                patient.rows[0].id;



            const {
                appointment_id,
                rating,
                professionalism_rating,
                treatment_rating,
                communication_rating
            } = req.body;
            const reviewText = resolveBilingualUserContent(req.body, {
                canonicalKey: 'review_text',
                legacyArKeys: ['review_text_ar', 'reviewTextAr'],
                legacyEnKeys: ['review_text_en', 'reviewTextEn'],
                label: 'Review text'
            });

            if (!isRating(rating)
                || !isRating(professionalism_rating)
                || !isRating(treatment_rating)
                || !isRating(communication_rating)) {
                return error(res, "Ratings must be whole numbers from 1 to 5", 400, "VALIDATION_ERROR");
            }

            if ((reviewText.ar && reviewText.ar.length > 5000)
                || (reviewText.en && reviewText.en.length > 5000)) {
                return error(res, "Review text is too long", 400, "VALIDATION_ERROR");
            }



            // Check appointment

            const appointment =
                await db.query(
                    `
                SELECT *
                FROM medorbit.appointments
                WHERE id=$1
                AND patient_id=$2
                AND doctor_id=$3
                AND status='completed'
                `,
                    [
                        appointment_id,
                        patient_id,
                        doctor_id
                    ]
                );



            if (!appointment.rows.length) {

                return error(
                    res,
                    "Completed appointment required",
                    400,
                    "INVALID_APPOINTMENT"
                );

            }

            // The canonical database enforces one review per appointment.
            // Check first so a normal duplicate attempt receives a stable API
            // response instead of a raw PostgreSQL unique-constraint error.
            const existingReview = await db.query(
                `SELECT id
                 FROM medorbit.doctor_reviews
                 WHERE appointment_id=$1`,
                [appointment_id]
            );

            if (existingReview.rows.length) {
                return error(
                    res,
                    "A review already exists for this appointment",
                    409,
                    "DUPLICATE_REVIEW"
                );
            }





            const result =
                await db.query(

                    `
                INSERT INTO medorbit.doctor_reviews
                (
                appointment_id,
                patient_id,
                doctor_id,
                rating,
                review_text_ar,
                review_text_en,
                professionalism_rating,
                treatment_rating,
                communication_rating
                )

                VALUES
                (
                $1,$2,$3,$4,$5,$6,$7,$8,$9
                )

                RETURNING id, rating, review_text_ar, review_text_en,
                          professionalism_rating, treatment_rating,
                          communication_rating, created_at

                `,

                    [

                        appointment_id,
                        patient_id,
                        doctor_id,
                        rating,
                        reviewText.ar,
                        reviewText.en,
                        professionalism_rating,
                        treatment_rating,
                        communication_rating

                    ]

                );




            // recalculate rating

            await db.query(

                `
                UPDATE medorbit.doctors

                SET average_rating =
                (
                    SELECT AVG(rating)
                    FROM medorbit.doctor_reviews
                    WHERE doctor_id=$1
                )

                WHERE id=$1
                `,

                [
                    doctor_id
                ]

            );



            return success(
                res,
                withCanonicalContent(result.rows[0], 'review_text', 'review_text_ar', 'review_text_en'),
                "Review submitted",
                201
            );



        }
        catch (err) {

            // Keep the concurrent-request race stable as well. The unique
            // database constraint remains the final authority.
            if (err.code === "23505") {
                return error(
                    res,
                    "A review already exists for this appointment",
                    409,
                    "DUPLICATE_REVIEW"
                );
            }

            next(err);

        }

    });







// =====================================================
// GET REVIEWS
// GET /api/doctors/:id/reviews
// =====================================================


router.get(
    "/doctors/:id/reviews",

    authenticate,

    async (req, res, next) => {


        try {


            const result =
                await db.query(

                    `
                SELECT

                r.id,
                r.rating,
                r.review_text_ar,
                r.review_text_en,
                r.professionalism_rating,
                r.treatment_rating,
                r.communication_rating,
                r.created_at,

                p.first_name_en,
                p.last_name_en,
                p.first_name_ar,
                p.last_name_ar


                FROM medorbit.doctor_reviews r


                JOIN medorbit.user_profiles p

                ON p.user_id =
                (
                    SELECT user_id
                    FROM medorbit.patients
                    WHERE id=r.patient_id
                )


                WHERE doctor_id=$1

                AND is_visible=true

                ORDER BY created_at DESC

                `,

                    [
                        req.params.id
                    ]

                );



            return success(
                res,
                result.rows.map((review) => withCanonicalContent(review, 'review_text', 'review_text_ar', 'review_text_en')),
                "Reviews retrieved"
            );


        }

        catch (err) {

            next(err);

        }


    });





module.exports = router;
