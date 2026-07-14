// src/services/email.service.js


const nodemailer = require("nodemailer");

const db = require("../config/database");





const transporter =
    nodemailer.createTransport({

        host: process.env.EMAIL_HOST,

        port: Number(process.env.EMAIL_PORT),

        secure: false,

        auth: {

            user: process.env.EMAIL_USER,

            pass: process.env.EMAIL_PASSWORD

        },

        tls: {

            rejectUnauthorized: false

        }

    });






/**
 * Send email directly
 */
async function sendEmail(
    email,
    subject,
    html,
    text = null
) {


    const info =
        await transporter.sendMail({

            from: process.env.EMAIL_FROM,

            to: email,

            subject: subject,

            html: html,

            text: text || ""

        });



    console.log(
        "Email sent:",
        info.messageId
    );


    return info;

}







/**
 * Add email to queue
 */
async function queueEmail(
    email,
    subject,
    html,
    text = null
) {


    await db.query(

        `
        INSERT INTO public.email_queue
        (
            recipient_email,
            subject,
            body_html,
            body_text,
            status,
            priority
        )

        VALUES
        (
            $1,
            $2,
            $3,
            $4,
            'pending',
            1
        )

        `,

        [

            email,

            subject,

            html,

            text || ""

        ]

    );


}





module.exports = {


    sendEmail,

    queueEmail


};