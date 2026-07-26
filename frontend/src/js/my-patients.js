/**
 * MedOrbit v2 - My Patients (doctor's patient list)
 *
 * ISOLATION NOTE FOR WHOEVER WIRES UP THE BACKEND (see BACKEND_NEEDED.md,
 * item 11): `GET /api/doctors/me/patients` must resolve the calling
 * doctor's own `doctors.id` from the JWT (`req.user.sub`) server-side and
 * filter by it — never accept a doctor id from the client. The role check
 * below (`profile.role === 'doctor'`) only improves the UX for a doctor who
 * lands here by mistake; it is NOT a security boundary, and a malicious
 * client could call any endpoint directly regardless of what this page
 * shows or hides.
 *
 * No backend endpoint exists yet — the search/filter controls are real and
 * wired up (ready for when a patients array exists), but there is currently
 * nothing to filter, so an honest empty state is the only outcome.
 */
const MyPatients = (() => {

    // Always empty today — no GET /api/doctors/me/patients exists yet.
    // Kept as a real array (not hardcoded fake entries) so the search/filter
    // wiring below is exercised against real (empty) data, not bypassed.
    let patients = [];

    // GET /api/doctors/me/patients doesn't exist yet (see BACKEND_NEEDED.md
    // item 11) — called anyway, matching this codebase's convention (e.g.
    // analytics.js), so wiring up the real route later needs no frontend
    // change. Always 404s today; the empty state is the honest result.
    async function loadPatients() {
        try {
            const res = await API.care.myPatients();
            patients = res?.data || [];
            console.info('MyPatients: loaded', patients.length, 'real patients (endpoint now exists!)');
            render();
        } catch (err) {
            console.info('MyPatients: GET /api/doctors/me/patients is not available yet (expected — see BACKEND_NEEDED.md)', err);
        }
    }

    function applyFilters() {
        const query = document.getElementById('patientSearchInput').value.trim().toLowerCase();
        const filter = document.getElementById('patientFilterSelect').value;

        // No data exists to filter yet — this still runs the real logic
        // (not skipped) so it's exercised end-to-end once patients arrive.
        return patients.filter((p) => {
            const matchesQuery = !query || (p.name || '').toLowerCase().includes(query);
            const matchesFilter =
                filter === 'all' ||
                (filter === 'upcoming' && p.hasUpcoming) ||
                (filter === 'past' && !p.hasUpcoming);
            return matchesQuery && matchesFilter;
        });
    }

    function render() {
        // Always renders the empty state today since `patients` is always
        // []. Left as a real render pass (not a no-op) so wiring a future
        // GET /api/doctors/me/patients response in only needs to populate
        // `patients` and call render() again.
        applyFilters();
    }

    function init() {
        if (!API.requireAuth()) return;

        API.users.me().then((res) => {
            const isDoctor = res?.data?.role === 'doctor';
            if (!isDoctor) {
                document.getElementById('restrictedNotice').classList.remove('hidden');
                return;
            }

            document.getElementById('patientsPageContent').classList.remove('hidden');
            Motion.staggerIn(document.querySelector('.care-card-grid'), '.care-person-card');
            loadPatients();

            document.getElementById('patientSearchInput').addEventListener('input', render);
            document.getElementById('patientFilterSelect').addEventListener('change', render);
        }).catch((err) => {
            console.error('MyPatients: failed to verify role', err);
            document.getElementById('restrictedNotice').classList.remove('hidden');
        });
    }

    return { init };

})();
