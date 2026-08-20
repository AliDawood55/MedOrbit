const AdminInvitations = (() => {
    const byId = (id) => document.getElementById(id);
    const isAr = () => I18n.getLang() === 'ar';
    const copy = (ar, en) => isAr() ? ar : en;
    let invitations = [];

    function localize() {
        byId('invitationTitle').textContent = copy('دعوات المشرفين', 'Admin Invitations');
        byId('invitationSubtitle').textContent = copy('ادعُ الحسابات الموثقة وأدر الدعوات المعلقة.', 'Invite verified accounts and manage pending invitations.');
        byId('invitationEmailLabel').textContent = copy('البريد الإلكتروني للحساب', 'Account email');
        byId('sendInvitationLabel').textContent = copy('إرسال الدعوة', 'Send invitation');
        byId('manualInvitationTitle').textContent = copy('رابط التسليم اليدوي', 'Manual delivery link');
        byId('invitationListTitle').textContent = copy('سجل الدعوات', 'Invitation history');
        render();
    }

    function feedback(message, type = 'error') {
        const node = byId('invitationFeedback');
        node.textContent = message;
        node.className = `page-feedback ${type}`;
    }

    function render() {
        const root = byId('invitationList');
        root.textContent = '';
        if (!invitations.length) {
            const empty = document.createElement('div');
            empty.className = 'profile-compact-empty';
            empty.textContent = copy('لا توجد دعوات بعد.', 'No invitations yet.');
            root.appendChild(empty);
            return;
        }
        invitations.forEach((invitation) => {
            const item = document.createElement('div');
            item.className = 'application-history-item';
            const detail = document.createElement('div');
            const email = document.createElement('strong');
            email.textContent = invitation.email;
            const meta = document.createElement('div');
            meta.className = 'text-muted';
            meta.textContent = `${new Date(invitation.created_at).toLocaleDateString(isAr() ? 'ar' : 'en-US')} · ${invitation.status}`;
            detail.append(email, meta);
            const actions = document.createElement('div');
            actions.className = 'application-actions';
            const status = document.createElement('span');
            status.className = `application-status ${invitation.status}`;
            status.textContent = invitation.status;
            actions.appendChild(status);
            if (invitation.status === 'pending') {
                const revoke = document.createElement('button');
                revoke.type = 'button';
                revoke.className = 'btn btn-danger btn-sm';
                revoke.textContent = copy('إلغاء', 'Revoke');
                revoke.addEventListener('click', () => revokeInvitation(invitation.id, revoke));
                actions.appendChild(revoke);
            }
            item.append(detail, actions);
            root.appendChild(item);
        });
    }

    async function load() {
        const response = await API.adminInvitations.list();
        invitations = Array.isArray(response?.data) ? response.data : [];
        render();
    }

    async function submit(event) {
        event.preventDefault();
        const button = byId('sendInvitation');
        button.disabled = true;
        byId('manualInvitation').classList.add('hidden');
        try {
            const response = await API.adminInvitations.create(byId('invitationEmail').value.trim());
            byId('adminInvitationForm').reset();
            const url = response?.data?.acceptance_url;
            if (url) {
                byId('manualInvitationHint').textContent = copy('لم يُرسل البريد في هذه البيئة. سلّم هذا الرابط بأمان مرة واحدة.', 'Email is not configured in this environment. Deliver this link securely once.');
                byId('manualInvitationLink').href = url;
                byId('manualInvitationLink').textContent = url;
                byId('manualInvitation').classList.remove('hidden');
            }
            feedback(copy('تم إنشاء الدعوة.', 'Invitation created.'), 'success');
            await load();
        } catch (err) {
            feedback(err.message || copy('تعذر إنشاء الدعوة.', 'Unable to create invitation.'));
        } finally {
            button.disabled = false;
        }
    }

    async function revokeInvitation(id, button) {
        if (!confirm(copy('إلغاء هذه الدعوة؟', 'Revoke this invitation?'))) return;
        button.disabled = true;
        try {
            await API.adminInvitations.revoke(id);
            feedback(copy('تم إلغاء الدعوة.', 'Invitation revoked.'), 'success');
            await load();
        } catch (err) {
            button.disabled = false;
            feedback(err.message || copy('تعذر إلغاء الدعوة.', 'Unable to revoke invitation.'));
        }
    }

    async function init() {
        if (!API.requireAuth()) return;
        try {
            const me = await API.users.me();
            if (me?.data?.role !== 'super_admin') {
                location.href = 'dashboard.html';
                return;
            }
            localize();
            window.addEventListener('languageChanged', localize);
            byId('adminInvitationForm').addEventListener('submit', submit);
            byId('refreshInvitations').addEventListener('click', () => load().catch((err) => feedback(err.message)));
            await load();
        } catch (err) {
            feedback(err.message || copy('تعذر تحميل الدعوات.', 'Unable to load invitations.'));
        }
    }

    return { init };
})();
