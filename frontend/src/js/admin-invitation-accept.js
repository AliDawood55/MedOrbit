(() => {
    if (typeof Theme !== 'undefined') Theme.apply();

    const token = new URLSearchParams(window.location.search).get('token');
    const message = document.getElementById('message');
    const button = document.getElementById('acceptInvitation');
    const loginLink = document.getElementById('loginLink');

    if (!token) {
        message.textContent = 'This invitation link is invalid.';
        button.disabled = true;
        return;
    }
    if (!API.isAuthenticated()) {
        message.textContent = 'Sign in to the account that received this invitation, then return here.';
        loginLink.href = `login.html?redirect=${encodeURIComponent(`admin-invitation-accept.html?token=${encodeURIComponent(token)}`)}`;
        button.disabled = true;
        return;
    }
    button.addEventListener('click', async () => {
        button.disabled = true;
        try {
            await API.post('/admin/invitations/accept', { token });
            history.replaceState({}, '', window.location.pathname);
            message.textContent = 'Invitation accepted. Please sign in again.';
            window.setTimeout(() => {
                API.clearSession();
                if (typeof AuthGate !== 'undefined' && typeof AuthGate.clearIntendedDestination === 'function') {
                    AuthGate.clearIntendedDestination();
                }
                window.location.replace('login.html');
            }, 800);
        } catch (err) {
            message.textContent = err.message || 'This invitation is unavailable.';
            button.disabled = false;
        }
    });
})();
