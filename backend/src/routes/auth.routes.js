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


module.exports = router;