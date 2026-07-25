/**
 * MedOrbit v2 - My Medical Records
 * medorbit.medical_records already has live data and an unused repository
 * layer (medical.repository.js), but no route exposes it to patients (see
 * BACKEND_NEEDED.md, item 5) — this page is a full UI shell (filters,
 * timeline preview) with an honest empty state. Nothing here is fetched or
 * fabricated; the "preview" timeline is plain skeleton shapes.
 */
const MyRecords = (() => {

    function init() {
        if (!API.requireAuth()) return;

        const timeline = document.querySelector('.records-timeline');
        if (timeline) Motion.staggerIn(timeline, '.records-timeline-item');
    }

    return { init };

})();
