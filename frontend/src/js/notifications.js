/**
 * MedOrbit v2 - Notifications (full inbox)
 * GET /api/notifications already returns everything (capped at 50 by the
 * backend) — no pagination needed. Uses the same PUT/PATCH/DELETE
 * endpoints already wired in api.js's notifications namespace.
 */
const NotificationsPage = (() => {

    let notifications = [];
    let unreadOnly = false;

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

    function renderItem(n) {
        const title = isAr() ? (n.title_ar || n.title_en) : (n.title_en || n.title_ar);
        const message = isAr() ? (n.message_ar || n.message_en) : (n.message_en || n.message_ar);
        const unread = !n.is_read;

        return (
            '<div class="dashboard-list-item dashboard-notif-item notif-page-item' + (unread ? ' unread' : '') + '" data-id="' + escapeHtml(n.id) + '">' +
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
    }

    async function markOneRead(id) {
        const item = notifications.find((n) => n.id === id);
        if (item) item.is_read = true;
        render();
        try {
            await API.notifications.markRead(id);
        } catch (err) {
            console.error('Notifications: failed to mark read', err);
        }
    }

    async function removeOne(id) {
        const prev = notifications;
        notifications = notifications.filter((n) => n.id !== id);
        render();
        try {
            await API.notifications.remove(id);
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
        } catch (err) {
            console.error('Notifications: failed to mark all read', err);
            if (typeof Toast !== 'undefined') Toast.error(t('notifications.markAllError'));
        } finally {
            btn.disabled = false;
        }
    }

    async function load() {
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
