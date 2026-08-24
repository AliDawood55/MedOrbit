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

## 4. SHARED-03 — Socket.IO direct-messaging contract

### Connection

Connect to the same backend origin as the REST API using Socket.IO transport
`websocket` or `polling`. Authenticate in either `auth.token` or the
`Authorization: Bearer <access-token>` handshake header. A missing, invalid,
revoked, or stale token rejects the connection with `UNAUTHORIZED`.

The server allows only configured CORS origins and limits a Socket.IO frame to
32 KiB. A client must reconnect using a refreshed access token after a 401
refresh cycle. Socket.IO room membership is connection-local, so after every
reconnect the client must re-subscribe to each visible conversation.

### Client events and acknowledgements

| Client event | Payload | Ack / effect |
|---|---|---|
| `conversation.subscribe` | `{ "conversation_id": "uuid" }` (camelCase accepted) | `{ "ok": true, "conversation_id": "uuid" }`; failure is `{ "ok": false, "code": "FORBIDDEN" \| "NOT_FOUND" }` |
| `conversation.unsubscribe` | `{ "conversation_id": "uuid" }` | Leaves the room; no acknowledgement |

Subscription does not create a conversation and is authorized against active
conversation membership. Do not subscribe to arbitrary IDs or rely on a room
as an authorization mechanism for REST actions.

### Server events

| Server event | Payload | Client handling |
|---|---|---|
| `message.created` | `{ id, conversation_id, sender_user_id, client_message_id, body, message_type, created_at }` | Upsert by `id` or `client_message_id`; do not add a second optimistic message. |
| `conversation.read` | `{ conversation_id, last_read_message_id, last_read_at, user_id }` | Update the other member's read state. |

There is no Socket.IO replay, typing signal, delivery signal, or push-notification
event in v1. REST remains the source of truth:

- `POST /messages/conversations` creates/retrieves a conversation.
- `GET /messages/conversations?limit=1..50&offset=n` lists conversations.
- `GET /messages/conversations/:id/messages?limit=1..100&cursor=...` loads
  older messages; `after=latest_cursor` catches up after reconnection.
- `POST /messages/conversations/:id/messages` sends a message with
  `{ "body": "1–4000 chars", "client_message_id": "uuid" }`. This key is
  idempotent for that sender/conversation.
- `POST /messages/conversations/:id/read` accepts optional `message_id`.
- `POST /messages/conversations/:id/accept` and `/decline` handle patient
  message requests.

The REST success/error envelope applies to all message actions. Send creation
is rate-limited to 120/minute; conversation creation is limited to 20 per 15
minutes. UI should preserve unsent drafts, retry only idempotent sends with the
same `client_message_id`, and refetch on authorization/request-status errors.

## 5. SHARED-04 — Mobile billing contract

**Decision: native IAP is deferred.** Mobile is read-only for billing and
opens the existing web billing page for purchases or subscription changes.
It must not call provider webhooks, sandbox simulation routes, or direct
payment-provider APIs.

Allowed authenticated mobile reads:

| Endpoint | Mobile use |
|---|---|
| `GET /billing/entitlements` | Current plan, server time, chatbot quota, and voice availability. |
| `GET /billing/plans` | Render server-owned plan names and prices. |
| `GET /billing/config` | Show whether web checkout is currently available/sandboxed. |
| `GET /billing/subscription` | Show the caller's current subscription state. |
| `GET /billing/history?limit=n` | Read the caller's billing-event timeline. |

The entitlement shape is:

```json
{
  "plan": "free|pro",
  "subscription": {
    "status": "active|past_due|canceled|null",
    "cancel_at_period_end": false,
    "current_period_end": "ISO-8601",
    "billing_interval": "month|year"
  },
  "features": {
    "chatbot": { "allowed": true, "unlimited": false, "used": 0, "limit": 20, "remaining": 20, "resets_at": "ISO-8601|null" },
    "voice_doctor": { "allowed": true, "unlimited": false, "active_session_id": null, "next_free_at": null }
  },
  "server_time": "ISO-8601"
}
```

Use `server_time` and returned absolute timestamps for countdowns; never
recalculate quotas or prices. For upgrade/manage actions, open the configured
web application billing route in the system browser, then refresh
`/billing/entitlements` and `/billing/subscription` when the app regains
focus. Mobile must not call `POST /billing/checkout`, cancellation, resume,
plan-change, `/billing/webhook`, or any `/billing/sandbox/*` route in v1.

## 6. SHARED-02 — Admin users and doctor reviews

### Admin user management

All endpoints below require an `admin` or `super_admin` access token.

| Operation | Endpoint | Current contract |
|---|---|---|
| List users | `GET /admin/users` | Filters: optional `role`, `active=true|false`, `search`; fixed `created_at DESC` order; returns an array, with no pagination or client-selected sorting in v1. |
| Deactivate | `PUT /admin/users/:id/deactivate` | No request body; revokes all target sessions and advances authorization version. |
| Reactivate | `PUT /admin/users/:id/reactivate` | No request body; revokes all target sessions and advances authorization version. |
| Change role | `PUT /admin/users/:id/role` | Deliberately disabled: always `403 FORBIDDEN`. |

List fields are `id`, `email`, `role`, `is_active`, `email_verified`,
`authorization_version`, `first_name_en`, `last_name_en`, `phone`, and `city`.
No password, token, or full profile data is returned.

Guardrails: administrators cannot alter their own security state; no ordinary
admin route can modify a `super_admin`; only a `super_admin` may modify an
`admin`. A missing target returns `404 NOT_FOUND`. Every successful state
change creates an audit record. UI must immediately discard an affected
target's cached authorization assumptions; the target's existing sessions are
invalidated by the backend.

Pagination, explicit sort, and role-change workflow are **not available** in
v1. Ali should implement local display filtering only where necessary and must
not invent query parameters or a role-edit control.

### Doctor reviews

| Operation | Endpoint | Caller | Success |
|---|---|---|---|
| Create review | `POST /doctors/:doctorId/reviews` | Authenticated patient with a completed matching appointment | 201 |
| List visible reviews | `GET /doctors/:doctorId/reviews` | Authenticated user | 200 |

Create payload:

```json
{
  "appointment_id": "uuid",
  "rating": 1,
  "review_text": { "ar": "optional", "en": "optional" },
  "professionalism_rating": 1,
  "treatment_rating": 1,
  "communication_rating": 1
}
```

For compatibility, `review_text_ar`/`review_text_en` and camelCase forms are
accepted. The appointment must belong to the authenticated patient's profile,
the target doctor, and have `status='completed'`; otherwise the response is
`400 INVALID_APPOINTMENT`. Publicly returned review text has canonical
`review_text` plus bilingual fields.

One review is allowed per appointment. A repeated attempt returns
`409 DUPLICATE_REVIEW`; the database unique constraint is the final guard
against concurrent submissions. There is no edit endpoint, delete endpoint,
moderation endpoint, or pagination in v1. The client should show one review
action per completed appointment and treat `DUPLICATE_REVIEW` as an already
submitted state. Those remaining review-management capabilities are the
outstanding OMAR-BE-007 product gap.

## 7. SHARED-08 — Virtual Doctor lifecycle

All Virtual Doctor traffic goes through `/api/virtual-doctor`; no Web or
Mobile client may call the AI service directly. Every endpoint requires an
access token. The backend derives the user identity from that token and sends
an internal service credential to the AI service; clients must never send a
`user_id` field.

### Lifecycle

1. Start/rejoin with `POST /virtual-doctor/start`, body `{ "language": "ar" | "en" }`.
   Omitted/invalid language defaults to `en`. The response contains the AI
   session payload plus `resumed` and `entitlement_source`.
2. Persist the returned `session_id` locally only for the active consultation.
   After refresh/reconnect, call `GET /virtual-doctor/session/:sessionId` or
   call `/start` again; the backend reuses an active owned session rather than
   charging for another consultation.
3. Send turns through `POST /virtual-doctor/message`:
   `{ "session_id": "uuid", "message": "text" }`. Render the upstream
   response in `data`. When `data.phase === "complete"`, the backend ends the
   consultation automatically.
4. End deliberately with `POST /virtual-doctor/session/:sessionId/end` when
   the user leaves. It returns `{ status, next_free_at }` and finalizes an
   abandoned consultation.
5. Generate a report with `POST /virtual-doctor/report/:sessionId`. This also
   finalizes the consultation; response data includes a backend-owned
   `download_url`. Download through that URL, which is a PDF binary response.

Only the owning account can access a session, send messages, generate a report,
or download it. A missing, guessed, ended, or other-user session is reported as
`404 NOT_FOUND`, not as an ownership disclosure.

### Voice assistance

| Operation | Endpoint | Request / response |
|---|---|---|
| Speech-to-text | `POST /virtual-doctor/transcribe` | `multipart/form-data`: `audio` (max 10 MiB), `session_id`, optional `language`; JSON envelope response. |
| Text-to-speech | `POST /virtual-doctor/speak` | JSON `{ session_id, text, language }`; binary `audio/wav`, with `X-TTS-Voice` and `X-TTS-Language` headers. TTS failure must not block text consultation. |
| Warm model | `POST /virtual-doctor/transcribe/warmup` or `/speak/warmup` | Optional `?language=`; best effort `{ warmed: boolean }`. |
| Model status | `GET /virtual-doctor/transcribe/status` or `/speak/status` | JSON envelope status. |

Transcription and synthesis require an active owned consultation. UI must keep
the text path usable if voice features are unavailable. Warm-up is not a
consultation start and must not be represented as one.

### Entitlements, failure, and abandoned state

The backend enforces quota and fair-use rate limits. Clients render the error
envelope and use its code, especially:

- `FREE_QUOTA_EXHAUSTED` (403): show the plan/upgrade state.
- `VOICE_COOLDOWN` (429): show `error.details.next_free_at` when supplied.
- `ENTITLEMENT_UNAVAILABLE` (403): retry later; do not claim access.
- `SESSION_STARTING` (409): retry `/start` after a short delay.
- `SESSION_UNAVAILABLE` (409): clear the local session; its upstream state is
  gone and the backend has finalized the orphaned grant.
- `AI_SERVICE_ERROR`, `TTS_UNAVAILABLE`, or `PDF_UNAVAILABLE`: preserve text
  and allow a safe retry where appropriate.

The server can expire stale grants according to its entitlement policy; there
is no client-side heartbeat contract. Therefore, clients must explicitly end
an abandoned session when possible and clear local state after 404/409. A
report or a completed AI phase is also an end event; do not send more turns
after either.

## 8. Compatibility and change policy

This is v1. Additive optional fields are allowed. Renaming/removing fields,
changing authorization, response envelopes, or the clinical visibility rules
requires a new documented version and coordinated client release. The following
planned contracts remain separate deliverables: SHARED-02 admin/reviews,
SHARED-05 public pages, SHARED-06 web auth storage, and SHARED-08 Virtual
Doctor lifecycle.
