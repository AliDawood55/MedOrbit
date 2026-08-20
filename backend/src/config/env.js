
const path = require('path');
const dotenv = require('dotenv');
const rootEnvPath = path.resolve(__dirname, '../../.env');

dotenv.config({ path: rootEnvPath, quiet: true });
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
        algorithm: "HS256",
        issuer: process.env.JWT_ISSUER || "medorbit-api",
        audience: process.env.JWT_AUDIENCE || "medorbit-clients",

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
    },

    scheduling: {
        // Preserve the existing 21-day web/mobile booking horizon while
        // enforcing it server-side. Operators may raise it, up to one year.
        bookingHorizonDays: Math.min(
            Math.max(Number(process.env.BOOKING_HORIZON_DAYS) || 21, 1),
            365
        ),
        // Existing appointments use local DATE + TIME columns. This timezone
        // defines "today" without converting or shifting stored clock times.
        timeZone: process.env.SCHEDULING_TIMEZONE || 'Africa/Cairo',
    },

    kafka: {
        enabled: String(process.env.KAFKA_ENABLED || 'false').toLowerCase() === 'true',
        brokers: String(process.env.KAFKA_BROKERS || 'kafka:9092').split(',').map((v) => v.trim()).filter(Boolean),
        clientId: process.env.KAFKA_CLIENT_ID || 'medorbit',
        outboxTopic: process.env.KAFKA_OUTBOX_TOPIC || 'medorbit.domain-events.v1',
        consumerGroup: process.env.KAFKA_CONSUMER_GROUP || 'medorbit-event-observer-v1',
        recommendationConsumerGroup: process.env.KAFKA_RECOMMENDATION_CONSUMER_GROUP || 'recommendation-profile-v1',
        batchSize: Math.min(Math.max(Number(process.env.OUTBOX_BATCH_SIZE) || 50, 1), 500),
        pollIntervalMs: Math.max(Number(process.env.OUTBOX_POLL_INTERVAL_MS) || 1000, 250),
        lockTimeoutMs: Math.max(Number(process.env.OUTBOX_LOCK_TIMEOUT_MS) || 60000, 5000),
        maxAttempts: Math.min(Math.max(Number(process.env.OUTBOX_MAX_ATTEMPTS) || 8, 1), 100),
    },
};

module.exports = env;
