const { Pool } = require('pg');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../../.env') });

const pool = new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT) || 5432,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: String(process.env.DB_PASSWORD || ''),
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
    options: '-c search_path=medorbit,public'

});

// // Set search_path on every new connection
// pool.on('connect', (client) => {
//     client.query('SET search_path TO medorbit, public').catch(() => {});
// });

console.log('✅ Connected to PostgreSQL (medorbit)');

const getClient = async () => {
    return await pool.connect();
};
// const getClient = async () => {
//     const client = await pool.connect();
//     await client.query('SET search_path TO medorbit, public');
//     return client;
// };

module.exports = {
    query: (text, params) => pool.query(text, params),
    getClient,
    pool
};