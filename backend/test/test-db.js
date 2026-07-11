const db = require("../src/config/database");


async function test() {

    try {

        const result =
            await db.query(
                "SELECT NOW();"
            );


        console.log(
            "Database connected:"
        );


        console.log(
            result.rows
        );


    } catch (error) {

        console.error(
            "Database connection failed:"
        );


        console.error(
            error.message
        );

    }

}


test();