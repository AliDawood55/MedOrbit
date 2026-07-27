const fs = require("fs");
const multer = require("multer");
const crypto = require("crypto");
const path = require("path");



const storage = multer.diskStorage({


    destination: (req, file, cb) => {


        const folder =
            path.join(
                process.cwd(),
                "storage",
                "medical-records"
            );


        fs.mkdirSync(
            folder,
            {
                recursive: true
            }
        );


        cb(
            null,
            folder
        );


    },



    filename: (req, file, cb) => {


        const ext =
            path.extname(
                file.originalname
            );


        cb(
            null,
            crypto.randomUUID() + ext
        );


    }


});





const allowedTypes = [

    "application/pdf",

    "image/jpeg",

    "image/png",

    "image/jpg"

];





module.exports =
    multer({

        storage,


        limits: {

            fileSize:
                10 * 1024 * 1024

        },



        fileFilter: (req, file, cb) => {


            if (
                !allowedTypes.includes(
                    file.mimetype
                )
            ) {

                return cb(
                    new Error(
                        "Invalid file type"
                    )
                );

            }


            cb(null, true);


        }


    });