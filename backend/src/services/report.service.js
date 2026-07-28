const db = require("../config/database");
const PDFDocument = require("pdfkit");
const { Parser } = require("json2csv");
const fs = require("fs");
const path = require("path");



// ===============================
// Dashboard Statistics
// ===============================

async function dashboardStats() {

    const result = {};



    const users =
        await db.query(
            `
        SELECT
        COUNT(*) total,

        COUNT(*) FILTER(
            WHERE role='patient'
        ) patients,

        COUNT(*) FILTER(
            WHERE role='doctor'
        ) doctors

        FROM medorbit.users
        `
        );


    result.users = users.rows[0];





    const appointments =
        await db.query(
            `
        SELECT

        COUNT(*) total,

        COUNT(*) FILTER(
        WHERE status='completed'
        ) completed,

        COUNT(*) FILTER(
        WHERE status='cancelled'
        ) cancelled,

        COUNT(*) FILTER(
        WHERE status='scheduled'
        ) scheduled

        FROM medorbit.appointments

        `
        );


    result.appointments =
        appointments.rows[0];





    const records =
        await db.query(
            `
        SELECT COUNT(*) total
        FROM medorbit.medical_records
        `
        );


    result.medical_records =
        records.rows[0];





    const prescriptions =
        await db.query(
            `
        SELECT COUNT(*) total
        FROM medorbit.prescriptions
        `
        );


    result.prescriptions =
        prescriptions.rows[0];





    const rating =
        await db.query(
            `
        SELECT

        ROUND(
        AVG(average_rating),
        2
        ) average

        FROM medorbit.doctors

        WHERE average_rating IS NOT NULL

        `
        );


    result.ratings =
        rating.rows[0];



    return result;

}






// ===============================
// Generate Report Data
// ===============================

async function generateReport(type) {


    let query;



    switch (type) {


        case "appointments":

            query =
                `
            SELECT *
            FROM medorbit.appointments
            ORDER BY created_at DESC
            `;

            break;



        case "medical_records":

            query =
                `
            SELECT *
            FROM medorbit.medical_records
            ORDER BY created_at DESC
            `;

            break;



        case "prescriptions":

            query =
                `
            SELECT *
            FROM medorbit.prescriptions
            ORDER BY created_at DESC
            `;

            break;



        default:

            throw new Error(
                "Invalid report type"
            );

    }



    const result =
        await db.query(query);



    return result.rows;


}





async function saveReport(data) {


    const result =
        await db.query(

            `
        INSERT INTO medorbit.generated_reports
        (
        generated_by,
        report_title,
        report_type,
        report_data,
        format,
        file_path,
        generated_at
        )

        VALUES
        (
        $1,$2,$3,$4,$5,$6,NOW()
        )

        RETURNING *
        `,

            [
                data.user_id,
                data.title,
                data.type,
                JSON.stringify(data.content),
                data.format,
                data.file_path
            ]

        );


    return result.rows[0];

}
// ==========================================
// Generate CSV File
// ==========================================

async function generateCSV(rows, filename) {

    const reportsDir =
        path.join(
            process.cwd(),
            "storage",
            "reports"
        );


    if (!fs.existsSync(reportsDir)) {
        fs.mkdirSync(
            reportsDir,
            { recursive: true }
        );
    }


    const parser =
        new Parser();


    const csv =
        parser.parse(rows);



    const filePath =
        path.join(
            reportsDir,
            filename
        );


    fs.writeFileSync(
        filePath,
        csv
    );


    return filePath;

}






// ==========================================
// Generate PDF File
// ==========================================


async function generatePDF(rows, filename) {

    const reportsDir =
        path.join(
            process.cwd(),
            "storage",
            "reports"
        );


    if (!fs.existsSync(reportsDir)) {
        fs.mkdirSync(
            reportsDir,
            { recursive: true }
        );
    }



    const filePath =
        path.join(
            reportsDir,
            filename
        );



    return new Promise((resolve, reject) => {


        const doc =
            new PDFDocument({
                margin: 40
            });



        const stream =
            fs.createWriteStream(
                filePath
            );


        doc.pipe(stream);



        doc.fontSize(18)
            .text(
                "MedOrbit Report",
                {
                    align: "center"
                }
            );


        doc.moveDown();



        rows.forEach((row, index) => {


            doc.fontSize(10)
                .text(
                    `${index + 1}. ${JSON.stringify(row)}`
                );


            doc.moveDown();


        });



        doc.end();



        stream.on(
            "finish",
            () => {
                resolve(filePath);
            }
        );


        stream.on(
            "error",
            reject
        );


    });


}




module.exports = {

    dashboardStats,
    generateReport,
    saveReport,
    generateCSV,
    generatePDF

};