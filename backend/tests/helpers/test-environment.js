const path = require('path');

require('dotenv').config({
    path: path.resolve(__dirname, '../../../.env'),
    quiet: true,
});

const apiBase = process.env.AUTH_TEST_API_BASE || 'http://127.0.0.1:3001/api';
const databaseName = process.env.DB_NAME || '';
const databaseHost = process.env.DB_HOST || '';

function refuse(message) {
    throw new Error(`Unsafe integration-test environment: ${message}`);
}

if (process.env.NODE_ENV !== 'test') {
    refuse('NODE_ENV must be "test"');
}

if (process.env.MEDORBIT_TEST_ISOLATION !== 'docker') {
    refuse('MEDORBIT_TEST_ISOLATION must be "docker"');
}

if (databaseHost !== 'postgres') {
    refuse('DB_HOST must be the Docker Compose service "postgres"');
}

if (!/^[a-zA-Z0-9_]+_test$/.test(databaseName)) {
    refuse('DB_NAME must be an approved database ending in "_test"');
}

const parsedApiBase = new URL(apiBase);
if (!['127.0.0.1', 'localhost'].includes(parsedApiBase.hostname) || parsedApiBase.port !== '3001') {
    refuse('AUTH_TEST_API_BASE must target the backend-test process on loopback port 3001');
}

const poolConfig = {
    host: databaseHost,
    port: Number(process.env.DB_PORT) || 5432,
    database: databaseName,
    user: process.env.DB_USER,
    password: String(process.env.DB_PASSWORD || ''),
    max: 5,
    idleTimeoutMillis: 10000,
    connectionTimeoutMillis: 2000,
    options: '-c search_path=medorbit,public',
};

module.exports = {
    apiBase,
    poolConfig,
};
