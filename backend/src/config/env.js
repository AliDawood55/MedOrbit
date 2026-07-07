// src/config/env.js

require("dotenv").config();

const env = {
    app: {
        name: "MedOrbit",
        environment: process.env.NODE_ENV || "development",
        port: Number(process.env.PORT) || 3001,
    },

    database: {
        host: process.env.DB_HOST,
        port: Number(process.env.DB_PORT),
        name: process.env.DB_NAME,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
    },

    jwt: {
        secret: process.env.JWT_SECRET,
    },
};

module.exports = env;