const db = require("../config/database");



class MedicalRecordService {


    async getPatientRecords(patientId) {


        const result = await db.query(

            `
SELECT
mr.*,

p.first_name_ar,
p.last_name_ar,

d.id AS doctor_id

FROM public.medical_records mr


LEFT JOIN public.patients pt
ON pt.id = mr.patient_id


LEFT JOIN public.user_profiles p
ON p.user_id = pt.user_id


WHERE mr.patient_id=$1

ORDER BY mr.created_at DESC

`,
            [
                patientId
            ]

        );


        return result.rows;


    }





    async getRecord(id) {


        const result = await db.query(

            `
SELECT *

FROM public.medical_records

WHERE id=$1
`,
            [
                id
            ]

        );


        return result.rows[0];


    }







    async createRecord(data) {


        const {

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
            doctor_notes

        } = data;



        const result = await db.query(

            `

INSERT INTO public.medical_records

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
doctor_notes
)


VALUES

(
'MR-' || floor(random()*1000000)::text,
$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13
)


RETURNING *

`,

            [

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
                doctor_notes

            ]


        );


        return result.rows[0];


    }







    async updateRecord(id, data) {


        const {

            diagnosis,
            treatment_plan,
            clinical_notes,
            doctor_notes,
            vitals

        } = data;



        const result = await db.query(

            `

UPDATE public.medical_records

SET

diagnosis=COALESCE($1,diagnosis),

treatment_plan=COALESCE($2,treatment_plan),

clinical_notes=COALESCE($3,clinical_notes),

doctor_notes=COALESCE($4,doctor_notes),

vitals=COALESCE($5,vitals),

updated_at=NOW()


WHERE id=$6

RETURNING *

`,

            [
                diagnosis,
                treatment_plan,
                clinical_notes,
                doctor_notes,
                vitals,
                id
            ]


        );


        return result.rows[0];


    }







    async deleteRecord(id) {


        await db.query(

            `
DELETE FROM public.medical_records

WHERE id=$1
`,
            [
                id
            ]

        );


    }



}


module.exports = new MedicalRecordService();