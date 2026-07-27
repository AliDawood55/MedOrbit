const db = require("../config/database");



class MedicalRecordService {



    async create(data) {


        const result = await db.query(

            `
INSERT INTO medorbit.medical_records
(
record_number,
patient_id,
doctor_id,
appointment_id,
record_type,
chief_complaint,
symptoms,
diagnosis,
diagnosis_codes,
treatment_plan,
prognosis,
vitals,
clinical_notes,
doctor_notes,
is_draft
)

VALUES

(
'MR-'||to_char(now(),'YYYY')||'-'||floor(random()*100000),
$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
)

RETURNING *

`,

            [
                data.patient_id,
                data.doctor_id,
                data.appointment_id,
                data.record_type,
                data.chief_complaint,
                data.symptoms,
                data.diagnosis,
                data.diagnosis_codes,
                data.treatment_plan,
                data.prognosis,
                data.vitals,
                data.clinical_notes,
                data.doctor_notes,
                data.is_draft
            ]


        );


        return result.rows[0];

    }





    async findAll() {


        const result =
            await db.query(

                `
SELECT *
FROM medorbit.medical_records
ORDER BY created_at DESC

`

            );


        return result.rows;


    }





    async findById(id) {


        const result =
            await db.query(

                `
SELECT *
FROM medorbit.medical_records
WHERE id=$1

`,
                [id]

            );


        return result.rows[0];

    }





    async update(id, data) {


        const result =
            await db.query(

                `
UPDATE medorbit.medical_records

SET

diagnosis=$1,
treatment_plan=$2,
clinical_notes=$3,
doctor_notes=$4,
vitals=$5,
is_draft=$6,
updated_at=NOW()

WHERE id=$7

RETURNING *

`,

                [
                    data.diagnosis,
                    data.treatment_plan,
                    data.clinical_notes,
                    data.doctor_notes,
                    data.vitals,
                    data.is_draft,
                    id
                ]


            );


        return result.rows[0];

    }





    async remove(id) {


        await db.query(

            `
DELETE FROM medorbit.medical_records

WHERE id=$1

`,
            [id]

        );


    }



    async addAttachment(data) {


        const result =
            await db.query(

                `
INSERT INTO medorbit.medical_record_attachments

(
record_id,
file_name,
file_type,
file_path,
file_size_bytes,
mime_type,
uploaded_by
)

VALUES

($1,$2,$3,$4,$5,$6,$7)

RETURNING *

`,

                [
                    data.record_id,
                    data.file_name,
                    data.file_type,
                    data.file_path,
                    data.file_size_bytes,
                    data.mime_type,
                    data.uploaded_by
                ]


            );


        return result.rows[0];


    }





    async getAttachments(id) {


        const result =
            await db.query(

                `
SELECT *

FROM medorbit.medical_record_attachments

WHERE record_id=$1

ORDER BY created_at DESC

`,
                [id]

            );


        return result.rows;


    }



}


module.exports = new MedicalRecordService();