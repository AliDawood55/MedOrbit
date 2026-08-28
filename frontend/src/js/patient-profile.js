const PatientSocialProfile = (() => {
    const byId = (id) => document.getElementById(id);
    const isAr = () => I18n.getLang() === 'ar';
    let profile = null;

    function setText(id, ar, en) {
        byId(id).textContent = isAr() ? ar : en;
    }

    function localize() {
        const copy = {
            patientProfileTitle: [
                'ملفي الاجتماعي',
                'My Social Profile'
            ],
            patientProfileSubtitle: [
                'تحكم بالمعلومات الآمنة المستخدمة للاكتشاف والمراسلة.',
                'Control the safe information used for social discovery and messages.'
            ],
            patientBioLabel: [
                'نبذة قصيرة',
                'Short bio'
            ],
            patientBioHelp: [
                'حقل واحد—اكتب بالعربية أو الإنجليزية أو نص مختلط.',
                'One field—write in Arabic, English, or mixed text.'
            ],
            patientCityLabel: [
                'المدينة العامة',
                'General city'
            ],
            patientLanguageLabel: [
                'لغة الواجهة',
                'Interface language'
            ],
            patientAvatarLabel: [
                'صورة الملف',
                'Profile image'
            ],
            patientAvatarHelp: [
                'JPG أو PNG أو WebP.',
                'JPG, PNG, or WebP.'
            ],
            privacyLabel: [
                'السماح للأطباء المعتمدين بالعثور عليّ ومراسلتي',
                'Allow approved doctors to find/message me'
            ],
            privacyHelp: [
                'عند الإيقاف، لا يمكن للأطباء اكتشاف ملفك أو إنشاء طلب مراسلة جديد غير مرتبط. المحادثات المقبولة سابقاً لا تتأثر.',
                'When off, doctors cannot discover this profile or start a new unrelated message request. Existing accepted conversations are unaffected.'
            ],
            cancelPatientEdit: [
                'إلغاء',
                'Cancel'
            ],
            savePatientLabel: [
                'حفظ الملف',
                'Save profile'
            ],
            patientPrivacyNote: [
                'السجلات الطبية والتشخيصات والمواعيد وبيانات الاتصال ومحتوى الطبيب الافتراضي ليست جزءاً من هذا الملف أبداً.',
                'Medical records, diagnoses, appointments, contact details, and Virtual Doctor content are never part of this profile.'
            ]
        };

        Object.entries(copy).forEach(([id, value]) => {
            setText(id, value[0], value[1]);
        });

        if (profile) {
            renderPreview();
        }
    }

    function feedback(message, type) {
        const node = byId('patientProfileFeedback');

        node.textContent = message;
        node.className = `page-feedback ${type}`;
    }

    function displayName() {
        if (!profile) return '';

        const primary = isAr()
            ? [profile.first_name_ar, profile.last_name_ar]
            : [profile.first_name_en, profile.last_name_en];

        const fallback = isAr()
            ? [profile.first_name_en, profile.last_name_en]
            : [profile.first_name_ar, profile.last_name_ar];

        return (
            primary.filter(Boolean).join(' ').trim() ||
            fallback.filter(Boolean).join(' ').trim()
        );
    }

    function renderPreview() {
        const name =
            displayName() ||
            (isAr() ? 'مريض MedOrbit' : 'MedOrbit Patient');

        byId('patientPreviewName').textContent = name;
        byId('patientPreviewCity').textContent = profile.city || '';

        byId('patientMemberSince').textContent = profile.member_since
            ? `${isAr() ? 'عضو منذ' : 'Member since'} ${new Date(
                  profile.member_since
              ).toLocaleDateString(isAr() ? 'ar' : 'en-US', {
                  year: 'numeric',
                  month: 'long'
              })}`
            : '';

        const avatar = byId('patientPreviewAvatar');

        avatar.textContent = '';

        if (profile.avatar_url) {
            const image = document.createElement('img');

            image.src = API.assetUrl(profile.avatar_url);
            image.alt = '';

            avatar.appendChild(image);
        } else {
            avatar.textContent = name.charAt(0).toUpperCase();
        }
    }

    async function load() {
        const response = await API.patientProfiles.me();

        profile = response.data;

        byId('patientBio').value = profile.bio || '';
        byId('patientCity').value = profile.city || '';
        byId('patientLanguage').value =
            profile.preferred_language || 'ar';
        byId('allowDoctorMessages').checked =
            Boolean(profile.allow_doctor_messages);

        renderPreview();
    }

    async function save(event) {
        event.preventDefault();

        const button = byId('savePatientProfile');

        button.disabled = true;

        feedback(
            isAr() ? 'جارٍ حفظ الملف…' : 'Saving profile…',
            'success'
        );

        try {
            const file = byId('patientAvatar').files[0];

            if (file) {
                await API.users.uploadAvatar(file);
            }

            await Promise.all([
                API.patientProfiles.updateMe({
                    bio: byId('patientBio').value,
                    city: byId('patientCity').value,
                    allowDoctorMessages:
                        byId('allowDoctorMessages').checked
                }),
                API.users.updatePreferences({
                    language: byId('patientLanguage').value
                })
            ]);

            await load();

            feedback(
                isAr()
                    ? 'تم حفظ ملفك الاجتماعي.'
                    : 'Your social profile was saved.',
                'success'
            );
        } catch (err) {
            feedback(
                err.message ||
                    (isAr()
                        ? 'تعذر حفظ الملف.'
                        : 'Unable to save profile.'),
                'error'
            );
        } finally {
            button.disabled = false;
        }
    }

    async function init() {
        if (!API.requireAuth()) return;

        if (API.getUser()?.role !== 'patient') {
            location.href = 'dashboard.html';
            return;
        }

        localize();

        window.addEventListener('languageChanged', localize);

        byId('patientProfileForm').addEventListener('submit', save);

        try {
            await load();
        } catch (err) {
            feedback(
                err.message || 'Unable to load profile.',
                'error'
            );
        }
    }

    return {
        init
    };
})();