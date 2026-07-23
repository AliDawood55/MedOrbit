const express = require('express');

const db = require('../config/database');

const {
    success,
    error
} = require('../utils/response');

const {
    authenticate
} = require('../middleware/auth');


const router = express.Router();



/*
GET USER NOTIFICATIONS

GET /api/notifications

*/
router.get(
    "/",
    authenticate,
    async (req, res, next) => {


        try {


            const userId = req.user.sub;


            const result = await db.query(

                `
                SELECT

                id,
                notification_type,
                title_ar,
                title_en,
                message_ar,
                message_en,
                is_read,
                read_at,
                created_at

                FROM medorbit.notifications

                WHERE user_id=$1

                ORDER BY created_at DESC

                LIMIT 50

                `,
                [
                    userId
                ]

            );


            return success(
                res,
                result.rows,
                "Notifications retrieved"
            );


        }
        catch (err) {

            next(err);

        }


    }
);





/*
MARK ONE NOTIFICATION READ


PATCH
/api/notifications/:id/read

*/
router.put(

    "/:id/read",

    authenticate,

    async (req, res, next) => {


        try {


            const userId = req.user.sub;


            const result =
                await db.query(

                    `
                UPDATE medorbit.notifications

                SET

                is_read=true,

                read_at=NOW()

                WHERE id=$1

                AND user_id=$2

                RETURNING *

                `,

                    [
                        req.params.id,
                        userId
                    ]

                );



            if (result.rows.length === 0) {

                return error(
                    res,
                    "Notification not found",
                    404,
                    "NOT_FOUND"
                );

            }



            return success(
                res,
                result.rows[0],
                "Notification marked as read"
            );



        }
        catch (err) {

            next(err);

        }

    }

);






/*
MARK ALL READ


PATCH
/api/notifications/read-all

*/

router.patch(

    "/read-all",

    authenticate,

    async (req, res, next) => {


        try {


            const userId = req.user.sub;


            const result =
                await db.query(

                    `

                UPDATE medorbit.notifications

                SET

                is_read=true,

                read_at=NOW()

                WHERE user_id=$1

                AND is_read=false

                `,

                    [
                        userId
                    ]

                );



            return success(

                res,

                {
                    updated:
                        result.rowCount
                },

                "All notifications marked as read"

            );



        }
        catch (err) {

            next(err);

        }


    }

);







/*
DELETE NOTIFICATION


DELETE
/api/notifications/:id

*/


router.delete(

    "/:id",

    authenticate,

    async (req, res, next) => {


        try {


            const userId = req.user.sub;



            const result =
                await db.query(

                    `

                DELETE FROM medorbit.notifications

                WHERE id=$1

                AND user_id=$2

                RETURNING id

                `,

                    [

                        req.params.id,

                        userId

                    ]

                );



            if (result.rows.length === 0) {

                return error(
                    res,
                    "Notification not found",
                    404,
                    "NOT_FOUND"
                );

            }



            return success(

                res,

                null,

                "Notification deleted"

            );



        }

        catch (err) {

            next(err);

        }


    }

);

// ============================================
// MARK ONE NOTIFICATION AS READ
// PUT /api/notifications/:id/read
// ============================================

router.put('/:id/read', authenticate, async (req, res, next) => {

    try {

        const notificationId = req.params.id;

        const userId = req.user.sub;


        const result = await db.query(
            `
            UPDATE medorbit.notifications

            SET 
                is_read = true,
                read_at = NOW()

            WHERE id = $1
            AND user_id = $2

            RETURNING *
            `,
            [
                notificationId,
                userId
            ]
        );


        if (result.rows.length === 0) {

            return error(
                res,
                "Notification not found",
                404,
                "NOT_FOUND"
            );

        }


        return success(
            res,
            result.rows[0],
            "Notification marked as read"
        );


    } catch (err) {

        next(err);

    }

});

module.exports = router;