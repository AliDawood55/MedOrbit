# MedOrbit Shared API Contracts — v1

**Status:** frozen for Ali's Web and Mobile integration on 2026-08-24.  These
contracts describe the current Express API; a client must not infer behavior
from database tables or call the AI service directly.

## 1. Common rules

Base path: `/api`.  Protected endpoints require `Authorization: Bearer <access-token>`.

All endpoints documented here use the envelope below unless explicitly noted
as a binary download.

```json
// Success
{ "success": true, "data": {}, "message": "...", "timestamp": "ISO-8601" }

// Error
{ "success": false, "error": { "code": "...", "message": "...", "details": null, "timestamp": "ISO-8601" } }
```

Clients must use the HTTP status and `error.code`; do not parse English
messages.  Common codes are `UNAUTHORIZED` (401), `FORBIDDEN` (403),
`NOT_FOUND` (404), `VALIDATION_ERROR` (400), and `AI_SERVICE_ERROR`.

## 2. SHARED-01 — Clinical authoring

### Medical records

| Operation | Endpoint | Caller | Success |
|---|---|---|---|
| Create | `POST /medical-records` | Approved doctor | 201 |
| List | `GET /medical-records` | Patient or doctor | 200 |
| Detail | `GET /medical-records/:id` | Authorized patient or doctor | 200 |
| Update | `PUT /medical-records/:id` | Record's authorized doctor | 200 |
| Delete | `DELETE /medical-records/:id` | Record's authorized doctor | 200 |
| Upload attachment | `POST /medical-records/:id/attachments` | Record's authorized doctor | 201 |
| List attachments | `GET /medical-records/:id/attachments` | Authorized reader | 200 |
| Download attachment | `GET /medical-records/:id/attachments/:attachmentId/download` | Authorized reader | binary PDF/image |

Create requires a doctor-owned `appointment_id`. The backend derives
`patient_id` and `doctor_id`; clients must not send either as authoritative
values. The appointment must belong to the doctor and the doctor/patient care
relationship must be active.

```json
{
  "appointment_id": "uuid",
  "record_type": "consultation",
  "chief_complaint": "string or null",
  "symptoms": "string/JSON or null",
  "diagnosis": "string or null",
  "diagnosis_codes": "string/JSON or null",
  "treatment_plan": "string or null",
  "prognosis": "string or null",
  "vitals": "object/JSON or null",
  "clinical_notes": "string or null",
  "doctor_notes": "string or null",
  "is_draft": false
}
```

Update accepts and replaces these six fields: `diagnosis`, `treatment_plan`,
`clinical_notes`, `doctor_notes`, `vitals`, and `is_draft`. Send the complete
desired values for those fields; omitted fields currently become `null`.

Patient visibility is **only** `is_draft`: patients receive records where
`is_draft=false`; there is no `visible_to_patient` field in v1. Doctor-facing
responses include the stored record. Patient-facing list/detail responses
exclude `clinical_notes`, `doctor_notes`, `is_draft`, and relationship IDs.

Attachment request: `multipart/form-data`, field name `file`; maximum 10 MiB;
allowed types are PDF, JPEG/JPG, and PNG. The download endpoint is an actual
file response, not the JSON envelope.

### Prescriptions

| Operation | Endpoint | Caller | Success |
|---|---|---|---|
| Create | `POST /prescriptions` | Approved doctor | 201 |
| Detail + items | `GET /prescriptions/:id` | Owning patient or authorized doctor | 200 |
| PDF | `GET /prescriptions/:id/pdf` | Owning patient or authorized doctor | PDF download |

Create requires `patient_id`, `appointment_id`, and at least one item. The
appointment must belong to the named patient and authenticated doctor, and an
active care relationship is required.

```json
{
  "patient_id": "uuid",
  "appointment_id": "uuid",
  "valid_until": "YYYY-MM-DD or null",
  "diagnosis": "string or null",
  "instructions": "string or null",
  "doctor_notes": "string or null",
  "items": [{
    "medication_name_ar": "string or null",
    "medication_name_en": "string or null",
    "dosage": "string or null",
    "frequency": "string or null",
    "duration": "string or null",
    "quantity": "number/string or null",
    "instructions": "string or null"
  }]
}
```

Detail data is `{ "prescription": { ... }, "items": [ ... ] }`. PDF is
served as `application/pdf` with an attachment disposition. Prescription
safety warnings are **not yet part of this contract**; UI must not assume a
`warnings` field until the Phase 5 contract amendment is published.

## 3. SHARED-07 — Drug-interaction API and response normalization

`POST /ai/drug-interactions` is the only client-facing drug-interaction path.
It requires authentication and must replace direct requests to port 8001.

Provide one or both of `medication_names` and `medication_ids`. Each is an
array of 2–20 unique values; names are trimmed strings up to 120 characters,
and IDs must be UUIDs.

```json
{
  "medication_names": ["Warfarin", "Ibuprofen"],
  "medication_ids": ["optional UUID", "optional UUID"]
}
```

Success is the common envelope with the AI response preserved in `data`.
Invalid input is `400 VALIDATION_ERROR`; burst-limit exhaustion is `429`; an
AI upstream failure is normalized to `AI_SERVICE_ERROR` (client status from
the AI is preserved for 4xx, server failures become 502). Clients must display
the standard error state and never retry rapidly on 429/5xx.

## 4. Compatibility and change policy

This is v1. Additive optional fields are allowed. Renaming/removing fields,
changing authorization, response envelopes, or the clinical visibility rules
requires a new documented version and coordinated client release. The following
planned contracts remain separate deliverables: SHARED-02 admin/reviews,
SHARED-03 Socket.IO, SHARED-04 mobile billing, SHARED-05 public pages,
SHARED-06 web auth storage, and SHARED-08 Virtual Doctor lifecycle.
