const Format = (() => {

function distance(meters) {
        if (meters == null) return '';
        if (meters < 1000) return `${Math.round(meters)} م`;
        return `${(meters / 1000).toFixed(1)} كم`;
    }

function toEnglishDigits(str) {
        if (!str) return str;
        return String(str).replace(/[\u0660-\u0669]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d));
    }

function number(n, decimals = 0) {
        if (n == null || isNaN(n)) return '';
        return Number(n).toFixed(decimals);
    }

function time(date = new Date(), lang = 'ar') {
        return date.toLocaleTimeString(
            lang === 'ar' ? 'ar-PS' : 'en-US',
            { hour: '2-digit', minute: '2-digit' }
        );
    }

function pluralize(count, singular, plural, lang = 'ar') {
        if (lang === 'ar') {

            return count === 1 ? singular : (plural || singular);
        }
        return count === 1 ? singular : plural;
    }

function stripEmoji(text) {
        if (!text) return '';
        return String(text).replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu, '').trim();
    }

function extractPhone(text) {
        if (!text) return null;
        const match = String(text).match(/(\+?[\d][\d\s\-]{7,}\d)/);
        return match ? match[1].trim() : null;
    }

function extractRating(text) {
        if (!text) return null;
        const match = String(text).match(/⭐\s*(\d+\.?\d*)/);
        return match ? parseFloat(match[1]) : null;
    }

    return {
        distance,
        toEnglishDigits,
        number,
        time,
        pluralize,
        stripEmoji,
        extractPhone,
        extractRating
    };
})();
