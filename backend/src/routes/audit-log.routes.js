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
// GET AUDIT LOGS
// GET /api/admin/audit-logs
// =====================================================

router.get(
    "/",
    authenticate,
    authorize("admin"),

    async (req, res, next) => {

        try {


            const {
                user_id,
                entity_type,
                from,
                to
            } = req.query;



            let query = `

            SELECT

            id,
            user_id,
            user_role,
            action,
            entity_type,
            entity_id,
            old_values,
            new_values,
            ip_address,
            user_agent,
            created_at

            FROM medorbit.audit_logs

            WHERE 1=1

            `;



            const params = [];



            if (user_id) {

                params.push(user_id);

                query += `
                AND user_id=$${params.length}
                `;

            }



            if (entity_type) {

                params.push(entity_type);

                query += `
                AND entity_type=$${params.length}
                `;

            }



            if (from) {

                params.push(from);

                query += `
                AND created_at >= $${params.length}
                `;

            }



            if (to) {

                params.push(to);

                query += `
                AND created_at <= $${params.length}
                `;

            }



            query += `

            ORDER BY created_at DESC

            `;



            const result =
                await db.query(
                    query,
                    params
                );



            return success(
                res,
                result.rows,
                "Audit logs retrieved"
            );


        }

        catch (e) {

            next(e);

        }


    }

);



module.exports = router;