// src/middleware/notFound.js

function notFound(req, res, next) {

    res.status(404).json({

        success: false,

        message: "Route not found.",

        path: req.originalUrl,

    });

}

module.exports = notFound;