const express = require('express');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');

const { authenticate, authorizeAdmin } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const contact = require('../services/contact.service');

const contactRoutes = express.Router();
const adminContactRoutes = express.Router();

const contactLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 8,
    keyGenerator: (req) => ipKeyGenerator(req.ip),
    standardHeaders: true,
    legacyHeaders: false,
    message: {
        success: false,
        error: { code: 'CONTACT_RATE_LIMITED', message: 'Too many contact requests. Please try again later.' },
    },
});

contactRoutes.post('/', contactLimiter, authenticate, async (req, res, next) => {
    try {
        if ('user_id' in req.body || 'userId' in req.body || 'status' in req.body) {
            return error(res, 'Client ownership and workflow fields are not accepted', 400, 'VALIDATION_ERROR');
        }
        const result = await contact.submitContact({
            userId: req.user?.sub || null,
            role: req.user?.role || null,
            body: req.body,
        });
        return success(res, result, 'Contact message submitted', 201);
    } catch (err) {
        return next(err);
    }
});

adminContactRoutes.use(authenticate, authorizeAdmin);

adminContactRoutes.get('/', async (req, res, next) => {
    try {
        return success(res, await contact.listContacts(req.query), 'Contact messages retrieved');
    } catch (err) {
        return next(err);
    }
});

adminContactRoutes.get('/:id', async (req, res, next) => {
    try {
        return success(res, await contact.getContact(req.params.id), 'Contact message retrieved');
    } catch (err) {
        return next(err);
    }
});

adminContactRoutes.post('/:id/read', async (req, res, next) => {
    try {
        return success(res, await contact.updateContact(req.params.id, req.user, 'read'), 'Contact message marked read');
    } catch (err) {
        return next(err);
    }
});

adminContactRoutes.post('/:id/resolve', async (req, res, next) => {
    try {
        return success(res, await contact.updateContact(req.params.id, req.user, 'resolved'), 'Contact message resolved');
    } catch (err) {
        return next(err);
    }
});

module.exports = { contactRoutes, adminContactRoutes };
