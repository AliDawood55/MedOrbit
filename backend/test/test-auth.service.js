const {
    login
} = require("../src/services/auth.service");



async function test() {


    const result =
        await login(
            "omar@test.com",
            "123456"
        );


    console.log(result);

}



test();