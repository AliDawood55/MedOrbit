// src/routes/health.routes.js

const express = require("express");

const router = express.Router();

router.get("/", (req, res) => {

    res.status(200).json({

        success: true,

        message: "MedOrbit API is running.",

        data: {

            uptime: process.uptime(),

            timestamp: new Date().toISOString(),

            environment: process.env.NODE_ENV,

        }

    });

});

module.exports = router;