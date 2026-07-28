const router = require("express").Router();

const {
    authenticate,
    authorize
} = require("../middleware/auth");


const {
    success,
    error
} = require("../utils/response");


const service =
    require("../services/report.service");





// Dashboard stats

router.get(

    "/dashboard/stats",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const data =
                await service.dashboardStats();


            success(
                res,
                data,
                "Dashboard statistics"
            );



        }

        catch (e) {

            next(e);

        }


    }

);








// Generate report


router.post(

    "/reports",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const {

                type,
                format = "json"

            } = req.body;



            const content =
                await service.generateReport(type);



            let filePath = null;



            const filename =
                `${type}-${Date.now()}.${format}`;





            if (format === "csv") {


                filePath =
                    await service.generateCSV(
                        content,
                        filename
                    );


            }





            if (format === "pdf") {


                filePath =
                    await service.generatePDF(
                        content,
                        filename
                    );


            }





            const report =
                await service.saveReport({

                    user_id: req.user.sub,

                    title:
                        `${type} report`,

                    type,

                    content,

                    format,

                    file_path: filePath

                });



            success(
                res,
                report,
                "Report generated",
                201
            );



        }

        catch (e) {

            next(e);

        }


    }

);





// Get generated reports


router.get(

    "/reports",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const result =
                await require("../config/database")
                    .query(

                        `
SELECT *
FROM medorbit.generated_reports
ORDER BY generated_at DESC
`

                    );



            success(
                res,
                result.rows,
                "Reports retrieved"
            );


        }

        catch (e) {

            next(e);

        }

    }

);

// ==========================================
// DOWNLOAD REPORT
// GET /api/reports/:id/download
// ==========================================


router.get(

    "/reports/:id/download",

    authenticate,

    authorize("admin"),

    async (req, res, next) => {


        try {


            const result =
                await require("../config/database")
                    .query(

                        `
SELECT file_path,format
FROM medorbit.generated_reports
WHERE id=$1
`,

                        [
                            req.params.id
                        ]

                    );



            if (!result.rows.length) {

                return error(
                    res,
                    "Report not found",
                    404,
                    "NOT_FOUND"
                );

            }



            const file =
                result.rows[0].file_path;



            if (!file) {

                return error(
                    res,
                    "No file available",
                    400,
                    "NO_FILE"
                );

            }



            res.download(file);



        }

        catch (e) {

            next(e);

        }


    }

);




module.exports = router;