const service =
    require("../services/medicalRecord.service");


const {
    success,
    error
} = require("../utils/response");





exports.getPatientRecords = async (req, res, next) => {

    try {


        const records =
            await service.getPatientRecords(
                req.params.id
            );


        return success(
            res,
            records,
            "Medical records retrieved"
        );



    }
    catch (err) {

        next(err);

    }

};







exports.getRecord = async (req, res, next) => {

    try {


        const record =
            await service.getRecord(
                req.params.id
            );



        if (!record) {

            return error(
                res,
                "Record not found",
                404,
                "NOT_FOUND"
            );

        }



        return success(
            res,
            record,
            "Medical record retrieved"
        );



    }
    catch (err) {

        next(err);

    }

};









exports.createRecord = async (req, res, next) => {

    try {


        const record =
            await service.createRecord(
                req.body
            );



        return success(
            res,
            record,
            "Medical record created"
        );



    }
    catch (err) {

        next(err);

    }

};









exports.updateRecord = async (req, res, next) => {


    try {


        const record =
            await service.updateRecord(
                req.params.id,
                req.body
            );



        return success(
            res,
            record,
            "Medical record updated"
        );



    }
    catch (err) {

        next(err);

    }

};








exports.deleteRecord = async (req, res, next) => {


    try {


        await service.deleteRecord(
            req.params.id
        );



        return success(
            res,
            null,
            "Medical record deleted"
        );



    }
    catch (err) {

        next(err);

    }

};