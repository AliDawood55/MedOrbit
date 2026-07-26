/**
 * MedOrbit v2 - Doctor Posts (management)
 *
 * ISOLATION NOTE FOR WHOEVER WIRES UP THE BACKEND (see BACKEND_NEEDED.md,
 * item 10): this page must only ever list/create/edit/delete the CALLING
 * doctor's own posts. `GET/POST /api/doctors/me/posts` and
 * `PUT/DELETE /api/doctors/me/posts/:postId` must resolve `doctor_id` from
 * the JWT (`req.user.sub` → `medorbit.doctors.id`) server-side — never from
 * a client-supplied value — and PUT/DELETE must additionally verify the
 * post being edited actually belongs to that doctor before touching it.
 * The role check below (`profile.role === 'doctor'`) is UX only; it stops
 * an honest user from landing on a page that isn't for them, it is NOT a
 * security boundary and enforces nothing server-side.
 *
 * No backend exists for any of this yet — the list is permanently empty and
 * the create/edit form never actually saves (honest "not connected" message
 * on submit, exactly like feedback.html's pattern elsewhere in this app).
 */
const DoctorPosts = (() => {

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    // ================= LIST =================
    // GET /api/doctors/me/posts doesn't exist yet — this call is made
    // anyway (matching the rest of this codebase's convention, e.g.
    // analytics.js) so wiring up the real route later needs no frontend
    // change. It always 404s today; the empty state is the honest result.

    async function loadPosts() {
        try {
            const res = await API.care.myPosts();
            const posts = res?.data || [];
            console.info('DoctorPosts: loaded', posts.length, 'real posts (endpoint now exists!)');
            // Intentionally not rendered as real cards yet — see
            // BACKEND_NEEDED.md item 10 for the expected shape once this
            // stops 404ing; the list UI itself is the skeleton preview
            // below until then.
        } catch (err) {
            console.info('DoctorPosts: GET /api/doctors/me/posts is not available yet (expected — see BACKEND_NEEDED.md)', err);
        }
    }

    // ================= FORM =================

    function showForm() {
        document.getElementById('postFormResult').classList.add('hidden');
        document.getElementById('postFormCard').classList.remove('hidden');
        document.getElementById('postFormAlert').className = 'alert';
        document.getElementById('postTitleAr').focus();
    }

    function hideForm() {
        document.getElementById('postFormCard').classList.add('hidden');
        resetForm();
    }

    function resetForm() {
        document.getElementById('postTitleAr').value = '';
        document.getElementById('postTitleEn').value = '';
        document.getElementById('postCategory').selectedIndex = 0;
        document.getElementById('postBody').value = '';
        document.getElementById('postBodyCount').textContent = '0';
        document.getElementById('postPublishToggle').checked = false;
        document.getElementById('postFormAlert').className = 'alert';
    }

    function initCharCount() {
        const body = document.getElementById('postBody');
        const counter = document.getElementById('postBodyCount');
        body.addEventListener('input', () => {
            counter.textContent = String(body.value.length);
        });
    }

    function validate() {
        const titleAr = document.getElementById('postTitleAr').value.trim();
        const titleEn = document.getElementById('postTitleEn').value.trim();
        const body = document.getElementById('postBody').value.trim();

        if (!titleAr && !titleEn) return t('doctorPosts.errorTitleRequired');
        if (!body) return t('doctorPosts.errorBodyRequired');
        return null;
    }

    async function submit() {
        const alertBox = document.getElementById('postFormAlert');
        alertBox.className = 'alert';

        const err = validate();
        if (err) {
            alertBox.classList.add('error');
            alertBox.textContent = err;
            return;
        }

        const btn = document.getElementById('postFormSubmitBtn');
        btn.classList.add('loading');

        const body = {
            titleAr: document.getElementById('postTitleAr').value.trim(),
            titleEn: document.getElementById('postTitleEn').value.trim(),
            category: document.getElementById('postCategory').value,
            body: document.getElementById('postBody').value.trim(),
            isPublished: document.getElementById('postPublishToggle').checked
        };

        // POST /api/doctors/me/posts doesn't exist yet (see
        // BACKEND_NEEDED.md item 10) — this call is made anyway so wiring
        // up the real route later needs no frontend change. It always
        // fails today; the honest "not saved" panel is the expected result.
        try {
            await API.care.createPost(body);
            console.info('DoctorPosts: post actually saved (endpoint now exists!)');
        } catch (err) {
            console.info('DoctorPosts: POST /api/doctors/me/posts is not available yet (expected — see BACKEND_NEEDED.md)', err);
        }

        btn.classList.remove('loading');
        document.getElementById('postFormCard').classList.add('hidden');
        document.getElementById('postFormResult').classList.remove('hidden');
    }

    // ================= ROLE GATE + INIT =================

    async function init() {
        if (!API.requireAuth()) return;

        let isDoctorRole = false;
        try {
            const res = await API.users.me();
            isDoctorRole = res?.data?.role === 'doctor';
        } catch (err) {
            console.error('DoctorPosts: failed to verify role', err);
        }

        if (!isDoctorRole) {
            document.getElementById('restrictedNotice').classList.remove('hidden');
            return;
        }

        document.getElementById('postsPageContent').classList.remove('hidden');
        Motion.staggerIn(document.querySelector('.records-preview-list'), '.records-preview-card');
        loadPosts();

        initCharCount();
        document.getElementById('newPostBtn').addEventListener('click', showForm);
        document.getElementById('postFormCancelBtn').addEventListener('click', hideForm);
        document.getElementById('postFormSubmitBtn').addEventListener('click', submit);
        document.getElementById('postFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('postFormResult').classList.add('hidden');
            resetForm();
        });
    }

    return { init };

})();
