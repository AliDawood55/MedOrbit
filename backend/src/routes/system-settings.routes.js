const router = require("express").Router();

const {
    authenticate,
    authorize
} = require("../middleware/auth");

const {
    success,
    error
} = require("../utils/response");

const db = require("../config/database");




// =====================================================
// GET ALL SETTINGS
// GET /api/admin/system-settings
// =====================================================

router.get(
    "/",
    authenticate,
    authorize("admin"),

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
    authorize("admin"),

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
    authorize("admin"),


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






            // Save audit log

            await db.query(

                `
                INSERT INTO medorbit.audit_logs
                (
                    user_id,
                    user_role,
                    action,
                    entity_type,
                    entity_id,
                    old_values,
                    new_values
                )

                VALUES

                (
                    $1,
                    'admin',
                    'UPDATE',
                    'system_settings',
                    $2,
                    $3,
                    $4
                )
                `,


                [

                    req.user.sub,

                    updated.rows[0].id,

                    JSON.stringify(old.rows[0]),

                    JSON.stringify(updated.rows[0])

                ]

            );






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
    authorize("admin"),


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