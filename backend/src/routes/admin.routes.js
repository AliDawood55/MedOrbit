const router = require("express").Router();


const db = require("../config/database");


const {

    authenticate,
    authorize

} = require("../middleware/auth");


const {

    success,
    error

} = require("../utils/response");


const {

    createAudit

} = require("../services/audit.service");



// =====================================
// GET ALL USERS
// =====================================


router.get(

    "/users",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const {

                role,
                active,
                search

            } = req.query;



            let query =

                `

SELECT

u.id,
u.email,
u.role,
u.is_active,
u.email_verified,

up.first_name_en,
up.last_name_en,
up.phone,
up.city

FROM medorbit.users u

LEFT JOIN medorbit.user_profiles up

ON u.id=up.user_id

WHERE 1=1

            `;


            const values = [];


            if (role) {

                values.push(role);

                query +=

                    `

AND u.role=$${values.length}

                `;

            }


            if (active) {

                values.push(active === "true");

                query +=

                    `

AND u.is_active=$${values.length}

                `;

            }



            if (search) {

                values.push(`%${search}%`);

                query +=

                    `

AND

(

u.email ILIKE $${values.length}

OR

up.first_name_en ILIKE $${values.length}

OR

up.last_name_en ILIKE $${values.length}

)

                `;

            }



            query +=

                `

ORDER BY u.created_at DESC

            `;



            const result =

                await db.query(

                    query,
                    values

                );


            return success(

                res,
                result.rows,
                "Users retrieved"

            );


        }

        catch (err) {

            next(err);

        }


    }

);





// =====================================
// DEACTIVATE USER
// =====================================


router.put(

    "/users/:id/deactivate",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const oldUser =

                await db.query(

                    `

SELECT *

FROM medorbit.users

WHERE id=$1

                `,

                    [

                        req.params.id

                    ]

                );


            if (!oldUser.rows.length) {

                return error(

                    res,
                    "User not found",
                    404,
                    "NOT_FOUND"

                );

            }



            const result =

                await db.query(

                    `

UPDATE medorbit.users

SET

is_active=false

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

                action: "USER_DEACTIVATED",

                entity_type: "USER",

                entity_id: req.params.id,

                old_values: oldUser.rows[0],

                new_values: result.rows[0],

                ip_address: req.ip,

                user_agent: req.headers["user-agent"]

            });



            return success(

                res,
                result.rows[0],
                "User deactivated"

            );


        }

        catch (err) {

            next(err);

        }


    }

);




// =====================================
// REACTIVATE USER
// =====================================


router.put(

    "/users/:id/reactivate",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const oldUser =

                await db.query(

                    `
SELECT *
FROM medorbit.users
WHERE id=$1
                `,

                    [

                        req.params.id

                    ]

                );


            const result =

                await db.query(

                    `
UPDATE medorbit.users

SET is_active=true

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

                action: "USER_REACTIVATED",

                entity_type: "USER",

                entity_id: req.params.id,

                old_values: oldUser.rows[0],

                new_values: result.rows[0],

                ip_address: req.ip,

                user_agent: req.headers["user-agent"]

            });



            return success(

                res,
                result.rows[0],
                "User reactivated"

            );


        }

        catch (err) {

            next(err);

        }


    }

);




// =====================================
// CHANGE ROLE
// =====================================


router.put(

    "/users/:id/role",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const {

                role

            } = req.body;


            const allowed =

                [

                    "patient",
                    "doctor",
                    "admin"

                ];


            if (

                !allowed.includes(role)

            ) {

                return error(

                    res,
                    "Invalid role",
                    400,
                    "INVALID_ROLE"

                );

            }



            const oldUser =

                await db.query(

                    `
SELECT *
FROM medorbit.users
WHERE id=$1
                `,

                    [

                        req.params.id

                    ]

                );



            const result =

                await db.query(

                    `
UPDATE medorbit.users

SET role=$1

WHERE id=$2

RETURNING *
                `,

                    [

                        role,
                        req.params.id

                    ]

                );



            await createAudit({

                user_id: req.user.sub,

                user_role: req.user.role,

                action: "ROLE_CHANGED",

                entity_type: "USER",

                entity_id: req.params.id,

                old_values: oldUser.rows[0],

                new_values: result.rows[0],

                ip_address: req.ip,

                user_agent: req.headers["user-agent"]

            });



            return success(

                res,
                result.rows[0],
                "Role updated"

            );


        }

        catch (err) {

            next(err);

        }


    }

);



module.exports = router;