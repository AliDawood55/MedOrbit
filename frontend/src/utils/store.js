/**
 * MedOrbit v2 - Storage Wrapper
 * localStorage with namespacing + JSON serialization
 */

const Store = {
    PREFIX: 'medorbit_v2_',

    get(key, defaultValue = null) {
        try {
            const raw = localStorage.getItem(this.PREFIX + key);
            if (raw == null) return defaultValue;
            return JSON.parse(raw);
        } catch {
            return defaultValue;
        }
    },

    set(key, value) {
        try {
            localStorage.setItem(this.PREFIX + key, JSON.stringify(value));
            return true;
        } catch (e) {
            console.warn('Store.set failed:', e);
            return false;
        }
    },

    remove(key) {
        localStorage.removeItem(this.PREFIX + key);
    },

    // Common helpers
    getTheme() {
        return this.get('theme', 'light');
    },
    setTheme(theme) {
        return this.set('theme', theme);
    },

    getLang() {
        return this.get('lang', null); // null = auto-detect
    },
    setLang(lang) {
        return this.set('lang', lang);
    },

    getRecentSearches() {
        return this.get('recentSearches', []);
    },
    addRecentSearch(query) {
        if (!query || !query.trim()) return;
        const list = this.getRecentSearches();
        const filtered = list.filter(q => q !== query);
        filtered.unshift(query);
        this.set('recentSearches', filtered.slice(0, 10));
    },
    clearRecentSearches() {
        this.remove('recentSearches');
    }
};