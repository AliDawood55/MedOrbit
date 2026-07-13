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

const {
    generateToken,
    hashToken
} = require("../utils/token");





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



    const existing =
        await db.query(
            `
            SELECT id
            FROM public.users
            WHERE email=$1
            `,
            [email]
        );



    if (existing.rows.length > 0) {

        throw new Error(
            "Email already registered"
        );

    }



    const passwordHash =
        await hashPassword(password);



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
                $1,$2,$3,true,'ar'
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



    if (role === "patient") {

        await db.query(
            `
            INSERT INTO public.patients
            (user_id)

            VALUES($1)
            `,
            [
                user.id
            ]
        );

    }



    if (role === "doctor") {

        await db.query(
            `
            INSERT INTO public.doctors
            (user_id)

            VALUES($1)
            `,
            [
                user.id
            ]
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
            ON p.user_id=u.id

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
        new Date(user.locked_until) > new Date()
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





    /*
        Save session

        New fields:
        - platform
        - device_name
        - revoked_at
        - last_used_at
    */


    await db.query(
        `
        INSERT INTO public.user_sessions
        (
            user_id,
            refresh_token,
            ip_address,
            user_agent,
            platform,
            device_name,
            expires_at
        )

        VALUES
        (
            $1,$2,$3,$4,$5,$6,
            NOW()+INTERVAL '7 days'
        )

        `,
        [

            user.id,

            refreshToken,

            req.ip,

            req.headers["user-agent"] || null,

            req.body.platform || "web",

            req.body.deviceName || null

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
        verifyRefreshToken(refreshToken);



    if (!decoded) {

        throw new Error(
            "Invalid refresh token"
        );

    }



    if (decoded.type !== "refresh") {

        throw new Error(
            "Invalid token type"
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

            AND s.revoked_at IS NULL

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




    await db.query(
        `
        UPDATE public.user_sessions

        SET last_used_at=NOW()

        WHERE refresh_token=$1
        `,
        [
            refreshToken
        ]
    );





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
        UPDATE public.user_sessions

        SET revoked_at=NOW()

        WHERE refresh_token=$1

        `,
        [
            refreshToken
        ]
    );


}

/**
 * Change user password
 */
async function changePassword(
    userId,
    currentPassword,
    newPassword
) {

    // Find user

    const result =
        await db.query(
            `
            SELECT
                password_hash

            FROM public.users

            WHERE id = $1
            `,
            [userId]
        );


    if (result.rows.length === 0) {

        throw new Error(
            "User not found"
        );

    }


    const user =
        result.rows[0];


    // Check current password

    const valid =
        await comparePassword(
            currentPassword,
            user.password_hash
        );


    if (!valid) {

        throw new Error(
            "Current password is incorrect"
        );

    }


    // Hash new password

    const newHash =
        await hashPassword(
            newPassword
        );


    // Update password

    await db.query(

        `
        UPDATE public.users

        SET
            password_hash = $1,
            updated_at = NOW()

        WHERE id = $2
        `,

        [
            newHash,
            userId
        ]

    );


    // Logout every device

    await db.query(

        `
        DELETE FROM public.user_sessions

        WHERE user_id = $1
        `,

        [
            userId
        ]

    );


    return;

}

async function forgotPassword(email) {


    const result =
        await db.query(
            `
        SELECT id,email
        FROM public.users
        WHERE email=$1
        AND deleted_at IS NULL
        `,
            [
                email
            ]);



    /*
      Security:
      Do not reveal if email exists
    */

    if (result.rows.length === 0) {

        return;

    }


    const user = result.rows[0];



    const token =
        generateToken();



    const tokenHash =
        hashToken(token);



    await db.query(
        `
    INSERT INTO public.password_reset_tokens
    (
        user_id,
        token_hash,
        expires_at
    )

    VALUES
    (
        $1,
        $2,
        NOW()+INTERVAL '15 minutes'
    )
    `,
        [
            user.id,
            tokenHash
        ]);



    /*
       Later:
       send email here

       For testing:
    */

    console.log(
        "PASSWORD RESET TOKEN:",
        token
    );


}

async function resetPassword(
    token,
    newPassword
) {


    const tokenHash =
        hashToken(token);



    const result =
        await db.query(
            `
        SELECT
            id,
            user_id

        FROM public.password_reset_tokens

        WHERE token_hash=$1

        AND expires_at > NOW()

        AND used_at IS NULL

        `,
            [
                tokenHash
            ]);



    if (result.rows.length === 0) {

        throw new Error(
            "Invalid or expired token"
        );

    }



    const reset =
        result.rows[0];



    const passwordHash =
        await hashPassword(
            newPassword
        );



    await db.query(
        `
    UPDATE public.users

    SET password_hash=$1

    WHERE id=$2
    `,
        [
            passwordHash,
            reset.user_id
        ]);



    await db.query(
        `
    UPDATE public.password_reset_tokens

    SET used_at=NOW()

    WHERE id=$1
    `,
        [
            reset.id
        ]);

    // Logout all existing sessions after password reset

    await db.query(
        `
    UPDATE public.user_sessions

    SET revoked_at = NOW()

    WHERE user_id=$1
    `,
        [
            reset.user_id
        ]
    );



}







module.exports = {

    register,

    login,

    refresh,

    logout,

    changePassword,

    forgotPassword,

    resetPassword

};