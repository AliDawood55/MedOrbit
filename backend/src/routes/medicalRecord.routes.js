const express = require("express");

const router = express.Router();


const controller =
    require("../controllers/medicalRecord.controller");


const {
    authenticate
} = require("../middleware/auth");





router.get(
    "/patient/:id",
    authenticate,
    controller.getPatientRecords
);



router.get(
    "/:id",
    authenticate,
    controller.getRecord
);



router.post(
    "/",
    authenticate,
    controller.createRecord
);



router.put(
    "/:id",
    authenticate,
    controller.updateRecord
);



router.delete(
    "/:id",
    authenticate,
    controller.deleteRecord
);



module.exports = router;