const express = require("express");

const router = express.Router();

const db = require("../config/database");

const {
    authenticate,
    authorize
} = require("../middleware/auth");

const {
    success,
    error
} = require("../utils/response");

const {
    generatePrescriptionPDF
} = require("../services/prescription.service");



// =======================================
// CREATE PRESCRIPTION
// POST /api/prescriptions
// =======================================

router.post(
    "/",
    authenticate,
    authorize("doctor"),

    async (req, res, next) => {

        try {


            const {

                patient_id,
                appointment_id,
                valid_until,
                diagnosis,
                instructions,
                doctor_notes,
                items

            } = req.body;



            const result =
                await db.query(

                    `
INSERT INTO medorbit.prescriptions

(
prescription_number,
patient_id,
doctor_id,
appointment_id,
prescription_date,
valid_until,
status,
diagnosis,
instructions,
doctor_notes
)

VALUES

(
'RX-'||floor(random()*1000000)::text,
$1,
(
SELECT id
FROM medorbit.doctors
WHERE user_id=$2
),
$3,
CURRENT_DATE,
$4,
'active',
$5,
$6,
$7
)

RETURNING *

`,
                    [
                        patient_id,
                        req.user.sub,
                        appointment_id,
                        valid_until,
                        diagnosis,
                        instructions,
                        doctor_notes
                    ]


                );



            const prescription = result.rows[0];



            // insert items

            for (const item of items) {


                await db.query(

                    `

INSERT INTO medorbit.prescription_items

(
prescription_id,
medication_name_ar,
medication_name_en,
dosage,
frequency,
duration,
quantity,
instructions
)

VALUES

($1,$2,$3,$4,$5,$6,$7,$8)

`,

                    [
                        prescription.id,
                        item.medication_name_ar,
                        item.medication_name_en,
                        item.dosage,
                        item.frequency,
                        item.duration,
                        item.quantity,
                        item.instructions
                    ]


                );


            }



            return success(
                res,
                prescription,
                "Prescription created"
            );


        }

        catch (err) {

            next(err);

        }


    });





// =======================================
// GET PRESCRIPTION
// =======================================

router.get(
    "/:id",

    authenticate,

    async (req, res, next) => {


        try {


            const prescription =
                await db.query(

                    `
SELECT *
FROM medorbit.prescriptions
WHERE id=$1
`,
                    [
                        req.params.id
                    ]

                );


            const items =
                await db.query(

                    `
SELECT *
FROM medorbit.prescription_items
WHERE prescription_id=$1
`,
                    [
                        req.params.id
                    ]

                );



            return success(
                res,
                {
                    prescription: prescription.rows[0],
                    items: items.rows
                },
                "Prescription retrieved"
            );



        }
        catch (err) {

            next(err);

        }


    });






// =======================================
// DOWNLOAD PDF
// =======================================

router.get(
    "/:id/pdf",

    authenticate,

    async (req, res, next) => {


        try {


            const prescription =
                await db.query(

                    `
SELECT *
FROM medorbit.prescriptions
WHERE id=$1
`,
                    [
                        req.params.id
                    ]

                );


            const items =
                await db.query(

                    `
SELECT *
FROM medorbit.prescription_items
WHERE prescription_id=$1
`,
                    [
                        req.params.id
                    ]

                );



            res.setHeader(
                "Content-Type",
                "application/pdf"
            );


            res.setHeader(
                "Content-Disposition",
                "attachment; filename=prescription.pdf"
            );



            const pdf =
                generatePrescriptionPDF(
                    prescription.rows[0],
                    items.rows
                );



            pdf.pipe(res);



        }
        catch (err) {

            next(err);

        }


    });





module.exports = router;