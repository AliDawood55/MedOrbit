const NotificationsPage = (() => {

    let notifications = [];
    let unreadOnly = false;
    let initialized = false;
    let loadRequest = null;

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

    function formatRelativeTime(dateStr) {
        if (!dateStr) return '';
        const diffMin = Math.round((Date.now() - new Date(dateStr).getTime()) / 60000);
        const ar = isAr();
        if (diffMin < 1) return ar ? 'الآن' : 'now';
        if (diffMin < 60) return ar ? `منذ ${diffMin} د` : `${diffMin}m ago`;
        const diffH = Math.round(diffMin / 60);
        if (diffH < 24) return ar ? `منذ ${diffH} س` : `${diffH}h ago`;
        const diffD = Math.round(diffH / 24);
        return ar ? `منذ ${diffD} يوم` : `${diffD}d ago`;
    }

    function destinationFor(notification) {
        if (!notification?.reference_id) return null;

        const role = API.getUser()?.role;
        const referenceType = String(notification.reference_type || '').toUpperCase();
        const notificationType = String(notification.notification_type || '').toUpperCase();
        if (['APPOINTMENT', 'APPOINTMENTS'].includes(referenceType)
            && (notificationType === 'APPOINTMENT'
                || notificationType === 'REMINDER'
                || notificationType.startsWith('APPOINTMENT_'))
            && ['patient', 'doctor'].includes(role)) {
            return role === 'doctor' ? 'my-schedule.html#appointments' : 'my-appointments.html';
        }
        if (notification.reference_type === 'DIRECT_CONVERSATION'
            && ['NEW_DIRECT_MESSAGE', 'NEW_MESSAGE_REQUEST', 'MESSAGE_REQUEST_ACCEPTED'].includes(notification.notification_type)
            && ['patient', 'doctor'].includes(role)) {
            return 'direct-messages.html?id=' + encodeURIComponent(notification.reference_id);
        }
        if (notification.reference_type === 'CONTACT_MESSAGE'
            && notification.notification_type === 'NEW_CONTACT_MESSAGE'
            && ['admin', 'super_admin'].includes(role)) {
            return 'admin-contact-messages.html?message=' + encodeURIComponent(notification.reference_id);
        }
        if (notification.reference_type === 'CLINIC_APPLICATION'
            && notification.notification_type === 'CLINIC_APPLICATION_SUBMITTED'
            && ['admin', 'super_admin'].includes(role)) {
            return 'admin-clinic-applications.html?status=pending&application=' + encodeURIComponent(notification.reference_id);
        }
        if (notification.reference_type === 'CLINIC_CREDENTIAL_CHANGE') {
            if (notification.notification_type === 'CLINIC_CREDENTIAL_CHANGE_REQUESTED'
                && ['admin', 'super_admin'].includes(role)) {
                return 'admin-clinic-credential-requests.html?status=pending';
            }
            if (['CLINIC_CREDENTIAL_CHANGE_APPROVED', 'CLINIC_CREDENTIAL_CHANGE_REJECTED'].includes(notification.notification_type)
                && role === 'clinic') {
                return 'clinic-workspace.html';
            }
        }
        if (notification.reference_type !== 'DOCTOR_APPLICATION') return null;
        if (notification.notification_type === 'DOCTOR_APPLICATION_SUBMITTED' && ['admin', 'super_admin'].includes(role)) {
            return 'admin-doctor-applications.html?status=pending&application=' + encodeURIComponent(notification.reference_id);
        }
        if (['DOCTOR_APPLICATION_SUBMITTED', 'DOCTOR_APPLICATION_APPROVED', 'DOCTOR_APPLICATION_REJECTED'].includes(notification.notification_type)) {
            return 'doctor-application.html';
        }
        return null;
    }

    function renderItem(n) {
        const title = isAr() ? (n.title_ar || n.title_en) : (n.title_en || n.title_ar);
        const message = isAr() ? (n.message_ar || n.message_en) : (n.message_en || n.message_ar);
        const unread = !n.is_read;

        const destination = destinationFor(n);
        return (
            '<div class="dashboard-list-item dashboard-notif-item notif-page-item' + (unread ? ' unread' : '') + (destination ? ' navigable' : '') + '" data-id="' + escapeHtml(n.id) + '"' + (destination ? ' tabindex="0" role="link"' : '') + '>' +
                '<span class="' + (unread ? 'notif-dot' : 'notif-dot-spacer') + '"></span>' +
                '<div class="dashboard-list-main">' +
                    '<div class="dashboard-list-title">' + escapeHtml(title || '') + '</div>' +
                    (message ? '<div class="dashboard-list-meta">' + escapeHtml(message) + '</div>' : '') +
                    '<div class="dashboard-list-meta notif-time">' + escapeHtml(formatRelativeTime(n.created_at)) + '</div>' +
                '</div>' +
                '<div class="dashboard-list-actions">' +
                    (unread ? '<button type="button" class="dashboard-item-btn" data-action="read" title="' + escapeHtml(t('notifications.markRead')) + '"><i class="fas fa-check"></i></button>' : '') +
                    '<button type="button" class="dashboard-item-btn" data-action="delete" title="' + escapeHtml(t('notifications.deleteOne')) + '"><i class="fas fa-trash"></i></button>' +
                '</div>' +
            '</div>'
        );
    }

    function render() {
        const list = document.getElementById('notifPageList');
        const empty = document.getElementById('notifPageEmpty');
        const markAllBtn = document.getElementById('markAllReadBtn');

        const unreadCount = notifications.filter((n) => !n.is_read).length;
        markAllBtn.classList.toggle('hidden', unreadCount === 0);

        const visible = unreadOnly ? notifications.filter((n) => !n.is_read) : notifications;

        if (!visible.length) {
            list.innerHTML = '';
            list.classList.add('hidden');
            empty.classList.remove('hidden');

            const titleEl = document.getElementById('notifPageEmptyTitle');
            const hintEl = document.getElementById('notifPageEmptyHint');
            if (unreadOnly && notifications.length) {
                titleEl.textContent = t('notifications.emptyUnreadTitle');
                hintEl.textContent = t('notifications.emptyUnreadHint');
            } else {
                titleEl.textContent = t('dashboard.notifEmptyTitle');
                hintEl.textContent = t('dashboard.notifEmptyHint');
            }
            return;
        }

        empty.classList.add('hidden');
        list.classList.remove('hidden');
        list.innerHTML = visible.map(renderItem).join('');
        Motion.staggerIn(list, '.notif-page-item');

        list.querySelectorAll('[data-action="read"]').forEach((btn) => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const id = btn.closest('.notif-page-item').dataset.id;
                markOneRead(id);
            });
        });
        list.querySelectorAll('[data-action="delete"]').forEach((btn) => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const id = btn.closest('.notif-page-item').dataset.id;
                removeOne(id);
            });
        });
        list.querySelectorAll('.notif-page-item.navigable').forEach((item) => {
            const notification = notifications.find((entry) => entry.id === item.dataset.id);
            const open = () => openNotification(notification);
            item.addEventListener('click', open);
            item.addEventListener('keydown', (event) => {
                if (event.key !== 'Enter' && event.key !== ' ') return;
                event.preventDefault();
                open();
            });
        });
    }

    async function openNotification(notification) {
        const destination = destinationFor(notification);
        if (!destination) return;

        if (!notification.is_read) {
            try {
                await API.notifications.markRead(notification.id);
                notification.is_read = true;
                window.dispatchEvent(new CustomEvent('notifications:changed'));
            } catch (err) {
                console.error('Notifications: failed to mark opened notification read', err);
            }
        }
        window.location.href = destination;
    }

    async function markOneRead(id) {
        const item = notifications.find((n) => n.id === id);
        try {
            await API.notifications.markRead(id);
            if (item) item.is_read = true;
            render();
            window.dispatchEvent(new CustomEvent('notifications:changed'));
        } catch (err) {
            console.error('Notifications: failed to mark read', err);
            if (typeof Toast !== 'undefined') Toast.error(t('notifications.markAllError'));
        }
    }

    async function removeOne(id) {
        const prev = notifications;
        notifications = notifications.filter((n) => n.id !== id);
        render();
        try {
            await API.notifications.remove(id);
            window.dispatchEvent(new CustomEvent('notifications:changed'));
        } catch (err) {
            console.error('Notifications: failed to delete', err);
            notifications = prev;
            render();
            if (typeof Toast !== 'undefined') Toast.error(t('notifications.deleteError'));
        }
    }

    async function markAllRead() {
        const btn = document.getElementById('markAllReadBtn');
        btn.disabled = true;
        try {
            await API.notifications.markAllRead();
            notifications = notifications.map((n) => ({ ...n, is_read: true }));
            render();
            window.dispatchEvent(new CustomEvent('notifications:changed'));
        } catch (err) {
            console.error('Notifications: failed to mark all read', err);
            if (typeof Toast !== 'undefined') Toast.error(t('notifications.markAllError'));
        } finally {
            btn.disabled = false;
        }
    }

    async function load() {
        if (loadRequest) return loadRequest;
        loadRequest = loadNotifications();
        try {
            return await loadRequest;
        } finally {
            loadRequest = null;
        }
    }

    async function loadNotifications() {
        document.getElementById('notifSkeleton').classList.remove('hidden');
        document.getElementById('notifPageError').classList.add('hidden');
        document.getElementById('notifPageContent').classList.add('hidden');

        try {
            const res = await API.notifications.list();
            notifications = res?.data || [];
            document.getElementById('notifSkeleton').classList.add('hidden');
            document.getElementById('notifPageContent').classList.remove('hidden');
            render();
        } catch (err) {
            console.error('Notifications: failed to load', err);
            document.getElementById('notifSkeleton').classList.add('hidden');
            document.getElementById('notifPageError').classList.remove('hidden');
        }
    }

    function init() {
        if (initialized) return;
        initialized = true;
        if (!API.requireAuth()) return;

        document.getElementById('markAllReadBtn')?.addEventListener('click', markAllRead);
        document.getElementById('notifRetryBtn')?.addEventListener('click', load);
        document.getElementById('unreadOnlyToggle')?.addEventListener('change', (e) => {
            unreadOnly = e.target.checked;
            render();
        });

        window.addEventListener('languageChanged', () => {
            if (!document.getElementById('notifPageContent').classList.contains('hidden')) render();
        });

        load();
    }

    return { init };

})();
