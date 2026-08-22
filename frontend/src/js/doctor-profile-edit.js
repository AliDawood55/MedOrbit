const DoctorProfileEditor = (() => {
    const editors = new Map();
    let profile = null;
    let profileSchedule = null;

    const isAr = () => I18n.getLang() === 'ar';
    const byId = (id) => document.getElementById(id);
    const assetUrl = (value) => API.assetUrl(value);

    class TagEditor {
        constructor(name, maxItems) {
            this.name = name;
            this.maxItems = maxItems;
            this.root = document.querySelector(`[data-tag-editor="${name}"]`);
            this.input = this.root.querySelector('input');
            this.values = [];
            this.input.addEventListener('keydown', (event) => {
                if (!['Enter', ','].includes(event.key)) return;
                event.preventDefault();
                this.add(this.input.value);
            });
            this.input.addEventListener('blur', () => this.add(this.input.value));
        }
        add(raw) {
            const value = String(raw || '').trim().replace(/\s+/g, ' ');
            this.input.value = '';
            if (!value || this.values.some((item) => item.toLocaleLowerCase('en-US') === value.toLocaleLowerCase('en-US'))) return;
            if (this.values.length >= this.maxItems) {
                Toast.error(isAr() ? `الحد الأقصى ${this.maxItems}` : `Maximum ${this.maxItems} entries`);
                return;
            }
            this.values.push(value);
            this.render();
        }
        set(values) {
            this.values = Array.isArray(values) ? [...values] : [];
            this.render();
        }
        render() {
            this.root.querySelectorAll('.tag-token').forEach((node) => node.remove());
            this.values.forEach((value, index) => {
                const token = document.createElement('span');
                token.className = 'tag-token';
                const copy = document.createElement('span');
                copy.textContent = value;
                const remove = document.createElement('button');
                remove.type = 'button';
                remove.setAttribute('aria-label', isAr() ? 'إزالة' : 'Remove');
                remove.textContent = '×';
                remove.addEventListener('click', () => {
                    this.values.splice(index, 1);
                    this.render();
                });
                token.append(copy, remove);
                this.root.insertBefore(token, this.input);
            });
        }
    }

    function setText(id, ar, en) { byId(id).textContent = isAr() ? ar : en; }
    function localize() {
        const copy = {
            editDoctorTitle:['تعديل الملف المهني','Edit Professional Profile'],editDoctorSubtitle:['حافظ على ملف عام واضح وحديث وموثوق.','Keep your public profile clear, current, and trustworthy.'],manageScheduleLabel:['جدولي','My Schedule'],viewProfileLabel:['عرض الملف العام','View public profile'],verifiedSpecialtyLabel:['التخصص المعتمد','Verified specialty'],verifiedSpecialtyHelp:['بيانات الاعتماد المراجعة للعرض فقط.','Reviewed credentials are read-only.'],verifiedLicenseLabel:['رقم الترخيص الطبي','Medical license'],headlineLabel:['العنوان المهني','Professional headline'],headlineHelp:['عبارة موجزة تظهر أسفل التخصص.','A concise statement shown below your specialty.'],bioLabel:['السيرة المهنية','Professional bio'],bioHelp:['اكتب مرة واحدة بالعربية أو الإنجليزية أو كليهما.','Write once in Arabic, English, or both.'],subSpecialtyLabel:['التخصص الفرعي','Sub-specialty'],experienceLabel:['سنوات الخبرة','Years of experience'],expertiseLabel:['مجالات الخبرة','Areas of expertise'],expertiseHelp:['اضغط Enter أو الفاصلة لإضافة 12 كحد أقصى.','Press Enter or comma to add up to 12.'],interestsLabel:['الاهتمامات المهنية','Professional interests'],interestsHelp:['اضغط Enter أو الفاصلة لإضافة 10 كحد أقصى.','Press Enter or comma to add up to 10.'],educationLabel:['التعليم','Education'],certificationsLabel:['الشهادات','Certifications'],languagesLabel:['اللغات','Languages spoken'],cityLabel:['المدينة','City'],feeLabel:['رسوم الاستشارة','Consultation fee'],feeHelp:['الرسوم المعروضة حالياً؛ لا تشمل معالجة الدفع.','Current displayed fee; payment processing is not included.'],durationLabel:['مدة الموعد الافتراضية','Default appointment duration'],durationHelp:['تُستخدم عند إضافة توفر جديد فقط.','Used for newly added availability only.'],acceptingLabel:['أستقبل مرضى جدداً','Accepting new patients'],acceptingHelp:['تظهر هذه الحالة علناً في ملفك.','Shown publicly on your profile.'],cancelDoctorEdit:['إلغاء','Cancel'],saveDoctorLabel:['حفظ الملف','Save profile'],changePhotoLabel:['تغيير الصورة','Change photo'],completionTitle:['جاهزية الملف','Profile readiness'],doctorPrivacyNote:['يبقى طلب الطبيب سجلاً تاريخياً مستقلاً. تعديل هذا الملف لا يغيّره.','Your application remains a separate historical review record. Editing this profile does not change it.']
        };
        Object.entries(copy).forEach(([id, values]) => setText(id, values[0], values[1]));
        editors.forEach((editor) => editor.render());
    }

    function feedback(message, type) {
        const node = byId('doctorProfileFeedback');
        node.textContent = message;
        node.className = `page-feedback ${type}`;
    }

    function renderPreview(user) {
        const fullName = (isAr()
            ? `${user.first_name_ar || ''} ${user.last_name_ar || ''}`
            : `${user.first_name_en || ''} ${user.last_name_en || ''}`).trim()
            || `${user.first_name_ar || ''} ${user.last_name_ar || ''}`.trim()
            || `${user.first_name_en || ''} ${user.last_name_en || ''}`.trim();
        byId('doctorEditName').textContent = fullName || (isAr() ? 'طبيب' : 'Doctor');
        byId('doctorEditSpecialty').textContent = (isAr() ? profile.specialty_ar : profile.specialty_en)
            || profile.specialty_en || profile.specialty_ar || '';
        const avatar = byId('doctorEditAvatar');
        avatar.textContent = '';
        if (profile.profile_image_url) {
            const image = document.createElement('img');
            image.src = assetUrl(profile.profile_image_url);
            image.alt = '';
            avatar.appendChild(image);
        } else {
            avatar.textContent = (fullName || 'D').charAt(0).toUpperCase();
        }
    }

    function renderCompletion() {
        const items = [
            [isAr() ? 'السيرة' : 'Bio', Boolean(profile.professional_bio)],
            [isAr() ? 'الخبرات' : 'Expertise', Boolean(profile.areas_of_expertise?.length)],
            [isAr() ? 'التوفر' : 'Availability', Boolean(profileSchedule?.weekly?.some((item) => item.is_active))],
            [isAr() ? 'الصورة' : 'Photo', Boolean(profile.profile_image_url)],
        ];
        byId('completionChecklist').replaceChildren(...items.map(([label, done]) => {
            const row = document.createElement('div');
            row.className = 'completion-item';
            const icon = document.createElement('i');
            icon.className = `fas ${done ? 'fa-circle-check complete' : 'fa-circle incomplete'}`;
            const text = document.createElement('span');
            text.textContent = label;
            row.append(icon, text);
            return row;
        }));
    }

    async function load() {
        const [profileResponse, state, scheduleResponse] = await Promise.all([API.doctors.myProfile(), AuthGate.verifySession(), API.doctors.mySchedule()]);
        if (state !== 'valid') return;
        profile = profileResponse.data;
        profileSchedule = scheduleResponse.data;
        byId('viewPublicProfile').href = `doctor.html?id=${encodeURIComponent(profile.id)}`;
        byId('professionalHeadline').value = profile.professional_headline || '';
        byId('verifiedSpecialty').value = (isAr() ? profile.specialty_ar : profile.specialty_en) || profile.specialty_en || profile.specialty_ar || '';
        byId('verifiedLicense').value = profile.medical_license_number || '';
        byId('professionalBio').value = profile.professional_bio || '';
        byId('subSpecialty').value = profile.sub_specialty || '';
        byId('yearsExperience').value = profile.years_of_experience ?? '';
        byId('doctorCity').value = profile.city || '';
        byId('consultationFee').value = profile.consultation_fee ?? '';
        byId('consultationDuration').value = String(profile.consultation_duration || 30);
        byId('acceptingPatients').checked = Boolean(profile.is_accepting_patients);
        editors.get('expertise').set(profile.areas_of_expertise);
        editors.get('interests').set(profile.professional_interests);
        editors.get('education').set(profile.education);
        editors.get('certifications').set(profile.certifications);
        editors.get('languages').set(profile.languages_spoken);
        renderPreview(AuthGate.getVerifiedUser());
        renderCompletion();
    }

    async function save(event) {
        event.preventDefault();
        const button = byId('saveDoctorProfile');
        button.disabled = true;
        feedback(isAr() ? 'جارٍ حفظ الملف…' : 'Saving profile…', 'success');
        try {
            const yearsRaw = byId('yearsExperience').value;
            const response = await API.doctors.updateMyProfile({
                professionalHeadline: byId('professionalHeadline').value,
                bio: byId('professionalBio').value,
                subSpecialty: byId('subSpecialty').value,
                ...(yearsRaw === '' ? {} : { yearsOfExperience: Number(yearsRaw) }),
                areasOfExpertise: editors.get('expertise').values,
                professionalInterests: editors.get('interests').values,
                education: editors.get('education').values,
                certifications: editors.get('certifications').values,
                languagesSpoken: editors.get('languages').values,
                city: byId('doctorCity').value,
                consultationFee: Number(byId('consultationFee').value || 0),
                consultationDuration: Number(byId('consultationDuration').value),
                isAcceptingPatients: byId('acceptingPatients').checked
            });
            profile = response.data;
            renderCompletion();
            feedback(isAr() ? 'تم حفظ ملفك المهني.' : 'Your professional profile was saved.', 'success');
        } catch (err) {
            feedback(err.message || (isAr() ? 'تعذر حفظ الملف.' : 'Unable to save profile.'), 'error');
        } finally {
            button.disabled = false;
        }
    }

    async function uploadAvatar(file) {
        if (!file) return;
        if (!['image/jpeg','image/png'].includes(file.type) || file.size > 2 * 1024 * 1024) {
            feedback(isAr() ? 'استخدم صورة JPG أو PNG بحجم لا يتجاوز 2 ميجابايت.' : 'Use a JPG or PNG image up to 2 MB.', 'error');
            return;
        }
        try {
            const response = await API.users.uploadAvatar(file);
            profile.profile_image_url = response.data.avatar;
            renderPreview((await API.users.me()).data);
            renderCompletion();
            feedback(isAr() ? 'تم تحديث الصورة.' : 'Photo updated.', 'success');
        } catch (err) {
            feedback(err.message || (isAr() ? 'تعذر تحديث الصورة.' : 'Unable to update photo.'), 'error');
        }
    }

    async function init() {
        if (!API.requireAuth()) return;
        if (API.getUser()?.role !== 'doctor') { location.href = 'dashboard.html'; return; }
        [['expertise',12],['interests',10],['education',20],['certifications',20],['languages',10]].forEach(([name,max]) => editors.set(name,new TagEditor(name,max)));
        localize();
        window.addEventListener('languageChanged', localize);
        byId('doctorProfileForm').addEventListener('submit', save);
        byId('doctorAvatarButton').addEventListener('click', () => byId('doctorAvatarInput').click());
        byId('doctorAvatarInput').addEventListener('change', (event) => uploadAvatar(event.target.files?.[0]));
        try { await load(); } catch (err) { feedback(err.message || 'Unable to load profile.', 'error'); }
    }
    return { init };
})();
