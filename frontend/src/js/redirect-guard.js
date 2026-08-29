(function () {
    const params = new URLSearchParams(window.location.search);
    const verifyToken = params.get('verify');
    const resetToken = params.get('reset');

if (verifyToken) {
        window.__medorbitNavigatingAway = true;
        window.location.replace('verify-email.html?token=' + encodeURIComponent(verifyToken));
    } else if (resetToken) {
        window.__medorbitNavigatingAway = true;
        window.location.replace('reset-password.html?token=' + encodeURIComponent(resetToken));
    }
})();
