/**
 * MedOrbit v2 - My Doctor (patient's view of their treating doctor(s))
 *
 * ISOLATION NOTE FOR WHOEVER WIRES UP THE BACKEND (see BACKEND_NEEDED.md,
 * item 14): `GET /api/patients/me/doctors` must resolve the calling
 * patient's own patients.id from req.user.sub server-side — never accept
 * one from the client. The "shared notes" endpoint
 * (`GET /api/patients/me/doctors/:doctorId/notes`) is even more sensitive:
 * a doctor's clinical notes are private by default, so that endpoint must
 * only ever return rows/fields a doctor explicitly marked visible to the
 * patient (a new `visible_to_patient` flag on medical_records, or
 * equivalent) — never the raw doctor_notes/clinical_notes columns as-is.
 * The role check below (`profile.role === 'patient'`) is UX only; it does
 * not enforce anything server-side.
 *
 * No backend endpoint exists yet — this whole page is a structural preview
 * (skeleton shapes, never fabricated doctor/appointment/note data) plus an
 * honest empty state.
 */
const MyDoctor = (() => {

    // GET /api/patients/me/doctors doesn't exist yet (see
    // BACKEND_NEEDED.md item 14) — called anyway, matching this codebase's
    // convention (e.g. analytics.js), so wiring up the real route later
    // needs no frontend change. Always 404s today.
    async function loadMyDoctors() {
        try {
            const res = await API.care.myDoctors();
            console.info('MyDoctor: loaded real doctor data (endpoint now exists!)', res?.data);
        } catch (err) {
            console.info('MyDoctor: GET /api/patients/me/doctors is not available yet (expected — see BACKEND_NEEDED.md)', err);
        }
    }

    async function init() {
        if (!API.requireAuth()) return;

        let isPatient = false;
        try {
            const res = await API.users.me();
            isPatient = res?.data?.role === 'patient';
        } catch (err) {
            console.error('MyDoctor: failed to verify role', err);
        }

        if (!isPatient) {
            document.getElementById('restrictedNotice').classList.remove('hidden');
            return;
        }

        document.getElementById('myDoctorContent').classList.remove('hidden');
        loadMyDoctors();
    }

    return { init };

})();
