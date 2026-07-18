const express = require("express");

const router = express.Router();

const db = require("../config/database");

const {
  success,
  error
} = require("../utils/response");


const {
  authenticate,
  authorize
} = require("../middleware/auth");



function haversine(

  lat1,
  lon1,
  lat2,
  lon2

) {

  const R = 6371;


  const dLat =

    (lat2 - lat1) *
    Math.PI / 180;


  const dLon =

    (lon2 - lon1) *
    Math.PI / 180;


  const a =

    Math.sin(dLat / 2) *
    Math.sin(dLat / 2)

    +

    Math.cos(

      lat1 *
      Math.PI / 180

    )

    *

    Math.cos(

      lat2 *
      Math.PI / 180

    )

    *

    Math.sin(dLon / 2)

    *

    Math.sin(dLon / 2);



  const c =

    2 *

    Math.atan2(

      Math.sqrt(a),

      Math.sqrt(1 - a)

    );


  return R * c;

}




//---------------------------------------------------
// GET ALL CLINICS
//---------------------------------------------------


router.get(

  "/",

  async (req, res, next) => {

    try {


      const {

        page = 1,

        limit = 10,

        city,

        type,

        search

      } = req.query;



      let query =

        `

SELECT

id,
name_ar,
name_en,
city,
region,
phone,
email,
website,
latitude,
longitude,
type,
verification_status

FROM public.clinics

WHERE is_active=true

`;


      const params = [];


      let index = 1;



      if (city) {

        query +=

          ` AND city ILIKE $${index}`;

        params.push(

          `%${city}%`

        );

        index++;

      }



      if (type) {

        query +=

          ` AND type=$${index}`;

        params.push(type);

        index++;

      }



      if (search) {

        query +=

          `

AND(

name_ar ILIKE $${index}

OR

name_en ILIKE $${index}

)

`;

        params.push(

          `%${search}%`

        );

        index++;

      }


      query +=

        `

ORDER BY name_en

LIMIT $${index}

OFFSET $${index + 1}

`;


      params.push(

        parseInt(limit),

        (parseInt(page) - 1)

        *

        parseInt(limit)

      );


      const result =

        await db.query(

          query,
          params
        );


      return success(

        res,

        result.rows,

        "Clinics retrieved successfully"

      );

    }

    catch (err) {

      next(err);

    }

  }

);




//---------------------------------------------------
// NEARBY CLINICS
//---------------------------------------------------


router.get(

  "/nearby",

  async (req, res, next) => {


    try {


      const {

        latitude,

        longitude,

        radius = 5

      } = req.query;



      if (

        !latitude ||

        !longitude

      ) {

        return error(

          res,

          "Latitude and longitude are required",

          400,

          "VALIDATION_ERROR"

        );

      }



      const result =

        await db.query(

          `

SELECT *

FROM public.clinics

WHERE is_active=true

`

        );



      const nearby =

        result.rows.filter(

          clinic => {


            const distance =

              haversine(

                parseFloat(latitude),

                parseFloat(longitude),

                parseFloat(clinic.latitude),

                parseFloat(clinic.longitude)

              );


            clinic.distance =

              distance.toFixed(2);


            return (

              distance <=

              parseFloat(radius)

            );


          }

        );


      return success(

        res,

        nearby,

        "Nearby clinics"

      );


    }

    catch (err) {

      next(err);

    }


  }

);




//---------------------------------------------------
// GET CLINIC BY ID
//---------------------------------------------------


router.get(

  "/:id",

  async (req, res, next) => {


    try {


      const result =

        await db.query(

          `

SELECT *

FROM public.clinics

WHERE id=$1

AND is_active=true

`,

          [

            req.params.id

          ]

        );



      if (

        result.rows.length === 0

      ) {

        return error(

          res,

          "Clinic not found",

          404,

          "NOT_FOUND"

        );

      }


      return success(

        res,

        result.rows[0]

      );


    }

    catch (err) {

      next(err);

    }


  }

);




//---------------------------------------------------
// CREATE CLINIC
//---------------------------------------------------


router.post(

  "/",

  authenticate,

  authorize("admin"),

  async (req, res, next) => {


    try {


      const {

        name_ar,
        name_en,
        address_ar,
        address_en,
        city,
        region,
        latitude,
        longitude,
        phone,
        email,
        website,
        type

      } = req.body;



      await db.query(

        `

INSERT INTO public.clinics(

name_ar,
name_en,
address_ar,
address_en,
city,
region,
latitude,
longitude,
phone,
email,
website,
type

)

VALUES(

$1,$2,$3,$4,
$5,$6,$7,$8,
$9,$10,$11,$12

)

`

        ,

        [

          name_ar,
          name_en,
          address_ar,
          address_en,
          city,
          region,
          latitude,
          longitude,
          phone,
          email,
          website,
          type

        ]

      );


      return success(

        res,

        null,

        "Clinic created successfully"

      );


    }

    catch (err) {

      next(err);

    }


  }

);




//---------------------------------------------------
// UPDATE
//---------------------------------------------------


router.put(

  "/:id",

  authenticate,

  authorize("admin"),

  async (req, res, next) => {


    try {


      const {

        name_ar,
        name_en,
        phone

      } = req.body;



      const result =

        await db.query(

          `

UPDATE public.clinics

SET

name_ar=COALESCE($1,name_ar),

name_en=COALESCE($2,name_en),

phone=COALESCE($3,phone)

WHERE id=$4

AND is_active=true

`

          ,

          [

            name_ar,

            name_en,

            phone,

            req.params.id

          ]

        );



      if (

        result.rowCount === 0

      ) {

        return error(

          res,

          "Clinic not found",

          404,

          "NOT_FOUND"

        );

      }



      return success(

        res,

        null,

        "Clinic updated"

      );


    }

    catch (err) {

      next(err);

    }


  }

);




//---------------------------------------------------
// DELETE
//---------------------------------------------------


router.delete(

  "/:id",

  authenticate,

  authorize("admin"),

  async (req, res, next) => {


    try {


      const result =

        await db.query(

          `

UPDATE public.clinics

SET is_active=false

WHERE id=$1

AND is_active=true

`

          ,

          [

            req.params.id

          ]

        );



      if (

        result.rowCount === 0

      ) {

        return error(

          res,

          "Clinic not found",

          404,

          "NOT_FOUND"

        );

      }


      return success(

        res,

        null,

        "Clinic deleted"

      );


    }

    catch (err) {

      next(err);

    }


  }

);

// POST /api/clinics/:id/assign-doctor
// Admin only

router.post(
  "/:id/assign-doctor",
  authenticate,
  authorize("admin"),
  async (req, res, next) => {

    try {

      const clinicId = req.params.id;


      const {
        doctorId,
        isPrimary = false,
        consultationFeeOverride = null
      } = req.body;



      if (!doctorId) {

        return error(
          res,
          "Doctor id is required",
          400,
          "VALIDATION_ERROR"
        );

      }



      // Check clinic exists

      const clinic =
        await db.query(
          `
          SELECT id
          FROM public.clinics
          WHERE id=$1
          AND is_active=true
          `,
          [
            clinicId
          ]
        );


      if (clinic.rows.length === 0) {

        return error(
          res,
          "Clinic not found",
          404,
          "NOT_FOUND"
        );

      }




      // Check doctor exists

      const doctor =
        await db.query(
          `
          SELECT id
          FROM public.doctors
          WHERE id=$1
          `,
          [
            doctorId
          ]
        );


      if (doctor.rows.length === 0) {

        return error(
          res,
          "Doctor not found",
          404,
          "NOT_FOUND"
        );

      }



      // Insert assignment

      await db.query(

        `
        INSERT INTO public.doctor_clinic_assignments
        (
          doctor_id,
          clinic_id,
          is_primary,
          consultation_fee_override,
          is_active
        )

        VALUES
        (
          $1,$2,$3,$4,true
        )

        ON CONFLICT
        (
          doctor_id,
          clinic_id
        )

        DO UPDATE SET

        is_active=true,
        is_primary=$3,
        consultation_fee_override=$4

        `,

        [
          doctorId,
          clinicId,
          isPrimary,
          consultationFeeOverride
        ]

      );



      return success(
        res,
        null,
        "Doctor assigned successfully"
      );


    }
    catch (err) {

      next(err);

    }

  });

// DELETE /api/clinics/:id/remove-doctor/:doctorId

router.delete(

  "/:id/remove-doctor/:doctorId",

  authenticate,

  authorize("admin"),

  async (req, res, next) => {


    try {


      await db.query(

        `
UPDATE public.doctor_clinic_assignments

SET is_active=false

WHERE clinic_id=$1

AND doctor_id=$2
`,

        [
          req.params.id,
          req.params.doctorId
        ]

      );



      return success(
        res,
        null,
        "Doctor removed from clinic"
      );



    }
    catch (err) {

      next(err);

    }


  });



module.exports = router;