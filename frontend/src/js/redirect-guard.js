/**
 * MedOrbit v2 - Redirect Guard
 * index.html is where the backend's password-reset and email-verification
 * emails link to (?reset=TOKEN / ?verify=TOKEN) — that contract must not
 * change. This hands those two cases off to their dedicated pages before
 * the chat app boots, so the link still "resolves to index.html" while the
 * actual work happens on reset-password.html / verify-email.html.
 *
 * Must load synchronously, as the very first script in <head>, so the
 * redirect happens before the chat UI has a chance to render.
 */
(function () {
    const params = new URLSearchParams(window.location.search);
    const verifyToken = params.get('verify');
    const resetToken = params.get('reset');

    if (verifyToken) {
        window.location.replace('verify-email.html?token=' + encodeURIComponent(verifyToken));
    } else if (resetToken) {
        window.location.replace('reset-password.html?token=' + encodeURIComponent(resetToken));
    }
})();
