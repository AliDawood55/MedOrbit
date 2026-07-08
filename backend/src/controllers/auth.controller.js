// src/controllers/auth.controller.js


const authService = require("../services/auth.service");



/**
 * Login controller
 *
 * POST /api/auth/login
 *
 * Request body:
 * {
 *    email,
 *    password
 * }
 */
async function login(req, res, next) {

    try {

        const {
            email,
            password
        } = req.body;


        const result =
            await authService.login(
                email,
                password
            );


        return res.status(200).json({

            success: true,

            message: "Login successful",

            data: result

        });


    } catch (error) {

        next(error);

    }

}




/**
 * Refresh token controller
 *
 * POST /api/auth/refresh
 *
 * Request body:
 * {
 *    refreshToken
 * }
 */
async function refresh(req, res, next) {

    try {


        const {
            refreshToken
        } = req.body;


        const result =
            await authService.refresh(
                refreshToken
            );


        return res.status(200).json({

            success: true,

            message: "Token refreshed successfully",

            data: result

        });


    } catch (error) {

        next(error);

    }

}





/**
 * Logout controller
 *
 * POST /api/auth/logout
 *
 * Request body:
 * {
 *    refreshToken
 * }
 */
async function logout(req, res, next) {


    try {


        const {
            refreshToken
        } = req.body;



        await authService.logout(
            refreshToken
        );



        return res.status(200).json({

            success: true,

            message: "Logout successful"

        });



    } catch (error) {

        next(error);

    }

}




module.exports = {

    login,

    refresh,

    logout

};