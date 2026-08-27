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
        byId('invitationListTitle').textContent = copy('الدعوات المعلقة', 'Pending invitations');
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
        const pending = invitations.filter((invitation) => invitation.status === 'pending');
        if (!pending.length) {
            const empty = document.createElement('div');
            empty.className = 'profile-compact-empty';
            empty.textContent = copy('لا توجد دعوات معلقة.', 'No pending invitations.');
            root.appendChild(empty);
            return;
        }
        pending.forEach((invitation) => {
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
            const delivered = response?.data?.delivery === 'sent';
            if (url) {
                byId('manualInvitationHint').textContent = delivered
                    ? copy('أفاد خادم البريد بإرسال الدعوة. هذا رابط احتياطي آمن لمرة واحدة إذا تأخر البريد أو انتقل إلى الرسائل غير المرغوب فيها. أرسله فقط إلى البريد المدعو.', 'The mail server reports that the invitation was sent. This is a one-time secure backup link if email is delayed or filtered; send it only to the invited email address.')
                    : copy('تعذر تسليم البريد تلقائياً. أرسل هذا الرابط الآمن لمرة واحدة إلى البريد المدعو فقط؛ يجب أن يسجل دخوله بالحساب المدعو ثم يقبل الدعوة.', 'The email could not be delivered automatically. Send this one-time secure link only to the invited email address; they must sign in to that account and accept it.');
                byId('manualInvitationLink').href = url;
                byId('manualInvitationLink').textContent = url;
                byId('manualInvitation').classList.remove('hidden');
            }
            feedback(delivered
                ? copy('تم إنشاء الدعوة وإرسال البريد. يظهر الرابط الاحتياطي أدناه.', 'Invitation created and email sent. A backup link is shown below.')
                : copy('تم إنشاء الدعوة، لكن يلزم تسليم الرابط يدوياً.', 'Invitation created, but the link needs manual delivery.'), 'success');
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
            // Remove it immediately; a later refresh remains available for
            // reconciliation, but cancellation should never look stuck.
            invitations = invitations.filter((invitation) => invitation.id !== id);
            render();
            feedback(copy('تم إلغاء الدعوة.', 'Invitation revoked.'), 'success');
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
            byId('refreshInvitations').addEventListener('click', async () => {
                const button = byId('refreshInvitations');
                button.disabled = true;
                button.setAttribute('aria-busy', 'true');
                try {
                    await load();
                    feedback(copy('تم تحديث الدعوات المعلقة.', 'Pending invitations refreshed.'), 'success');
                } catch (err) {
                    feedback(err.message || copy('تعذر تحديث الدعوات.', 'Could not refresh invitations.'));
                } finally {
                    button.disabled = false;
                    button.removeAttribute('aria-busy');
                }
            });
            await load();
        } catch (err) {
            feedback(err.message || copy('تعذر تحميل الدعوات.', 'Unable to load invitations.'));
        }
    }

    return { init };
})();
