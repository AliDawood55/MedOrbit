/**
 * MedOrbit v2 - App Entry Point (index.html / chat app)
 * Wires up:
 *   - Map init
 *   - Chat init
 *   - Header actions (locate, search, lang, theme)
 *   - Filter bar (category filter)
 *   - Map controls
 *   - Quick search bar
 *
 * I18n, Theme, Toast, and Layout are shared modules (src/js/i18n.js,
 * theme.js, toast.js, layout.js) reused across every page, not just this one.
 */
document.addEventListener('DOMContentLoaded', () => {
    // 0. The chat app requires an account (Part 2: index.html moved from
    //    "anonymous chat allowed" to auth-required, same as profile.html/
    //    dashboard.html). requireAuth() redirects to login.html?redirect=...
    //    and returns false before anything below renders — #app stays
    //    visibility:hidden the whole time, so there's no flash of the chat UI.
    if (typeof API !== 'undefined' && !API.requireAuth('index.html')) {
        return;
    }

    // 1. Apply theme + language + shared layout (nav/auth area) — Layout.init()
    //    calls Theme.apply()/I18n.apply() itself, so every page (this one and
    //    the auth pages) only needs this one call.
    if (typeof Layout !== 'undefined' && Layout.init) {
        Layout.init();
    }

    // 2. Initialize map
    if (typeof MapApp !== 'undefined' && MapApp.init) {
        MapApp.init();
    }

    // 2b. Mount the shared location picker (status pill + GPS/manual fallback)
    if (typeof LocationPicker !== 'undefined' && LocationPicker.mount) {
        LocationPicker.mount('locationPicker');
    }

    // 3. Initialize chat
    if (typeof Chat !== 'undefined' && Chat.init) {
        Chat.init();
    }

    // 3b. Initialize conversation sidebar (self-hides for anonymous users)
    if (typeof Sidebar !== 'undefined' && Sidebar.init) {
        Sidebar.init();
    }

    // 3c. Deep-link into a specific conversation (dashboard's "Continue"
    // links use index.html?conversation=<id>) — after Sidebar.init() so its
    // 'chat:conversationChanged' listener is already registered and can
    // highlight the right item in the list immediately.
    const conversationParam = new URLSearchParams(window.location.search).get('conversation');
    if (conversationParam && typeof Chat !== 'undefined' && Chat.loadConversation) {
        Chat.loadConversation(conversationParam);
    }

    // 4. Show app, hide loader
    setTimeout(() => {
        const loader = document.getElementById('appLoader');
        const app = document.getElementById('app');
        if (loader) loader.classList.add('hidden');
        if (app) app.style.visibility = 'visible';
    }, 400);

    // 5. Wire up header actions (langToggle/themeToggle are wired once for
    // every page by Layout.init() itself — see layout.js)
    document.getElementById('locateBtn')?.addEventListener('click', () => {
        if (typeof Location !== 'undefined') Location.locate(true);
    });
    document.getElementById('clearChatBtn')?.addEventListener('click', () => {
        if (typeof Chat !== 'undefined' && Chat.clearChat) Chat.clearChat();
    });
    document.getElementById('locationBtn')?.addEventListener('click', () => {
        if (typeof Location !== 'undefined') {
            Location.locate(true);
            Toast.info(I18n.getLang() === 'ar' ? 'جاري تحديد موقعك...' : 'Locating...');
        }
    });

    // 6. Map controls
    document.getElementById('recenterBtn')?.addEventListener('click', () => {
        if (typeof MapApp !== 'undefined' && MapApp.recenter) MapApp.recenter();
    });
    document.getElementById('fitAllBtn')?.addEventListener('click', () => {
        if (typeof MapApp !== 'undefined' && MapApp.fitToMarkers) MapApp.fitToMarkers();
    });
    // 6b. Mobile chat/map view toggle (FAB, only visible on narrow screens)
    document.getElementById('mobileViewToggle')?.addEventListener('click', function () {
        const main = document.querySelector('.app-main');
        if (!main) return;

        const showingMap = main.classList.toggle('mobile-show-map');
        this.innerHTML = showingMap
            ? '<i class="fas fa-comments"></i>'
            : '<i class="fas fa-map-location-dot"></i>';
        const viewLabel = I18n.t(showingMap ? 'common.showChat' : 'common.showMap');
        this.title = viewLabel;
        this.setAttribute('aria-label', viewLabel);

        // Leaflet can't size a map that was display:none when it initialized —
        // nudge it once its container becomes visible again.
        if (showingMap && typeof MapApp !== 'undefined' && MapApp.invalidateSize) {
            MapApp.invalidateSize();
        }
    });

    // 7. Filter chips
    document.querySelectorAll('.filter-chip').forEach(chip => {
        chip.addEventListener('click', () => {
            document.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
            chip.classList.add('active');
            const cat = chip.dataset.category;
            if (typeof MapApp !== 'undefined' && MapApp.setCategoryFilter) {
                MapApp.setCategoryFilter(cat);
            }
        });
    });

    // 8. Quick search bar
    const quickSearch = document.getElementById('quickSearch');
    if (quickSearch) {
        quickSearch.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                const text = quickSearch.value.trim();
                if (text) {
                    const input = document.getElementById('chatInput');
                    if (input) input.value = text;
                    if (typeof Chat !== 'undefined' && Chat.handleSend) {
                        Chat.handleSend(text);
                    }
                }
            }
        });
    }

    // 9. Do NOT re-init chat on language change — it would wipe the conversation
    //    I18n.apply() already handles DOM text updates via data-i18n attributes

    // 10. Console banner
    console.log('%cMedOrbit v2', 'color:#2563EB;font-size:18px;font-weight:bold;');
    console.log('API:', typeof API !== 'undefined' ? API.getOrigin() + '/api' : '(API module not loaded)');
    console.log('Theme:', Theme.get(), '| Language:', I18n.getLang());
});
