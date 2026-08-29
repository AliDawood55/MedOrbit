document.addEventListener('DOMContentLoaded', () => {

if (typeof API !== 'undefined' && !API.requireAuth('index.html')) {
        return;
    }

if (typeof Layout !== 'undefined' && Layout.init) {
        Layout.init();
    }

if (typeof MapApp !== 'undefined' && MapApp.init) {
        MapApp.init();
    }

if (typeof LocationPicker !== 'undefined' && LocationPicker.mount) {
        LocationPicker.mount('locationPicker');
    }

if (typeof Chat !== 'undefined' && Chat.init) {
        Chat.init();
    }

if (typeof Sidebar !== 'undefined' && Sidebar.init) {
        Sidebar.init();
    }

const conversationParam = new URLSearchParams(window.location.search).get('conversation');
    if (conversationParam && typeof Chat !== 'undefined' && Chat.loadConversation) {
        Chat.loadConversation(conversationParam);
    }

setTimeout(() => {
        const loader = document.getElementById('appLoader');
        const app = document.getElementById('app');
        if (loader) loader.classList.add('hidden');
        if (app) app.style.visibility = 'visible';
    }, 400);

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

document.getElementById('recenterBtn')?.addEventListener('click', () => {
        if (typeof MapApp !== 'undefined' && MapApp.recenter) MapApp.recenter();
    });
    document.getElementById('fitAllBtn')?.addEventListener('click', () => {
        if (typeof MapApp !== 'undefined' && MapApp.fitToMarkers) MapApp.fitToMarkers();
    });

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

if (showingMap && typeof MapApp !== 'undefined' && MapApp.invalidateSize) {
            MapApp.invalidateSize();
        }
    });

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

console.log('%cMedOrbit v2', 'color:#2563EB;font-size:18px;font-weight:bold;');
    console.log('API:', typeof API !== 'undefined' ? API.getOrigin() + '/api' : '(API module not loaded)');
    console.log('Theme:', Theme.get(), '| Language:', I18n.getLang());
});
