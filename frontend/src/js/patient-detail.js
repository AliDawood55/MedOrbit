/**
 * MedOrbit v2 - Patient Detail (one patient's file, as seen by their doctor)
 *
 * ISOLATION NOTE FOR WHOEVER WIRES UP THE BACKEND (see BACKEND_NEEDED.md,
 * item 12): `GET /api/doctors/me/patients/:patientId` is the single most
 * sensitive endpoint in this whole feature set. It MUST, in this order:
 *   1. Resolve the caller's own doctors.id from req.user.sub (never trust
 *      a client value for "which doctor is asking").
 *   2. Verify a real relationship exists — e.g.
 *      EXISTS(SELECT 1 FROM medorbit.appointments WHERE doctor_id=$1 AND
 *      patient_id=$2) — and return 404 (not 403) if it doesn't, so a
 *      doctor probing random patient ids can't even confirm which ids are
 *      real.
 *   3. Only then query medical_records / prescriptions, and even then
 *      ALWAYS filtered by both doctor_id AND patient_id — a doctor must
 *      never see another doctor's notes about the same patient.
 * The role check below (`profile.role === 'doctor'`) is UX only. It hides
 * this page from a patient who wandered here by mistake; it enforces
 * nothing server-side and a dishonest client could call the API directly
 * regardless of what this page does.
 *
 * No backend endpoint exists yet for any of this — the whole page is a
 * structural preview (skeleton shapes, never fabricated patient data) plus
 * an honest empty state. The "add note" form is fully real and validated;
 * submitting it attempts the documented endpoint (which 404s today) and
 * shows an honest "not saved" message, never a fake success.
 */
const PatientDetail = (() => {

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function getPatientIdFromUrl() {
        return new URLSearchParams(window.location.search).get('id');
    }

    // ================= ADD NOTE FORM =================

    function validateNote() {
        const complaint = document.getElementById('noteChiefComplaint').value.trim();
        const clinical = document.getElementById('noteClinicalNotes').value.trim();
        if (!complaint && !clinical) return t('patientDetail.errorNoteRequired');
        return null;
    }

    async function submitNote(patientId) {
        const alertBox = document.getElementById('noteFormAlert');
        alertBox.className = 'alert';

        const err = validateNote();
        if (err) {
            alertBox.classList.add('error');
            alertBox.textContent = err;
            return;
        }

        const btn = document.getElementById('noteSubmitBtn');
        btn.classList.add('loading');

        const body = {
            record_type: document.getElementById('noteRecordType').value,
            diagnosis: document.getElementById('noteDiagnosis').value.trim(),
            chief_complaint: document.getElementById('noteChiefComplaint').value.trim(),
            clinical_notes: document.getElementById('noteClinicalNotes').value.trim(),
            is_draft: document.getElementById('noteDraftToggle').checked
        };

        // POST /api/doctors/me/patients/:patientId/notes doesn't exist yet
        // (see BACKEND_NEEDED.md item 13) — called anyway so wiring up the
        // real route later needs no frontend change. Always fails today.
        try {
            await API.care.addPatientNote(patientId, body);
            console.info('PatientDetail: note actually saved (endpoint now exists!)');
        } catch (err2) {
            console.info('PatientDetail: POST .../notes is not available yet (expected — see BACKEND_NEEDED.md)', err2);
        }

        btn.classList.remove('loading');
        document.getElementById('noteFormResult').classList.remove('hidden');
    }

    // ================= LOAD =================
    // GET /api/doctors/me/patients/:patientId doesn't exist yet — called
    // anyway (matching this codebase's convention, e.g. analytics.js) so
    // wiring up the real route later needs no frontend change. Always
    // 404s today; the structural preview + honest empty state is the
    // permanent, expected result.

    async function loadPatient(patientId) {
        try {
            const res = await API.care.patientDetail(patientId);
            console.info('PatientDetail: loaded real patient data (endpoint now exists!)', res?.data);
        } catch (err) {
            console.info('PatientDetail: GET /api/doctors/me/patients/:id is not available yet (expected — see BACKEND_NEEDED.md)', err);
        }
    }

    // ================= INIT =================

    async function init() {
        if (!API.requireAuth()) return;

        const patientId = getPatientIdFromUrl();
        if (!patientId) {
            document.getElementById('noIdNotice').classList.remove('hidden');
            return;
        }

        let isDoctor = false;
        try {
            const res = await API.users.me();
            isDoctor = res?.data?.role === 'doctor';
        } catch (err) {
            console.error('PatientDetail: failed to verify role', err);
        }

        if (!isDoctor) {
            document.getElementById('restrictedNotice').classList.remove('hidden');
            return;
        }

        document.getElementById('patientDetailContent').classList.remove('hidden');
        loadPatient(patientId);

        document.getElementById('noteSubmitBtn').addEventListener('click', () => submitNote(patientId));
        document.getElementById('noteFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('noteFormResult').classList.add('hidden');
        });
    }

    return { init };

})();
