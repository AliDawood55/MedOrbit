/**
 * MedOrbit v2 - My Prescriptions
 * No backend endpoint exists for prescriptions at all (see
 * BACKEND_NEEDED.md, item 5) — this page is a full UI shell (filters,
 * card/detail preview) with an honest empty state. Nothing here is
 * fetched or fabricated; the "preview" cards are plain skeleton shapes.
 */
const MyPrescriptions = (() => {

    function init() {
        if (!API.requireAuth()) return;

        const list = document.querySelector('.records-preview-list');
        if (list) Motion.staggerIn(list, '.records-preview-card');
    }

    return { init };

})();
