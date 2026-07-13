// src/controllers/auth.controller.js


const authService = require("../services/auth.service");

const {
    success,
    error
} = require("../utils/response");



/**
 * POST /api/auth/register
 */
async function register(req, res, next) {

    try {


        const {
            email,
            password,
            role,
            firstNameAr,
            lastNameAr,
            firstNameEn,
            lastNameEn,
            phone,
            gender
        } = req.body;



        // Basic validation

        if (
            !email ||
            !password ||
            !role ||
            !firstNameAr ||
            !lastNameAr ||
            !firstNameEn ||
            !lastNameEn
        ) {

            return error(
                res,
                "Missing required fields",
                400,
                "VALIDATION_ERROR"
            );

        }



        const user =
            await authService.register({

                email,
                password,
                role,

                firstNameAr,
                lastNameAr,

                firstNameEn,
                lastNameEn,

                phone,
                gender

            });



        return success(

            res,

            user,

            "Registration successful",

            201

        );



    } catch (err) {

        next(err);

    }

}





/**
 * POST /api/auth/login
 */
async function login(req, res, next) {


    try {


        const {
            email,
            password
        } = req.body;



        if (!email || !password) {

            return error(

                res,

                "Email and password required",

                400,

                "VALIDATION_ERROR"

            );

        }



        const result =
            await authService.login(

                email,

                password,

                req

            );



        return success(

            res,

            result,

            "Login successful"

        );



    } catch (err) {

        next(err);

    }

}






/**
 * POST /api/auth/refresh
 */
async function refresh(req, res, next) {


    try {


        const {
            refreshToken
        } = req.body;



        if (!refreshToken) {

            return error(

                res,

                "Refresh token required",

                401,

                "UNAUTHORIZED"

            );

        }



        const result =
            await authService.refresh(
                refreshToken
            );



        return success(

            res,

            result,

            "Token refreshed"

        );



    } catch (err) {

        next(err);

    }

}






/**
 * POST /api/auth/logout
 */
async function logout(req, res, next) {


    try {


        const {
            refreshToken
        } = req.body;



        if (!refreshToken) {

            return error(

                res,

                "Refresh token required",

                401,

                "UNAUTHORIZED"

            );

        }



        await authService.logout(
            refreshToken
        );



        return success(

            res,

            null,

            "Logout successful"

        );



    } catch (err) {

        next(err);

    }

}

async function changePassword(req, res, next) {

    try {

        const {

            currentPassword,

            newPassword

        } = req.body;


        if (!currentPassword || !newPassword) {

            return error(

                res,

                "Current password and new password are required",

                400,

                "VALIDATION_ERROR"

            );

        }


        await authService.changePassword(

            req.user.sub,

            currentPassword,

            newPassword

        );


        return success(

            res,

            null,

            "Password changed successfully"

        );

    }

    catch (err) {

        next(err);

    }

}





module.exports = {

    register,

    login,

    refresh,

    logout,

    changePassword

};