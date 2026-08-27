const router = require('express').Router();
const { authenticate, authorizeSuperAdmin } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const { createInvitation, acceptInvitation, listInvitations, revokeInvitation } = require('../services/adminInvitation.service');
const { adminInvitationTemplate } = require('../utils/emailTemplates');
const { sendEmail } = require('../services/email.service');

router.post('/', authenticate, authorizeSuperAdmin, async (req, res, next) => {
    try {
        const created = await createInvitation({ email: req.body.email, actor: { id: req.user.sub, role: req.user.role } });
        const url = `${String(process.env.FRONTEND_URL || 'http://localhost:8080').replace(/\/$/, '')}/admin-invitation-accept.html?token=${encodeURIComponent(created.token)}`;
        const template = adminInvitationTemplate(url, created.invitation.expires_at);
        let delivered = false;
        const smtpConfigured = process.env.NODE_ENV !== 'test' && process.env.EMAIL_HOST && process.env.EMAIL_USER && process.env.EMAIL_PASS && process.env.EMAIL_FROM;
        if (smtpConfigured) {
            try {
                await sendEmail(created.invitation.email, 'MedOrbit administrative invitation', template.html, template.text);
                delivered = true;
            } catch (sendError) {
                // The invitation is already safely stored. Do not make the
                // super-admin believe it was delivered when SMTP rejects it;
                // return the existing one-time handoff URL instead.
                console.error('Admin invitation email delivery failed:', sendError.message);
            }
        }
        // The one-time URL is deliberately returned only in this creation
        // response to the super-admin who created the invitation. It is never
        // stored or returned by the list endpoint, but lets the sender safely
        // recover when a recipient's mail provider delays or filters mail.
        return success(res, {
            invitation: created.invitation,
            delivery: delivered ? 'sent' : 'manual',
            acceptance_url: url,
        }, 'Admin invitation created', 201);
    } catch (err) { return next(err); }
});

router.post('/accept', authenticate, async (req, res, next) => {
    try {
        const accepted = await acceptInvitation({ token: req.body.token, user: req.user });
        return success(res, { invitation: accepted.invitation }, 'Invitation accepted. Please sign in again.');
    } catch (err) { return next(err); }
});

router.get('/', authenticate, authorizeSuperAdmin, async (_req, res, next) => {
    try { return success(res, await listInvitations(), 'Admin invitations retrieved'); } catch (err) { return next(err); }
});

router.delete('/:id', authenticate, authorizeSuperAdmin, async (req, res, next) => {
    try { return success(res, await revokeInvitation({ id: req.params.id, actor: { id: req.user.sub, role: req.user.role } }), 'Admin invitation revoked'); } catch (err) { return next(err); }
});

module.exports = router;
