/**
 * MedOrbit v2 - Dashboard
 * Built only from endpoints that actually exist: GET /users/me,
 * GET /conversations, GET /users/me/saved-places. Appointments/
 * prescriptions/medical-records have no backing API yet — rendered as
 * static "coming soon" cards, never fabricated data.
 */
const Dashboard = (() => {

    let profile = null;

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

    function t(ar, en) {
        return isAr() ? ar : en;
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

    // ================= WELCOME HEADER =================

    function displayName() {
        if (!profile) return '';
        const name = isAr()
            ? [profile.first_name_ar, profile.last_name_ar].filter(Boolean).join(' ')
            : [profile.first_name_en, profile.last_name_en].filter(Boolean).join(' ');
        return name || profile.email;
    }

    function renderWelcome() {
        const avatarEl = document.getElementById('dashAvatar');
        if (avatarEl) {
            if (profile.avatar_url) {
                avatarEl.innerHTML = '<img src="' + escapeHtml(API.getOrigin() + profile.avatar_url) + '" alt="">';
            } else {
                avatarEl.textContent = (displayName() || profile.email || '?').trim().charAt(0).toUpperCase() || '?';
            }
        }
        const nameEl = document.getElementById('dashName');
        if (nameEl) nameEl.textContent = displayName();
    }

    // ================= PROFILE COMPLETENESS =================
    // Fields required at registration (name, email) are always present —
    // only the genuinely optional ones count toward completeness.

    const COMPLETENESS_FIELDS = [
        { key: 'avatar_url', ar: 'صورة الملف الشخصي', en: 'Profile photo' },
        { key: 'phone', ar: 'رقم الهاتف', en: 'Phone number' },
        { key: 'gender', ar: 'الجنس', en: 'Gender' },
        { key: 'address', ar: 'العنوان', en: 'Address' },
        { key: 'city', ar: 'المدينة', en: 'City' }
    ];

    function renderCompleteness() {
        const filled = COMPLETENESS_FIELDS.filter((f) => !!profile[f.key]);
        const percent = Math.round((filled.length / COMPLETENESS_FIELDS.length) * 100);

        const fill = document.getElementById('completenessFill');
        if (fill) fill.style.width = percent + '%';

        const label = document.getElementById('completenessLabel');
        if (label) label.textContent = t(`${percent}% مكتمل`, `${percent}% complete`);

        const list = document.getElementById('completenessList');
        if (list) {
            list.innerHTML = COMPLETENESS_FIELDS.map((f) => {
                const done = !!profile[f.key];
                return '<li class="' + (done ? 'done' : '') + '">' +
                    '<i class="fas ' + (done ? 'fa-circle-check' : 'fa-circle') + '"></i>' +
                    '<span>' + escapeHtml(t(f.ar, f.en)) + '</span>' +
                    '</li>';
            }).join('');
        }
    }

    // ================= RECENT CONVERSATIONS =================

    function renderConversations(conversations) {
        const list = document.getElementById('conversationsList');
        const empty = document.getElementById('conversationsEmpty');
        if (!list || !empty) return;

        if (!conversations.length) {
            list.innerHTML = '';
            document.getElementById('conversationsEmptyTitle').textContent = t('لا توجد محادثات بعد', 'No conversations yet');
            document.getElementById('conversationsEmptyHint').textContent =
                t('ابدأ محادثة جديدة مع مساعدنا الذكي', 'Start a new conversation with our AI assistant');
            empty.classList.remove('hidden');
            return;
        }

        empty.classList.add('hidden');
        list.innerHTML = '';

        conversations.forEach((c) => {
            const item = document.createElement('div');
            item.className = 'dashboard-list-item';
            item.dataset.id = c.id;

            const title = c.title || t('محادثة جديدة', 'New conversation');
            const meta = formatRelativeTime(c.last_message_at || c.started_at) +
                (c.message_count != null ? ' · ' + c.message_count : '');

            item.innerHTML =
                '<a class="dashboard-list-main" href="index.html?conversation=' + encodeURIComponent(c.id) + '">' +
                    '<div class="dashboard-list-title">' + escapeHtml(title) + '</div>' +
                    '<div class="dashboard-list-meta">' + escapeHtml(meta) + '</div>' +
                '</a>' +
                '<div class="dashboard-list-actions">' +
                    '<button type="button" class="dashboard-item-btn" data-action="rename" title="' + t('إعادة تسمية', 'Rename') + '"><i class="fas fa-pen"></i></button>' +
                    '<button type="button" class="dashboard-item-btn" data-action="delete" title="' + t('حذف', 'Delete') + '"><i class="fas fa-trash"></i></button>' +
                '</div>';

            item.querySelector('[data-action="rename"]')?.addEventListener('click', () => startRename(item, c));
            item.querySelector('[data-action="delete"]')?.addEventListener('click', () => removeConversation(item, c.id));

            list.appendChild(item);
        });
    }

    function startRename(item, conversation) {
        const titleEl = item.querySelector('.dashboard-list-title');
        if (!titleEl) return;

        const current = conversation.title || '';
        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'dashboard-rename-input';
        input.value = current;

        titleEl.replaceWith(input);
        input.focus();
        input.select();

        let committed = false;
        const commit = async () => {
            if (committed) return;
            committed = true;

            const newTitle = input.value.trim();
            if (newTitle && newTitle !== current) {
                conversation.title = newTitle;
                try {
                    await API.conversations.rename(conversation.id, newTitle);
                    input.replaceWith((() => {
                        const el = document.createElement('div');
                        el.className = 'dashboard-list-title';
                        el.textContent = newTitle;
                        return el;
                    })());
                } catch (err) {
                    console.error('Dashboard: rename failed', err);
                    if (typeof Toast !== 'undefined') {
                        Toast.error(t('تعذر إعادة تسمية المحادثة', 'Could not rename the conversation'));
                    }
                    loadConversations();
                }
            } else {
                loadConversations();
            }
        };

        input.addEventListener('blur', commit);
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
            if (e.key === 'Escape') { e.preventDefault(); committed = true; loadConversations(); }
        });
    }

    async function removeConversation(item, id) {
        if (!window.confirm(t('حذف هذه المحادثة نهائياً؟', 'Delete this conversation permanently?'))) return;

        try {
            await API.conversations.remove(id);
            item.remove();
            const list = document.getElementById('conversationsList');
            if (list && !list.children.length) loadConversations();
        } catch (err) {
            console.error('Dashboard: delete failed', err);
            if (typeof Toast !== 'undefined') {
                Toast.error(t('تعذر حذف المحادثة', 'Could not delete the conversation'));
            }
        }
    }

    async function loadConversations() {
        try {
            const res = await API.conversations.list({ limit: 5 });
            renderConversations(res?.data?.conversations || []);
        } catch (err) {
            console.error('Dashboard: failed to load conversations', err);
            renderConversations([]);
        }
    }

    // ================= SAVED PLACES =================

    const PLACE_ICONS = { clinic: 'fa-hospital', pharmacy: 'fa-pills', hospital: 'fa-hospital-user' };

    function renderSavedPlaces(places) {
        const list = document.getElementById('savedPlacesList');
        const empty = document.getElementById('savedPlacesEmpty');
        if (!list || !empty) return;

        if (!places.length) {
            list.innerHTML = '';
            document.getElementById('savedPlacesEmptyTitle').textContent = t('لا توجد أماكن محفوظة بعد', 'No saved places yet');
            document.getElementById('savedPlacesEmptyHint').textContent =
                t('احفظ عيادة أو صيدلية أثناء محادثة لتظهر هنا', 'Save a clinic or pharmacy during a chat to see it here');
            empty.classList.remove('hidden');
            return;
        }

        empty.classList.add('hidden');
        list.innerHTML = places.map((p) => {
            const icon = PLACE_ICONS[p.place_type] || 'fa-map-pin';
            const dist = p.distance_km != null ? Number(p.distance_km).toFixed(1) + ' ' + t('كم', 'km') : '';
            return (
                '<div class="dashboard-list-item dashboard-place-item">' +
                    '<div class="dashboard-place-icon"><i class="fas ' + icon + '"></i></div>' +
                    '<div class="dashboard-list-main">' +
                        '<div class="dashboard-list-title">' + escapeHtml(p.place_name) + '</div>' +
                        '<div class="dashboard-list-meta">' + escapeHtml([p.address, dist].filter(Boolean).join(' · ')) + '</div>' +
                    '</div>' +
                '</div>'
            );
        }).join('');
    }

    async function loadSavedPlaces() {
        try {
            const res = await API.users.savedPlaces();
            renderSavedPlaces(res?.data?.places || []);
        } catch (err) {
            console.error('Dashboard: failed to load saved places', err);
            renderSavedPlaces([]);
        }
    }

    // ================= INIT =================

    async function load() {
        document.getElementById('dashLoading')?.classList.remove('hidden');
        document.getElementById('dashError')?.classList.remove('error');
        document.getElementById('dashContent')?.classList.add('hidden');

        try {
            const res = await API.users.me();
            profile = res.data;

            renderWelcome();
            renderCompleteness();
            document.getElementById('dashContent')?.classList.remove('hidden');

            // Independent, non-blocking — one failing section shouldn't take
            // down the rest of an already-rendered dashboard.
            loadConversations();
            loadSavedPlaces();
        } catch (err) {
            console.error('Dashboard: failed to load profile', err);
            const errBox = document.getElementById('dashError');
            if (errBox) {
                errBox.classList.add('error');
                errBox.textContent = typeof I18n !== 'undefined' ? I18n.t('dashboard.errorLoad') : 'Could not load your dashboard data';
            }
        } finally {
            document.getElementById('dashLoading')?.classList.add('hidden');
        }
    }

    function init() {
        if (!API.requireAuth()) return;

        window.addEventListener('languageChanged', () => {
            if (profile) {
                renderWelcome();
                renderCompleteness();
                loadConversations();
                loadSavedPlaces();
            }
        });

        load();
    }

    return { init };

})();
