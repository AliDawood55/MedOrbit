// src/config/env.js
// Loads environment from root .env — called once at startup.
// All other modules read process.env after this is loaded.

const path = require('path');
const dotenv = require('dotenv');

// Resolve root .env: server.js -> src/ -> config/ -> ../../../ = project root
const rootEnvPath = path.resolve(__dirname, '../../.env');
// quiet: true — suppress dotenv's own "injecting env (N)" console line; by
// the time this runs, src/config/database.js has usually already loaded
// everything anyway (see its own comment), so this call would otherwise log
// a redundant/misleading "(0)".
dotenv.config({ path: rootEnvPath, quiet: true });

// Also set in process.env for any direct readers
process.env.DOTENV_LOADED = '1';

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
        password: String(process.env.DB_PASSWORD || ''),
        schema: process.env.DB_SCHEMA || "medorbit",
    },

    jwt: {
        secret: process.env.JWT_SECRET,

        accessExpiresIn:
            process.env.JWT_ACCESS_EXPIRES_IN || "15m",

        refreshExpiresIn:
            process.env.JWT_REFRESH_EXPIRES_IN || "7d",
    },


    security: {
        bcryptRounds:
            Number(process.env.BCRYPT_ROUNDS) || 12,
    },

    google: {
        clientId: process.env.GOOGLE_CLIENT_ID,
    },


    cors: {
        origin:
            process.env.CORS_ORIGIN || "*",
    }
};

module.exports = env;