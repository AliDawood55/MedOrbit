const fs = require('fs');
const path = require('path');
const router = require('express').Router();

const db = require('../config/database');
const { authenticate, authorize } = require('../middleware/auth');
const upload = require('../middleware/medicalRecordUpload');
const service = require('../services/medicalRecord.service');
const {
    resolvePatientForUser,
    resolveDoctorForUser,
    hasActiveCareRelationship,
    findAuthorizedMedicalRecord,
} = require('../services/clinicalAuthorization.service');
const { success, error } = require('../utils/response');
const { createAudit } = require('../services/audit.service');

function auditRecord(record) {
    return { id: record.id, patient_id: record.patient_id, doctor_id: record.doctor_id, appointment_id: record.appointment_id, record_type: record.record_type, is_draft: record.is_draft };
}

function patientRecordDto(record) {
    return {
        id: record.id,
        record_number: record.record_number,
        record_type: record.record_type,
        chief_complaint: record.chief_complaint,
        symptoms: record.symptoms,
        diagnosis: record.diagnosis,
        treatment_plan: record.treatment_plan,
        prognosis: record.prognosis,
        vitals: record.vitals,
        created_at: record.created_at,
        updated_at: record.updated_at,
    };
}

function attachmentDto(row) {
    return {
        id: row.id,
        record_id: row.record_id,
        file_name: row.file_name,
        file_type: row.file_type,
        file_size_bytes: row.file_size_bytes,
        mime_type: row.mime_type,
        created_at: row.created_at,
    };
}

async function requireRecordRead(req, res, next) {
    try {
        const record = await findAuthorizedMedicalRecord(req.params.id, req.user);
        if (!record) return error(res, 'Record not found', 404, 'NOT_FOUND');
        req.medicalRecord = record;
        return next();
    } catch (err) {
        return next(err);
    }
}

async function requireRecordMutation(req, res, next) {
    try {
        const record = await findAuthorizedMedicalRecord(req.params.id, req.user, { mutation: true });
        if (!record) return error(res, 'Record not found', 404, 'NOT_FOUND');
        req.medicalRecord = record;
        return next();
    } catch (err) {
        return next(err);
    }
}

router.post('/', authenticate, authorize('doctor'), async (req, res, next) => {
    let client;
    try {
        const doctor = await resolveDoctorForUser(req.user.sub);
        if (!doctor) return error(res, 'Appointment not found', 404, 'NOT_FOUND');

        const appointment = await db.query(
            `SELECT patient_id, doctor_id
             FROM medorbit.appointments
             WHERE id=$1 AND doctor_id=$2`,
            [req.body.appointment_id, doctor.id]
        );
        if (!appointment.rows.length) return error(res, 'Appointment not found', 404, 'NOT_FOUND');
        if (!await hasActiveCareRelationship(doctor.id, appointment.rows[0].patient_id)) {
            return error(res, 'Patient not found', 404, 'NOT_FOUND');
        }

        client = await db.getClient();
        await client.query('BEGIN');
        const record = await service.create({
            ...req.body,
            patient_id: appointment.rows[0].patient_id,
            doctor_id: doctor.id,
        }, client);
        await createAudit({ user_id: req.user.sub, user_role: req.user.role, action: 'MEDICAL_RECORD_CREATED', entity_type: 'MEDICAL_RECORD', entity_id: record.id, new_values: auditRecord(record) }, client);
        await client.query('COMMIT');
        return success(res, record, 'Medical record created', 201);
    } catch (err) {
        await client?.query('ROLLBACK').catch(() => {});
        return next(err);
    } finally { client?.release();
    }
});

router.get('/', authenticate, async (req, res, next) => {
    try {
        let result;
        if (req.user.role === 'patient') {
            const patient = await resolvePatientForUser(req.user.sub);
            if (!patient) return success(res, []);
            result = await db.query(
                `SELECT * FROM medorbit.medical_records
                 WHERE patient_id=$1 AND is_draft=false
                 ORDER BY created_at DESC`,
                [patient.id]
            );
            return success(res, result.rows.map(patientRecordDto));
        }
        if (req.user.role === 'doctor') {
            const doctor = await resolveDoctorForUser(req.user.sub);
            if (!doctor) return success(res, []);
            result = await db.query(
                `SELECT DISTINCT mr.*
                 FROM medorbit.medical_records mr
                 WHERE mr.doctor_id=$1 OR EXISTS (
                   SELECT 1 FROM medorbit.doctor_patient_relationships r
                   WHERE r.doctor_id=$1 AND r.patient_id=mr.patient_id
                     AND r.status='active'
                 )
                 ORDER BY mr.created_at DESC`,
                [doctor.id]
            );
            return success(res, result.rows);
        }
        return error(res, 'You do not have permission', 403, 'FORBIDDEN');
    } catch (err) {
        return next(err);
    }
});

router.get('/:id', authenticate, requireRecordRead, (req, res) => {
    const data = req.user.role === 'patient'
        ? patientRecordDto(req.medicalRecord)
        : req.medicalRecord;
    return success(res, data);
});

router.put('/:id', authenticate, authorize('doctor'), requireRecordMutation, async (req, res, next) => {
    let client;
    try {
        client = await db.getClient(); await client.query('BEGIN');
        const data = await service.update(req.params.id, req.body, client);
        if (!data) return error(res, 'Record not found', 404, 'NOT_FOUND');
        await createAudit({ user_id: req.user.sub, user_role: req.user.role, action: 'MEDICAL_RECORD_UPDATED', entity_type: 'MEDICAL_RECORD', entity_id: data.id, old_values: auditRecord(req.medicalRecord), new_values: auditRecord(data) }, client);
        await client.query('COMMIT');
        return success(res, data, 'Updated');
    } catch (err) {
        await client?.query('ROLLBACK').catch(() => {});
        return next(err);
    } finally { client?.release(); }
});

router.delete('/:id', authenticate, authorize('doctor'), requireRecordMutation, async (req, res, next) => {
    let client;
    try {
        client = await db.getClient(); await client.query('BEGIN');
        await service.remove(req.params.id, client);
        await createAudit({ user_id: req.user.sub, user_role: req.user.role, action: 'MEDICAL_RECORD_DELETED', entity_type: 'MEDICAL_RECORD', entity_id: req.params.id, old_values: auditRecord(req.medicalRecord), new_values: { deleted: true } }, client);
        await client.query('COMMIT');
        return success(res, null, 'Deleted');
    } catch (err) {
        await client?.query('ROLLBACK').catch(() => {});
        return next(err);
    } finally { client?.release(); }
});

router.post(
    '/:id/attachments',
    authenticate,
    authorize('doctor'),
    requireRecordMutation,
    upload.single('file'),
    async (req, res, next) => {
        try {
            if (!req.file) return error(res, 'No file uploaded', 400, 'FILE_REQUIRED');
            const relativePath = path.relative(process.cwd(), req.file.path).replace(/\\/g, '/');
            const result = await db.query(
                `INSERT INTO medorbit.medical_record_attachments
                   (record_id, file_name, file_path, file_size_bytes, mime_type, uploaded_by)
                 VALUES ($1,$2,$3,$4,$5,$6)
                 RETURNING id, record_id, file_name, file_type, file_size_bytes, mime_type, created_at`,
                [req.params.id, req.file.originalname, relativePath, req.file.size, req.file.mimetype, req.user.sub]
            );
            return success(res, attachmentDto(result.rows[0]), 'Attachment uploaded successfully', 201);
        } catch (err) {
            if (req.file?.path) fs.promises.unlink(req.file.path).catch(() => {});
            return next(err);
        }
    }
);

router.get('/:id/attachments', authenticate, requireRecordRead, async (req, res, next) => {
    try {
        const result = await db.query(
            `SELECT id, record_id, file_name, file_type, file_size_bytes, mime_type, created_at
             FROM medorbit.medical_record_attachments
             WHERE record_id=$1
             ORDER BY created_at DESC`,
            [req.params.id]
        );
        return success(res, result.rows.map(attachmentDto));
    } catch (err) {
        return next(err);
    }
});

router.get('/:id/attachments/:attachmentId/download', authenticate, requireRecordRead, async (req, res, next) => {
    try {
        const result = await db.query(
            `SELECT file_name, file_path
             FROM medorbit.medical_record_attachments
             WHERE id=$1 AND record_id=$2`,
            [req.params.attachmentId, req.params.id]
        );
        if (!result.rows.length) return error(res, 'Attachment not found', 404, 'NOT_FOUND');

        const storageRoot = path.resolve(process.cwd(), 'storage', 'medical-records');
        const absolutePath = path.resolve(process.cwd(), result.rows[0].file_path);
        if (!absolutePath.startsWith(`${storageRoot}${path.sep}`)) {
            return error(res, 'Attachment not found', 404, 'NOT_FOUND');
        }
        return res.download(absolutePath, result.rows[0].file_name, (err) => {
            if (err && !res.headersSent) next(err);
        });
    } catch (err) {
        return next(err);
    }
});

module.exports = router;
