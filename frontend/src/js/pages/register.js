document.addEventListener('DOMContentLoaded', () => {
    Layout.init();
    if (new URLSearchParams(window.location.search).get('intent') === 'doctor') {
        document.getElementById('doctorApplicationIntro')?.classList.remove('hidden');
    }
    GoogleSignIn.init('googleSignInBtn');
});
