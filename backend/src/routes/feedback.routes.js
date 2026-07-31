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


// =======================================
// POST /api/feedback
// =======================================
// Platform feedback (feedback.html) — any authenticated user, patient or
// doctor. user_id is always resolved from the JWT (req.user.sub), never
// from the request body.

router.post(
    "/",
    authenticate,

    async (req, res, next) => {

        try {

            const {
                overallRating,
                categoryRatings,
                comment,
                wouldRecommend
            } = req.body;

            const rating = Number(overallRating);

            if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
                return error(res, "overallRating must be an integer from 1 to 5", 400, "VALIDATION_ERROR");
            }

            const categories = categoryRatings || {};
            const recommend = wouldRecommend === "yes" ? true : (wouldRecommend === "no" ? false : null);

            const result = await db.query(
                `INSERT INTO medorbit.feedback
                     (user_id, overall_rating, category_chatbot, category_clinics, category_booking, category_design, comment, would_recommend)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                 RETURNING id, overall_rating, created_at`,
                [
                    req.user.sub,
                    rating,
                    Number(categories.chatbot) || null,
                    Number(categories.clinics) || null,
                    Number(categories.booking) || null,
                    Number(categories.design) || null,
                    comment || null,
                    recommend
                ]
            );

            return success(res, result.rows[0], "Feedback submitted", 201);

        } catch (err) {
            next(err);
        }
    });


module.exports = router;
