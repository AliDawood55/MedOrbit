const router = require("express").Router();

const {
    authenticate,
    authorizeAdmin
} = require("../middleware/auth");


const {
    success,
    error
} = require("../utils/response");


const service =
    require("../services/report.service");

const fs = require("fs");
const path = require("path");

const REPORT_TYPES = new Set(["appointments", "medical_records", "prescriptions"]);
const REPORT_FORMATS = new Set(["json", "csv", "pdf"]);

function resolveStoredReportPath(filePath, format) {
    if (!filePath || !["csv", "pdf"].includes(format)) return null;

    const reportsDirectory = `${path.resolve(service.REPORTS_DIR)}${path.sep}`;
    const resolvedFile = path.resolve(filePath);

    if (!resolvedFile.startsWith(reportsDirectory)) return null;
    if (path.extname(resolvedFile).toLowerCase() !== `.${format}`) return null;

    try {
        return fs.statSync(resolvedFile).isFile() ? resolvedFile : null;
    } catch {
        return null;
    }
}





// Dashboard stats

router.get(

    "/dashboard/stats",

    authenticate,

    authorizeAdmin,

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

    authorizeAdmin,

    async (req, res, next) => {


        try {


            const {

                type,
                format = "json"

            } = req.body;



            if (!REPORT_TYPES.has(type)) {
                return error(res, "Unsupported report type", 400, "VALIDATION_ERROR");
            }

            if (!REPORT_FORMATS.has(format)) {
                return error(res, "Unsupported report format", 400, "VALIDATION_ERROR");
            }

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

    authorizeAdmin,

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
// current user's own AI report summaries — written through the Node
// POST /api/ai/summarize identity boundary — ordered newest first. Only safe,
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

    authorizeAdmin,

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



            const file = resolveStoredReportPath(
                result.rows[0].file_path,
                result.rows[0].format
            );



            if (!file) {

                return error(
                    res,
                    "Report file is unavailable",
                    404,
                    "REPORT_FILE_UNAVAILABLE"
                );

            }



            res.download(file, path.basename(file));



        }

        catch (e) {

            next(e);

        }


    }

);




module.exports = router;
