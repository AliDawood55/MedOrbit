const PDFDocument = require("pdfkit");
const db = require("../config/database");


function generatePrescriptionPDF(prescription, items) {

    const doc = new PDFDocument();


    doc.fontSize(20)
        .text("MedOrbit Prescription");


    doc.moveDown();


    doc.fontSize(12)
        .text(
            `Prescription Number: ${prescription.prescription_number}`
        );


    doc.text(
        `Date: ${prescription.prescription_date}`
    );


    doc.text(
        `Diagnosis: ${prescription.diagnosis || ""}`
    );


    doc.moveDown();


    doc.text("Medications:");

    items.forEach((item, index) => {

        doc.text(
            `${index + 1}. ${item.medication_name_en}
             - ${item.dosage}
             - ${item.frequency}`
        );

    });


    doc.end();


    return doc;

}


// Patient's own "my prescriptions" list. Ownership is enforced in the WHERE
// clause, not checked after the fact — mirrors medical.repository.js's
// findRecordsByPatientId, the existing pattern for this exact page pair.
//
// Items are aggregated in the same query (not a separate per-row fetch):
// the frontend has no separate "detail" call — my-prescriptions.js renders
// its detail panel from the same object this list returns — so a list
// response without items would silently break the medication breakdown for
// every prescription.
async function findByPatientId(patientId, { limit = 20, offset = 0 } = {}) {
    const result = await db.query(
        `SELECT
             p.id, p.prescription_number, p.prescription_date, p.valid_until,
             p.status, p.diagnosis, p.instructions, p.doctor_notes,
             COALESCE(
                 json_agg(
                     json_build_object(
                         'medication_name_ar', i.medication_name_ar,
                         'medication_name_en', i.medication_name_en,
                         'dosage', i.dosage,
                         'frequency', i.frequency,
                         'duration', i.duration,
                         'quantity', i.quantity,
                         'instructions', i.instructions
                     )
                 ) FILTER (WHERE i.id IS NOT NULL),
                 '[]'
             ) AS items
         FROM medorbit.prescriptions p
         LEFT JOIN medorbit.prescription_items i ON i.prescription_id = p.id
         WHERE p.patient_id = $1
         GROUP BY p.id
         ORDER BY p.prescription_date DESC
         LIMIT $2 OFFSET $3`,
        [patientId, limit, offset]
    );
    return result.rows;
}

// Single prescription + its items, for the patient's own detail view. The
// id+patient_id match IS the ownership check — a prescription that belongs
// to someone else returns null here, same as not found.
async function findByIdForPatient(id, patientId) {
    const prescription = await db.query(
        `SELECT id, prescription_number, prescription_date, valid_until, status,
                diagnosis, instructions, doctor_notes
         FROM medorbit.prescriptions
         WHERE id = $1 AND patient_id = $2`,
        [id, patientId]
    );
    if (!prescription.rows[0]) return null;

    const items = await db.query(
        `SELECT medication_name_ar, medication_name_en, dosage, frequency,
                duration, quantity, instructions
         FROM medorbit.prescription_items
         WHERE prescription_id = $1`,
        [id]
    );
    return { prescription: prescription.rows[0], items: items.rows };
}

module.exports = {
    generatePrescriptionPDF,
    findByPatientId,
    findByIdForPatient
};