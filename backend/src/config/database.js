const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
});

// ✅ Set schema
pool.on('connect', (client) => {
    client.query('SET search_path TO medorbit, public');
    console.log('✅ Connected to PostgreSQL (medorbit)');
});

const getClient = async () => {
    return await pool.connect();
};

module.exports = {
    query: (text, params) => pool.query(text, params),
    getClient,
    pool
};