// src/routes/auth.routes.js

const express = require("express");

const router = express.Router();

const authController =
  require("../controllers/auth.controller");


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


module.exports = router;