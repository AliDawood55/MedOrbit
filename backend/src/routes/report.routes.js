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
// GET MY REPORT SUMMARIES
// GET /api/reports/summaries
// Patient-scoped (any authenticated role, not admin-only): returns only the
// current user's own AI report summaries — written by the AI service's
// POST /summarize (Report Summarizer) — ordered newest first. Only safe,
// truncated fields are returned; the full extracted_text column is never
// sent to the client.
// ==========================================


router.get(

    "/reports/summaries",

    authenticate,

    async (req, res, next) => {

        try {

            const result =
                await require("../config/database")
                    .query(

                        `
SELECT id, summary_ar, summary_en,
       LEFT(extracted_text, 500) AS extracted_text_preview,
       model_used, source_file_type, created_at
FROM medorbit.report_summarizations
WHERE user_id=$1
ORDER BY created_at DESC
`,

                        [
                            req.user.sub
                        ]

                    );

            success(
                res,
                result.rows,
                "Report summaries retrieved"
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