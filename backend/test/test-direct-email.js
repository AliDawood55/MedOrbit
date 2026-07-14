require("dotenv").config();

const nodemailer = require("nodemailer");


const transporter =
    nodemailer.createTransport({

        host: process.env.EMAIL_HOST,

        port: process.env.EMAIL_PORT,

        secure: false,

        auth: {
            user: process.env.EMAIL_USER,
            pass: process.env.EMAIL_PASSWORD
        }

    });


async function test() {

    const info =
        await transporter.sendMail({

            from:
                process.env.EMAIL_FROM,

            to:
                "YOUR_EMAIL@gmail.com",

            subject:
                "MedOrbit Test",

            text:
                "Hello from MedOrbit"

        });


    console.log(info);

}


test();