// src/routes/auth.routes.js

const express = require("express");

const router = express.Router();

const authController = require("../controllers/auth.controller");

const { authenticate } = require("../middleware/auth");


// Register
router.post(
  "/register",
  authController.register
);


// Login
router.post(
  "/login",
  authController.login
);


// Refresh token
router.post(
  "/refresh",
  authController.refresh
);


// Logout
router.post(
  "/logout",
  authController.logout
);

router.post(
  "/change-password",
  authenticate,
  authController.changePassword
);

// Forgot password
router.post(
  "/forgot-password",
  authController.forgotPassword
);


// Reset password
router.post(
  "/reset-password",
  authController.resetPassword
);

// Verify email

router.post(
  "/verify-email",
  authController.verifyEmail
);



// Resend verification

router.post(
  "/resend-verification",
  authController.resendVerification
);

const {
  queueEmail
} = require("../services/email.service");



router.post(
  "/test-email",
  async (req, res, next) => {

    try {


      await queueEmail(

        req.body.email,

        "MedOrbit Test Email",

        `
            <h1>
            MedOrbit Email Test
            </h1>

            <p>
            Email system works successfully.
            </p>
            `

      );


      res.json({

        success: true,

        message: "Email queued"

      });


    }

    catch (err) {

      next(err);

    }

  });


module.exports = router;