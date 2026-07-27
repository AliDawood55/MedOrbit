const PDFDocument = require("pdfkit");


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


module.exports = {
    generatePrescriptionPDF
};