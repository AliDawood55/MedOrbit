const router = require("express").Router();


const {

    authenticate,

    authorize

} = require("../middleware/auth");


const upload =
    require("../middleware/upload.middleware");


const service =
    require("../services/medicalRecord.service");


const {
    success,
    error

} = require("../utils/response");



const db = require("../config/database");



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
    authorize("doctor", "admin"),

    upload.single("file"),


    async (req, res, next) => {


        try {


            const file = req.file;



            if (!file)

                return error(
                    res,
                    "No file",
                    400
                );



            const attachment =
                await service.addAttachment({

                    record_id: req.params.id,

                    file_name: file.originalname,

                    file_type: file.extension,

                    file_path: file.path,

                    file_size_bytes: file.size,

                    mime_type: file.mimetype,

                    uploaded_by: req.user.sub


                });



            success(
                res,
                attachment,
                "Uploaded",
                201
            );


        }

        catch (e) {

            next(e);

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