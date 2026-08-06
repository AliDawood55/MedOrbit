// src/routes/auth.routes.js

const express = require("express");
const router = express.Router();
const authController = require("../controllers/auth.controller");
const { authenticate } = require("../middleware/auth");
const rateLimit = require("express-rate-limit");

function createAuthLimiter({ windowMs, max, message }) {
    return rateLimit({
        windowMs,
        max,
        standardHeaders: true,
        legacyHeaders: false,
        message: {
            success: false,
            error: { code: 'RATE_LIMITED', message }
        }
    });
}

// Per-IP login rate limit: 10 attempts per 15 minutes
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
        success: false,
        error: { code: 'RATE_LIMITED', message: 'Too many login attempts. Please try again later.' }
    }
});

const registerLimiter = createAuthLimiter({
    windowMs: 60 * 60 * 1000,
    max: 10,
    message: 'Too many registration attempts. Please try again later.'
});

const verifyEmailLimiter = createAuthLimiter({
    windowMs: 15 * 60 * 1000,
    max: 10,
    message: 'Too many verification attempts. Please try again later.'
});

const resendVerificationLimiter = createAuthLimiter({
    windowMs: 15 * 60 * 1000,
    max: 5,
    message: 'Too many verification email requests. Please try again later.'
});

router.post("/register", registerLimiter, authController.register);

router.post("/login", loginLimiter, authController.login);

router.post("/google", loginLimiter, authController.google);

router.post("/refresh", authController.refresh);

router.post("/logout", authController.logout);

router.post("/change-password", authenticate, authController.changePassword);

router.post("/forgot-password", authController.forgotPassword);

router.post("/reset-password", authController.resetPassword);

router.post("/verify-email", verifyEmailLimiter, authController.verifyEmail);

router.post("/resend-verification", resendVerificationLimiter, authController.resendVerification);

module.exports = router;
