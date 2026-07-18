export const resetPassword = (data) => {

    return API.post(
        "/auth/reset-password",
        data
    );

};



export const verifyEmail = (data) => {

    return API.post(
        "/auth/verify-email",
        data
    );

};