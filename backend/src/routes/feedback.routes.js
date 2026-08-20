const express = require("express");

const router = express.Router();

const db = require("../config/database");

const {
    authenticate,
    authenticateOptional
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


// =======================================
// GET /api/feedback/stats
// =======================================
// The one product read that stays reachable without an account: the
// home-page feedback dashboard on the public landing page needs it.
//
// What anonymous callers get is deliberately narrower than what the page
// used to serve them. The aggregates (rating distribution, category
// averages, recommend split, total) are non-identifiable and are the whole
// point of a public social-proof panel, so they stay public. The `users`
// array is NOT: it is a list of real MedOrbit users' names and avatars, and
// under the guest policy that is product data about people, not a statistic.
// It is now returned only to an authenticated caller, and the marquee simply
// does not render for guests.

router.get(
    "/stats",

    authenticateOptional,

    async (req, res, next) => {

        try {

            // The users query is skipped outright for guests — no reason to make
            // the one public product endpoint pay for a join it will not send.
            const [totals, distribution, users] = await Promise.all([

                db.query(
                    `SELECT
                         COUNT(*)::int AS total,
                         ROUND(AVG(overall_rating)::numeric, 2) AS average_rating,
                         ROUND(AVG(category_chatbot)::numeric, 2) AS avg_chatbot,
                         ROUND(AVG(category_clinics)::numeric, 2) AS avg_clinics,
                         ROUND(AVG(category_booking)::numeric, 2) AS avg_booking,
                         ROUND(AVG(category_design)::numeric, 2) AS avg_design,
                         COUNT(*) FILTER (WHERE would_recommend = true)::int AS recommend_yes,
                         COUNT(*) FILTER (WHERE would_recommend = false)::int AS recommend_no
                     FROM medorbit.feedback`
                ),

                db.query(
                    `SELECT overall_rating AS rating, COUNT(*)::int AS count
                     FROM medorbit.feedback
                     GROUP BY overall_rating`
                ),

                req.user
                    ? db.query(
                        `SELECT
                             u.id,
                             up.first_name_ar, up.last_name_ar,
                             up.first_name_en, up.last_name_en,
                             up.profile_image_url,
                             MAX(f.created_at) AS last_feedback_at
                         FROM medorbit.feedback f
                         JOIN medorbit.users u ON u.id = f.user_id
                         LEFT JOIN medorbit.user_profiles up ON up.user_id = u.id
                         GROUP BY u.id, up.first_name_ar, up.last_name_ar,
                                  up.first_name_en, up.last_name_en, up.profile_image_url
                         ORDER BY last_feedback_at DESC
                         LIMIT 100`
                    )
                    : { rows: [] }

            ]);

            const distByRating = new Map(
                distribution.rows.map((row) => [row.rating, row.count])
            );

            const ratingDistribution = [1, 2, 3, 4, 5].map((rating) => ({
                rating,
                count: distByRating.get(rating) || 0
            }));

            const t = totals.rows[0] || {};

            const data = {
                total: t.total || 0,
                averageRating: t.average_rating === null ? null : Number(t.average_rating),
                ratingDistribution,
                categoryAverages: {
                    chatbot: t.avg_chatbot === null ? null : Number(t.avg_chatbot),
                    clinics: t.avg_clinics === null ? null : Number(t.avg_clinics),
                    booking: t.avg_booking === null ? null : Number(t.avg_booking),
                    design: t.avg_design === null ? null : Number(t.avg_design)
                },
                recommend: {
                    yes: t.recommend_yes || 0,
                    no: t.recommend_no || 0
                }
            };

            // Omitted entirely (not sent as an empty array) for guests, so the
            // frontend can tell "nobody has left feedback" apart from "you are
            // not signed in" and hide the section instead of claiming there is
            // no feedback yet.
            if (req.user) {
                data.users = users.rows.map((row) => ({
                    id: row.id,
                    nameAr: [row.first_name_ar, row.last_name_ar].filter(Boolean).join(" ") || null,
                    nameEn: [row.first_name_en, row.last_name_en].filter(Boolean).join(" ") || null,
                    avatarUrl: row.profile_image_url || null
                }));
            }

            return success(res, data, "Feedback statistics");

        } catch (err) {
            next(err);
        }
    });


module.exports = router;
