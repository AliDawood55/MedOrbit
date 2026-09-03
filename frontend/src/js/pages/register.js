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
            registerDoctorOptionTitle: ['التقديم كطبيب', 'Apply as a doctor'],
            registerClinicOptionTitle: ['التقديم لمنشأة صحية', 'Apply for a healthcare facility'],
            clinicRegisterIntroTitle: ['تسجيل منشأة صحية', 'Register a healthcare facility'],
            clinicRegisterIntroDescription: ['أنشئ حساباً، فعّل البريد، ثم أرسل بيانات المنشأة وترخيصها للمراجعة.', 'Create an account, verify the email, then submit the facility details and licence for review.'],
            clinicRegisterIntroNoteLabel: ['ملاحظة:', 'Note:'],
            clinicRegisterIntroNote: ['هذا البريد هو بريد التحقق للحساب، وستصلك عليه نتيجة مراجعة طلب المنشأة.', 'This email verifies the account and receives the clinic-application decision.'],
            clinicSignupNameLabel: ['اسم المنشأة', 'Facility name'],
            clinicSignupAddressLabel: ['عنوان المنشأة', 'Facility address'],
            clinicExtraPhonesLabel: ['أرقام إضافية للمنشأة', 'Additional facility phone numbers'],
            addClinicPhoneLabel: ['إضافة رقم', 'Add number'],
        };
        Object.entries(copy).forEach(([id, values]) => {
            const element = document.getElementById(id);
            if (element) element.textContent = text(values[0], values[1]);
        });
        const name = document.getElementById('clinicSignupName');
        const address = document.getElementById('clinicSignupAddress');
        if (name) {
            name.placeholder = text('مركز الشفاء الطبي', 'Al Shifa Medical Center');
            name.dir = arabic ? 'rtl' : 'ltr';
        }
        if (address) {
            address.placeholder = text('المدينة، الشارع، رقم المبنى', 'City, street, building');
            address.dir = arabic ? 'rtl' : 'ltr';
        }
    }

    localizeApplicationOptions();
    window.addEventListener('languageChanged', localizeApplicationOptions);
    GoogleSignIn.init('googleSignInBtn');
});
