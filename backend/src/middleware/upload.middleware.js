const multer = require("multer");
const path = require("path");
const crypto = require("crypto");


const storage = multer.diskStorage({

    destination: (req, file, cb) => {

        cb(
            null,
            "storage/medical-records"
        );

    },


    filename: (req, file, cb) => {


        const ext =
            path.extname(file.originalname);


        cb(
            null,
            crypto.randomUUID() + ext
        );


    }

});



const fileFilter = (req, file, cb) => {


    const allowed = [

        "application/pdf",

        "image/png",

        "image/jpeg",

        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    ];



    if (allowed.includes(file.mimetype)) {

        cb(null, true);

    }

    else {

        cb(
            new Error("File type not allowed"),
            false
        );

    }

};



module.exports = multer({

    storage,

    fileFilter,

    limits: {
        fileSize: 10 * 1024 * 1024
    }

});