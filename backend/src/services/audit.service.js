const db = require("../config/database");


async function createAudit({

    user_id = null,
    user_role = null,
    action,
    entity_type = null,
    entity_id = null,
    old_values = null,
    new_values = null,
    ip_address = null,
    user_agent = null

}) {


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
new_values,
ip_address,
user_agent

)

VALUES

(

$1,
$2,
$3,
$4,
$5,
$6,
$7,
$8,
$9

)

        `,

        [

            user_id,
            user_role,
            action,
            entity_type,
            entity_id,
            old_values,
            new_values,
            ip_address,
            user_agent

        ]

    );


}


module.exports = {

    createAudit

};