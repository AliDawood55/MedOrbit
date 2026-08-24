const express = require('express');

const db = require('../config/database');

const {
    authenticate,
    authorizeAdmin
} = require('../middleware/auth');

const {
    success,
    error
} = require('../utils/response');


const router = express.Router();



// GET ALL templates
router.get(
    "/",
    authenticate,
    authorizeAdmin,

    async (req, res, next) => {

        try {


            const result = await db.query(

                `
SELECT *
FROM medorbit.notification_templates
ORDER BY created_at DESC
`

            );


            return success(
                res,
                result.rows,
                "Templates retrieved"
            );



        }
        catch (err) {

            next(err);

        }


    });




// GET one template

router.get(
    "/:id",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {

        try {


            const result = await db.query(

                `
SELECT *
FROM medorbit.notification_templates
WHERE id=$1
`,
                [
                    req.params.id
                ]

            );


            if (result.rows.length === 0) {

                return error(
                    res,
                    "Template not found",
                    404,
                    "NOT_FOUND"
                );

            }


            return success(
                res,
                result.rows[0],
                "Template retrieved"
            );


        }
        catch (err) {

            next(err);

        }


    });





// CREATE template

router.post(

    "/",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {


        try {


            const {

                name,
                type,
                subject_en,
                subject_ar,
                body_html,
                body_text,
                variables

            } = req.body;



            const result = await db.query(

                `
INSERT INTO medorbit.notification_templates
(
name,
type,
subject_en,
subject_ar,
body_html,
body_text,
variables
)

VALUES
($1,$2,$3,$4,$5,$6,$7)

RETURNING *

`,

                [
                    name,
                    type,
                    subject_en,
                    subject_ar,
                    body_html,
                    body_text,
                    variables
                ]


            );



            return success(
                res,
                result.rows[0],
                "Template created"
            );


        }
        catch (err) {

            next(err);

        }


    });





// UPDATE template

router.put(

    "/:id",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {


        try {


            const {

                subject_en,
                subject_ar,
                body_html,
                body_text,
                variables,
                is_active

            } = req.body;



            await db.query(

                `

UPDATE medorbit.notification_templates

SET

subject_en = COALESCE($1,subject_en),

subject_ar = COALESCE($2,subject_ar),

body_html = COALESCE($3,body_html),

body_text = COALESCE($4,body_text),

variables = COALESCE($5,variables),

is_active = COALESCE($6,is_active)

WHERE id=$7

`,

                [
                    subject_en,
                    subject_ar,
                    body_html,
                    body_text,
                    variables,
                    is_active,
                    req.params.id
                ]

            );



            return success(
                res,
                null,
                "Template updated"
            );



        }
        catch (err) {

            next(err);

        }

    });





// DELETE template (soft delete)

router.delete(

    "/:id",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {


        try {


            const result = await db.query(

                `
                UPDATE medorbit.notification_templates

                SET 
                    is_active = false,
                    updated_at = CURRENT_TIMESTAMP

                WHERE id = $1

                RETURNING *
                `,

                [
                    req.params.id
                ]

            );


            if (result.rows.length === 0) {

                return error(
                    res,
                    "Template not found",
                    404,
                    "NOT_FOUND"
                );

            }


            return success(
                res,
                result.rows[0],
                "Template deleted"
            );


        }

        catch (err) {

            next(err);

        }


    });
module.exports = router;
