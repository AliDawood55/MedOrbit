/**
 * MedOrbit v2 - Doctor Posts (management)
 *
 * GET/POST /doctors/me/posts, PUT/DELETE /doctors/me/posts/:postId
 * (backend/src/routes/doctor.routes.js) — doctor_id resolved server-side
 * from the JWT for every operation; PUT/DELETE additionally verify the
 * post belongs to the calling doctor (id + doctor_id match in the WHERE
 * clause) before touching it.
 */
const DoctorPosts = (() => {

    const CATEGORY_KEY = {
        health_tip: 'doctorPosts.categoryHealthTip',
        announcement: 'doctorPosts.categoryAnnouncement',
        clinic_news: 'doctorPosts.categoryClinicNews',
        article: 'doctorPosts.categoryArticle'
    };

    let posts = [];
    let editingPostId = null;

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function fmtDate(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString(isAr() ? 'ar' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    function postTitle(p) {
        return (isAr() ? p.title_ar : p.title_en) || p.title_ar || p.title_en || '';
    }

    // ================= LIST =================

    async function loadPosts() {
        const el = document.getElementById('postsList');
        if (!el) return;
        el.innerHTML = renderSkeleton();

        try {
            const res = await API.care.myPosts();
            posts = Array.isArray(res?.data) ? res.data : [];
            renderPosts();
        } catch (err) {
            console.error('DoctorPosts: failed to load posts', err);
            el.innerHTML = renderError();
        }
    }

    function renderSkeleton() {
        const card = '<div class="records-preview-card">' +
            '<div class="records-preview-card-icon skeleton"></div>' +
            '<div class="records-preview-card-lines">' +
                '<div class="sk-line tall w-60 skeleton"></div>' +
                '<div class="sk-line w-40 skeleton"></div>' +
            '</div>' +
        '</div>';
        return '<div class="records-preview-list">' + card.repeat(2) + '</div>';
    }

    function renderEmpty() {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas fa-newspaper"></i></div>' +
            '<h3>' + escapeHtml(t('doctorPosts.emptyTitle')) + '</h3>' +
            '<p>' + escapeHtml(t('doctorPosts.emptyHint')) + '</p>' +
        '</div>';
    }

    function renderError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('doctorPosts.error')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="postsRetryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
        '</div>';
    }

    function renderPosts() {
        const el = document.getElementById('postsList');
        if (!el) return;

        if (!posts.length) {
            el.innerHTML = renderEmpty();
            return;
        }

        el.innerHTML = '<div class="records-real-list">' + posts.map(renderPostCard).join('') + '</div>';

        el.querySelectorAll('[data-edit-id]').forEach((btn) => {
            btn.addEventListener('click', () => openEditForm(btn.dataset.editId));
        });
        el.querySelectorAll('[data-delete-id]').forEach((btn) => {
            btn.addEventListener('click', () => openDeleteModal(btn.dataset.deleteId));
        });
    }

    function renderPostCard(p) {
        const bodyPreview = p.body && p.body.length > 140 ? p.body.slice(0, 140) + '…' : (p.body || '');
        return (
            '<div class="records-real-card" style="cursor:default;">' +
                '<span class="records-real-icon"><i class="fas fa-newspaper"></i></span>' +
                '<span class="records-real-card-main">' +
                    '<span class="records-real-title">' + escapeHtml(postTitle(p)) + '</span>' +
                    '<span class="records-real-meta">' +
                        '<span class="records-real-badge ' + (p.is_published ? 'active' : '') + '">' + escapeHtml(t(p.is_published ? 'doctorPosts.published' : 'doctorPosts.draftLabel')) + '</span>' +
                        '<span>' + escapeHtml(t(CATEGORY_KEY[p.category] || p.category)) + '</span>' +
                        '<span>' + escapeHtml(fmtDate(p.created_at)) + '</span>' +
                    '</span>' +
                    (bodyPreview ? '<span class="records-real-subtitle">' + escapeHtml(bodyPreview) + '</span>' : '') +
                    '<span class="care-person-actions" style="margin-top:8px;">' +
                        '<button type="button" class="btn btn-secondary btn-sm" data-edit-id="' + escapeHtml(p.id) + '"><i class="fas fa-pen"></i> ' + escapeHtml(t('doctorPosts.edit')) + '</button>' +
                        '<button type="button" class="btn btn-secondary btn-sm" data-delete-id="' + escapeHtml(p.id) + '"><i class="fas fa-trash"></i> ' + escapeHtml(t('doctorPosts.delete')) + '</button>' +
                    '</span>' +
                '</span>' +
            '</div>'
        );
    }

    // ================= FORM (create + edit) =================

    function showForm() {
        editingPostId = null;
        resetForm();
        document.getElementById('postFormTitle').textContent = t('doctorPosts.newPost');
        document.getElementById('postFormResult').classList.add('hidden');
        document.getElementById('postFormCard').classList.remove('hidden');
        document.getElementById('postFormAlert').className = 'alert';
        document.getElementById('postTitleAr').focus();
    }

    function openEditForm(id) {
        const p = posts.find((x) => String(x.id) === String(id));
        if (!p) return;

        editingPostId = p.id;
        document.getElementById('postFormTitle').textContent = t('doctorPosts.editPost');
        document.getElementById('postTitleAr').value = p.title_ar || '';
        document.getElementById('postTitleEn').value = p.title_en || '';
        document.getElementById('postCategory').value = p.category || 'health_tip';
        document.getElementById('postBody').value = p.body || '';
        document.getElementById('postBodyCount').textContent = String((p.body || '').length);
        document.getElementById('postPublishToggle').checked = !!p.is_published;

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
        editingPostId = null;
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

        let ok = true;
        try {
            if (editingPostId) {
                await API.care.updatePost(editingPostId, body);
            } else {
                await API.care.createPost(body);
            }
        } catch (err2) {
            console.error('DoctorPosts: failed to save post', err2);
            ok = false;
        }

        btn.classList.remove('loading');
        document.getElementById('postFormCard').classList.add('hidden');
        showResult(ok);

        if (ok) loadPosts();
    }

    function showResult(ok) {
        const icon = document.getElementById('postFormResultIcon');
        icon.className = 'feedback-result-icon ' + (ok ? 'success' : 'error');
        icon.innerHTML = '<i class="fas ' + (ok ? 'fa-circle-check' : 'fa-triangle-exclamation') + '"></i>';
        document.getElementById('postFormResultTitle').textContent = t(ok ? 'doctorPosts.savedTitle' : 'doctorPosts.errorTitle');
        document.getElementById('postFormResultHint').textContent = t(ok ? 'doctorPosts.savedHint' : 'doctorPosts.errorHint');
        document.getElementById('postFormResult').classList.remove('hidden');
    }

    // ================= DELETE =================

    function openDeleteModal(id) {
        const backdrop = document.createElement('div');
        backdrop.className = 'modal-backdrop';
        backdrop.innerHTML =
            '<div class="modal-box">' +
                '<h3>' + escapeHtml(t('doctorPosts.deleteModalTitle')) + '</h3>' +
                '<p>' + escapeHtml(t('doctorPosts.deleteModalHint')) + '</p>' +
                '<div class="alert" id="deleteModalAlert"></div>' +
                '<div class="modal-actions">' +
                    '<button type="button" class="btn btn-secondary" id="deleteDismissBtn">' + escapeHtml(t('doctorPosts.deleteDismiss')) + '</button>' +
                    '<button type="button" class="btn btn-primary" id="deleteConfirmBtn">' +
                        '<span class="btn-label">' + escapeHtml(t('doctorPosts.deleteConfirmBtn')) + '</span>' +
                        '<span class="spinner spinner-sm btn-spinner"></span>' +
                    '</button>' +
                '</div>' +
            '</div>';

        document.body.appendChild(backdrop);
        if (typeof Dom !== 'undefined') Dom.lockScroll();

        const close = () => {
            backdrop.remove();
            if (typeof Dom !== 'undefined') Dom.unlockScroll();
        };

        backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
        document.getElementById('deleteDismissBtn').addEventListener('click', close);
        document.getElementById('deleteConfirmBtn').addEventListener('click', () => confirmDelete(id, close));
    }

    async function confirmDelete(id, closeFn) {
        const btn = document.getElementById('deleteConfirmBtn');
        const alertBox = document.getElementById('deleteModalAlert');
        alertBox.className = 'alert';
        btn.classList.add('loading');

        try {
            await API.care.deletePost(id);
            if (typeof Toast !== 'undefined') Toast.success(t('doctorPosts.deleteSuccess'));
            closeFn();
            loadPosts();
        } catch (err) {
            console.error('DoctorPosts: failed to delete post', err);
            alertBox.classList.add('error');
            alertBox.textContent = t('doctorPosts.deleteError');
        } finally {
            btn.classList.remove('loading');
        }
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
        loadPosts();

        initCharCount();
        document.getElementById('newPostBtn').addEventListener('click', showForm);
        document.getElementById('postFormCancelBtn').addEventListener('click', hideForm);
        document.getElementById('postFormSubmitBtn').addEventListener('click', submit);
        document.getElementById('postFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('postFormResult').classList.add('hidden');
            resetForm();
        });
        document.getElementById('postsList')?.addEventListener('click', (e) => {
            if (e.target.closest('#postsRetryBtn')) loadPosts();
        });
    }

    return { init };

})();
