const fs = require("fs");
const multer = require("multer");


const storage =
    multer.diskStorage({

        destination:
            (req, file, cb) => {

                fs.mkdirSync("uploads/avatars", { recursive: true });
                cb(null, "uploads/avatars");

            },


        filename:
            (req, file, cb) => {

                const ext =
                    file.originalname.split(".").pop();


                cb(
                    null,
                    Date.now() + "." + ext
                );

            }

    });



module.exports =
    multer({

        storage,

        limits: {
            fileSize: 2 * 1024 * 1024
        }

    });