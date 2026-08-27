const db = require("../config/database");
const PDFDocument = require("pdfkit");
const { Parser } = require("json2csv");
const fs = require("fs");
const path = require("path");

const REPORTS_DIR = path.resolve(process.cwd(), "storage", "reports");

// Shared trailing window for the two time-series analytics charts (appointments,
// AI conversations) so both cover the same span and a single constant documents
// the choice: 12 weeks gives a quarter-ish trend without downloading raw rows
// and grouping them in JS.
const ANALYTICS_WEEKS = 12;

// ===============================
// Dashboard Analytics (per-chart)
// ===============================
// Each section is queried and caught independently: a single query failing
// (e.g. a table that genuinely has no rows yet, or an unexpected error) must
// not take down the aggregate totals above or the other five sections. Every
// query aggregates in SQL — no SELECT * + in-memory grouping.

async function usersByRoleAnalytics() {
    const result = await db.query(
        `SELECT role, COUNT(*)::int AS count
         FROM medorbit.users
         WHERE deleted_at IS NULL
         GROUP BY role
         ORDER BY count DESC`
    );
    return {
        labels: result.rows.map((r) => r.role),
        counts: result.rows.map((r) => r.count)
    };
}

async function appointmentsOverTimeAnalytics() {
    const result = await db.query(
        `WITH weeks AS (
            SELECT generate_series(
                date_trunc('week', CURRENT_DATE) - ($1 - 1) * INTERVAL '1 week',
                date_trunc('week', CURRENT_DATE),
                INTERVAL '1 week'
            )::date AS week_start
         )
         SELECT w.week_start, COUNT(a.id)::int AS count
         FROM weeks w
         LEFT JOIN medorbit.appointments a
             ON date_trunc('week', a.scheduled_date) = w.week_start
         GROUP BY w.week_start
         ORDER BY w.week_start`,
        [ANALYTICS_WEEKS]
    );
    return {
        labels: result.rows.map((r) => r.week_start.toISOString().slice(0, 10)),
        counts: result.rows.map((r) => r.count)
    };
}

async function topSpecialtiesAnalytics() {
    const result = await db.query(
        `SELECT s.name_ar, s.name_en, COUNT(a.id)::int AS count
         FROM medorbit.specialties s
         JOIN medorbit.doctors d ON d.specialty_id = s.id
         JOIN medorbit.appointments a ON a.doctor_id = d.id
         GROUP BY s.id, s.name_ar, s.name_en
         ORDER BY count DESC
         LIMIT 8`
    );
    return {
        items: result.rows.map((r) => ({ nameAr: r.name_ar, nameEn: r.name_en, count: r.count }))
    };
}

async function conversationsPerWeekAnalytics() {
    const result = await db.query(
        `WITH weeks AS (
            SELECT generate_series(
                date_trunc('week', CURRENT_DATE) - ($1 - 1) * INTERVAL '1 week',
                date_trunc('week', CURRENT_DATE),
                INTERVAL '1 week'
            )::date AS week_start
         )
         SELECT w.week_start, COUNT(c.id)::int AS count
         FROM weeks w
         LEFT JOIN medorbit.chatbot_conversations c
             ON date_trunc('week', c.started_at) = w.week_start
         GROUP BY w.week_start
         ORDER BY w.week_start`,
        [ANALYTICS_WEEKS]
    );
    return {
        labels: result.rows.map((r) => r.week_start.toISOString().slice(0, 10)),
        counts: result.rows.map((r) => r.count)
    };
}

async function triageLevelsAnalytics() {
    const result = await db.query(
        `SELECT urgency_level, COUNT(*)::int AS count
         FROM medorbit.virtual_doctor_sessions
         WHERE urgency_level IS NOT NULL
         GROUP BY urgency_level`
    );
    return {
        labels: result.rows.map((r) => r.urgency_level),
        counts: result.rows.map((r) => r.count)
    };
}

async function clinicTypesAnalytics() {
    const result = await db.query(
        `SELECT type, COUNT(*)::int AS count
         FROM medorbit.clinics
         WHERE type IS NOT NULL
         GROUP BY type
         ORDER BY count DESC`
    );
    return {
        labels: result.rows.map((r) => r.type),
        counts: result.rows.map((r) => r.count)
    };
}

// Runs one section, swallowing its own failure so the rest of the dashboard
// still renders. Returns { data } on success or { error } on failure — the
// route layer never sees a thrown exception from an individual section.
async function runAnalyticsSection(label, fn) {
    try {
        return { data: await fn() };
    } catch (err) {
        console.error(`Analytics: ${label} query failed`, err);
        return { error: true };
    }
}

async function dashboardAnalytics() {
    const [
        usersByRole,
        appointmentsOverTime,
        topSpecialties,
        conversationsPerWeek,
        triageLevels,
        clinicTypes
    ] = await Promise.all([
        runAnalyticsSection("usersByRole", usersByRoleAnalytics),
        runAnalyticsSection("appointmentsOverTime", appointmentsOverTimeAnalytics),
        runAnalyticsSection("topSpecialties", topSpecialtiesAnalytics),
        runAnalyticsSection("conversationsPerWeek", conversationsPerWeekAnalytics),
        runAnalyticsSection("triageLevels", triageLevelsAnalytics),
        runAnalyticsSection("clinicTypes", clinicTypesAnalytics)
    ]);

    return { usersByRole, appointmentsOverTime, topSpecialties, conversationsPerWeek, triageLevels, clinicTypes };
}

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



    result.analytics =
        await dashboardAnalytics();



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

    const reportsDir = REPORTS_DIR;


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

    const reportsDir = REPORTS_DIR;


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
    dashboardAnalytics,
    generateReport,
    saveReport,
    generateCSV,
    generatePDF,
    REPORTS_DIR

};
