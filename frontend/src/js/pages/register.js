document.addEventListener('DOMContentLoaded', () => {
    Layout.init();
    const intent = new URLSearchParams(window.location.search).get('intent');
    if (intent === 'doctor') {
        document.getElementById('doctorApplicationIntro')?.classList.remove('hidden');
    }
    if (intent === 'clinic') {
        document.getElementById('clinicApplicationIntro')?.classList.remove('hidden');
    }

    function localizeApplicationOptions() {
        const arabic = I18n?.getLang?.() === 'ar';
        const text = (ar, en) => arabic ? ar : en;
        const copy = {
            registrationOptionsTitle: ['انضم إلى MedOrbit بالطريقة المناسبة لك', 'Join MedOrbit in the way that fits you'],
            registerDoctorOptionTitle: ['التقديم كطبيب', 'Apply as a doctor'],
            registerDoctorOptionHint: ['أنشئ حسابك ثم أرسل بياناتك المهنية للمراجعة.', 'Create your account, then submit your professional details for review.'],
            registerClinicOptionTitle: ['التقديم لمنشأة صحية', 'Apply for a healthcare facility'],
            registerClinicOptionHint: ['سجّل المنشأة ثم أرسل بياناتها وترخيصها للمراجعة.', 'Register the facility, then submit its details and licence for review.'],
        };
        Object.entries(copy).forEach(([id, values]) => {
            const element = document.getElementById(id);
            if (element) element.textContent = text(values[0], values[1]);
        });
        document.querySelectorAll('.auth-application-option > .fa-arrow-left').forEach((icon) => {
            icon.className = `fas ${arabic ? 'fa-arrow-left' : 'fa-arrow-right'}`;
        });
    }

    localizeApplicationOptions();
    window.addEventListener('languageChanged', localizeApplicationOptions);
    GoogleSignIn.init('googleSignInBtn');
});
