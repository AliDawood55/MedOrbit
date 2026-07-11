// src/services/auth.service.js


const db = require("../config/database");


const {
    hashPassword,
    comparePassword
} = require("../utils/password");


const {
    generateAccessToken,
    generateRefreshToken,
    verifyRefreshToken
} = require("../utils/jwt");



const env = require("../config/env");



/**
 * Register new user
 */
async function register(userData) {


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
    } = userData;



    // Check existing email

    const existing =
        await db.query(
            `
            SELECT id 
            FROM public.users
            WHERE email = $1
            `,
            [email]
        );



    if (existing.rows.length > 0) {

        throw new Error(
            "Email already registered"
        );

    }



    // Hash password

    const passwordHash =
        await hashPassword(password);



    // Create user

    const userResult =
        await db.query(
            `
            INSERT INTO public.users
            (
                email,
                password_hash,
                role,
                email_verified,
                preferred_language
            )

            VALUES
            (
                $1,
                $2,
                $3,
                true,
                'ar'
            )

            RETURNING id,email,role
            `,
            [
                email,
                passwordHash,
                role
            ]
        );



    const user =
        userResult.rows[0];



    // Create profile

    await db.query(
        `
        INSERT INTO public.user_profiles
        (
            user_id,
            first_name_ar,
            last_name_ar,
            first_name_en,
            last_name_en,
            phone,
            gender
        )

        VALUES
        (
            $1,$2,$3,$4,$5,$6,$7
        )
        `,
        [
            user.id,
            firstNameAr,
            lastNameAr,
            firstNameEn,
            lastNameEn,
            phone || null,
            gender || null
        ]
    );



    // Role specific table

    if (role === "patient") {

        await db.query(
            `
            INSERT INTO public.patients
            (user_id)

            VALUES($1)
            `,
            [user.id]
        );

    }



    if (role === "doctor") {

        await db.query(
            `
            INSERT INTO public.doctors
            (user_id)

            VALUES($1)
            `,
            [user.id]
        );

    }



    return user;

}





/**
 * Login user
 */
async function login(
    email,
    password,
    req
) {



    const result =
        await db.query(
            `
            SELECT 
                u.id,
                u.email,
                u.password_hash,
                u.role,
                u.is_active,
                u.failed_login_attempts,
                u.locked_until,

                p.first_name_ar,
                p.last_name_en

            FROM public.users u

            LEFT JOIN public.user_profiles p
            ON p.user_id = u.id

            WHERE u.email=$1
            AND u.deleted_at IS NULL

            `,
            [
                email
            ]
        );



    if (result.rows.length === 0) {

        throw new Error(
            "Invalid credentials"
        );

    }



    const user =
        result.rows[0];




    if (
        user.locked_until &&
        new Date(user.locked_until)
        >
        new Date()
    ) {

        throw new Error(
            "Account locked"
        );

    }




    if (!user.is_active) {

        throw new Error(
            "Account inactive"
        );

    }




    const validPassword =
        await comparePassword(
            password,
            user.password_hash
        );



    if (!validPassword) {

        await db.query(
            `
            UPDATE public.users

            SET failed_login_attempts =
            failed_login_attempts + 1

            WHERE id=$1
            `,
            [
                user.id
            ]
        );


        throw new Error(
            "Invalid credentials"
        );

    }




    // Reset failed attempts

    await db.query(
        `
        UPDATE public.users

        SET failed_login_attempts=0,
        locked_until=NULL

        WHERE id=$1
        `,
        [
            user.id
        ]
    );




    const accessToken =
        generateAccessToken({

            sub: user.id,

            email: user.email,

            role: user.role

        });





    const refreshToken =
        generateRefreshToken({

            sub: user.id,

            type: "refresh"

        });





    // Save refresh token

    await db.query(

        `
        INSERT INTO public.user_sessions

        (
            user_id,
            refresh_token,
            ip_address,
            user_agent,
            expires_at
        )


        VALUES
        (
            $1,$2,$3,$4,
            NOW()+INTERVAL '7 days'
        )

        `,

        [

            user.id,

            refreshToken,

            req.ip,

            req.headers["user-agent"] || null

        ]

    );




    return {

        user: {

            id: user.id,

            email: user.email,

            role: user.role,

            name:
                user.first_name_ar ||
                user.last_name_en

        },


        accessToken,

        refreshToken

    };

}






/**
 * Refresh access token
 */
async function refresh(refreshToken) {


    const decoded =
        verifyRefreshToken(
            refreshToken
        );



    if (!decoded) {

        throw new Error(
            "Invalid refresh token"
        );

    }



    const session =
        await db.query(
            `
            SELECT 
                s.user_id,
                u.email,
                u.role

            FROM public.user_sessions s

            JOIN public.users u

            ON u.id=s.user_id


            WHERE s.refresh_token=$1

            AND s.expires_at > NOW()

            `,
            [
                refreshToken
            ]
        );



    if (session.rows.length === 0) {

        throw new Error(
            "Expired refresh token"
        );

    }



    const user =
        session.rows[0];



    const accessToken =
        generateAccessToken({

            sub: user.user_id,

            email: user.email,

            role: user.role

        });



    return {

        accessToken

    };

}





/**
 * Logout user
 */
async function logout(refreshToken) {


    await db.query(

        `
        DELETE FROM public.user_sessions

        WHERE refresh_token=$1

        `,

        [
            refreshToken
        ]

    );


}




module.exports = {


    register,

    login,

    refresh,

    logout


};