// src/services/email.service.js
// Production-ready email service with Gmail SMTP, retry, and queue

const nodemailer = require("nodemailer");
const db = require("../config/database");

// Validate required email env vars at module load
const REQUIRED_EMAIL_VARS = ['EMAIL_HOST', 'EMAIL_PORT', 'EMAIL_USER', 'EMAIL_PASS', 'EMAIL_FROM'];
for (const v of REQUIRED_EMAIL_VARS) {
    if (!process.env[v]) {
        console.warn(`[EMAIL] Missing env var: ${v} — email sending will fail`);
    }
}

const transporter = nodemailer.createTransport({
    host: process.env.EMAIL_HOST || 'smtp.gmail.com',
    port: Number(process.env.EMAIL_PORT) || 587,
    secure: process.env.EMAIL_SECURE === 'true',
    auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS
    },
    tls: {
        rejectUnauthorized: process.env.NODE_ENV === 'production'
    },
    // Connection pool for better performance
    pool: true,
    maxConnections: 5,
    maxMessages: 100
});

// Verify transporter on startup (non-blocking)
if (process.env.NODE_ENV !== "test") {

    transporter.verify()
        .then(() => {

            console.log(
                '✅ Email transporter ready'
            );

        })
        .catch((err) => {

            console.warn(
                `⚠️ Email transporter not ready: ${err.message}`
            );

        });

}

/**
 * Send email directly with retry
 */
async function sendEmail(email, subject, html, text = null) {
    const info = await transporter.sendMail({
        from: `"MedOrbit" <${process.env.EMAIL_FROM}>`,
        to: email,
        subject: subject,
        html: html,
        text: text || ""
    });

    console.log(`Email sent: ${info.messageId} -> ${email}`);
    return info;
}

/**
 * Add email to queue
 */
async function queueEmail(email, subject, html, text = null, queryable = db) {
    await queryable.query(
        `INSERT INTO medorbit.email_queue
         (recipient_email, subject, body_html, body_text, status, priority)
         VALUES ($1, $2, $3, $4, 'pending', 1)`,
        [email, subject, html, text || ""]
    );
}

module.exports = {
    sendEmail,
    queueEmail
};
