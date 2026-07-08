// src/services/auth.service.js


const {
    comparePassword
} = require("../utils/password");


const {
    generateAccessToken,
    generateRefreshToken
} = require("../utils/jwt");



/**
 * Login user
 *
 * @param {Object} credentials
 * @param {string} credentials.email
 * @param {string} credentials.password
 *
 * @returns tokens
 */
async function login(email, password) {


    /*
        TODO:
        1. Find user by email from database
        2. Check if user exists
        3. Compare password
        4. Generate tokens
        5. Save refresh token
    */


    // Temporary user for testing
    const user = {

        id: "123",

        email: email,

        role: "patient",

        passwordHash:
            "$2b$12$example"

    };



    /*
        Password verification
        will be enabled after connecting database
    */


    const accessToken =
        generateAccessToken({

            id: user.id,

            email: user.email,

            role: user.role

        });



    const refreshToken =
        generateRefreshToken({

            id: user.id,

            email: user.email,

            role: user.role

        });



    return {

        user: {

            id: user.id,

            email: user.email,

            role: user.role

        },


        tokens: {

            accessToken,

            refreshToken

        }

    };

}




module.exports = {

    login

};