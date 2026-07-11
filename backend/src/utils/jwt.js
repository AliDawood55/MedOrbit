// src/utils/jwt.js


const jwt = require("jsonwebtoken");
const crypto = require("crypto");

const env = require("../config/env");



/**
 * Generate JWT Access Token
 *
 * Access token is used to access protected APIs.
 *
 * Lifetime:
 * 15 minutes (configured in .env)
 *
 * @param {Object} payload - User information
 * @returns {string} JWT token
 */
function generateAccessToken(payload) {


    const token = jwt.sign(
        payload,

        env.jwt.secret,

        {
            expiresIn: env.jwt.accessExpiresIn,
        }
    );


    return token;
}





/**
 * Generate JWT Refresh Token
 *
 * Refresh token is used to generate
 * a new access token after expiration.
 *
 * A unique jti is added because:
 *
 * Without jti:
 * Same user + same payload + same second
 * = same JWT token
 *
 * With jti:
 * Every login generates a unique token.
 *
 * Lifetime:
 * 7 days (configured in .env)
 *
 * @param {Object} payload - User information
 * @returns {string} JWT token
 */
function generateRefreshToken(payload) {


    const token = jwt.sign(

        {
            ...payload,

            // Unique ID for this refresh token/session
            jti: crypto.randomUUID()
        },


        env.jwt.secret,


        {
            expiresIn: env.jwt.refreshExpiresIn,
        }

    );


    return token;
}






/**
 * Verify Access Token
 *
 * Checks:
 * - token signature
 * - token expiration
 *
 * @param {string} token
 * @returns {Object|null}
 */
function verifyAccessToken(token) {


    try {


        const decoded = jwt.verify(
            token,
            env.jwt.secret
        );


        return decoded;


    } catch (error) {


        return null;

    }

}







/**
 * Verify Refresh Token
 *
 * Checks:
 * - token signature
 * - token expiration
 *
 * @param {string} token
 * @returns {Object|null}
 */
function verifyRefreshToken(token) {


    try {


        const decoded = jwt.verify(
            token,
            env.jwt.secret
        );


        return decoded;


    } catch (error) {


        return null;

    }

}





module.exports = {


    generateAccessToken,

    generateRefreshToken,

    verifyAccessToken,

    verifyRefreshToken,

};