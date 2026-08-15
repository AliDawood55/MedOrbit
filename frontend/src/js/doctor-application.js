const DoctorApplication = (() => {
    let profile = null;
    let applications = [];

    const byId = (id) => document.getElementById(id);
    const lines = (value) => String(value || '').split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[char]));
    const localized = (arValue, enValue) => (
        typeof I18n !== 'undefined' && typeof I18n.localizedContent === 'function'
            ? I18n.localizedContent(arValue, enValue)
            : (arValue || enValue || '')
    );

    function showAlert(message, type = 'error') {
        const element = byId('applicationAlert');
        element.className = `alert ${type}`;
        element.textContent = message;
    }

    function clearAlert() {
        const element = byId('applicationAlert');
        element.className = 'alert';
        element.textContent = '';
    }

    function statusCard(latest) {
        if (!latest) return '';
        const reason = latest.status === 'rejected' && latest.rejection_reason
            ? `<div class="application-note"><strong>سبب الرفض / Reason</strong><p>${escapeHtml(latest.rejection_reason)}</p></div>`
            : '';
        const relogin = latest.status === 'approved'
            ? '<p>تمت الموافقة. سجّل الدخول مجدداً لتحميل صلاحية الطبيب الجديدة.</p><button id="reloginBtn" class="btn btn-primary">تسجيل الدخول مجدداً / Sign in again</button>'
            : '';
        const withdraw = latest.status === 'pending'
            ? `<button id="withdrawBtn" class="btn btn-secondary" data-id="${escapeHtml(latest.id)}">سحب الطلب / Withdraw</button>`
            : '';
        return `<div class="application-hero"><div><h2>حالة الطلب / Application status</h2><span class="application-status ${escapeHtml(latest.status)}">${escapeHtml(latest.status)}</span></div></div><p>تاريخ التقديم: ${new Date(latest.submitted_at).toLocaleDateString()}</p>${reason}${relogin}<div class="application-actions">${withdraw}</div>`;
    }

    function render() {
        const latest = applications[0];
        byId('applicationLoading').classList.add('hidden');
        if (latest) {
            byId('applicationState').innerHTML = statusCard(latest);
            byId('applicationState').classList.remove('hidden');
        } else {
            byId('applicationState').classList.add('hidden');
        }

        const canApply = profile.role === 'patient' && (!latest || ['rejected', 'withdrawn'].includes(latest.status));
        byId('applicationFormCard').classList.toggle('hidden', !canApply);
        byId('applicationHistoryCard').classList.toggle('hidden', !applications.length);
        byId('applicationHistory').innerHTML = applications.map((application) => (
            `<div class="application-history-item"><div><strong>${escapeHtml(application.medical_license_number)}</strong>` +
            `<div class="text-muted">${new Date(application.submitted_at).toLocaleDateString()}</div></div>` +
            `<span class="application-status ${escapeHtml(application.status)}">${escapeHtml(application.status)}</span></div>`
        )).join('');
        byId('withdrawBtn')?.addEventListener('click', withdraw);
        byId('reloginBtn')?.addEventListener('click', () => {
            API.clearSession();
            location.href = 'login.html?redirect=doctor-application.html';
        });
    }

    async function loadSpecialties() {
        const response = await API.get('/specialties');
        const items = response.data?.specialties || response.data || [];
        byId('specialtyId').innerHTML = '<option value="">اختر التخصص / Select specialty</option>' + items.map((specialty) => (
            `<option value="${escapeHtml(specialty.id)}">${escapeHtml(localized(specialty.name_ar, specialty.name_en))}</option>`
        )).join('');
    }

    async function load() {
        if (!API.requireAuth('doctor-application.html')) return;
        try {
            const [me, apps] = await Promise.all([
                API.users.me(),
                API.get('/doctor-applications/me'),
            ]);
            profile = me.data;
            applications = apps.data || [];
            if (!['patient', 'doctor'].includes(profile.role)) {
                showAlert('هذه الصفحة متاحة لحسابات المرضى فقط / Patient accounts only');
                byId('applicationLoading').classList.add('hidden');
                return;
            }
            await loadSpecialties();
            render();
        } catch (error) {
            byId('applicationLoading').classList.add('hidden');
            showAlert(error.message || 'تعذر تحميل الطلب');
        }
    }

    async function submit(event) {
        event.preventDefault();
        clearAlert();
        const button = byId('submitApplication');
        button.disabled = true;
        try {
            await API.post('/doctor-applications', {
                specialty_id: byId('specialtyId').value,
                medical_license_number: byId('licenseNumber').value.trim(),
                sub_specialty: byId('subSpecialty').value.trim() || null,
                years_of_experience: byId('experience').value ? Number(byId('experience').value) : null,
                education: lines(byId('education').value),
                certifications: lines(byId('certifications').value),
                bio: byId('bio').value.trim() || null,
            });
            Toast.success('تم إرسال الطلب / Application submitted');
            await load();
        } catch (error) {
            showAlert(error.message || 'تعذر إرسال الطلب');
        } finally {
            button.disabled = false;
        }
    }

    async function withdraw(event) {
        const button = event.currentTarget;
        if (!confirm('سحب الطلب المعلق؟ / Withdraw this pending application?')) return;
        button.disabled = true;
        try {
            await API.post(`/doctor-applications/${button.dataset.id}/withdraw`, {});
            Toast.success('تم سحب الطلب / Application withdrawn');
            await load();
        } catch (error) {
            showAlert(error.message);
        } finally {
            button.disabled = false;
        }
    }

    function init() {
        byId('doctorApplicationForm').addEventListener('submit', submit);
        load();
    }

    return { init };
})();
