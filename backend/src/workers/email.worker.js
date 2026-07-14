// src/workers/email.worker.js


const db = require("../config/database");


const {
    sendEmail
} = require("../services/email.service");








async function processEmails() {


    const result =
        await db.query(

            `
        SELECT *

        FROM public.email_queue

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





    for (const email of result.rows) {


        try {


            await db.query(

                `
                UPDATE public.email_queue

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
                UPDATE public.email_queue

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
                UPDATE public.email_queue

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