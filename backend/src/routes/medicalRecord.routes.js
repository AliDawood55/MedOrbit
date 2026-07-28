const router = require("express").Router();


const {

    authenticate,

    authorize

} = require("../middleware/auth");


//const upload = require("../middleware/upload.middleware");


const service =
    require("../services/medicalRecord.service");


const {
    success,
    error

} = require("../utils/response");



const db = require("../config/database");

const upload = require("../middleware/medicalRecordUpload");



// CREATE

router.post(
    "/",
    authenticate,
    authorize("doctor", "admin"),

    async (req, res, next) => {


        try {


            const appointment =
                await db.query(

                    `
SELECT

patient_id,
doctor_id

FROM medorbit.appointments

WHERE id=$1

`,
                    [
                        req.body.appointment_id
                    ]


                );



            if (!appointment.rows.length)

                return error(
                    res,
                    "Appointment not found",
                    404,
                    "NOT_FOUND"
                );



            const record =
                await service.create({

                    ...req.body,

                    patient_id:
                        appointment.rows[0].patient_id,

                    doctor_id:
                        appointment.rows[0].doctor_id


                });



            return success(
                res,
                record,
                "Medical record created",
                201
            );



        }

        catch (e) {

            next(e);

        }

    });







// GET ALL

router.get(
    "/",
    authenticate,

    async (req, res, next) => {

        try {


            const data =
                await service.findAll();


            success(res, data);



        }

        catch (e) {

            next(e);

        }


    });







// GET ONE


router.get(
    "/:id",
    authenticate,

    async (req, res, next) => {


        try {


            const record =
                await service.findById(
                    req.params.id
                );



            if (!record)

                return error(
                    res,
                    "Record not found",
                    404,
                    "NOT_FOUND"
                );



            success(res, record);



        }

        catch (e) {

            next(e);

        }


    });








// UPDATE


router.put(
    "/:id",
    authenticate,
    authorize("doctor", "admin"),

    async (req, res, next) => {


        try {


            const data =
                await service.update(
                    req.params.id,
                    req.body
                );


            success(
                res,
                data,
                "Updated"
            );


        }

        catch (e) {

            next(e);

        }


    });







// DELETE


router.delete(
    "/:id",
    authenticate,
    authorize("doctor", "admin"),

    async (req, res, next) => {


        try {


            await service.remove(
                req.params.id
            );


            success(
                res,
                null,
                "Deleted"
            );



        }

        catch (e) {

            next(e);

        }


    });








// UPLOAD ATTACHMENT


router.post(
    "/:id/attachments",

    authenticate,

    upload.single("file"),

    async (req, res, next) => {


        try {


            if (!req.file) {

                return error(
                    res,
                    "No file uploaded",
                    400,
                    "FILE_REQUIRED"
                );

            }



            const filePath =
                req.file.path
                    .replace(
                        process.cwd(),
                        ""
                    )
                    .replace(
                        /\\/g,
                        "/"
                    )
                    .substring(1);



            const result =
                await db.query(

                    `
INSERT INTO medorbit.medical_record_attachments

(
record_id,
file_name,
file_path,
file_size_bytes,
mime_type,
uploaded_by
)

VALUES

($1,$2,$3,$4,$5,$6)

RETURNING *

`,

                    [

                        req.params.id,

                        req.file.originalname,

                        filePath,

                        req.file.size,

                        req.file.mimetype,

                        req.user.sub

                    ]

                );



            return success(
                res,
                result.rows[0],
                "Attachment uploaded successfully"
            );



        }
        catch (err) {

            next(err);

        }


    });





// GET ATTACHMENTS


router.get(
    "/:id/attachments",
    authenticate,


    async (req, res, next) => {


        try {


            const data =
                await service.getAttachments(
                    req.params.id
                );


            success(res, data);



        }

        catch (e) {

            next(e);

        }

    });





module.exports = router;