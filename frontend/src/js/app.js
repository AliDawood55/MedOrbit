/**
 * MedOrbit v2 - App Entry Point
 * Wires up:
 *   - i18n (AR/EN)
 *   - Theme (light/dark)
 *   - Map init
 *   - Chat init
 *   - Header actions (locate, search, lang, theme)
 *   - Filter bar (category filter)
 *   - Map controls
 *   - Quick search bar
 */

const I18n = (() => {
    const dict = {
        ar: {
            'brand.tagline': 'منصة طبية ذكية',
            'search.placeholder': 'ابحث عن عيادة، صيدلية، تخصص...',
            'filter.all': 'الكل',
            'filter.clinic': 'العيادات',
            'filter.pharmacy': 'الصيدليات',
            'filter.hospital': 'المستشفيات',
            'filter.doctor': 'الأطباء',
            'meta.results': 'النتائج',
            'chat.title': 'مساعد MedOrbit',
            'chat.subtitle': 'متصل الآن',
            'chat.placeholder': 'اسأل عن أقرب عيادة، صيدلية، أو طبيب...',
            'send': 'إرسال',
            'locate': 'موقعي',
            'theme': 'الوضع',
            'language': 'English',
            'newChat': 'محادثة جديدة',
            'shareLocation': 'مشاركة موقعي',
            'map.statusDefault': 'حدد موقعك أو اسأل عن أقرب عيادة',
            'map.emptyTitle': 'لا توجد نتائج بعد',
            'map.emptyDesc': 'اسأل المساعد عن أقرب عيادة أو صيدلية وستظهر النتائج هنا',
            'recenter': 'إعادة التمركز',
            'layers': 'تغيير الخريطة',
            'fitAll': 'عرض الكل'
        },
        en: {
            'brand.tagline': 'Smart Healthcare AI',
            'search.placeholder': 'Search clinic, pharmacy, specialty...',
            'filter.all': 'All',
            'filter.clinic': 'Clinics',
            'filter.pharmacy': 'Pharmacies',
            'filter.hospital': 'Hospitals',
            'filter.doctor': 'Doctors',
            'meta.results': 'Results',
            'chat.title': 'MedOrbit Assistant',
            'chat.subtitle': 'Online',
            'chat.placeholder': 'Ask about the nearest clinic, pharmacy, or doctor...',
            'send': 'Send',
            'locate': 'My location',
            'theme': 'Theme',
            'language': 'العربية',
            'newChat': 'New chat',
            'shareLocation': 'Share my location',
            'map.statusDefault': 'Locate yourself or ask about the nearest clinic',
            'map.emptyTitle': 'No results yet',
            'map.emptyDesc': 'Ask the assistant about the nearest clinic or pharmacy and results will appear here',
            'recenter': 'Recenter',
            'layers': 'Toggle layers',
            'fitAll': 'Fit all'
        }
    };

    let current = Store.getLang() || 'ar';

    function t(key) {
        return (dict[current] && dict[current][key]) || key;
    }

    function apply() {
        document.documentElement.lang = current;
        document.documentElement.dir = current === 'ar' ? 'rtl' : 'ltr';
        document.body.lang = current;

        const setText = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
        const setPlaceholder = (id, val) => { const el = document.getElementById(id); if (el) el.placeholder = val; };
        const setTitle = (id, val) => { const el = document.getElementById(id); if (el) el.title = val; };

        setText('chatTitle', t('chat.title'));
        setText('chatSubtitle', t('chat.subtitle'));
        setText('mapStatusText', t('map.statusDefault'));
        setPlaceholder('chatInput', t('chat.placeholder'));
        setPlaceholder('quickSearch', t('search.placeholder'));

        ['sendBtn', 'locateBtn', 'themeToggle', 'langToggle', 'clearChatBtn', 'locationBtn', 'recenterBtn', 'layerBtn', 'fitAllBtn']
            .forEach(id => setTitle(id, t(document.getElementById(id)?.dataset?.i18nTitle || id)));

        // Translate all data-i18n elements
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            const text = t(key);
            if (text) el.textContent = text;
        });

        // Translate placeholders
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            const text = t(key);
            if (text) el.placeholder = text;
        });

        const langLabel = document.getElementById('langLabel');
        if (langLabel) langLabel.textContent = current === 'ar' ? 'EN' : 'AR';

        Store.setLang(current);
        window.dispatchEvent(new CustomEvent('languageChanged', { detail: { lang: current } }));
    }

    function toggle() {
        current = current === 'ar' ? 'en' : 'ar';
        apply();
    }

    function getLang() {
        return current;
    }

    return { apply, toggle, getLang, t };
})();

/**
 * Theme manager (light / dark)
 */
const Theme = (() => {
    let current = Store.getTheme() || 'light';

    function apply() {
        document.body.setAttribute('data-theme', current);
        const btn = document.getElementById('themeToggle');
        if (btn) {
            const icon = btn.querySelector('i');
            if (icon) {
                icon.className = current === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
            }
        }
        Store.setTheme(current);
    }

    function toggle() {
        current = current === 'light' ? 'dark' : 'light';
        apply();
    }

    return { apply, toggle, get: () => current };
})();

/**
 * Toast helper
 */
const Toast = (() => {
    function show(message, type = 'info', duration = 3000) {
        const container = document.getElementById('toastContainer');
        if (!container) return;

        const icons = {
            success: 'fa-check-circle',
            error: 'fa-times-circle',
            warning: 'fa-exclamation-triangle',
            info: 'fa-info-circle'
        };

        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.innerHTML = `<i class="fas ${icons[type] || icons.info}"></i><span>${message}</span>`;
        container.appendChild(toast);

        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateY(-10px)';
            setTimeout(() => toast.remove(), 300);
        }, duration);
    }

    return {
        success: (m, d) => show(m, 'success', d),
        error: (m, d) => show(m, 'error', d),
        warning: (m, d) => show(m, 'warning', d),
        info: (m, d) => show(m, 'info', d)
    };
})();

/**
 * App bootstrap
 */
document.addEventListener('DOMContentLoaded', () => {
    // 1. Apply theme + language
    Theme.apply();
    I18n.apply();

    // 2. Initialize map
    if (typeof MapApp !== 'undefined' && MapApp.init) {
        MapApp.init();
    }

    // 3. Initialize chat
    if (typeof Chat !== 'undefined' && Chat.init) {
        Chat.init();
    }

    // 4. Show app, hide loader
    setTimeout(() => {
        const loader = document.getElementById('appLoader');
        const app = document.getElementById('app');
        if (loader) loader.classList.add('hidden');
        if (app) app.style.visibility = 'visible';
    }, 400);

    // 5. Wire up header actions
    document.getElementById('langToggle')?.addEventListener('click', () => I18n.toggle());
    document.getElementById('themeToggle')?.addEventListener('click', () => Theme.toggle());
    document.getElementById('locateBtn')?.addEventListener('click', () => {
        if (typeof MapApp !== 'undefined' && MapApp.locateUser) {
            MapApp.locateUser(true);
        }
    });
    document.getElementById('clearChatBtn')?.addEventListener('click', () => {
        if (typeof Chat !== 'undefined' && Chat.clearChat) Chat.clearChat();
    });
    document.getElementById('locationBtn')?.addEventListener('click', () => {
        if (typeof MapApp !== 'undefined' && MapApp.locateUser) {
            MapApp.locateUser(true);
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
    document.getElementById('layerBtn')?.addEventListener('click', () => {
        Toast.info(I18n.getLang() === 'ar' ? 'تبديل الطبقات قريباً' : 'Layer toggle coming soon');
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
    console.log('API:', window.MEDORBIT_API_URL || 'http://localhost:3001/api');
    console.log('Theme:', Theme.get(), '| Language:', I18n.getLang());
});