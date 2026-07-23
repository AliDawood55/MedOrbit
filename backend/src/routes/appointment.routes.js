const express = require("express");

const db = require("../config/database");

const {
    authenticate,
    authorize
} = require("../middleware/auth");

const {
    success,
    error
} = require("../utils/response");

const crypto = require("crypto");


const router = express.Router();



// =====================================================
// GET AVAILABLE SLOTS
// GET /api/appointments/available-slots
// =====================================================

router.get(
    "/available-slots",

    async (req, res, next) => {

        try {


            const {
                doctor_id,
                clinic_id,
                date
            } = req.query;



            if (!doctor_id || !clinic_id || !date) {

                return error(
                    res,
                    "doctor_id clinic_id and date are required",
                    400,
                    "VALIDATION_ERROR"
                );

            }



            const day = new Date(date).getDay();



            const result = await db.query(

                `
SELECT *

FROM medorbit.doctor_availability

WHERE doctor_id=$1

AND clinic_id=$2

AND is_active=true

AND
(
specific_date=$3

OR

(
specific_date IS NULL

AND day_of_week=$4
)

)

ORDER BY start_time

`,

                [
                    doctor_id,
                    clinic_id,
                    date,
                    day
                ]


            );



            return success(
                res,
                result.rows,
                "Available slots retrieved"
            );



        }

        catch (err) {

            next(err);

        }


    });



const {
    generateMeetingLink
}
    =
    require("../services/telemedicine.service");

// =====================================================
// CREATE APPOINTMENT
// POST /api/appointments
// =====================================================


router.post(
    "/",

    authenticate,

    async (req, res, next) => {


        try {

            const {
                doctor_id,
                clinic_id,
                scheduled_date,
                start_time,
                end_time,
                duration_minutes,
                appointment_type,
                reason_for_visit,
                notes
            } = req.body;


            const patientResult = await db.query(
                `
    SELECT id
    FROM medorbit.patients
    WHERE user_id=$1
    `,
                [
                    req.user.sub
                ]
            );


            if (patientResult.rows.length === 0) {

                return error(
                    res,
                    "Patient profile not found",
                    404,
                    "PATIENT_NOT_FOUND"
                );

            }


            const patient_id = patientResult.rows[0].id;

            let meetingLink = null;


            if (appointment_type === "telemedicine") {

                meetingLink =
                    generateMeetingLink(
                        crypto.randomUUID()
                    );

            }



            const exists = await db.query(

                `
SELECT id

FROM medorbit.appointments

WHERE doctor_id=$1

AND scheduled_date=$2

AND start_time=$3

AND status NOT IN
('cancelled')

`,

                [
                    doctor_id,
                    scheduled_date,
                    start_time
                ]

            );



            if (exists.rows.length) {

                return error(
                    res,
                    "Appointment slot already booked",
                    400,
                    "SLOT_BUSY"
                );

            }




            const result = await db.query(

                `
INSERT INTO medorbit.appointments
(
appointment_number,
patient_id,
doctor_id,
clinic_id,
scheduled_date,
start_time,
end_time,
duration_minutes,
appointment_type,
status,
meeting_link,
reason_for_visit,
notes
)

VALUES
(
'APT-' || floor(random()*1000000)::text,
$1,
$2,
$3,
$4,
$5,
$6,
$7,
$8,
'pending',
$9,
$10,
$11
)

RETURNING *

`,
                [
                    patient_id,
                    doctor_id,
                    clinic_id,
                    scheduled_date,
                    start_time,
                    end_time,
                    duration_minutes,
                    appointment_type,
                    meetingLink,
                    reason_for_visit,
                    notes
                ]

            );


            const appointment = result.rows[0];



            // history

            await db.query(

                `
INSERT INTO medorbit.appointment_status_history

(
appointment_id,
new_status
)

VALUES

($1,'pending')

`,

                [
                    appointment.id
                ]

            );



            return success(
                res,
                appointment,
                "Appointment booked"
            );



        }

        catch (err) {

            next(err);

        }


    });





// =====================================================
// GET MY APPOINTMENTS
// GET /api/appointments
// =====================================================


router.get(
    "/",

    authenticate,

    async (req, res, next) => {


        try {


            const result = await db.query(

                `

SELECT *

FROM medorbit.appointments

WHERE patient_id=$1

ORDER BY scheduled_date DESC

`,

                [
                    req.user.sub
                ]


            );



            return success(
                res,
                result.rows,
                "Appointments retrieved"
            );


        }

        catch (err) {

            next(err);

        }


    });





// =====================================================
// GET ONE
// =====================================================


router.get(
    "/:id",

    authenticate,

    async (req, res, next) => {


        try {


            const result = await db.query(

                `

SELECT *

FROM medorbit.appointments

WHERE id=$1

`,

                [
                    req.params.id
                ]

            );



            if (!result.rows.length) {

                return error(
                    res,
                    "Appointment not found",
                    404,
                    "NOT_FOUND"
                );

            }



            return success(
                res,
                result.rows[0],
                "Appointment retrieved"
            );



        }

        catch (err) {

            next(err);

        }

    });






// =====================================================
// CANCEL
// PUT /:id/cancel
// =====================================================


router.put(
    "/:id/cancel",

    authenticate,

    async (req, res, next) => {


        try {


            const result = await db.query(

                `

UPDATE medorbit.appointments

SET

status='cancelled',

cancelled_at=NOW(),

cancelled_by=$2,

cancellation_reason=$3

WHERE id=$1

RETURNING *

`,

                [
                    req.params.id,
                    req.user.sub,
                    req.body.reason
                ]

            );



            await db.query(

                `

INSERT INTO medorbit.appointment_status_history

(
appointment_id,
new_status,
changed_by
)

VALUES

($1,'cancelled',$2)

`,

                [
                    req.params.id,
                    req.user.sub
                ]

            );



            return success(
                res,
                result.rows[0],
                "Appointment cancelled"
            );



        }

        catch (err) {

            next(err);

        }

    });





// =====================================================
// CONFIRM
// =====================================================


router.put(
    "/:id/confirm",

    authenticate,

    authorize("doctor", "admin"),

    async (req, res, next) => {


        try {


            const result = await db.query(

                `

UPDATE medorbit.appointments

SET status='confirmed'

WHERE id=$1

RETURNING *

`,

                [
                    req.params.id
                ]

            );



            await db.query(

                `

INSERT INTO medorbit.appointment_status_history

(
appointment_id,
new_status,
changed_by
)

VALUES

($1,'confirmed',$2)

`,

                [
                    req.params.id,
                    req.user.sub
                ]

            );



            return success(
                res,
                result.rows[0],
                "Appointment confirmed"
            );



        }

        catch (err) {

            next(err);

        }

    });






// =====================================================
// COMPLETE
// =====================================================


router.put(
    "/:id/complete",

    authenticate,

    authorize("doctor"),

    async (req, res, next) => {


        try {


            const result = await db.query(

                `

UPDATE medorbit.appointments

SET status='completed'

WHERE id=$1

RETURNING *

`,

                [
                    req.params.id
                ]

            );



            return success(
                res,
                result.rows[0],
                "Appointment completed"
            );



        }

        catch (err) {

            next(err);

        }


    });





module.exports = router;