// src/utils/password.js


const bcrypt = require("bcrypt");

const env = require("../config/env");


/**
 * Hash a plain text password
 *
 * @param {string} password - User plain password
 * @returns {Promise<string>} - Hashed password
 */
async function hashPassword(password) {

    const hashedPassword = await bcrypt.hash(
        password,
        env.security.bcryptRounds
    );

    return hashedPassword;
}



/**
 * Compare plain password with hashed password
 *
 * @param {string} password - Password entered by user
 * @param {string} hashedPassword - Password stored in database
 * @returns {Promise<boolean>}
 */
async function comparePassword(password, hashedPassword) {

    const isMatch = await bcrypt.compare(
        password,
        hashedPassword
    );

    return isMatch;
}



module.exports = {
    hashPassword,
    comparePassword,
};