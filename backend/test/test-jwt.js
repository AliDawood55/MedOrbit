// test file for // src/utils/jwt.js

const {
    generateAccessToken,
    generateRefreshToken,
    verifyAccessToken,
    verifyRefreshToken
} = require("../src/utils/jwt");



const userPayload = {

    userId: "12345",

    role: "patient"

};



const accessToken =
    generateAccessToken(userPayload);


const refreshToken =
    generateRefreshToken(userPayload);



console.log("\nACCESS TOKEN:");
console.log(accessToken);



console.log("\nREFRESH TOKEN:");
console.log(refreshToken);




const decodedAccess =
    verifyAccessToken(accessToken);

// const decodedAccess =
// verifyAccessToken("wrong-token");


console.log("\nDECODED ACCESS:");
console.log(decodedAccess);




const decodedRefresh =
    verifyRefreshToken(refreshToken);


console.log("\nDECODED REFRESH:");
console.log(decodedRefresh);