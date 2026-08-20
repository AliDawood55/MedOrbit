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

    // The global auth gate also boots on index.html and would otherwise race
    // this hand-off, bouncing a legitimate reset/verify link to Home before the
    // dedicated page loads. The flag tells it this document is already on its
    // way somewhere and it should stand down.
    if (verifyToken) {
        window.__medorbitNavigatingAway = true;
        window.location.replace('verify-email.html?token=' + encodeURIComponent(verifyToken));
    } else if (resetToken) {
        window.__medorbitNavigatingAway = true;
        window.location.replace('reset-password.html?token=' + encodeURIComponent(resetToken));
    }
})();
