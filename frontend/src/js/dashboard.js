/**
 * MedOrbit v2 - Dashboard (hub)
 * Built only from endpoints that actually exist and actually work:
 * GET /users/me, GET /conversations, GET /appointments, GET /notifications,
 * and GET /doctors/me/schedule for the doctor's own appointment preview.
 * Prescriptions/medical-records have their own dedicated pages — see
 * my-prescriptions.html / my-records.html. Every other page in
 * frontend/public is reachable from here via QUICK_GROUPS below.
 */
const Dashboard = (() => {

    let profile = null;
    let notifications = [];
    const doctorCache = new Map();

    const STATUS_KEY = {
        scheduled: 'appt.statusScheduled',
        confirmed: 'appt.statusConfirmed',
        in_progress: 'appt.statusInProgress',
        completed: 'appt.statusCompleted',
        cancelled: 'appt.statusCancelled',
        no_show: 'appt.statusNoShow'
    };

    const STATUS_BADGE = {
        scheduled: 'badge-info',
        confirmed: 'badge-primary',
        in_progress: 'badge-warning',
        completed: 'badge-success',
        cancelled: 'badge-danger',
        no_show: 'badge-danger'
    };

    // ================= QUICK ACTION GROUPS =================
    // Every page in frontend/public that a logged-in user can meaningfully
    // navigate to from a hub lives here, grouped the way the task asked:
    // Care, AI Tools, My Data, Other. doctor.html/clinic.html are excluded
    // on purpose — they're detail pages reached via an ?id= from
    // find-doctors.html/find-clinics.html, not standalone hub destinations.
    // Auth pages (login/register/forgot-password/reset-password/verify-email)
    // and home.html are pre-login and out of scope for a post-login hub.
    const QUICK_GROUPS = [
        {
            id: 'care',
            icon: 'fa-briefcase-medical',
            titleKey: 'dashboard.groupCare',
            tiles: [
                { id: 'qaBookAppt', href: 'book-appointment.html', icon: 'fa-calendar-plus', titleKey: 'nav.bookAppointment', descKey: 'dashboard.descBookAppt', hideForDoctor: true },
                { href: 'my-appointments.html', icon: 'fa-calendar-check', titleKey: 'nav.myAppointments', descKey: 'dashboard.descMyAppts', hideForDoctor: true },
                { href: 'my-schedule.html', icon: 'fa-calendar-days', titleKey: 'nav.mySchedule', descKey: 'dashboard.descMySchedule', doctorOnly: true },
                { href: 'my-schedule.html#appointments', icon: 'fa-calendar-check', titleKey: 'nav.doctorAppointments', descKey: 'dashboard.descDoctorAppointments', doctorOnly: true },
                { href: 'find-doctors.html', icon: 'fa-user-md', titleKey: 'nav.doctors', descKey: 'dashboard.descFindDoctors' },
                { href: 'doctor-application.html', icon: 'fa-user-doctor', titleKey: 'Apply as Doctor', descKey: 'Doctor application status', patientOnly: true },
                { href: 'find-clinics.html', icon: 'fa-hospital', titleKey: 'nav.clinics', descKey: 'dashboard.descFindClinics' }
            ]
        },
        {
            id: 'aiTools',
            icon: 'fa-wand-magic-sparkles',
            titleKey: 'dashboard.groupAiTools',
            tiles: [
                { href: 'index.html', icon: 'fa-comments', titleKey: 'nav.chat', descKey: 'dashboard.descChat' },
                { href: 'symptom-checker.html', icon: 'fa-stethoscope', titleKey: 'nav.symptomChecker', descKey: 'dashboard.descSymptomChecker' },
                { href: 'drug-checker.html', icon: 'fa-pills', titleKey: 'nav.drugChecker', descKey: 'dashboard.descDrugChecker' },
                { href: 'report-summary.html', icon: 'fa-file-medical', titleKey: 'nav.reportSummary', descKey: 'dashboard.descReportSummary' }
            ]
        },
        {
            id: 'myData',
            icon: 'fa-address-card',
            titleKey: 'dashboard.groupMyData',
            tiles: [
                { href: 'my-records.html', icon: 'fa-file-waveform', titleKey: 'nav.myRecords', descKey: 'dashboard.descMyRecords', patientOnly: true },
                { href: 'my-prescriptions.html', icon: 'fa-prescription-bottle-medical', titleKey: 'nav.myPrescriptions', descKey: 'dashboard.descMyPrescriptions', patientOnly: true },
                { href: 'my-reports.html', icon: 'fa-file-lines', titleKey: 'nav.myReports', descKey: 'dashboard.descMyReports' },
                { href: 'profile.html', icon: 'fa-user-gear', titleKey: 'nav.account', descKey: 'dashboard.descProfile' }
            ]
        },
        {
            id: 'other',
            icon: 'fa-layer-group',
            titleKey: 'dashboard.groupOther',
            tiles: [
                { href: 'feedback.html', icon: 'fa-comment-dots', titleKey: 'nav.feedback', descKey: 'dashboard.descFeedback' },
                { href: 'notifications.html', icon: 'fa-bell', titleKey: 'nav.notifications', descKey: 'dashboard.descNotifications' },
                { id: 'qaAnalytics', href: 'analytics.html', icon: 'fa-chart-line', titleKey: 'nav.analytics', descKey: 'dashboard.descAnalytics', adminOnly: true },
                { href: 'admin-doctor-applications.html', icon: 'fa-user-check', titleKey: 'Doctor Applications', descKey: 'Review pending doctor applications', adminOnly: true },
                { href: 'admin-contact-messages.html', icon: 'fa-envelope-open-text', titleKey: 'Contact Messages', descKey: 'Review support messages', adminOnly: true },
                { href: 'admin-social.html', icon: 'fa-shield-halved', titleKey: 'Social Moderation', descKey: 'Moderate posts and comments', adminOnly: true },
                { href: 'admin-invitations.html', icon: 'fa-user-plus', titleKey: 'Admin Invitations', descKey: 'Invite and manage administrators', superAdminOnly: true },
                { href: 'admin-users.html', icon: 'fa-users-gear', titleKey: 'nav.userManagement', descKey: 'adminUsers.dashDesc', adminOnly: true }
            ]
        }
    ];

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

    function t(ar, en) {
        return isAr() ? ar : en;
    }

    function tk(key) {
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

    function name(d, arKey, enKey) {
        const ar = isAr();
        return ((ar ? d[arKey] : d[enKey]) || d[arKey] || d[enKey] || '').trim();
    }

    function doctorName(d) {
        const full = (name(d, 'first_name_ar', 'first_name_en') + ' ' + name(d, 'last_name_ar', 'last_name_en')).trim();
        return full || d.email || '';
    }

    function truncate(s, n) {
        if (!s) return '';
        return s.length > n ? s.slice(0, n).trim() + '…' : s;
    }

    function pad2(n) {
        return String(n).padStart(2, '0');
    }

    function todayKey() {
        const d = new Date();
        return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    }

    function toDateOnlyStr(v) {
        if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
        // See my-appointments.js for why this rounds instead of truncates:
        // scheduled_date (a DATE column) can round-trip as a UTC instant
        // shifted a few hours off the true calendar day.
        const d = new Date(v);
        d.setUTCHours(d.getUTCHours() + 12);
        return d.toISOString().slice(0, 10);
    }

    function formatDateDisplay(dateOnlyStr) {
        return new Date(dateOnlyStr + 'T00:00:00').toLocaleDateString(isAr() ? 'ar' : 'en-US', {
            month: 'short', day: 'numeric'
        });
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
        const n = isAr()
            ? [profile.first_name_ar, profile.last_name_ar].filter(Boolean).join(' ')
            : [profile.first_name_en, profile.last_name_en].filter(Boolean).join(' ');
        return n || profile.email;
    }

    function renderWelcome() {
        const avatarEl = document.getElementById('dashAvatar');
        if (avatarEl) {
            if (profile.avatar_url) {
                avatarEl.innerHTML = '<img src="' + escapeHtml(API.assetUrl(profile.avatar_url)) + '" alt="">';
            } else {
                avatarEl.textContent = (displayName() || profile.email || '?').trim().charAt(0).toUpperCase() || '?';
            }
        }
        const nameEl = document.getElementById('dashName');
        if (nameEl) nameEl.textContent = displayName();

        const subtitleEl = document.getElementById('dashSubtitle');
        if (subtitleEl) {
            subtitleEl.textContent = profile.role === 'doctor'
                ? t('إليك نظرة سريعة على حسابك المهني', "Here's a quick look at your professional account")
                : tk('dashboard.subtitle');
        }
    }

    function isDoctor() {
        return profile?.role === 'doctor';
    }

    function isAdmin() {
        return ['admin', 'super_admin'].includes(profile?.role);
    }

    // ================= ROLE-AWARE SECTIONS =================

    function applyRoleAwareness() {
        const doctor = isDoctor();

        const statTile = document.getElementById('statApptTile');
        const viewAll = document.getElementById('dashboardAppointmentsLink');
        if (statTile) statTile.href = doctor ? 'my-schedule.html#appointments' : 'my-appointments.html';
        if (viewAll) viewAll.href = doctor ? 'my-schedule.html#appointments' : 'my-appointments.html';
        document.getElementById('dashboardBookAppointment')?.classList.toggle('hidden', doctor);

        // Appointment booking/listing is patient-scoped (doctors have no
        // patients row) — show the explanatory notice instead of an empty
        // list that would otherwise look broken for a doctor account.
        document.getElementById('apptDoctorNotice')?.classList.add('hidden');
        document.getElementById('apptEmpty')?.classList.add('hidden');
        document.getElementById('apptSkeleton')?.classList.remove('hidden');
        document.getElementById('apptList')?.classList.add('hidden');
    }

    // ================= QUICK ACTION GROUPS: RENDER =================

    function tileVisible(tile) {
        if (tile.adminOnly && !isAdmin()) return false;
        if (tile.superAdminOnly && profile?.role !== 'super_admin') return false;
        if (tile.patientOnly && profile?.role !== 'patient') return false;
        if (tile.doctorOnly && !isDoctor()) return false;
        if (tile.hideForDoctor && isDoctor()) return false;
        return true;
    }

    function renderTile(tile) {
        // Text is embedded directly via tk() rather than data-i18n + a
        // follow-up I18n.apply() pass — I18n.apply() dispatches a global
        // 'languageChanged' event, which this same module already listens
        // for; calling it synchronously from inside the initial load()
        // sequence re-entered that listener mid-load and raced the real
        // notifications fetch (a stat count-up would get stuck at 0 whenever
        // that empty-data re-render's animation frame landed after the real
        // one). Direct text embedding sidesteps the whole event entirely.
        return (
            '<a class="quick-tile hover-lift" href="' + tile.href + '"' + (tile.id ? ' id="' + tile.id + '"' : '') + '>' +
                '<div class="quick-tile-icon"><i class="fas ' + tile.icon + '"></i></div>' +
                '<div class="quick-tile-text">' +
                    '<span class="quick-tile-title">' + escapeHtml(tk(tile.titleKey)) + '</span>' +
                    '<span class="quick-tile-desc">' + escapeHtml(tk(tile.descKey)) + '</span>' +
                '</div>' +
            '</a>'
        );
    }

    function renderGroupPanel(group) {
        const tiles = group.tiles.filter(tileVisible);
        if (!tiles.length) return '';

        const state = Store.get('dashboardGroupState', {});
        const expanded = state[group.id] !== false; // default: expanded

        return (
            '<div class="quick-group" data-group-id="' + group.id + '">' +
                '<button type="button" class="quick-group-header" data-group-toggle="' + group.id + '" aria-expanded="' + expanded + '">' +
                    '<span class="quick-group-icon"><i class="fas ' + group.icon + '"></i></span>' +
                    '<span class="quick-group-title">' + escapeHtml(tk(group.titleKey)) + '</span>' +
                    '<i class="fas fa-chevron-down quick-group-chevron' + (expanded ? ' open' : '') + '"></i>' +
                '</button>' +
                '<div class="collapsible' + (expanded ? '' : ' collapsed') + '" id="groupBody-' + group.id + '">' +
                    '<div><div class="quick-tile-grid">' + tiles.map(renderTile).join('') + '</div></div>' +
                '</div>' +
            '</div>'
        );
    }

    function renderQuickGroups() {
        const grid = document.getElementById('quickGroupsGrid');
        grid.innerHTML = QUICK_GROUPS.map(renderGroupPanel).join('');

        grid.querySelectorAll('[data-group-toggle]').forEach((btn) => {
            btn.addEventListener('click', () => toggleGroup(btn.dataset.groupToggle));
        });

        Motion.staggerIn(grid, '.quick-group');
    }

    function toggleGroup(groupId) {
        const body = document.getElementById('groupBody-' + groupId);
        const btn = document.querySelector('[data-group-toggle="' + groupId + '"]');
        const chevron = btn.querySelector('.quick-group-chevron');
        const nowCollapsed = !body.classList.contains('collapsed');

        body.classList.toggle('collapsed', nowCollapsed);
        chevron.classList.toggle('open', !nowCollapsed);
        btn.setAttribute('aria-expanded', String(!nowCollapsed));

        const state = Store.get('dashboardGroupState', {});
        state[groupId] = !nowCollapsed;
        Store.set('dashboardGroupState', state);
    }

    // ================= SEARCH FILTER =================
    // Client-side only — filters the quick-action tiles (and hides an
    // entire group panel if nothing in it matches). While actively
    // searching, matching groups are force-expanded so results are never
    // hidden behind a collapsed section; clearing the search restores each
    // group's saved localStorage preference.

    function initSearchFilter() {
        const input = document.getElementById('dashboardSearch');
        const noResults = document.getElementById('dashboardSearchEmpty');

        input.addEventListener('input', () => {
            const query = input.value.trim().toLowerCase();
            const groups = document.querySelectorAll('.quick-group');
            let anyVisible = false;

            groups.forEach((groupEl) => {
                const tiles = groupEl.querySelectorAll('.quick-tile');
                let groupHasMatch = false;

                tiles.forEach((tile) => {
                    const text = tile.textContent.toLowerCase();
                    const matches = !query || text.includes(query);
                    tile.classList.toggle('hidden', !matches);
                    if (matches) groupHasMatch = true;
                });

                groupEl.classList.toggle('hidden', !groupHasMatch);
                if (groupHasMatch) anyVisible = true;

                const body = groupEl.querySelector('.collapsible');
                if (query) {
                    body.classList.remove('collapsed');
                } else {
                    const state = Store.get('dashboardGroupState', {});
                    const expanded = state[groupEl.dataset.groupId] !== false;
                    body.classList.toggle('collapsed', !expanded);
                }
            });

            noResults.classList.toggle('hidden', !query || anyVisible);
        });
    }

    // ================= PROFILE COMPLETENESS =================

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

    // ================= UPCOMING APPOINTMENTS =================

    function classifyUpcoming(a) {
        if (a.status === 'cancelled' || a.status === 'completed' || a.status === 'no_show') return false;
        return toDateOnlyStr(a.scheduled_date) >= todayKey();
    }

    async function enrichDoctors(appts) {
        const ids = [...new Set(appts.map((a) => a.doctor_id).filter(Boolean))]
            .filter((id) => !doctorCache.has(id));

        await Promise.all(ids.map(async (id) => {
            try {
                const res = await API.doctors.get(id);
                doctorCache.set(id, res.data.doctor);
            } catch {
                doctorCache.set(id, null);
            }
        }));
    }

    function renderApptItem(a) {
        const doctor = doctorCache.get(a.doctor_id);
        const doctorLabel = doctor ? doctorName(doctor) : ('#' + String(a.doctor_id || '').slice(0, 8));
        const patientLabel = (name(a, 'first_name_ar', 'first_name_en') + ' ' + name(a, 'last_name_ar', 'last_name_en')).trim();
        const personLabel = isDoctor() ? (patientLabel || t('مريض', 'Patient')) : doctorLabel;
        const dateOnly = toDateOnlyStr(a.scheduled_date);

        return (
            '<div class="dashboard-list-item dashboard-appt-item">' +
                '<div class="dashboard-appt-icon"><i class="fas ' + (a.appointment_type === 'telemedicine' ? 'fa-comments' : 'fa-hospital') + '"></i></div>' +
                '<div class="dashboard-list-main">' +
                    '<div class="dashboard-list-title">' + escapeHtml(personLabel) + '</div>' +
                    '<div class="dashboard-list-meta">' + escapeHtml(formatDateDisplay(dateOnly) + ' · ' + String(a.start_time || '').slice(0, 5)) + '</div>' +
                '</div>' +
                '<span class="badge ' + (STATUS_BADGE[a.status] || 'badge-info') + '">' + escapeHtml(tk(STATUS_KEY[a.status] || a.status)) + '</span>' +
            '</div>'
        );
    }

    async function loadAppointments() {
        document.getElementById('apptSkeleton')?.classList.remove('hidden');
        document.getElementById('apptList')?.classList.add('hidden');
        document.getElementById('apptEmpty')?.classList.add('hidden');

        try {
            const res = isDoctor() ? await API.doctors.mySchedule() : await API.appointments.list();
            const all = isDoctor() ? (res?.data?.appointments || []) : (res?.data || []);
            const upcoming = all.filter(classifyUpcoming).sort((a, b) => {
                const da = toDateOnlyStr(a.scheduled_date) + (a.start_time || '');
                const db = toDateOnlyStr(b.scheduled_date) + (b.start_time || '');
                return da < db ? -1 : da > db ? 1 : 0;
            });

            Motion.countUp(document.getElementById('statApptCount'), upcoming.length);

            const preview = upcoming.slice(0, 4);
            if (!isDoctor()) await enrichDoctors(preview);

            document.getElementById('apptSkeleton')?.classList.add('hidden');

            const list = document.getElementById('apptList');
            const empty = document.getElementById('apptEmpty');

            if (!preview.length) {
                list.classList.add('hidden');
                list.innerHTML = '';
                empty.classList.remove('hidden');
                return;
            }

            empty.classList.add('hidden');
            list.classList.remove('hidden');
            list.innerHTML = preview.map(renderApptItem).join('');
            Motion.staggerIn(list, '.dashboard-appt-item');
        } catch (err) {
            console.error('Dashboard: failed to load appointments', err);
            document.getElementById('apptSkeleton')?.classList.add('hidden');
            document.getElementById('apptList')?.classList.add('hidden');
            document.getElementById('apptEmpty')?.classList.remove('hidden');
        }
    }

    // ================= NOTIFICATIONS =================

    function renderNotifItem(n) {
        const title = isAr() ? (n.title_ar || n.title_en) : (n.title_en || n.title_ar);
        const message = isAr() ? (n.message_ar || n.message_en) : (n.message_en || n.message_ar);
        const unread = !n.is_read;

        return (
            '<div class="dashboard-list-item dashboard-notif-item' + (unread ? ' unread' : '') + '">' +
                '<span class="' + (unread ? 'notif-dot' : 'notif-dot-spacer') + '"></span>' +
                '<div class="dashboard-list-main">' +
                    '<div class="dashboard-list-title">' + escapeHtml(title || '') + '</div>' +
                    (message ? '<div class="dashboard-list-meta">' + escapeHtml(truncate(message, 80)) + '</div>' : '') +
                    '<div class="dashboard-list-meta notif-time">' + escapeHtml(formatRelativeTime(n.created_at)) + '</div>' +
                '</div>' +
            '</div>'
        );
    }

    function renderNotifications() {
        const list = document.getElementById('notifList');
        const moreList = document.getElementById('notifMoreList');
        const moreWrap = document.getElementById('notifMoreWrap');
        const showMoreBtn = document.getElementById('notifShowMoreBtn');
        const empty = document.getElementById('notifEmpty');
        const markAllBtn = document.getElementById('markAllReadBtn');

        const unreadCount = notifications.filter((n) => !n.is_read).length;
        Motion.countUp(document.getElementById('statNotifCount'), unreadCount);
        markAllBtn.classList.toggle('hidden', unreadCount === 0);

        if (!notifications.length) {
            list.classList.add('hidden');
            list.innerHTML = '';
            moreList.innerHTML = '';
            showMoreBtn.classList.add('hidden');
            empty.classList.remove('hidden');
            return;
        }

        empty.classList.add('hidden');
        list.classList.remove('hidden');

        const first = notifications.slice(0, 5);
        const rest = notifications.slice(5, 15);

        list.innerHTML = first.map(renderNotifItem).join('');
        Motion.staggerIn(list, '.dashboard-notif-item');

        if (rest.length) {
            moreList.innerHTML = rest.map(renderNotifItem).join('');
            showMoreBtn.classList.remove('hidden');
            showMoreBtn.dataset.expanded = 'false';
            const label = showMoreBtn.querySelector('[data-i18n]');
            if (label) label.setAttribute('data-i18n', 'dashboard.showMore');
            if (label) label.textContent = tk('dashboard.showMore');
            moreWrap.classList.add('collapsed');
        } else {
            showMoreBtn.classList.add('hidden');
            moreList.innerHTML = '';
        }
    }

    async function loadNotifications() {
        document.getElementById('notifSkeletonDash')?.classList.remove('hidden');
        document.getElementById('notifList')?.classList.add('hidden');

        try {
            const res = await API.notifications.list();
            notifications = res?.data || [];
            document.getElementById('notifSkeletonDash')?.classList.add('hidden');
            renderNotifications();
        } catch (err) {
            console.error('Dashboard: failed to load notifications', err);
            notifications = [];
            document.getElementById('notifSkeletonDash')?.classList.add('hidden');
            renderNotifications();
        }
    }

    async function markAllRead() {
        const btn = document.getElementById('markAllReadBtn');
        btn.disabled = true;
        try {
            await API.notifications.markAllRead();
            notifications = notifications.map((n) => ({ ...n, is_read: true }));
            renderNotifications();
            window.dispatchEvent(new CustomEvent('notifications:changed'));
        } catch (err) {
            console.error('Dashboard: failed to mark all notifications read', err);
            if (typeof Toast !== 'undefined') {
                Toast.error(t('تعذر تحديث الإشعارات', 'Could not update notifications'));
            }
        } finally {
            btn.disabled = false;
        }
    }

    function toggleShowMoreNotifications() {
        const btn = document.getElementById('notifShowMoreBtn');
        const wrap = document.getElementById('notifMoreWrap');
        const expanded = btn.dataset.expanded === 'true';

        wrap.classList.toggle('collapsed', expanded);
        btn.dataset.expanded = expanded ? 'false' : 'true';

        const label = btn.querySelector('[data-i18n]');
        const icon = btn.querySelector('i');
        if (label) {
            label.setAttribute('data-i18n', expanded ? 'dashboard.showMore' : 'dashboard.showLess');
            label.textContent = tk(expanded ? 'dashboard.showMore' : 'dashboard.showLess');
        }
        if (icon) icon.classList.toggle('fa-chevron-up', !expanded);
        if (icon) icon.classList.toggle('fa-chevron-down', expanded);

        if (!expanded) Motion.staggerIn(document.getElementById('notifMoreList'), '.dashboard-notif-item');
    }

    // ================= RECENT CONVERSATIONS =================

    function renderConversations(conversations) {
        const list = document.getElementById('conversationsList');
        const empty = document.getElementById('conversationsEmpty');
        if (!list || !empty) return;

        if (!conversations.length) {
            list.classList.add('hidden');
            list.innerHTML = '';
            document.getElementById('conversationsEmptyTitle').textContent = t('لا توجد محادثات بعد', 'No conversations yet');
            document.getElementById('conversationsEmptyHint').textContent =
                t('ابدأ محادثة جديدة مع مساعدنا الذكي', 'Start a new conversation with our AI assistant');
            empty.classList.remove('hidden');
            return;
        }

        empty.classList.add('hidden');
        list.classList.remove('hidden');
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

        Motion.staggerIn(list, '.dashboard-list-item');
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
        document.getElementById('convoSkeleton')?.classList.remove('hidden');
        document.getElementById('conversationsList')?.classList.add('hidden');

        try {
            const res = await API.conversations.list({ limit: 5 });
            document.getElementById('convoSkeleton')?.classList.add('hidden');
            renderConversations(res?.data?.conversations || []);
            Motion.countUp(document.getElementById('statConvoCount'), res?.data?.pagination?.total ?? (res?.data?.conversations || []).length);
        } catch (err) {
            console.error('Dashboard: failed to load conversations', err);
            document.getElementById('convoSkeleton')?.classList.add('hidden');
            renderConversations([]);
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
            applyRoleAwareness();
            renderQuickGroups();
            document.getElementById('dashContent')?.classList.remove('hidden');

            // Independent, non-blocking — one failing section shouldn't take
            // down the rest of an already-rendered dashboard.
            loadAppointments();
            loadNotifications();
            loadConversations();
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

        document.getElementById('markAllReadBtn')?.addEventListener('click', markAllRead);
        document.getElementById('notifShowMoreBtn')?.addEventListener('click', toggleShowMoreNotifications);
        initSearchFilter();

        window.addEventListener('languageChanged', () => {
            if (profile) {
                renderWelcome();
                renderCompleteness();
                renderQuickGroups();
                renderNotifications();
                loadAppointments();
                loadConversations();
            }
        });

        load();
    }

    return { init };

})();
