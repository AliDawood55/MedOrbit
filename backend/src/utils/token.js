const crypto = require("crypto");


function generateToken() {

    return crypto
        .randomBytes(32)
        .toString("hex");

}

function generateOtp() {

    return crypto
        .randomInt(0, 1000000)
        .toString()
        .padStart(6, "0");

}



function hashToken(token) {

    return crypto
        .createHash("sha256")
        .update(token)
        .digest("hex");

}

function hashRefreshToken(token) {
    return hashToken(token);
}

function hashOtp(otp, email, secret) {

    return crypto
        .createHmac("sha256", secret)
        .update(`email-verification-otp:${email}:${otp}`)
        .digest("hex");

}



module.exports = {

    generateToken,

    generateOtp,

    hashToken,

    hashRefreshToken,

    hashOtp

};
