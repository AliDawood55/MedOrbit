const DoctorClinicInvitations = (() => {
    const $ = (id) => document.getElementById(id);
    const ar = () => I18n?.getLang?.() === 'ar';
    const t = (arabic, english) => ar() ? arabic : english;
    const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[char]));
    const status = (value) => ({ pending:t('قيد الانتظار', 'Pending'), accepted:t('مقبولة', 'Accepted'), declined:t('مرفوضة', 'Declined'), cancelled:t('ملغاة', 'Cancelled') }[value] || value);
    const clinicName = (invitation) => ar()
        ? invitation.name_ar || invitation.name_en
        : invitation.name_en || invitation.name_ar;

    async function load() {
        try {
            const response = await API.doctors.clinicInvitations();
            const invitations = response.data || [];
            $('invitations').innerHTML = invitations.length
                ? invitations.map((invitation) => `<article class="control-list-item"><div><a class="clinic-invitation-profile-link" href="clinic.html?id=${encodeURIComponent(invitation.clinic_id)}"><strong>${esc(clinicName(invitation))}</strong></a><small>${esc(invitation.city || '')}${invitation.message ? ` · ${esc(invitation.message)}` : ''}</small></div><div>${invitation.clinic_id ? `<a class="btn btn-ghost btn-sm" href="direct-messages.html?counterpart=${encodeURIComponent(invitation.clinic_id)}">${t('مراسلة المنشأة', 'Message clinic')}</a>` : ''}${invitation.status === 'pending' ? `<button class="btn btn-primary btn-sm" data-accept="${esc(invitation.id)}">${t('قبول', 'Accept')}</button><button class="btn btn-danger btn-sm" data-decline="${esc(invitation.id)}">${t('رفض', 'Decline')}</button>` : `<span class="request-status">${esc(status(invitation.status))}</span>`}</div></article>`).join('')
                : `<p class="text-muted">${t('لا توجد دعوات منشآت.', 'No clinic invitations.')}</p>`;
            $('invitations').querySelectorAll('[data-accept]').forEach((button) => { button.onclick = () => respond(button.dataset.accept, true); });
            $('invitations').querySelectorAll('[data-decline]').forEach((button) => { button.onclick = () => respond(button.dataset.decline, false); });
        } catch (error) { $('invitations').textContent = error.message || t('تعذر تحميل الدعوات', 'Could not load invitations'); }
    }

    async function respond(id, accepted) {
        try {
            await API.doctors.respondToClinicInvitation(id, accepted);
            Toast.success(accepted ? t('تم قبول الدعوة', 'Invitation accepted') : t('تم رفض الدعوة', 'Invitation declined'));
            await load();
        } catch (error) { alert(error.message); }
    }

    async function init() {
        if (!API.requireAuth('doctor-clinic-invitations.html')) return;
        if (await AuthGate.verifySession() !== 'valid') return;
        if (AuthGate.getVerifiedUser()?.role !== 'doctor') { location.href = 'dashboard.html'; return; }
        window.addEventListener('languageChanged', load);
        await load();
    }
    return { init };
})();
