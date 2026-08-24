const express = require('express');

const db = require('../config/database');
const { createAudit } = require('../services/audit.service');

const {
    authenticate,
    authorizeAdmin
} = require('../middleware/auth');

const {
    success,
    error
} = require('../utils/response');


const router = express.Router();

function isNonEmptyString(value, maxLength) {
    return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= maxLength;
}

function isTemplateVariables(value) {
    return value === undefined || (value !== null && typeof value === 'object' && !Array.isArray(value));
}



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
        let client;
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

            if (!isNonEmptyString(name, 100) || !isNonEmptyString(type, 50)
                || !isNonEmptyString(subject_en, 255) || !isNonEmptyString(body_html, 100000)
                || (subject_ar !== undefined && subject_ar !== null && (typeof subject_ar !== 'string' || subject_ar.length > 255))
                || (body_text !== undefined && body_text !== null && typeof body_text !== 'string')
                || !isTemplateVariables(variables)) {
                return error(res, "Invalid notification template fields", 400, "VALIDATION_ERROR");
            }



            client = await db.getClient();
            await client.query('BEGIN');
            const result = await client.query(

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

            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'NOTIFICATION_TEMPLATE_CREATED',
                entity_type: 'NOTIFICATION_TEMPLATE',
                entity_id: result.rows[0].id,
                new_values: result.rows[0],
            }, client);
            await client.query('COMMIT');



            return success(
                res,
                result.rows[0],
                "Template created"
            );


        }
        catch (err) {
            if (client) await client.query('ROLLBACK').catch(() => {});
            next(err);
        } finally {
            client?.release();
        }


    });





// UPDATE template

router.put(

    "/:id",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {
        let client;
        try {


            const {

                subject_en,
                subject_ar,
                body_html,
                body_text,
                variables,
                is_active

            } = req.body;

            if ((subject_en !== undefined && !isNonEmptyString(subject_en, 255))
                || (subject_ar !== undefined && subject_ar !== null && (typeof subject_ar !== 'string' || subject_ar.length > 255))
                || (body_html !== undefined && !isNonEmptyString(body_html, 100000))
                || (body_text !== undefined && body_text !== null && typeof body_text !== 'string')
                || (is_active !== undefined && typeof is_active !== 'boolean')
                || !isTemplateVariables(variables)) {
                return error(res, "Invalid notification template fields", 400, "VALIDATION_ERROR");
            }



            client = await db.getClient();
            await client.query('BEGIN');
            const previous = await client.query(
                `SELECT id, name, type, subject_en, subject_ar, body_html, body_text, variables, is_active
                 FROM medorbit.notification_templates WHERE id = $1 FOR UPDATE`,
                [req.params.id]
            );
            if (previous.rowCount === 0) {
                await client.query('ROLLBACK');
                return error(res, "Template not found", 404, "NOT_FOUND");
            }

            const result = await client.query(

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
RETURNING *

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

            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'NOTIFICATION_TEMPLATE_UPDATED',
                entity_type: 'NOTIFICATION_TEMPLATE',
                entity_id: result.rows[0].id,
                old_values: previous.rows[0],
                new_values: result.rows[0],
            }, client);
            await client.query('COMMIT');



            return success(
                res,
                null,
                "Template updated"
            );



        }
        catch (err) {
            if (client) await client.query('ROLLBACK').catch(() => {});
            next(err);
        } finally {
            client?.release();
        }

    });





// DELETE template (soft delete)

router.delete(

    "/:id",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {
        let client;
        try {
            client = await db.getClient();
            await client.query('BEGIN');
            const previous = await client.query(
                `SELECT id, name, type, subject_en, subject_ar, body_html, body_text, variables, is_active
                 FROM medorbit.notification_templates WHERE id = $1 FOR UPDATE`,
                [req.params.id]
            );
            if (previous.rowCount === 0) {
                await client.query('ROLLBACK');
                return error(res, "Template not found", 404, "NOT_FOUND");
            }

            const result = await client.query(

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


            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'NOTIFICATION_TEMPLATE_DEACTIVATED',
                entity_type: 'NOTIFICATION_TEMPLATE',
                entity_id: result.rows[0].id,
                old_values: previous.rows[0],
                new_values: result.rows[0],
            }, client);
            await client.query('COMMIT');


            return success(
                res,
                result.rows[0],
                "Template deleted"
            );


        }

        catch (err) {
            if (client) await client.query('ROLLBACK').catch(() => {});
            next(err);
        } finally {
            client?.release();
        }


    });
module.exports = router;
