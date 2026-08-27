/**
 * MedOrbit v2 - Form Alert
 * Shared #formAlert error box used by the AI-tool pages (drug checker,
 * report summary, symptom checker).
 */
const FormAlert = (() => {
    function error(message) {
        const box = document.getElementById('formAlert');
        if (!box) return;
        box.className = 'alert error';
        box.textContent = message;
    }

    function clear() {
        const box = document.getElementById('formAlert');
        if (box) box.className = 'alert';
    }

    return { error, clear };
})();
