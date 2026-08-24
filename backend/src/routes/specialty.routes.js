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



// ======================================
// GET ALL SPECIALTIES (PUBLIC)
// ======================================

router.get(
    "/",
    authenticate,
    async (req, res, next) => {

        try {

            const result = await db.query(
                `
                SELECT *
                FROM medorbit.specialties
                WHERE is_active = true
                ORDER BY name_en
                `
            );

            return success(
                res,
                result.rows,
                "Specialties retrieved"
            );


        } catch (err) {

            next(err);

        }

    }
);



// ======================================
// GET ONE SPECIALTY (PUBLIC)
// ======================================

router.get(
    "/:id",
    authenticate,
    async (req, res, next) => {
        try {
            const result = await db.query(
                `
                SELECT *
                FROM medorbit.specialties
                WHERE id=$1
                AND is_active=true
                `,
                [
                    req.params.id
                ]
            );
            if (result.rows.length === 0) {

                return error(
                    res,
                    "Specialty not found",
                    404,
                    "NOT_FOUND"
                );

            }


            return success(
                res,
                result.rows[0],
                "Specialty retrieved"
            );


        }
        catch (err) {
            next(err);
        }


    }
);





// ======================================
// CREATE SPECIALTY (ADMIN)
// ======================================

router.post(
    "/",
    authenticate,
    authorizeAdmin,

    async (req, res, next) => {
        let client;
        try {


            const {

                name_ar,
                name_en,
                description_ar,
                description_en,
                icon

            } = req.body;



            client = await db.getClient();
            await client.query('BEGIN');
            const result = await client.query(
                `
                INSERT INTO medorbit.specialties
                (
                    name_ar,
                    name_en,
                    description_ar,
                    description_en,
                    icon
                )

                VALUES
                ($1,$2,$3,$4,$5)

                RETURNING *
                `,
                [
                    name_ar,
                    name_en,
                    description_ar,
                    description_en,
                    icon
                ]
            );

            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'SPECIALTY_CREATED',
                entity_type: 'SPECIALTY',
                entity_id: result.rows[0].id,
                new_values: result.rows[0],
            }, client);
            await client.query('COMMIT');



            return success(
                res,
                result.rows[0],
                "Specialty created"
            );



        }
        catch (err) {
            if (client) await client.query('ROLLBACK').catch(() => {});
            next(err);
        } finally {
            client?.release();
        }


    }
);





// ======================================
// UPDATE SPECIALTY (ADMIN)
// ======================================


router.put(
    "/:id",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {
        let client;
        try {


            const {

                name_ar,
                name_en,
                description_ar,
                description_en,
                icon,
                is_active

            } = req.body;



            client = await db.getClient();
            await client.query('BEGIN');
            const previous = await client.query(
                `SELECT id, name_ar, name_en, description_ar, description_en, icon, is_active
                 FROM medorbit.specialties WHERE id = $1 FOR UPDATE`,
                [req.params.id]
            );
            if (previous.rowCount === 0) {
                await client.query('ROLLBACK');
                return error(res, "Specialty not found", 404, "NOT_FOUND");
            }

            const result = await client.query(
                `
                UPDATE medorbit.specialties

                SET

                name_ar = COALESCE($1,name_ar),

                name_en = COALESCE($2,name_en),

                description_ar = COALESCE($3,description_ar),

                description_en = COALESCE($4,description_en),

                icon = COALESCE($5,icon),

                is_active = COALESCE($6,is_active)

                WHERE id=$7

                RETURNING *

                `,
                [
                    name_ar,
                    name_en,
                    description_ar,
                    description_en,
                    icon,
                    is_active,
                    req.params.id
                ]
            );



            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'SPECIALTY_UPDATED',
                entity_type: 'SPECIALTY',
                entity_id: result.rows[0].id,
                old_values: previous.rows[0],
                new_values: result.rows[0],
            }, client);
            await client.query('COMMIT');



            return success(
                res,
                result.rows[0],
                "Specialty updated"
            );



        }
        catch (err) {
            if (client) await client.query('ROLLBACK').catch(() => {});
            next(err);
        } finally {
            client?.release();
        }


    }
);





// ======================================
// DELETE (SOFT DELETE)
// ======================================


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
                `SELECT id, name_ar, name_en, description_ar, description_en, icon, is_active
                 FROM medorbit.specialties WHERE id = $1 FOR UPDATE`,
                [req.params.id]
            );
            if (previous.rowCount === 0) {
                await client.query('ROLLBACK');
                return error(res, "Specialty not found", 404, "NOT_FOUND");
            }

            const result = await client.query(

                `
                UPDATE medorbit.specialties

                SET is_active=false

                WHERE id=$1

                RETURNING *

                `,
                [
                    req.params.id
                ]

            );



            await createAudit({
                user_id: req.user.sub,
                user_role: req.user.role,
                action: 'SPECIALTY_DEACTIVATED',
                entity_type: 'SPECIALTY',
                entity_id: result.rows[0].id,
                old_values: previous.rows[0],
                new_values: result.rows[0],
            }, client);
            await client.query('COMMIT');



            return success(
                res,
                result.rows[0],
                "Specialty deleted"
            );



        }
        catch (err) {
            if (client) await client.query('ROLLBACK').catch(() => {});
            next(err);
        } finally {
            client?.release();
        }


    }
);



module.exports = router;
