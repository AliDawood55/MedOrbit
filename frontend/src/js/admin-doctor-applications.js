const AdminDoctorApplications = (() => {
    const VALID_STATUSES = new Set(['pending', 'approved', 'rejected', '']);
    const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    let applications = [];
    let selected = null;
    let initialized = false;
    let loadRequest = null;
    let actionRequest = null;

    const byId = (id) => document.getElementById(id);
    const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[char]));
    const localized = (arValue, enValue) => (
        typeof I18n !== 'undefined' && typeof I18n.localizedContent === 'function'
            ? I18n.localizedContent(arValue, enValue)
            : (arValue || enValue || '')
    );
    const applicantName = (application) => [
        localized(application.applicant?.first_name_ar, application.applicant?.first_name_en),
        localized(application.applicant?.last_name_ar, application.applicant?.last_name_en),
    ].filter(Boolean).join(' ') || application.applicant?.email || 'Applicant';

    function showAlert(message, type = 'error') {
        const element = byId('reviewAlert');
        element.className = `alert ${type}`;
        element.textContent = message;
    }

    function clearAlert() {
        const element = byId('reviewAlert');
        element.className = 'alert';
        element.textContent = '';
    }

    function valueList(value) {
        if (Array.isArray(value)) return value.map(escapeHtml).join('<br>');
        return value ? escapeHtml(value) : '—';
    }

    function renderList() {
        byId('reviewLoading').classList.add('hidden');
        byId('reviewEmpty').classList.toggle('hidden', applications.length > 0);
        byId('reviewList').innerHTML = applications.map((application) => (
            `<button class="review-item${selected?.id === application.id ? ' active' : ''}" data-id="${escapeHtml(application.id)}">` +
                `<strong>${escapeHtml(applicantName(application))}</strong>` +
                `<div>${escapeHtml(localized(application.specialty?.name_ar, application.specialty?.name_en))}</div>` +
                `<small>${new Date(application.submitted_at).toLocaleDateString()} · ${escapeHtml(application.status)}</small>` +
            '</button>'
        )).join('');

        byId('reviewList').querySelectorAll('.review-item').forEach((button) => {
            button.addEventListener('click', () => selectApplication(button.dataset.id));
        });
    }

    function renderDetail() {
        if (!selected) {
            byId('reviewDetail').innerHTML = '<div class="empty-state"><h3>Select an application / اختر طلباً</h3></div>';
            return;
        }

        const application = selected;
        const pending = application.status === 'pending';
        byId('reviewDetail').innerHTML =
            '<div class="application-hero"><div>' +
                `<h2>${escapeHtml(applicantName(application))}</h2>` +
                `<p>${escapeHtml(application.applicant?.email)}</p>` +
            `</div><span class="application-status ${escapeHtml(application.status)}">${escapeHtml(application.status)}</span></div>` +
            '<div class="review-detail-grid">' +
                `<div class="review-field"><strong>Specialty / التخصص</strong>${escapeHtml(localized(application.specialty?.name_ar, application.specialty?.name_en))}</div>` +
                `<div class="review-field"><strong>Medical license / الترخيص</strong>${escapeHtml(application.medical_license_number)}</div>` +
                `<div class="review-field"><strong>Sub-specialty</strong>${escapeHtml(application.sub_specialty || '—')}</div>` +
                `<div class="review-field"><strong>Experience</strong>${escapeHtml(application.years_of_experience ?? '—')}</div>` +
                `<div class="review-field"><strong>Education</strong>${valueList(application.education)}</div>` +
                `<div class="review-field"><strong>Certifications</strong>${valueList(application.certifications)}</div>` +
                `<div class="review-field full"><strong>Professional bio</strong><div class="review-bio">${escapeHtml(application.bio || localized(application.bio_ar, application.bio_en) || '—')}</div></div>` +
            '</div>' +
            (pending
                ? '<div class="form-group review-rejection-group"><label for="rejectionReason">سبب الرفض / Rejection reason</label><textarea id="rejectionReason" rows="3"></textarea></div>' +
                  '<div class="application-actions"><button id="approveApplication" class="btn btn-primary"><i class="fas fa-check"></i> Approve / موافقة</button>' +
                  '<button id="rejectApplication" class="btn btn-danger"><i class="fas fa-xmark"></i> Reject / رفض</button></div>'
                : '');

        byId('approveApplication')?.addEventListener('click', approve);
        byId('rejectApplication')?.addEventListener('click', reject);
    }

    function selectApplication(id) {
        selected = applications.find((application) => application.id === id) || null;
        if (!selected) return;

        const params = new URLSearchParams(window.location.search);
        params.set('application', selected.id);
        history.replaceState({}, '', `${window.location.pathname}?${params.toString()}`);
        clearAlert();
        renderList();
        renderDetail();
    }

    async function load(targetApplicationId = null) {
        if (loadRequest) return loadRequest;

        loadRequest = (async () => {
            clearAlert();
            byId('reviewLoading').classList.remove('hidden');
            byId('statusFilter').disabled = true;
            try {
                const status = byId('statusFilter').value;
                const response = await API.get('/admin/doctor-applications', status ? { status } : null);
                applications = response.data || [];
                selected = null;
                renderList();
                renderDetail();

                if (targetApplicationId && UUID_PATTERN.test(targetApplicationId)) {
                    selectApplication(targetApplicationId);
                }
            } catch (err) {
                byId('reviewLoading').classList.add('hidden');
                showAlert(err.message);
            } finally {
                byId('statusFilter').disabled = false;
            }
        })();

        try {
            return await loadRequest;
        } finally {
            loadRequest = null;
        }
    }

    async function runDecision(path, body, successMessage) {
        if (!selected || actionRequest) return;
        const buttons = byId('reviewDetail').querySelectorAll('button');
        buttons.forEach((button) => { button.disabled = true; });
        actionRequest = API.post(path, body);
        try {
            await actionRequest;
            Toast.success(successMessage);
            const params = new URLSearchParams(window.location.search);
            params.delete('application');
            history.replaceState({}, '', `${window.location.pathname}?${params.toString()}`);
            await load();
        } catch (err) {
            showAlert(err.message);
        } finally {
            actionRequest = null;
            buttons.forEach((button) => { button.disabled = false; });
        }
    }

    async function approve() {
        if (!window.confirm('Approve this doctor application?')) return;
        await runDecision(`/admin/doctor-applications/${selected.id}/approve`, {}, 'Application approved');
    }

    async function reject() {
        const reason = byId('rejectionReason').value.trim();
        if (!reason) {
            showAlert('سبب الرفض مطلوب / Rejection reason is required');
            return;
        }
        await runDecision(
            `/admin/doctor-applications/${selected.id}/reject`,
            { rejection_reason: reason },
            'Application rejected'
        );
    }

    async function init() {
        if (initialized) return;
        initialized = true;
        if (!API.requireAuth('admin-doctor-applications.html')) return;

        const state = await AuthGate.verifySession();
        if (state !== 'valid') return;

        const me = AuthGate.getVerifiedUser();
        if (!['admin', 'super_admin'].includes(me?.role)) {
            location.href = 'dashboard.html';
            return;
        }

        try {
            const params = new URLSearchParams(window.location.search);
            const requestedStatus = params.get('status');
            if (requestedStatus !== null && VALID_STATUSES.has(requestedStatus)) {
                byId('statusFilter').value = requestedStatus;
            }
            const targetApplicationId = params.get('application');

            byId('statusFilter').addEventListener('change', () => {
                const next = new URLSearchParams(window.location.search);
                const status = byId('statusFilter').value;
                if (status) next.set('status', status); else next.delete('status');
                next.delete('application');
                history.replaceState({}, '', `${window.location.pathname}?${next.toString()}`);
                load();
            });
            window.addEventListener('languageChanged', () => {
                renderList();
                renderDetail();
            });
            await load(targetApplicationId);
        } catch (err) {
            showAlert(err.message);
        }
    }

    return { init };
})();
