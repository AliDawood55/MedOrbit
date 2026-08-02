// src/workers/email.worker.js


const db = require("../config/database");


const {
    sendEmail
} = require("../services/email.service");








async function processEmails() {


    // This runs on an unawaited setInterval (see app.js), so a rejection
    // here is an unhandled promise rejection that crashes the whole process
    // — not just this one tick. That happened for real: a fresh database
    // (no seed data, e.g. in CI) has no medorbit.email_queue table yet, the
    // SELECT throws relation "medorbit.email_queue" does not exist, and the
    // entire backend died in a restart loop every ~10s. Catching here just
    // skips this tick and logs it; the per-email try/catch below is
    // unrelated (it already handled individual send failures gracefully).
    let result;

    try {

        result =
            await db.query(

                `
        SELECT *

        FROM medorbit.email_queue

        WHERE status='pending'

        AND attempts < 3

        AND
        (
            scheduled_for IS NULL

            OR

            scheduled_for <= NOW()
        )

        ORDER BY priority DESC, created_at

        LIMIT 10

        `

            );

    }

    catch (error) {

        console.log(
            "Email queue check failed:",
            error.message
        );

        return;

    }





    for (const email of result.rows) {


        try {


            await db.query(

                `
                UPDATE medorbit.email_queue

                SET
                    attempts = attempts + 1,
                    last_attempt_at = NOW()

                WHERE id=$1

                `,

                [
                    email.id
                ]

            );




            await sendEmail(

                email.recipient_email,

                email.subject,

                email.body_html,

                email.body_text

            );





            await db.query(

                `
                UPDATE medorbit.email_queue

                SET
                    status='sent',
                    sent_at=NOW()

                WHERE id=$1

                `,

                [
                    email.id
                ]

            );




        }


        catch (error) {


            console.log(
                "Email failed:",
                error.message
            );



            await db.query(

                `
                UPDATE medorbit.email_queue

                SET

                status =
                CASE
                    WHEN attempts >= 3
                    THEN 'failed'
                    ELSE 'pending'
                END,


                error_message=$1

                WHERE id=$2

                `,


                [

                    error.message,

                    email.id

                ]

            );


        }


    }


}






module.exports = {

    processEmails

};