# Historical: backend gap investigation (archived)

> **Status: superseded on 2026-08-25.** This document is preserved for its
> original investigation notes, not as a current work queue. Several items
> below were completed as the backend evolved. Do not implement work from this
> list without first checking `docs/SHARED_API_CONTRACTS_V1.md`, the current
> route tests, and `docs/DEFERRED_BACKEND_SURFACES.md`.

---

## Original investigation notes

Frontend-side notes for Omar, written while building `book-appointment.html` /
`my-appointments.html` against the current API. Nothing in `backend/**`,
`db/**`, or `database/**` was changed to produce this list — read-only
investigation only (route files, and read-only `psql` checks against the live
`medorbit` schema). Five items, ordered by how much they block the frontend.

---

## 1. `GET /api/appointments` compares the wrong id — always returns zero rows (blocking)

**File:** `backend/src/routes/appointment.routes.js`, lines 368–387 (the `router.get("/", authenticate, ...)` handler starting at line 357).

```js
const result = await db.query(
    `
SELECT *
FROM medorbit.appointments
WHERE patient_id=$1
ORDER BY scheduled_date DESC
`,
    [
        req.user.sub
    ]
);
```

`req.user.sub` is the JWT subject, i.e. `medorbit.users.id`. But
`medorbit.appointments.patient_id` is a foreign key into `medorbit.patients.id`
— a **different** UUID. Confirmed via:

```
\d medorbit.patients
```

which shows `id` (PK) and `user_id` (FK to `users.id`) as two distinct
columns. The correct comparison is the same lookup `POST /` already does
correctly two handlers above it (lines 159–168 in the same file):

```js
const patientResult = await db.query(
    `SELECT id FROM medorbit.patients WHERE user_id=$1`,
    [req.user.sub]
);
const patient_id = patientResult.rows[0].id;
```

**Fix:** in the `GET /` handler, do the same `patients` lookup first, then
query `WHERE patient_id = $1` using that resolved `patients.id`, not
`req.user.sub` directly.

**Why the frontend needs it:** `my-appointments.html` calls this endpoint to
list a logged-in patient's appointments (upcoming/past/cancelled tabs). Right
now it returns `{success:true, data:[]}` for every real patient, regardless of
how many appointments they actually have.

**How I verified it's broken (not just read the code):** registered a real
test patient account, booked a real appointment end-to-end through the wizard
(`POST /api/appointments` → row created, `appointment_number` returned,
confirmed live in the DB with a matching `appointment_status_history` row),
then called `GET /api/appointments` with that same user's access token —
response was `{"success":true,"data":[],"message":"Appointments
retrieved",...}`. Test appointment and account were deleted afterward.

The UI is already built and shipped against the *documented* contract (built
with sign-off to proceed anyway) — no frontend change will be needed once
this query is fixed; the tabs will simply start populating.

**Related, smaller issue in the same file:** `GET /:id` (line ~418) and
`PUT /:id/cancel` (line ~491) have no ownership check at all — any
authenticated user's token works against any appointment id, not just their
own. Worth closing at the same time since you'll already be in this file.

---

## 2. `GET /api/appointments` returns bare `doctor_id` / `clinic_id`, no names

**File:** same handler as #1 — `SELECT * FROM medorbit.appointments` has no
joins.

Every appointment row comes back with only foreign keys
(`doctor_id`, `clinic_id`, `patient_id`), never a doctor or clinic name. There
is no way to render a usable appointments list from this response alone.

**What we're doing instead (frontend workaround, not a fix):**
`frontend/src/js/my-appointments.js`'s `enrich()` function collects the
unique `doctor_id`/`clinic_id` values from the list response and calls the
existing public `GET /api/doctors/:id` and `GET /api/clinics/:id` once per
unique id to resolve display names, caching results in memory for the
session. This works, but for a patient with N appointments across M distinct
doctors/clinics it's `1 + M×2` requests just to render one page, instead of 1.

**Suggested fix:** join in the doctor and clinic display fields directly,
mirroring how `GET /doctors/:id` already joins `user_profiles` for
`first_name_ar/en` etc. Something like:

```sql
SELECT
    a.*,
    p.first_name_ar AS doctor_first_name_ar, p.first_name_en AS doctor_first_name_en,
    p.last_name_ar  AS doctor_last_name_ar,  p.last_name_en  AS doctor_last_name_en,
    c.name_ar AS clinic_name_ar, c.name_en AS clinic_name_en
FROM medorbit.appointments a
JOIN medorbit.doctors d ON d.id = a.doctor_id
LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
JOIN medorbit.clinics c ON c.id = a.clinic_id
WHERE a.patient_id = $1
ORDER BY a.scheduled_date DESC
```

**Why the frontend needs it:** every appointment card needs a doctor name and
clinic name — that's the primary information a patient scans for, not raw
ids. A join means one request instead of the current fan-out, and removes an
entire caching layer from the frontend that only exists to paper over this.

**How I verified:** read the full `GET /` handler (only `SELECT *` on
`medorbit.appointments`, no `JOIN`), and confirmed the appointments table
itself has no denormalized name columns via `\d medorbit.appointments`.

---

## 3. No way to know which generated slots are already booked before submitting

**Files:** `GET /api/appointments/available-slots` (lines 27–120) and
`POST /api/appointments` (lines 136–345) in `appointment.routes.js`.

`available-slots` returns raw `doctor_availability` *windows*
(e.g. "08:00–15:00, 30-min slots"), not discrete bookable slots, and doesn't
cross-reference existing bookings at all. The frontend (`book-appointment.js`,
`buildSlotsFromWindows()`) divides each window into `slot_duration` chunks
client-side to build the slot grid the patient picks from — but has no way to
know which of those generated slots already have a non-cancelled appointment
against them. The *only* place that conflict is checked is the `exists`
query inside `POST /` (lines 199–223, `SLOT_BUSY`, 400), which fires after the
patient has already gone through the whole wizard and hit "confirm".

**What the frontend does today:** submits, and on `SLOT_BUSY` sends the
patient back to step 2 with a toast asking them to pick a different time.
Works, but is a bad experience compared to just not showing a taken slot in
the first place — and if two patients are looking at the calendar at the same
moment, both can pick the same slot and only one finds out at the end.

**Suggested fix:** either (a) have `available-slots` exclude times that
already have a non-cancelled `medorbit.appointments` row for that
`doctor_id` + `scheduled_date` + `start_time`, using the same predicate
already written in `POST /`'s `exists` check (lines 199–223) — just run it
per generated slot instead of only at submit time — or (b) add a lighter
`GET /api/appointments/booked-slots?doctor_id=&clinic_id=&date=` that returns
just the list of taken `start_time` values for a day, which the frontend can
subtract from its generated grid without changing the existing
`available-slots` response shape.

**Why the frontend needs it:** removes an entire error-recovery path from the
wizard, and prevents patients from picking a slot that was never actually
available.

**How I verified:** read both handlers in full — confirmed `available-slots`
only ever queries `doctor_availability`, never `appointments`; confirmed the
only booked-vs-available cross-check anywhere in the file is the `exists`
query inside `POST /`.

---

## 4. No reschedule endpoint

**File:** `appointment.routes.js` — the only status-changing routes are
`PUT /:id/cancel` (line 491), `PUT /:id/confirm` (line 588), and
`PUT /:id/complete` (line 678). Confirmed via a repo-wide grep for
"reschedul(e)" — zero matches anywhere in `backend/src`.

**What's missing:** a way to change `scheduled_date` / `start_time` /
`end_time` (and probably `clinic_id`, if the patient wants a different
location) on an existing, still-upcoming appointment.

**Why the frontend needs it:** right now the only way for a patient to change
an appointment time is cancel-and-rebook from scratch through the full
3-step wizard, which also throws away the original `appointment_number`. A
`PUT /:id/reschedule` (or extending `PUT /:id` generically) taking
`{scheduled_date, start_time, end_time, clinic_id}`, re-running the same
`SLOT_BUSY` conflict check `POST /` already does, and writing an
`appointment_status_history` row (`new_status` could stay the same, just log
the reschedule some other way, e.g. a new `previous_*` columns or a
dedicated `notes` entry) would let `my-appointments.html` add a "Reschedule"
action next to "Cancel" without a full rebuild.

**How I verified:** read every route in `appointment.routes.js` end to end
(7 handlers total: available-slots, POST /, GET /, GET /:id, cancel, confirm,
complete) and grepped the whole backend for "reschedul" — no hits.

---

## 5. Prescriptions and medical records have no API at all

**Confirmed via:**
- `ls backend/src/routes/` — 11 route files, none named anything like
  `prescription` or `medical-record`.
- `grep -rn "app.use" backend/src/app.js` — 8 mounted API path groups
  (`auth`, `users`, `doctors`, `clinics`, `specialties`, `appointments`,
  `notifications`, `admin/notifications/templates`, `chat`,
  `conversations`) — no `prescriptions` or `medical-records` path.
- Both tables already exist live in the `medorbit` schema with real data:
  `\d medorbit.prescriptions` (1 row) and `\d medorbit.medical_records`
  (2 rows) both returned full column lists.

**Two different situations underneath, worth knowing about separately:**

- **`medical_records`:** not dead-empty — `backend/src/repositories/medical.repository.js`
  already has `findLatestRecordByPatientId(patientId)` (line 48) and
  `findRecordsByPatientId(patientId, {limit, offset})` (line 60) querying
  `medorbit.medical_records` directly, and
  `backend/src/services/chatbot/medical.service.js` has a matching
  `getLatestRecord(patientId)` (line 19). But grepping the whole backend for
  callers of these three methods turns up **only their own definitions** —
  nothing in any route ever calls them. They look like they were built to
  feed the AI chatbot's context (recent medical history informing a chat
  response) but were never wired to a route, and there's certainly no
  patient-facing "my medical records" endpoint.
- **`prescriptions` / `prescription_items`:** no repository, no service, no
  route — a full repo-wide grep for `prescriptions` inside `backend/src`
  returns nothing. The tables exist and have data, but there is zero backend
  code touching them.

**Why the frontend needs it:** `dashboard.html`'s dedicated "coming soon"
teaser cards were retired during the dashboard redesign (professional/no-
clutter pass) in favor of two full dedicated pages —
`frontend/public/my-prescriptions.html` and `frontend/public/my-records.html`
— that build the entire UI (filters, card/timeline preview, empty state) but
have nothing to fetch, since no endpoint exists. If you add read endpoints
(at minimum `GET /api/patients/me/prescriptions` and
`GET /api/patients/me/medical-records`, ownership-scoped like the
`GET /api/users/me/saved-places` endpoint added earlier this engagement), the
frontend can wire up both pages to real data without any other backend
change or redesign — the UI is already built and waiting.

**How I verified:** file listing of `backend/src/routes/`, grep of
`app.js`'s mount list, grep of the whole backend tree for "prescription" and
"medical.?record" (case-insensitive), and read-only `\d` checks against both
tables in the live `medorbit` schema confirming they exist with real rows.

---

## 6. No way for a doctor account to see their own schedule/appointments

**Found while making `dashboard.html` role-aware** (showing something
sensible for doctor-role accounts instead of assuming every logged-in user
is a patient).

`GET /api/appointments` (line 357 in `appointment.routes.js`, see item #1) is
patient-scoped by design — even once the `patient_id`/`user_id` bug is fixed,
it will only ever resolve the caller's row in `medorbit.patients`. A doctor
account has no `patients` row (`auth.service.js` only inserts one when
`role === "patient"` at registration), so there is no endpoint at all — not
even a broken one — that lets a logged-in doctor fetch "my appointments as a
doctor" (i.e. `WHERE doctor_id = <their doctors.id>`).

**Confirmed via:**
- `\d medorbit.patients` / registration flow — doctors never get a
  `patients` row, so the item #1 fix alone will not help doctor accounts.
- Re-read every handler in `appointment.routes.js` — the only routes that
  filter by `doctor_id` at all are `PUT /:id/confirm` and `PUT /:id/complete`
  (both `authorize('doctor','admin')`, both act on a single appointment id
  already known to the caller, not a list).
- Grepped the whole backend for any `doctors.id`-scoped appointment list —
  none exists.

**What's missing:** something like
`GET /api/appointments/doctor-schedule?date=` (auth + `authorize('doctor')`,
resolving the caller's `doctors.id` via `user_id` the same way `POST /`
already resolves `patients.id` via `user_id` at lines 159–168, then
`WHERE doctor_id = $1`).

**Why the frontend needs it:** right now `dashboard.html` simply hides the
"Book Appointment" quick action and the appointments stat/list for
`role === 'doctor'` accounts, showing an honest "appointment management for
doctors is coming soon" notice instead of a broken or empty patient-shaped
list. This is a placeholder, not a real feature — a doctor currently has no
way to see their upcoming patient appointments anywhere in the app.

**How I verified:** read `GET /users/me`'s response (confirmed it returns
`role`, which is what the dashboard uses to detect a doctor account),
re-read all 7 handlers in `appointment.routes.js`, and confirmed via
`auth.service.js` (lines 67–72) that `patients` rows are only created for
`role === "patient"` (`doctors` rows get created instead, at line 71, with no
equivalent self-service lookup route for a doctor's own `doctors.id`).

---

## 7. CORS config blocks `PATCH` — "mark all notifications read" fails in every browser (blocking that one action)

**File:** `backend/src/app.js`, line 40:

```js
app.use(cors({
    origin: corsOrigin === '*' ? true : corsOrigin.split(',').map(s => s.trim()),
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: corsOrigin !== '*'
}));
```

`PATCH` is missing from the `methods` allowlist. `PATCH /api/notifications/read-all`
(`notification.routes.js`, `router.patch("/read-all", ...)`) is the *only*
route in the whole backend that uses the `PATCH` verb, so this was invisible
until the dashboard redesign added a "mark all as read" button that calls it.

**Confirmed via:** clicking "Mark all as read" on the new dashboard in a real
Chrome instance (Playwright) and reading the console — the browser's CORS
preflight (`OPTIONS`) rejects the follow-up `PATCH` before it ever reaches
the route handler:

```
Access to fetch at 'http://127.0.0.1:3001/api/notifications/read-all' from
origin 'http://127.0.0.1:8080' has been blocked by CORS policy: Method PATCH
is not allowed by Access-Control-Allow-Methods in preflight response.
```

A direct `curl -X PATCH` (no browser, no CORS preflight) works fine and
updates the rows correctly — this is purely a CORS configuration gap, not a
route bug.

**Fix:** add `'PATCH'` to the `methods` array on line 40.

**Why the frontend needs it:** the dashboard's notifications card has a
"Mark all as read" button (visible whenever there's at least one unread
notification) that calls exactly this endpoint. Right now clicking it always
fails with a caught error (shown as a toast, not a crash) and the unread
badge never clears. Once the one-line fix lands, no frontend change is
needed — the button already calls the right endpoint with the right method.

**How I verified:** read the exact `cors()` call in `app.js`, reproduced the
failure in a real browser via Playwright, and confirmed the same request
succeeds via `curl -X PATCH` outside the browser (proving it's a CORS-layer
rejection, not a route or auth problem).

---

## 8. No feedback/rating submission API at all

**Confirmed via:** grepped every file in `backend/src/routes/` (case-
insensitive) for "feedback", "rating", and "review". The only hits are
`doctor_reviews` (rating a specific doctor, on `doctor.routes.js` — a
different, already-implemented feature) and `saved_places.rating` (a
distance/quality field on a saved place, unrelated). There is no route,
controller, or table anywhere for general platform feedback. `ls
backend/src/routes/` — 11 files, none named anything like `feedback`.

**What's missing:** a `POST /api/feedback` endpoint (auth required — the
form is only reachable to logged-in users) accepting:

```json
{
  "overallRating": 5,
  "categoryRatings": { "chatbot": 4, "clinics": 5, "booking": 3, "design": 4 },
  "comment": "free text, optional",
  "wouldRecommend": "yes"
}
```

`overallRating` is 1–5, required. `categoryRatings.*` are each 1–5, 0 means
"not rated" (optional per category). `comment` is a trimmed string, optional,
capped at 500 characters client-side. `wouldRecommend` is `"yes"`, `"no"`, or
`null` (optional, deselectable). A minimal table would need: `id`, `user_id`,
`overall_rating`, `chatbot_rating`, `clinics_rating`, `booking_rating`,
`design_rating`, `comment`, `would_recommend`, `created_at`.

**Why the frontend needs it:** `frontend/public/feedback.html` is a fully
built, validated form (5-star widgets for overall + 4 categories, optional
recommend toggle, optional comment with a live character counter) — but
since nothing exists to send it to, submitting always shows an explicit
"your feedback wasn't saved yet" message instead of a fake success, and logs
the validated payload to the console for reference. No frontend change will
be needed once `POST /api/feedback` exists — just point the submit handler
at it (currently intentionally left uncalled, `frontend/src/js/feedback.js`).

**How I verified:** grepped all route files case-insensitively for
`feedback|rating|review`, read every hit to confirm it belongs to an
unrelated existing feature, and confirmed via `ls` that no route file
resembles feedback/reviews/ratings as a platform-wide concept.

---

## 9. No aggregate platform statistics endpoint (T-030)

**Confirmed via:** grepped every route file for "stats", "analytics", and
"dashboard" (case-insensitive) — zero matches. `GET /api/dashboard/stats`
does not exist in any form.

**What's missing:** a single admin-only aggregate endpoint. Suggested
contract — `GET /api/dashboard/stats` (auth + `authorize('admin')`),
returning:

```json
{
  "appointmentsOverTime": { "labels": ["2026-01", "2026-02", "..."], "counts": [12, 18] },
  "usersByRole":          { "labels": ["patient", "doctor", "admin"], "counts": [420, 35, 2] },
  "topSpecialties":       { "labels": ["Cardiology", "Dermatology", "..."], "counts": [80, 65] },
  "conversationsPerWeek": { "labels": ["2026-W01", "2026-W02", "..."], "counts": [30, 45] },
  "triageLevels":         { "labels": ["2026-W01", "2026-W02", "..."], "emergency": [2, 3], "urgent": [10, 12], "routine": [20, 22] },
  "clinicTypes":          { "labels": ["clinic", "pharmacy", "hospital"], "counts": [50, 30, 10] }
}
```

Each `labels`/`counts` (or `emergency`/`urgent`/`routine`) array pair must be
the same length. Any section can be omitted or returned empty while it's
still being built — the frontend treats each of the 6 charts independently
and only unlocks the ones with data.

**Why the frontend needs it:** `frontend/public/analytics.html` (admin-only,
gated by `role === 'admin'` from a fresh `GET /users/me` call — not the
cached login-time role) already renders all 6 charts via Chart.js — line,
doughnut, horizontal bar, bar, stacked bar, and pie — with real axes, titles,
and legends, each showing an explicit "awaiting backend data" overlay since
every section is currently empty (zero hardcoded/random numbers anywhere in
the code). `frontend/src/js/api.js`'s `analytics.dashboardStats()` already
calls the exact endpoint above and `frontend/src/js/analytics.js` already
reads the exact shape documented here — the moment real data comes back for
any section, that chart's overlay disappears and it renders for real. No
frontend change needed.

**How I verified:** grepped all route files for `stats|analytics|dashboard`
(only hits were `dashboard.html`-unrelated frontend-side matches, confirming
zero backend routes), and confirmed via `app.js`'s mount list that no
`/api/dashboard` or `/api/analytics` path is registered.

---

# Doctor↔patient care features (posts, patient list, patient file, notes, my-doctor)

Everything in items 10–14 below is genuinely new — none of these five pages
had any existing frontend before this pass, and **none of the backing
endpoints exist at all**, confirmed via:
- `ls backend/src/routes/` — same 11 files as before, nothing named
  `post`, `patient`, or `note`.
- `grep -rniE "post|article|announcement|my-patients|doctor.?patient|session.?note|clinical.?note" backend/src/routes` —
  zero real hits (only the HTTP `POST` verb).
- `\dt medorbit.*` (36 tables) — no `posts`/`articles`/`announcements` table
  exists at all. `medorbit.medical_records` and
  `medorbit.prescriptions`/`prescription_items` do exist with real data-
  bearing columns (confirmed via `\d` on each), but — as already noted in
  item 5 — nothing reads or writes them from a route.

## ⚠️ Data isolation — read this before implementing any of items 10–14

**A patient must never be able to see another patient's data. A doctor must
only ever see their own patients — never another doctor's.** This cannot be
enforced from the frontend; it is a server-side responsibility on every
single endpoint below.

Concretely:
- `authorize('doctor')` (the existing middleware, `backend/src/middleware/auth.js`)
  only checks **role membership** — "is this JWT a doctor" — never
  **ownership**. It does not know or care *which* doctor, or whether that
  doctor has any relationship with the patient in the URL.
- Every "my X" endpoint below (`/doctors/me/...`, `/patients/me/...`) must
  resolve the caller's own `doctors.id` / `patients.id` server-side from
  `req.user.sub` (the same `SELECT id FROM medorbit.doctors WHERE user_id=$1`
  pattern already used correctly elsewhere, e.g. `appointment.routes.js`
  lines 159–168) — **never** trust a client-supplied doctor/patient id for
  "whose data is this" decisions.
- Every endpoint that takes a `:patientId` in the URL (patient detail,
  notes, prescriptions) must additionally verify a real relationship exists
  before returning anything — e.g.
  `EXISTS (SELECT 1 FROM medorbit.appointments WHERE doctor_id=$1 AND patient_id=$2)`.
  If it doesn't exist, return 404 (not 403 — a 403 confirms the patient id is
  real, which is itself a small information leak). The frontend's own
  role-gating (hiding nav links, redirecting non-doctors away from
  `my-patients.html`) is **UX only** — it stops an honest user from getting
  lost, not a dishonest one from probing the API directly.
- `medical_records` currently has no patient-visibility flag — every column
  (`clinical_notes`, `doctor_notes`, `diagnosis`, etc.) is implicitly
  doctor-internal today. Item 14 (`my-doctor.html`, "shared notes") assumes
  a new boolean (e.g. `visible_to_patient`) gating which fields/rows a
  patient-facing endpoint may return — without it, a "share with patient"
  endpoint would leak a doctor's private clinical shorthand to the patient.

Every one of `frontend/src/js/doctor-posts.js`, `my-patients.js`,
`patient-detail.js`, and `my-doctor.js` has this same warning at the top of
the file, restated for whoever wires up the corresponding route.

---

## 10. No doctor posts/articles API (new feature — no table, no route)

**What's missing:** a table (suggested `medorbit.doctor_posts`: `id`,
`doctor_id` FK, `title_ar`, `title_en`, `excerpt_ar`, `excerpt_en`, `body_ar`,
`body_en`, `category`, `is_published`, `created_at`, `updated_at`) plus:

- `GET /api/doctors/:id/posts` — **public**, read-only. Returns only
  `WHERE doctor_id=$1 AND is_published=true`. Backs `doctor.html`'s new
  "Posts" tab (any visitor, no auth).
- `GET /api/doctors/me/posts` — auth + `authorize('doctor')`. Returns *all*
  the caller's own posts (published + drafts), `doctor_id` resolved from
  `req.user.sub`, never from a query param. Backs `doctor-posts.html`'s list.
- `POST /api/doctors/me/posts` — auth + `authorize('doctor')`. `doctor_id`
  forced server-side, never accepted from the request body.
- `PUT /api/doctors/me/posts/:postId` / `DELETE /api/doctors/me/posts/:postId` —
  auth + `authorize('doctor')`, **and** must verify
  `posts.doctor_id === (resolved doctor id for req.user.sub)` before allowing
  the edit/delete — otherwise any doctor could edit any other doctor's posts.

**Why the frontend needs it:** `doctor.html`'s Posts tab and the new
`doctor-posts.html` management page are both fully built (cards, detail
view, create/edit form with AR/EN title + body + category + publish toggle,
delete confirmation) but permanently show their honest empty state / a
"not saved" message on submit, since there is nothing to call.

---

## 11. No doctor's-patient-list endpoint

**What's missing:** `GET /api/doctors/me/patients` — auth +
`authorize('doctor')`. Since there's no dedicated relationship table, the
natural derivation is *"every patient this doctor has ever had an
appointment with"*:

```sql
SELECT DISTINCT ON (p.id)
    p.id, u.email, pr.first_name_ar, pr.last_name_ar, pr.first_name_en, pr.last_name_en,
    pr.phone, pr.profile_image_url,
    a.scheduled_date AS last_or_next_appointment_date, a.status
FROM medorbit.patients p
JOIN medorbit.users u ON u.id = p.user_id
LEFT JOIN medorbit.user_profiles pr ON pr.user_id = u.id
JOIN medorbit.appointments a ON a.patient_id = p.id
WHERE a.doctor_id = $1   -- resolved server-side from req.user.sub, see warning above
ORDER BY p.id, a.scheduled_date DESC
```

Should support a `?search=` query param (matching patient name) since
`my-patients.html`'s search box is already built to send one.

**Why the frontend needs it:** `my-patients.html` (search + filter + patient
cards showing name/last visit/upcoming appointment/quick actions) is fully
built but shows an honest empty state today — there is no way to list a
doctor's patients at all right now.

---

## 12. No single-patient detail endpoint for a doctor

**What's missing:** `GET /api/doctors/me/patients/:patientId` — auth +
`authorize('doctor')`, **plus** the relationship check from the warning
above (404 if no appointment ever existed between this doctor and this
patient — do this check *first*, before querying anything else). Once
verified, return: patient profile, this doctor's appointment history with
this patient, this doctor's `medical_records` rows for this patient
(**not** records from other doctors — always filter by
`doctor_id = $1 AND patient_id = $2`, both), and this doctor's
`prescriptions` for this patient (same double filter).

**Why the frontend needs it:** `patient-detail.html?id=` (appointment
history, session-notes timeline, prescriptions section) is fully built but
shows an honest empty state today.

---

## 13. No session/clinical-notes write API

**What's missing:** `POST /api/doctors/me/patients/:patientId/notes` — auth +
`authorize('doctor')` + the same relationship check as item 12. Inserts into
`medorbit.medical_records` with `doctor_id`/`patient_id` both forced
server-side (never from the request body). Suggested body:
`{ record_type, chief_complaint, diagnosis, treatment_plan, clinical_notes, is_draft }`.
A matching `GET /api/doctors/me/patients/:patientId/notes` (or fold into
item 12's response) serves the timeline.

**Why the frontend needs it:** `patient-detail.html`'s "add note" form is
fully built and validated but shows an honest "not saved" message on submit
today, exactly like `feedback.html`'s pattern elsewhere in this codebase.

---

## 14. No patient-facing "my doctor(s)" endpoint

**What's missing:** `GET /api/patients/me/doctors` — auth +
`authorize('patient')`, `patient_id` resolved server-side from
`req.user.sub`. Derived the same way as item 11 but from the patient's side:
every doctor this patient has an appointment with. A second endpoint,
`GET /api/patients/me/doctors/:doctorId/notes`, would back the "shared
notes" section — but per the isolation warning above, this **requires** a
new `visible_to_patient` boolean on `medorbit.medical_records` (or an
equivalent join table) so a doctor's private notes are never exposed by
default; only rows/fields a doctor has explicitly marked shareable should
come back.

**Why the frontend needs it:** `my-doctor.html` (doctor card, shared
notes/sessions, upcoming appointments with them) is fully built but shows an
honest empty state today.

---

### Summary for triage

| # | Gap | Blocking? | Fix size |
|---|-----|-----------|----------|
| 1 | `GET /appointments` patient_id/user_id mismatch | Yes — feature is non-functional without it | 1-line query fix, reuses existing lookup pattern |
| 2 | No joined doctor/clinic names on `GET /appointments` | No — frontend works around it | Small — add 2 joins |
| 3 | No pre-submit slot-conflict check | No — SLOT_BUSY on submit is a working fallback | Small — reuse existing `exists` query |
| 4 | No reschedule endpoint | No — cancel-and-rebook works today | Medium — new route |
| 5 | No prescriptions/medical-records API (patient's own view) | No — both are full UI shells with an honest empty state today | Medium — new routes, `medical_records` repo layer already exists |
| 6 | No doctor-facing appointment/schedule endpoint | No — dashboard hides the feature with an honest notice today | Medium — new route, reuses the `user_id → doctors.id` lookup pattern already used elsewhere |
| 7 | CORS `methods` allowlist missing `PATCH` | Yes — "mark all read" always fails in-browser | 1-line fix (`app.js:40`) |
| 8 | No feedback/rating submission API | No — form shows an honest "not saved" message today | Medium — new route + table |
| 9 | No aggregate stats endpoint (T-030) | No — analytics page shows honest "awaiting data" overlays today | Medium-Large — new route, several aggregate queries |
| 10 | No doctor posts/articles API (no table, no route) | No — Posts tab + management page show honest empty states today | Large — new table + full CRUD route set |
| 11 | No doctor's-patient-list endpoint | No — my-patients.html shows honest empty state today | Medium — new route, must resolve doctor_id server-side |
| 12 | No single-patient detail endpoint for a doctor | No — patient-detail.html shows honest empty state today | Large — new route, **must** verify doctor↔patient relationship server-side |
| 13 | No session/clinical-notes write API | No — add-note form shows honest "not saved" message today | Medium — new route, `medical_records` table already fits |
| 14 | No patient-facing "my doctor(s)" endpoint | No — my-doctor.html shows honest empty state today | Medium — new route + a patient-visibility flag on `medical_records` |
