// test file for // src/utils/password.js

const {
    hashPassword,
    comparePassword
} = require("../src/utils/password");


async function test() {


    const password = "MyPassword123";


    const hash = await hashPassword(password);


    console.log("Original:");
    console.log(password);


    console.log("\nHash:");
    console.log(hash);



    const result = await comparePassword(
        password,
        hash
    );


    console.log("\nPassword match:");
    console.log(result);

}


test();