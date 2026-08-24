const router = require("express").Router();

const {
    authenticate,
    authorizeAdmin
} = require("../middleware/auth");

const {
    success,
    error
} = require("../utils/response");

const db = require("../config/database");
const { createAudit } = require('../services/audit.service');




// =====================================================
// GET ALL SETTINGS
// GET /api/admin/system-settings
// =====================================================

router.get(
    "/",
    authenticate,
    authorizeAdmin,

    async (req, res, next) => {

        try {

            const result =
                await db.query(
                    `
                    SELECT
                    id,
                    setting_key,
                    setting_value,
                    description,
                    is_public,
                    requires_restart,
                    updated_at,
                    updated_by

                    FROM medorbit.system_settings

                    ORDER BY setting_key
                    `
                );


            return success(
                res,
                result.rows,
                "System settings retrieved"
            );


        }
        catch (e) {

            next(e);

        }

    }

);



// =====================================================
// GET ONE SETTING
// GET /api/admin/system-settings/:key
// =====================================================


router.get(
    "/:key",

    authenticate,
    authorizeAdmin,

    async (req, res, next) => {


        try {


            const result =
                await db.query(

                    `
                    SELECT *

                    FROM medorbit.system_settings

                    WHERE setting_key=$1
                    `,

                    [
                        req.params.key
                    ]

                );



            if (!result.rows.length) {

                return error(
                    res,
                    "Setting not found",
                    404,
                    "NOT_FOUND"
                );

            }



            return success(
                res,
                result.rows[0],
                "Setting retrieved"
            );


        }

        catch (e) {

            next(e);

        }


    }

);







// =====================================================
// UPDATE ONE SETTING
// PUT /api/admin/system-settings/:key
// =====================================================


router.put(

    "/:key",

    authenticate,
    authorizeAdmin,


    async (req, res, next) => {


        try {


            const {
                value,
                requires_restart = false
            } = req.body;



            if (value === undefined) {

                return error(
                    res,
                    "value is required",
                    400,
                    "VALIDATION_ERROR"
                );

            }



            const old =
                await db.query(

                    `
                    SELECT *

                    FROM medorbit.system_settings

                    WHERE setting_key=$1
                    `,

                    [
                        req.params.key
                    ]

                );



            if (!old.rows.length) {

                return error(
                    res,
                    "Setting not found",
                    404,
                    "NOT_FOUND"
                );

            }





            const updated =
                await db.query(

                    `
                    UPDATE medorbit.system_settings

                    SET

                    setting_value=$2,

                    requires_restart=$3,

                    updated_at=NOW(),

                    updated_by=$4

                    WHERE setting_key=$1

                    RETURNING *

                    `,

                    [

                        req.params.key,

                        JSON.stringify(value),

                        requires_restart,

                        req.user.sub

                    ]

                );






            await createAudit({ user_id: req.user.sub, user_role: req.user.role, action: 'SYSTEM_SETTING_UPDATED', entity_type: 'SYSTEM_SETTING', entity_id: updated.rows[0].id, old_values: old.rows[0], new_values: updated.rows[0] });






            return success(

                res,

                updated.rows[0],

                "Setting updated"

            );


        }

        catch (e) {

            next(e);

        }


    }


);






// =====================================================
// UPDATE MULTIPLE SETTINGS
// PUT /api/admin/system-settings
// =====================================================


router.put(

    "/",

    authenticate,
    authorizeAdmin,


    async (req, res, next) => {


        const client =
            await db.getClient();



        try {


            const {
                settings
            } = req.body;



            if (!Array.isArray(settings)) {


                return error(
                    res,
                    "settings array required",
                    400,
                    "VALIDATION_ERROR"
                );

            }



            await client.query("BEGIN");



            const results = [];



            for (const item of settings) {


                const result =
                    await client.query(

                        `
                        UPDATE medorbit.system_settings

                        SET

                        setting_value=$2,

                        requires_restart=$3,

                        updated_at=NOW(),

                        updated_by=$4

                        WHERE setting_key=$1

                        RETURNING *

                        `,


                        [

                            item.key,

                            JSON.stringify(item.value),

                            item.requires_restart || false,

                            req.user.sub

                        ]

                    );


                results.push(result.rows[0]);
                if (result.rows[0]) {
                    await createAudit({ user_id: req.user.sub, user_role: req.user.role, action: 'SYSTEM_SETTING_UPDATED', entity_type: 'SYSTEM_SETTING', entity_id: result.rows[0].id, new_values: result.rows[0] }, client);
                }


            }



            await client.query("COMMIT");



            return success(

                res,

                results,

                "Settings updated"

            );



        }

        catch (e) {

            await client.query("ROLLBACK");

            next(e);

        }

        finally {

            client.release();

        }


    }


);





module.exports = router;
