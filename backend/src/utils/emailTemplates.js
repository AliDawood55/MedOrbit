// src/utils/emailTemplates.js
// Responsive HTML email templates with MedOrbit branding

const BRAND = 'MedOrbit';
const SUPPORT_EMAIL = 'support@medorbit.ps';

function baseTemplate(title, bodyContent) {
    return `
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title} - ${BRAND}</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f7fb;font-family:'Segoe UI',Tahoma,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f7fb;">
        <tr>
            <td align="center" style="padding:40px 20px;">
                <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
                    <!-- Header -->
                    <tr>
                        <td style="background:linear-gradient(135deg,#2563EB,#1d4ed8);padding:30px 40px;text-align:center;">
                            <h1 style="color:#ffffff;margin:0;font-size:24px;font-weight:700;">${BRAND}</h1>
                            <p style="color:#bfdbfe;margin:5px 0 0;font-size:14px;">Smart Healthcare AI Platform</p>
                        </td>
                    </tr>
                    <!-- Body -->
                    <tr>
                        <td style="padding:40px;">
                            ${bodyContent}
                        </td>
                    </tr>
                    <!-- Footer -->
                    <tr>
                        <td style="background-color:#f8fafc;padding:20px 40px;text-align:center;border-top:1px solid #e2e8f0;">
                            <p style="color:#64748b;font-size:12px;margin:0;">&copy; 2026 ${BRAND}. All rights reserved.</p>
                            <p style="color:#64748b;font-size:12px;margin:5px 0 0;">
                                <a href="mailto:${SUPPORT_EMAIL}" style="color:#2563EB;text-decoration:none;">${SUPPORT_EMAIL}</a>
                            </p>
                            <p style="color:#94a3b8;font-size:11px;margin:10px 0 0;">
                                Nablus, Palestine
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>`;
}

function verifyEmailTemplate(verifyUrl, otpCode = null) {
    const otpBlock = otpCode ? `
        <p style="color:#475569;font-size:15px;line-height:1.6;margin:0 0 12px;">
            Enter this verification code in the MedOrbit mobile app:
        </p>
        <p style="color:#1e293b;font-size:32px;font-weight:700;letter-spacing:8px;text-align:center;margin:0 0 24px;direction:ltr;">
            ${otpCode}
        </p>
        <p style="color:#94a3b8;font-size:12px;margin:0 0 24px;">
            This code expires in 10 minutes.
        </p>
    ` : '';
    const body = `
        <h2 style="color:#1e293b;margin:0 0 20px;font-size:20px;">Verify Your Email Address</h2>
        <p style="color:#475569;font-size:15px;line-height:1.6;margin:0 0 20px;">
            Welcome to ${BRAND}! Verify your email using the mobile code or the web link below.
        </p>
        ${otpBlock}
        <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto 30px;">
            <tr>
                <td style="background-color:#2563EB;border-radius:8px;text-align:center;">
                    <a href="${verifyUrl}" style="display:inline-block;padding:14px 36px;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;">Verify Email</a>
                </td>
            </tr>
        </table>
        <p style="color:#64748b;font-size:13px;line-height:1.5;margin:0 0 10px;">
            Or copy this link into your browser:
        </p>
        <p style="color:#2563EB;font-size:12px;word-break:break-all;margin:0;">
            ${verifyUrl}
        </p>
        <p style="color:#94a3b8;font-size:12px;margin:20px 0 0;">
            This link expires in 24 hours. If you did not create an account, ignore this email.
        </p>
    `;
    return {
        html: baseTemplate('Verify Email', body),
        text: `Welcome to ${BRAND}!${otpCode ? `\n\nYour verification code is:\n${otpCode}\n\nThis code expires in 10 minutes.` : ''}\n\nYou can also verify your email by visiting:\n${verifyUrl}\n\nThis link expires in 24 hours.`
    };
}

function resetPasswordTemplate(resetUrl) {
    const body = `
        <h2 style="color:#1e293b;margin:0 0 20px;font-size:20px;">Reset Your Password</h2>
        <p style="color:#475569;font-size:15px;line-height:1.6;margin:0 0 20px;">
            We received a request to reset your ${BRAND} password. Click the button below to set a new password.
        </p>
        <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto 30px;">
            <tr>
                <td style="background-color:#2563EB;border-radius:8px;text-align:center;">
                    <a href="${resetUrl}" style="display:inline-block;padding:14px 36px;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;">Reset Password</a>
                </td>
            </tr>
        </table>
        <p style="color:#64748b;font-size:13px;line-height:1.5;margin:0 0 10px;">
            Or copy this link into your browser:
        </p>
        <p style="color:#2563EB;font-size:12px;word-break:break-all;margin:0;">
            ${resetUrl}
        </p>
        <p style="color:#94a3b8;font-size:12px;margin:20px 0 0;">
            This link expires in 15 minutes. If you did not request a password reset, ignore this email.
        </p>
    `;
    return {
        html: baseTemplate('Reset Password', body),
        text: `Reset your ${BRAND} password by visiting:\n${resetUrl}\n\nThis link expires in 15 minutes.`
    };
}

function welcomeTemplate(name) {
    const body = `
        <h2 style="color:#1e293b;margin:0 0 20px;font-size:20px;">Welcome to ${BRAND}!</h2>
        <p style="color:#475569;font-size:15px;line-height:1.6;margin:0 0 10px;">
            Hello ${name},
        </p>
        <p style="color:#475569;font-size:15px;line-height:1.6;margin:0 0 20px;">
            Your account has been created successfully. You can now explore healthcare services in Nablus, find nearby clinics, book appointments, and consult our AI medical assistant.
        </p>
        <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto 30px;">
            <tr>
                <td style="background-color:#2563EB;border-radius:8px;text-align:center;">
                    <a href="${process.env.FRONTEND_URL || 'http://localhost:8080/public/'}" style="display:inline-block;padding:14px 36px;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;">Get Started</a>
                </td>
            </tr>
        </table>
        <p style="color:#94a3b8;font-size:12px;margin:20px 0 0;">
            If you did not create this account, please contact support immediately.
        </p>
    `;
    return {
        html: baseTemplate('Welcome', body),
        text: `Welcome to ${BRAND}, ${name}!\n\nYour account has been created successfully.\n\nVisit: ${process.env.FRONTEND_URL || 'http://localhost:8080/public/'}`
    };
}

module.exports = {
    verifyEmailTemplate,
    resetPasswordTemplate,
    welcomeTemplate
};
