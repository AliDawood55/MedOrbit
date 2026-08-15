/**
 * MedOrbit v2 - Shared Layout Module
 * Renders site navigation, the auth-aware header area, and the footer
 * into placeholder elements so every page shares the same header/nav/footer
 * without a build step (plain HTML placeholders + JS injection).
 *
 * Pages opt in by including empty containers with these IDs:
 *   #navLinks    - site navigation links
 *   #authArea    - login/register buttons OR the logged-in user menu
 *   #siteFooter  - full footer (brand, nav, copyright)
 * Any container that isn't present on a page is simply skipped.
 */
const Layout = (() => {

    const PAGES = [
        { href: 'home.html', key: 'nav.home', match: ['home.html', ''] },
        { href: 'feed.html', key: 'nav.feed', match: ['feed.html'] },
        { href: 'index.html', key: 'nav.chat', match: ['index.html'] },
        { href: 'find-doctors.html', key: 'nav.doctors', match: ['find-doctors.html', 'doctor.html'] },
        { href: 'find-clinics.html', key: 'nav.clinics', match: ['find-clinics.html', 'clinic.html'] },
        { href: 'contact.html', key: 'nav.contactUs', match: ['contact.html'] },
        {
            key: 'nav.aiTools',
            match: ['symptom-checker.html', 'drug-checker.html', 'report-summary.html', 'avatar-preview.html'],
            children: [
                { href: 'symptom-checker.html', key: 'nav.symptomChecker' },
                { href: 'drug-checker.html', key: 'nav.drugChecker' },
                { href: 'report-summary.html', key: 'nav.reportSummary' },
                { href: 'avatar-preview.html', key: 'nav.voiceConsult' }
            ]
        }
    ];

    const NOTIFICATION_POLL_MS = 60_000;
    const NOTIFICATION_FOCUS_MIN_MS = 15_000;
    let initialized = false;
    let notificationTimer = null;
    let notificationRequest = null;
    let lastNotificationRefreshAt = 0;
    let lastUnreadCount = 0;

    function currentPage() {
        const parts = window.location.pathname.split('/');
        return parts[parts.length - 1] || 'home.html';
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function initials(user) {
        const name = (user && (user.name || user.email)) || '';
        return name.trim().charAt(0).toUpperCase() || '?';
    }

    // ================= NAV =================

    function renderLink(p, page) {
        const active = (p.match ? p.match.includes(page) : page === p.href) ? ' active' : '';
        return `<a href="${p.href}" class="nav-link${active}" data-i18n="${p.key}"></a>`;
    }

    /**
     * @param {boolean} [options.flat] - render grouped items (e.g. AI Tools)
     * as plain sibling links instead of a dropdown — used for the footer,
     * where a click-to-open dropdown would be unusual UX.
     */
    function renderNav(containerId = 'navLinks', options = {}) {
        const el = document.getElementById(containerId);
        if (!el) return;

        const page = currentPage();
        const flat = !!options.flat;

        el.innerHTML = PAGES.map(p => {
            if (!p.children) return renderLink(p, page);

            if (flat) {
                return p.children.map(c => renderLink(c, page)).join('');
            }

            const groupActive = p.match.includes(page);
            const items = p.children.map(c =>
                `<a href="${c.href}" class="nav-dropdown-item${page === c.href ? ' active' : ''}" data-i18n="${c.key}"></a>`
            ).join('');

            return (
                `<div class="nav-dropdown${groupActive ? ' active' : ''}">` +
                    `<span class="nav-link nav-dropdown-toggle" data-i18n="${p.key}"></span>` +
                    `<i class="fas fa-chevron-down"></i>` +
                    `<div class="nav-dropdown-menu">${items}</div>` +
                `</div>`
            );
        }).join('');

        if (!flat) {
            el.querySelectorAll('.nav-dropdown').forEach(dropdown => {
                dropdown.addEventListener('click', (e) => {
                    // Let clicks on the actual menu items (<a> hrefs) navigate normally.
                    if (e.target.closest('.nav-dropdown-item')) return;
                    e.stopPropagation();
                    const wasOpen = dropdown.classList.contains('open');
                    el.querySelectorAll('.nav-dropdown.open').forEach(d => d.classList.remove('open'));
                    if (!wasOpen) dropdown.classList.add('open');
                });
            });
        }

        if (typeof I18n !== 'undefined') I18n.apply();
    }

    // ================= AUTH AREA =================

    function renderAuthArea(containerId = 'authArea') {
        const el = document.getElementById(containerId);
        if (!el) return;

        const loggedIn = typeof API !== 'undefined' && API.isAuthenticated();

        if (!loggedIn) {
            el.innerHTML =
                '<a href="login.html" class="btn btn-secondary btn-sm" data-i18n="auth.login"></a>' +
                '<a href="register.html" class="btn btn-primary btn-sm" data-i18n="auth.register"></a>';
            if (typeof I18n !== 'undefined') I18n.apply();
            return;
        }

        const user = API.getUser();
        const isAdmin = ['admin', 'super_admin'].includes(user?.role);
        const isSuperAdmin = user?.role === 'super_admin';
        const isDoctor = user?.role === 'doctor';
        const isPatient = user?.role === 'patient';

        el.innerHTML =
            '<a href="notifications.html" class="icon-btn notification-bell" id="notificationBell" title="Notifications / الإشعارات" aria-label="Notifications">' +
                '<i class="fas fa-bell" aria-hidden="true"></i>' +
                '<span class="notification-badge hidden" id="notificationBadge" aria-hidden="true"></span>' +
            '</a>' +
            '<div class="user-chip" id="userChip">' +
                '<span class="user-avatar">' + escapeHtml(initials(user)) + '</span>' +
                '<span class="user-name">' + escapeHtml((user && (user.name || user.email)) || '') + '</span>' +
                '<i class="fas fa-chevron-down"></i>' +
                '<div class="user-menu" id="userMenu">' +
                    '<a href="dashboard.html" class="user-menu-item" data-i18n="nav.dashboard"></a>' +
                    (isPatient ? '<a href="find-doctors.html" class="user-menu-item" data-i18n="nav.doctors"></a>' : '') +
                    (isPatient ? '<a href="feed.html" class="user-menu-item" data-i18n="nav.feed"></a>' : '') +
                    ((isPatient || isDoctor) ? '<a href="direct-messages.html" class="user-menu-item" data-i18n="nav.messages"></a>' : '') +
                    (isPatient ? '<a href="my-appointments.html" class="user-menu-item" data-i18n="nav.myAppointments"></a>' : '') +
                    (isDoctor ? '<a href="my-schedule.html" class="user-menu-item" data-i18n="nav.mySchedule"></a>' : '') +
                    (isDoctor ? '<a href="my-schedule.html#appointments" class="user-menu-item" data-i18n="nav.doctorAppointments"></a>' : '') +
                    (isPatient ? '<a href="patient-profile.html" class="user-menu-item" data-i18n="nav.patientProfile"></a>' : '') +
                    (isPatient ? '<a href="my-records.html" class="user-menu-item" data-i18n="nav.myRecords"></a>' : '') +
                    (isPatient ? '<a href="my-prescriptions.html" class="user-menu-item" data-i18n="nav.myPrescriptions"></a>' : '') +
                    (isDoctor ? '<a href="doctor-profile-edit.html" class="user-menu-item" data-i18n="nav.professionalProfile"></a>' : '') +
                    (isDoctor ? '<a href="doctor-posts.html" class="user-menu-item" data-i18n="nav.doctorPosts"></a>' : '') +
                    (isDoctor ? '<a href="my-patients.html" class="user-menu-item" data-i18n="nav.myPatients"></a>' : '') +
                    (isAdmin ? '<a href="admin-doctor-applications.html" class="user-menu-item" data-i18n="nav.doctorApplications"></a>' : '') +
                    (isAdmin ? '<a href="admin-contact-messages.html" class="user-menu-item" data-i18n="nav.contactMessages"></a>' : '') +
                    (isAdmin ? '<a href="admin-social.html" class="user-menu-item" data-i18n="nav.socialModeration"></a>' : '') +
                    (isSuperAdmin ? '<a href="admin-invitations.html" class="user-menu-item">Admin Invitations</a>' : '') +
                    (isAdmin ? '<a href="analytics.html" class="user-menu-item" data-i18n="nav.analytics"></a>' : '') +
                    '<a href="notifications.html" class="user-menu-item" data-i18n="nav.notifications"></a>' +
                    (!isAdmin ? '<a href="contact.html" class="user-menu-item" data-i18n="nav.contactUs"></a>' : '') +
                    '<a href="profile.html" class="user-menu-item" data-i18n="nav.account"></a>' +
                    // Unconditional, and deliberately so: a subscription
                    // belongs to a user, not to a role. A patient, doctor,
                    // admin and super_admin all subscribe on identical terms.
                    '<a href="billing.html" class="user-menu-item" data-i18n="nav.billing"></a>' +
                    '<button type="button" class="user-menu-item" id="logoutBtn" data-i18n="auth.logout"></button>' +
                '</div>' +
            '</div>';

        const chip = document.getElementById('userChip');
        if (chip) {
            chip.addEventListener('click', (e) => {
                e.stopPropagation();
                chip.classList.toggle('open');
            });
        }

        document.getElementById('logoutBtn')?.addEventListener('click', async (e) => {
            e.stopPropagation();
            await API.logout();
            window.location.href = 'home.html';
        });

        if (typeof I18n !== 'undefined') I18n.apply();
    }

    // ================= MOBILE DRAWER =================
    // Injected entirely via JS (no per-page HTML needed) — every page with
    // an .app-header automatically gets a hamburger trigger + slide-in
    // drawer containing the nav, AI Tools group, and the user/auth menu.
    // Shown only ≤1024px via CSS; this is the ONLY nav+auth surface at
    // that width (the desktop nav/auth area is hidden by the same query).

    function renderDrawerNavItems() {
        const page = currentPage();
        return PAGES.map(p => {
            if (!p.children) {
                const active = (p.match ? p.match.includes(page) : page === p.href) ? ' active' : '';
                return `<a href="${p.href}" class="drawer-link${active}" data-i18n="${p.key}"></a>`;
            }

            const items = p.children.map(c =>
                `<a href="${c.href}" class="drawer-link drawer-sublink${page === c.href ? ' active' : ''}" data-i18n="${c.key}"></a>`
            ).join('');

            return (
                `<div class="drawer-group-label" data-i18n="${p.key}"></div>` +
                items
            );
        }).join('');
    }

    function renderDrawerAuth() {
        const loggedIn = typeof API !== 'undefined' && API.isAuthenticated();

        if (!loggedIn) {
            return (
                '<a href="login.html" class="btn btn-secondary drawer-auth-btn" data-i18n="auth.login"></a>' +
                '<a href="register.html" class="btn btn-primary drawer-auth-btn" data-i18n="auth.register"></a>'
            );
        }

        const user = API.getUser();
        const isAdmin = ['admin', 'super_admin'].includes(user?.role);
        const isSuperAdmin = user?.role === 'super_admin';
        const isDoctor = user?.role === 'doctor';
        const isPatient = user?.role === 'patient';
        return (
            '<div class="drawer-user">' +
                '<span class="user-avatar">' + escapeHtml(initials(user)) + '</span>' +
                '<span class="user-name">' + escapeHtml((user && (user.name || user.email)) || '') + '</span>' +
            '</div>' +
            '<a href="dashboard.html" class="drawer-link" data-i18n="nav.dashboard"></a>' +
            (isPatient ? '<a href="find-doctors.html" class="drawer-link" data-i18n="nav.doctors"></a>' : '') +
            (isPatient ? '<a href="feed.html" class="drawer-link" data-i18n="nav.feed"></a>' : '') +
            ((isPatient || isDoctor) ? '<a href="direct-messages.html" class="drawer-link" data-i18n="nav.messages"></a>' : '') +
            (isPatient ? '<a href="my-appointments.html" class="drawer-link" data-i18n="nav.myAppointments"></a>' : '') +
            (isDoctor ? '<a href="my-schedule.html" class="drawer-link" data-i18n="nav.mySchedule"></a>' : '') +
            (isDoctor ? '<a href="my-schedule.html#appointments" class="drawer-link" data-i18n="nav.doctorAppointments"></a>' : '') +
            (isPatient ? '<a href="patient-profile.html" class="drawer-link" data-i18n="nav.patientProfile"></a>' : '') +
            (isPatient ? '<a href="my-records.html" class="drawer-link" data-i18n="nav.myRecords"></a>' : '') +
            (isPatient ? '<a href="my-prescriptions.html" class="drawer-link" data-i18n="nav.myPrescriptions"></a>' : '') +
            (isDoctor ? '<a href="doctor-profile-edit.html" class="drawer-link" data-i18n="nav.professionalProfile"></a>' : '') +
            (isDoctor ? '<a href="doctor-posts.html" class="drawer-link" data-i18n="nav.doctorPosts"></a>' : '') +
            (isDoctor ? '<a href="my-patients.html" class="drawer-link" data-i18n="nav.myPatients"></a>' : '') +
            (isAdmin ? '<a href="admin-doctor-applications.html" class="drawer-link" data-i18n="nav.doctorApplications"></a>' : '') +
            (isAdmin ? '<a href="admin-contact-messages.html" class="drawer-link" data-i18n="nav.contactMessages"></a>' : '') +
            (isAdmin ? '<a href="admin-social.html" class="drawer-link" data-i18n="nav.socialModeration"></a>' : '') +
            (isSuperAdmin ? '<a href="admin-invitations.html" class="drawer-link">Admin Invitations</a>' : '') +
            (isAdmin ? '<a href="analytics.html" class="drawer-link" data-i18n="nav.analytics"></a>' : '') +
            '<a href="notifications.html" class="drawer-link drawer-notification-link"><i class="fas fa-bell" aria-hidden="true"></i><span data-i18n="nav.notifications"></span><span class="notification-badge hidden" id="drawerNotificationBadge" aria-hidden="true"></span></a>' +
            (!isAdmin ? '<a href="contact.html" class="drawer-link" data-i18n="nav.contactUs"></a>' : '') +
            '<a href="profile.html" class="drawer-link" data-i18n="nav.account"></a>' +
            '<button type="button" class="drawer-link" id="drawerLogoutBtn" data-i18n="auth.logout"></button>'
        );
    }

    function renderDrawer() {
        const header = document.querySelector('.app-header');
        if (!header || document.getElementById('mobileDrawer')) return;

        const actions = header.querySelector('.header-actions') || header;
        const hamburger = document.createElement('button');
        hamburger.type = 'button';
        hamburger.id = 'hamburgerBtn';
        hamburger.className = 'hamburger-btn';
        hamburger.setAttribute('aria-label', 'Menu');
        hamburger.innerHTML = '<i class="fas fa-bars"></i>';
        actions.insertBefore(hamburger, actions.firstChild);

        const backdrop = document.createElement('div');
        backdrop.className = 'mobile-drawer-backdrop';
        backdrop.id = 'mobileDrawerBackdrop';

        const drawer = document.createElement('div');
        drawer.className = 'mobile-drawer';
        drawer.id = 'mobileDrawer';
        drawer.innerHTML =
            '<div class="mobile-drawer-header">' +
                '<div class="header-brand">' +
                    '<div class="brand-icon"><i class="fas fa-heartbeat"></i></div>' +
                    '<div class="brand-text"><h1>MedOrbit</h1></div>' +
                '</div>' +
                '<button type="button" class="icon-btn" id="mobileDrawerClose" aria-label="Close"><i class="fas fa-times"></i></button>' +
            '</div>' +
            '<nav class="mobile-drawer-nav">' + renderDrawerNavItems() + '</nav>' +
            '<div class="mobile-drawer-auth">' + renderDrawerAuth() + '</div>';

        document.body.appendChild(backdrop);
        document.body.appendChild(drawer);

        function open() {
            drawer.classList.add('open');
            backdrop.classList.add('open');
            if (typeof Dom !== 'undefined') Dom.lockScroll();
        }
        function close() {
            const wasOpen = drawer.classList.contains('open');
            drawer.classList.remove('open');
            backdrop.classList.remove('open');
            if (wasOpen && typeof Dom !== 'undefined') Dom.unlockScroll();
        }

        hamburger.addEventListener('click', open);
        backdrop.addEventListener('click', close);
        document.getElementById('mobileDrawerClose')?.addEventListener('click', close);
        drawer.querySelectorAll('a').forEach(a => a.addEventListener('click', close));
        document.getElementById('drawerLogoutBtn')?.addEventListener('click', async () => {
            close();
            await API.logout();
            window.location.href = 'home.html';
        });

        window.addEventListener('auth:changed', () => {
            drawer.querySelector('.mobile-drawer-auth').innerHTML = renderDrawerAuth();
            updateNotificationBadge(lastUnreadCount);
            const btn = document.getElementById('drawerLogoutBtn');
            btn?.addEventListener('click', async () => {
                close();
                await API.logout();
                window.location.href = 'home.html';
            });
            if (typeof I18n !== 'undefined') I18n.apply();
        });

        if (typeof I18n !== 'undefined') I18n.apply();
    }

    // ================= FOOTER =================

    function renderFooter(containerId = 'siteFooter') {
        const el = document.getElementById(containerId);
        if (!el) return;

        const year = new Date().getFullYear();

        el.innerHTML =
            '<div class="footer-content">' +
                '<div class="footer-brand">' +
                    '<div class="brand-icon"><i class="fas fa-heartbeat"></i></div>' +
                    '<div>' +
                        '<h3>MedOrbit</h3>' +
                        '<p data-i18n="footer.tagline"></p>' +
                    '</div>' +
                '</div>' +
                '<nav class="footer-links" id="footerLinks"></nav>' +
                '<p class="footer-copy">&copy; ' + year + ' MedOrbit — <span data-i18n="footer.rights"></span></p>' +
            '</div>';

        renderNav('footerLinks', { flat: true });
    }

    // ================= INIT =================

    function updateNotificationBadge(value) {
        const count = Math.max(0, Number(value) || 0);
        lastUnreadCount = count;
        const label = count > 9 ? '9+' : String(count);

        ['notificationBadge', 'drawerNotificationBadge'].forEach((id) => {
            const badge = document.getElementById(id);
            if (!badge) return;
            badge.textContent = count ? label : '';
            badge.classList.toggle('hidden', count === 0);
            badge.setAttribute('aria-hidden', count === 0 ? 'true' : 'false');
        });

        const bell = document.getElementById('notificationBell');
        if (bell) {
            bell.setAttribute('aria-label', count
                ? `Notifications (${count} unread)`
                : 'Notifications');
        }
    }

    function stopNotificationPolling() {
        if (notificationTimer) window.clearTimeout(notificationTimer);
        notificationTimer = null;
    }

    function scheduleNotificationRefresh(delay = NOTIFICATION_POLL_MS) {
        stopNotificationPolling();
        if (typeof API === 'undefined' || !API.isAuthenticated()) return;
        notificationTimer = window.setTimeout(() => refreshNotificationBadge(), delay);
    }

    async function refreshNotificationBadge({ force = false } = {}) {
        if (typeof API === 'undefined' || !API.isAuthenticated()) {
            stopNotificationPolling();
            updateNotificationBadge(0);
            return;
        }
        if (notificationRequest) return notificationRequest;

        const elapsed = Date.now() - lastNotificationRefreshAt;
        if (!force && lastNotificationRefreshAt && elapsed < NOTIFICATION_FOCUS_MIN_MS) {
            scheduleNotificationRefresh(Math.max(NOTIFICATION_FOCUS_MIN_MS - elapsed, 1_000));
            return;
        }

        notificationRequest = (async () => {
            let nextDelay = NOTIFICATION_POLL_MS;
            try {
                const response = await API.notifications.unreadCount();
                updateNotificationBadge(response?.data?.count || 0);
            } catch (err) {
                if (err.status === 429 && err.retryAfterSeconds) {
                    nextDelay = Math.max(nextDelay, err.retryAfterSeconds * 1000);
                }
            } finally {
                lastNotificationRefreshAt = Date.now();
                notificationRequest = null;
                scheduleNotificationRefresh(nextDelay);
            }
        })();

        return notificationRequest;
    }

    /**
     * Floating "back to top" button — document pages only (app-shell pages
     * scroll internally, not at the document level, so it has nothing to
     * do there). Appears after scrolling past one viewport height.
     */
    function renderBackToTop() {
        if (!document.body.classList.contains('site-page')) return;

        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'back-to-top';
        btn.setAttribute('aria-label', 'Back to top');
        btn.innerHTML = '<i class="fas fa-arrow-up"></i>';
        document.body.appendChild(btn);

        const toggle = () => {
            btn.classList.toggle('visible', window.scrollY > window.innerHeight * 0.6);
        };
        window.addEventListener('scroll', toggle, { passive: true });
        toggle();

        btn.addEventListener('click', () => {
            window.scrollTo({ top: 0, behavior: 'smooth' });
        });
    }

    function init() {
        if (initialized) return;
        initialized = true;

        if (typeof Theme !== 'undefined') Theme.apply();
        if (typeof I18n !== 'undefined') I18n.apply();

        renderNav('navLinks');
        renderAuthArea('authArea');
        renderFooter('siteFooter');
        renderDrawer();
        renderBackToTop();
        updateNotificationBadge(lastUnreadCount);
        refreshNotificationBadge({ force: true });

        // Header theme/language toggles — every page (not just index.html,
        // which used to be the only one wiring these up in app.js).
        document.getElementById('langToggle')?.addEventListener('click', () => {
            if (typeof I18n !== 'undefined') I18n.toggle();
        });
        document.getElementById('themeToggle')?.addEventListener('click', () => {
            if (typeof Theme !== 'undefined') Theme.toggle();
        });

        // Note: language switching does NOT need a re-render here — every
        // element above carries data-i18n, so I18n.apply()'s own global
        // pass re-translates them on every toggle. Re-rendering (and thus
        // calling I18n.apply() again) on a 'languageChanged' event it
        // itself triggers would recurse forever.
        window.addEventListener('auth:changed', () => {
            renderAuthArea('authArea');
            if (API.isAuthenticated()) {
                refreshNotificationBadge({ force: true });
            } else {
                lastNotificationRefreshAt = 0;
                updateNotificationBadge(0);
                stopNotificationPolling();
            }
        });

        window.addEventListener('notifications:changed', () => {
            refreshNotificationBadge({ force: true });
        });

        window.addEventListener('focus', () => {
            refreshNotificationBadge();
        });

        window.addEventListener('beforeunload', stopNotificationPolling);

        // Single global listener (not re-registered per renderNav call, since
        // renderNav also runs for the footer) to close any open nav dropdown.
        document.addEventListener('click', () => {
            document.getElementById('userChip')?.classList.remove('open');
            document.querySelectorAll('.nav-dropdown.open').forEach(d => d.classList.remove('open'));
        });
    }

    /**
     * Shows a "log in to save your history" banner on pages that stay public
     * but offer more value to a logged-in user (the AI tools). No-op for
     * already-authenticated visitors — the container stays hidden.
     */
    function renderAuthPromptBanner(containerId) {
        if (typeof API === 'undefined' || API.isAuthenticated()) return;

        const banner = document.getElementById(containerId);
        if (!banner) return;

        banner.classList.remove('hidden');
        const link = banner.querySelector('a');
        if (link) {
            const page = window.location.pathname.split('/').pop();
            link.href = 'login.html?redirect=' + encodeURIComponent(page);
        }
    }

    return { init, renderNav, renderAuthArea, renderFooter, renderAuthPromptBanner };
})();
