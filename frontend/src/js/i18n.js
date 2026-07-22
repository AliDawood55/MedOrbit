/**
 * MedOrbit v2 - i18n Module
 * Shared across every page (chat app, auth pages, future content pages).
 * Reads/persists language via Store; toggles document dir/lang.
 */
const I18n = (() => {
    const dict = {
        ar: {
            'brand.tagline': 'منصة طبية ذكية',
            'search.placeholder': 'ابحث عن عيادة، صيدلية، تخصص...',
            'filter.all': 'الكل',
            'filter.clinic': 'العيادات',
            'filter.pharmacy': 'الصيدليات',
            'filter.hospital': 'المستشفيات',
            'filter.doctor': 'الأطباء',
            'meta.results': 'النتائج',
            'chat.title': 'مساعد MedOrbit',
            'chat.subtitle': 'متصل الآن',
            'chat.placeholder': 'اسأل عن أقرب عيادة، صيدلية، أو طبيب...',
            'send': 'إرسال',
            'locate': 'موقعي',
            'theme': 'الوضع',
            'language': 'English',
            'newChat': 'محادثة جديدة',
            'shareLocation': 'مشاركة موقعي',
            'map.statusDefault': 'حدد موقعك أو اسأل عن أقرب عيادة',
            'map.emptyTitle': 'لا توجد نتائج بعد',
            'map.emptyDesc': 'اسأل المساعد عن أقرب عيادة أو صيدلية وستظهر النتائج هنا',
            'recenter': 'إعادة التمركز',
            'layers': 'تغيير الخريطة',
            'fitAll': 'عرض الكل',

            // Navigation
            'nav.home': 'الرئيسية',
            'nav.chat': 'المحادثة',
            'nav.doctors': 'الأطباء',
            'nav.clinics': 'العيادات',
            'nav.aiTools': 'أدوات ذكية',
            'nav.symptomChecker': 'فحص الأعراض',
            'nav.drugChecker': 'تداخل الأدوية',
            'nav.reportSummary': 'تلخيص التقارير',
            'nav.account': 'حسابي',
            'nav.dashboard': 'لوحة التحكم',

            // Auth
            'auth.login': 'تسجيل الدخول',
            'auth.register': 'إنشاء حساب',
            'auth.logout': 'تسجيل الخروج',

            // Footer
            'footer.tagline': 'منصة الرعاية الصحية الذكية لنابلس',
            'footer.rights': 'جميع الحقوق محفوظة',

            // Auth pages
            'auth.loginTitle': 'تسجيل الدخول',
            'auth.loginSubtitle': 'أهلاً بعودتك، سجّل الدخول إلى حسابك',
            'auth.registerTitle': 'إنشاء حساب جديد',
            'auth.registerSubtitle': 'انضم إلى MedOrbit وابدأ رحلتك الصحية',
            'auth.forgotTitle': 'نسيت كلمة المرور؟',
            'auth.forgotSubtitle': 'أدخل بريدك الإلكتروني وسنرسل لك رابط إعادة التعيين',
            'auth.resetTitle': 'إعادة تعيين كلمة المرور',
            'auth.resetSubtitle': 'أدخل كلمة مرور جديدة لحسابك',
            'auth.verifyTitle': 'تفعيل البريد الإلكتروني',
            'auth.orDivider': 'أو',
            'auth.email': 'البريد الإلكتروني',
            'auth.emailPlaceholder': 'example@medorbit.com',
            'auth.password': 'كلمة المرور',
            'auth.passwordPlaceholder': 'أدخل كلمة المرور',
            'auth.newPassword': 'كلمة المرور الجديدة',
            'auth.newPasswordPlaceholder': '8 أحرف على الأقل',
            'auth.pwHint': 'حرف كبير + صغير + رقم + رمز خاص (8 أحرف على الأقل)',
            'auth.firstNameAr': 'الاسم الأول (عربي)',
            'auth.lastNameAr': 'الاسم الأخير (عربي)',
            'auth.firstNameEn': 'الاسم الأول (إنجليزي)',
            'auth.lastNameEn': 'الاسم الأخير (إنجليزي)',
            'auth.phone': 'رقم الهاتف',
            'auth.phonePlaceholder': '+970-59-1234567',
            'auth.gender': 'الجنس',
            'auth.genderMale': 'ذكر',
            'auth.genderFemale': 'أنثى',
            'auth.submitLogin': 'تسجيل الدخول',
            'auth.submitRegister': 'إنشاء الحساب',
            'auth.submitForgot': 'إرسال رابط إعادة التعيين',
            'auth.submitReset': 'تعيين كلمة المرور الجديدة',
            'auth.noAccount': 'ليس لديك حساب؟',
            'auth.haveAccount': 'لديك حساب بالفعل؟',
            'auth.forgotPassword': 'نسيت كلمة المرور؟',
            'auth.backToLogin': 'العودة لتسجيل الدخول',
            'auth.verify.checking': 'جارِ التحقق من بريدك الإلكتروني...',
            'auth.resend.title': 'لم يصلك رابط التفعيل؟',
            'auth.resend.submit': 'إعادة إرسال رابط التفعيل',

            // Conversation sidebar
            'sidebar.newChat': 'محادثة جديدة',
            'sidebar.searchPlaceholder': 'ابحث في المحادثات...',
            'sidebar.toggle': 'سجل المحادثات',

            // Home / landing page
            'home.badge': 'نابلس، فلسطين',
            'home.heroTitle': 'رعاية صحية <span>ذكية</span> في متناول يدك',
            'home.heroSubtitle': 'اعثر على أقرب طبيب أو عيادة أو صيدلية، تحدث مع مساعدنا الذكي، واحصل على إجابات طبية موثوقة — كل ذلك في مكان واحد.',
            'home.startChat': 'ابدأ محادثة',
            'home.goToDashboard': 'الذهاب إلى لوحة التحكم',
            'home.searchPlaceholder': 'ابحث عن طبيب، تخصص، أو عيادة...',
            'home.searchDoctors': 'أطباء',
            'home.searchClinics': 'عيادات',
            'home.featuresTitle': 'كل ما تحتاجه لرعاية صحية أفضل',
            'home.featuresSubtitle': 'منصة واحدة تجمع بين الذكاء الاصطناعي والبيانات الطبية الموثوقة',
            'home.feature1Title': 'مساعد ذكي على مدار الساعة',
            'home.feature1Desc': 'اسأل عن أقرب عيادة أو صيدلية أو استشر حول الأعراض، وسيرشدك المساعد فوراً.',
            'home.feature2Title': 'أطباء موثوقون',
            'home.feature2Desc': 'تصفح الأطباء حسب التخصص، وشاهد التقييمات وساعات العمل قبل الحجز.',
            'home.feature3Title': 'عيادات ومستشفيات قريبة',
            'home.feature3Desc': 'ابحث عن أقرب مرفق طبي على الخريطة، مع الاتجاهات وأرقام التواصل.',
            'home.feature4Title': 'أدوات صحية ذكية',
            'home.feature4Desc': 'فحص الأعراض، التحقق من تداخل الأدوية، وتلخيص التقارير الطبية.',
            'home.tryNow': 'جرّب الآن',
            'home.browse': 'تصفح',
            'home.comingSoon': 'قريباً',
            'home.ctaTitle': 'ابدأ رحلتك الصحية اليوم',
            'home.ctaSubtitle': 'أنشئ حساباً مجانياً لحفظ محادثاتك والوصول السريع لأطبائك المفضلين',

            // Find Doctors
            'doctors.title': 'الأطباء',
            'doctors.subtitle': 'ابحث عن الطبيب المناسب لاحتياجك الصحي',
            'doctors.searchPlaceholder': 'ابحث بالاسم...',
            'doctors.filters': 'تصفية',
            'doctors.specialtyAll': 'كل التخصصات',
            'doctors.yearsExp': 'سنة خبرة',
            'doctors.viewProfile': 'عرض الملف',
            'doctors.accepting': 'يستقبل مرضى جدد',
            'doctors.notAccepting': 'لا يستقبل حالياً',
            'doctors.empty': 'لم يتم العثور على أطباء مطابقين',
            'doctors.error': 'تعذر تحميل قائمة الأطباء',

            // Doctor profile
            'doctor.notFound': 'الطبيب غير موجود',
            'doctor.about': 'نبذة',
            'doctor.availability': 'مواعيد الدوام',
            'doctor.clinics': 'العيادات',
            'doctor.reviews': 'التقييمات',
            'doctor.noReviews': 'لا توجد تقييمات بعد',
            'doctor.noAvailability': 'لا توجد مواعيد متاحة حالياً',
            'doctor.consultationFee': 'رسوم الكشف',
            'doctor.experience': 'الخبرة',
            'doctor.license': 'رقم الترخيص',
            'doctor.closed': 'مغلق',
            'doctor.backToList': 'العودة لقائمة الأطباء',

            // Find Clinics
            'clinics.title': 'العيادات والمراكز الطبية',
            'clinics.subtitle': 'اعثر على أقرب مرفق طبي إليك',
            'clinics.searchPlaceholder': 'ابحث بالاسم...',
            'clinics.nearMe': 'بالقرب مني',
            'clinics.locating': 'جارٍ تحديد موقعك...',
            'clinics.viewDetails': 'عرض التفاصيل',
            'clinics.empty': 'لم يتم العثور على نتائج',
            'clinics.error': 'تعذر تحميل قائمة العيادات',
            'clinics.typeAll': 'الكل',

            // Clinic profile
            'clinic.notFound': 'العيادة غير موجودة',
            'clinic.hours': 'ساعات العمل',
            'clinic.services': 'الخدمات',
            'clinic.insurance': 'شركات التأمين المقبولة',
            'clinic.doctors': 'الأطباء',
            'clinic.getDirections': 'الاتجاهات',
            'clinic.noDoctors': 'لا يوجد أطباء مسجلون حالياً',
            'clinic.backToList': 'العودة لقائمة العيادات',
            'clinic.verified': 'موثقة',

            // Days of week
            'day.sun': 'الأحد',
            'day.mon': 'الإثنين',
            'day.tue': 'الثلاثاء',
            'day.wed': 'الأربعاء',
            'day.thu': 'الخميس',
            'day.fri': 'الجمعة',
            'day.sat': 'السبت',

            // Common
            'common.loading': 'جارٍ التحميل...',
            'common.retry': 'إعادة المحاولة',
            'common.page': 'صفحة',

            // AI Tools — shared
            'aitools.disclaimer': 'هذه الأداة لا تُقدّم تشخيصاً طبياً ولا تُغني عن استشارة الطبيب. في حال وجود أعراض خطيرة أو حالة طارئة، توجّه فوراً لأقرب مستشفى أو اتصل بالإسعاف.',
            'aitools.loginPrompt': 'سجّل الدخول لحفظ سجل استخدامك لهذه الأداة',
            'aitools.serverError': 'تعذر الوصول إلى خدمة الذكاء الاصطناعي. تأكد من تشغيلها ثم حاول مرة أخرى.',

            // Symptom Checker
            'symptomChecker.title': 'فحص الأعراض',
            'symptomChecker.subtitle': 'أدخل أعراضك وسنساعدك في معرفة التخصص الطبي المناسب',
            'symptomChecker.inputPlaceholder': 'اكتب عرضاً واضغط Enter، مثال: صداع',
            'symptomChecker.addBtn': 'إضافة',
            'symptomChecker.quickChipsLabel': 'أعراض شائعة',
            'symptomChecker.submit': 'فحص الأعراض',
            'symptomChecker.loadingText': 'جارِ تحليل الأعراض...',
            'symptomChecker.errorMinSymptoms': 'يرجى إضافة عرض واحد على الأقل',
            'symptomChecker.emergencyTitle': 'حالة طارئة محتملة',
            'symptomChecker.emergencyMsg': 'توجّه فوراً إلى أقرب غرفة طوارئ أو اتصل بالإسعاف. لا تنتظر.',
            'symptomChecker.urgentTitle': 'يُنصح بموعد عاجل',
            'symptomChecker.routineTitle': 'يُنصح بموعد عادي',
            'symptomChecker.recommendedSpecialty': 'التخصص المقترح',
            'symptomChecker.confidence': 'درجة الثقة',
            'symptomChecker.recommendations': 'التوصيات',
            'symptomChecker.findSpecialist': 'ابحث عن أطباء هذا التخصص',
            'symptomChecker.checkAnother': 'فحص أعراض أخرى',

            // Drug Interaction Checker
            'drugChecker.title': 'التحقق من تداخل الأدوية',
            'drugChecker.subtitle': 'أضف الأدوية التي تتناولها للتحقق من وجود تداخلات محتملة بينها',
            'drugChecker.inputPlaceholder': 'اكتب اسم الدواء واضغط Enter',
            'drugChecker.quickChipsLabel': 'أدوية شائعة',
            'drugChecker.submit': 'التحقق من التداخلات',
            'drugChecker.loadingText': 'جارِ التحقق من التداخلات...',
            'drugChecker.errorMinMeds': 'يرجى إضافة دوائين على الأقل للمقارنة',
            'drugChecker.noInteractionsTitle': 'لا توجد تداخلات معروفة',
            'drugChecker.noInteractionsDesc': 'لم يتم العثور على تداخلات معروفة بين الأدوية المدخلة',
            'drugChecker.severitySevere': 'خطير',
            'drugChecker.severityModerate': 'متوسط',
            'drugChecker.severityMild': 'بسيط',
            'drugChecker.severityUnknown': 'غير محدد',
            'drugChecker.checkAnother': 'فحص أدوية أخرى',
            'drugChecker.disclaimer': 'استشر الصيدلاني أو الطبيب دائماً قبل إجراء أي تغيير على أدويتك.',

            // Report Summarizer
            'reportSummary.title': 'تلخيص التقارير الطبية',
            'reportSummary.subtitle': 'ارفع تقريرك الطبي (PDF أو صورة) للحصول على ملخص فوري بالعربية والإنجليزية',
            'reportSummary.dropzoneTitle': 'اسحب الملف هنا أو انقر للاختيار',
            'reportSummary.dropzoneHint': 'PDF أو صورة (JPG, PNG) — حتى 10 ميجابايت',
            'reportSummary.chooseFile': 'اختيار ملف',
            'reportSummary.remove': 'إزالة',
            'reportSummary.submit': 'تلخيص التقرير',
            'reportSummary.loadingText': 'جارِ استخراج النص وإنشاء الملخص...',
            'reportSummary.loadingHint': 'قد تستغرق هذه العملية من 30 إلى 60 ثانية',
            'reportSummary.tabAr': 'بالعربية',
            'reportSummary.tabEn': 'بالإنجليزية',
            'reportSummary.extractedTextToggle': 'عرض النص المستخرج',
            'reportSummary.summarizeAnother': 'تلخيص تقرير آخر',
            'reportSummary.errorFileType': 'نوع الملف غير مدعوم. الأنواع المدعومة: PDF, JPG, PNG',
            'reportSummary.errorFileSize': 'حجم الملف كبير جداً (الحد الأقصى 10 ميجابايت)',
            'reportSummary.disclaimer': 'هذا الملخص للاسترشاد فقط ولا يُغني عن مراجعة طبيبك للتقرير الأصلي.',

            // Profile page
            'profile.title': 'حسابي',
            'profile.subtitle': 'إدارة معلوماتك الشخصية وإعدادات حسابك',
            'profile.memberSince': 'عضو منذ',
            'profile.changePhoto': 'تغيير الصورة',
            'profile.avatarHint': 'JPG أو PNG — حتى 2 ميجابايت',
            'profile.avatarError': 'تعذر رفع الصورة. تأكد أن حجمها أقل من 2 ميجابايت.',
            'profile.sectionInfo': 'المعلومات الشخصية',
            'profile.address': 'العنوان',
            'profile.addressPlaceholder': 'الحي، الشارع...',
            'profile.city': 'المدينة',
            'profile.cityPlaceholder': 'نابلس',
            'profile.saveChanges': 'حفظ التغييرات',
            'profile.saveSuccess': 'تم حفظ التغييرات بنجاح',
            'profile.saveError': 'تعذر حفظ التغييرات، حاول مرة أخرى',
            'profile.sectionLanguage': 'لغة الواجهة',
            'profile.languageDesc': 'تُطبَّق فوراً وتُحفظ لحسابك',
            'profile.languageAr': 'العربية',
            'profile.languageEn': 'English',
            'profile.sectionPassword': 'تغيير كلمة المرور',
            'profile.passwordDesc': 'سيتم تسجيل خروجك من كل الأجهزة بعد تغيير كلمة المرور، وستحتاج لتسجيل الدخول من جديد.',
            'profile.currentPassword': 'كلمة المرور الحالية',
            'profile.newPassword': 'كلمة المرور الجديدة',
            'profile.changePassword': 'تغيير كلمة المرور',
            'profile.passwordChanged': 'تم تغيير كلمة المرور بنجاح. سيتم تحويلك لتسجيل الدخول من جديد...',
            'profile.errorRequired': 'يرجى ملء جميع الحقول المطلوبة',
            'profile.loadError': 'تعذر تحميل بيانات حسابك',

            // Dashboard
            'dashboard.welcomeBack': 'مرحباً بعودتك،',
            'dashboard.subtitle': 'إليك نظرة سريعة على حسابك',
            'dashboard.quickActions': 'إجراءات سريعة',
            'dashboard.recentConversations': 'المحادثات الأخيرة',
            'dashboard.newChat': 'محادثة جديدة',
            'dashboard.profileCompleteness': 'اكتمال الملف الشخصي',
            'dashboard.completeProfile': 'إكمال الملف الشخصي',
            'dashboard.savedPlaces': 'الأماكن المحفوظة',
            'dashboard.comingSoon': 'قريباً',
            'dashboard.appointments': 'المواعيد',
            'dashboard.prescriptions': 'الوصفات الطبية',
            'dashboard.medicalRecords': 'السجلات الطبية',
            'dashboard.errorLoad': 'تعذر تحميل بيانات لوحة التحكم'
        },
        en: {
            'brand.tagline': 'Smart Healthcare AI',
            'search.placeholder': 'Search clinic, pharmacy, specialty...',
            'filter.all': 'All',
            'filter.clinic': 'Clinics',
            'filter.pharmacy': 'Pharmacies',
            'filter.hospital': 'Hospitals',
            'filter.doctor': 'Doctors',
            'meta.results': 'Results',
            'chat.title': 'MedOrbit Assistant',
            'chat.subtitle': 'Online',
            'chat.placeholder': 'Ask about the nearest clinic, pharmacy, or doctor...',
            'send': 'Send',
            'locate': 'My location',
            'theme': 'Theme',
            'language': 'العربية',
            'newChat': 'New chat',
            'shareLocation': 'Share my location',
            'map.statusDefault': 'Locate yourself or ask about the nearest clinic',
            'map.emptyTitle': 'No results yet',
            'map.emptyDesc': 'Ask the assistant about the nearest clinic or pharmacy and results will appear here',
            'recenter': 'Recenter',
            'layers': 'Toggle layers',
            'fitAll': 'Fit all',

            // Navigation
            'nav.home': 'Home',
            'nav.chat': 'Chat',
            'nav.doctors': 'Doctors',
            'nav.clinics': 'Clinics',
            'nav.aiTools': 'AI Tools',
            'nav.symptomChecker': 'Symptom Checker',
            'nav.drugChecker': 'Drug Interactions',
            'nav.reportSummary': 'Report Summarizer',
            'nav.account': 'Account',
            'nav.dashboard': 'Dashboard',

            // Auth
            'auth.login': 'Log in',
            'auth.register': 'Sign up',
            'auth.logout': 'Log out',

            // Footer
            'footer.tagline': 'Smart healthcare platform for Nablus',
            'footer.rights': 'All rights reserved',

            // Auth pages
            'auth.loginTitle': 'Log in',
            'auth.loginSubtitle': 'Welcome back — log in to your account',
            'auth.registerTitle': 'Create your account',
            'auth.registerSubtitle': 'Join MedOrbit and start your health journey',
            'auth.forgotTitle': 'Forgot your password?',
            'auth.forgotSubtitle': "Enter your email and we'll send you a reset link",
            'auth.resetTitle': 'Reset your password',
            'auth.resetSubtitle': 'Enter a new password for your account',
            'auth.verifyTitle': 'Email verification',
            'auth.orDivider': 'or',
            'auth.email': 'Email',
            'auth.emailPlaceholder': 'example@medorbit.com',
            'auth.password': 'Password',
            'auth.passwordPlaceholder': 'Enter your password',
            'auth.newPassword': 'New password',
            'auth.newPasswordPlaceholder': 'At least 8 characters',
            'auth.pwHint': 'Uppercase + lowercase + number + special character (min 8 characters)',
            'auth.firstNameAr': 'First name (Arabic)',
            'auth.lastNameAr': 'Last name (Arabic)',
            'auth.firstNameEn': 'First name (English)',
            'auth.lastNameEn': 'Last name (English)',
            'auth.phone': 'Phone number',
            'auth.phonePlaceholder': '+970-59-1234567',
            'auth.gender': 'Gender',
            'auth.genderMale': 'Male',
            'auth.genderFemale': 'Female',
            'auth.submitLogin': 'Log in',
            'auth.submitRegister': 'Create account',
            'auth.submitForgot': 'Send reset link',
            'auth.submitReset': 'Set new password',
            'auth.noAccount': "Don't have an account?",
            'auth.haveAccount': 'Already have an account?',
            'auth.forgotPassword': 'Forgot password?',
            'auth.backToLogin': 'Back to login',
            'auth.verify.checking': 'Verifying your email...',
            'auth.resend.title': "Didn't get a verification link?",
            'auth.resend.submit': 'Resend verification link',

            // Conversation sidebar
            'sidebar.newChat': 'New chat',
            'sidebar.searchPlaceholder': 'Search conversations...',
            'sidebar.toggle': 'Conversation history',

            // Home / landing page
            'home.badge': 'Nablus, Palestine',
            'home.heroTitle': 'Smart healthcare, <span>right</span> at your fingertips',
            'home.heroSubtitle': 'Find the nearest doctor, clinic, or pharmacy, chat with our AI assistant, and get trustworthy medical answers — all in one place.',
            'home.startChat': 'Start chatting',
            'home.goToDashboard': 'Go to Dashboard',
            'home.searchPlaceholder': 'Search doctor, specialty, or clinic...',
            'home.searchDoctors': 'Doctors',
            'home.searchClinics': 'Clinics',
            'home.featuresTitle': 'Everything you need for better healthcare',
            'home.featuresSubtitle': 'One platform combining AI and trustworthy medical data',
            'home.feature1Title': '24/7 smart assistant',
            'home.feature1Desc': 'Ask about the nearest clinic or pharmacy, or get guidance on your symptoms instantly.',
            'home.feature2Title': 'Trusted doctors',
            'home.feature2Desc': 'Browse doctors by specialty, check ratings and working hours before booking.',
            'home.feature3Title': 'Nearby clinics & hospitals',
            'home.feature3Desc': 'Find the nearest medical facility on the map, with directions and contact numbers.',
            'home.feature4Title': 'Smart health tools',
            'home.feature4Desc': 'Symptom checker, drug interaction checker, and medical report summarizer.',
            'home.tryNow': 'Try it now',
            'home.browse': 'Browse',
            'home.comingSoon': 'Coming soon',
            'home.ctaTitle': 'Start your health journey today',
            'home.ctaSubtitle': 'Create a free account to save your conversations and quickly reach your favorite doctors',

            // Find Doctors
            'doctors.title': 'Doctors',
            'doctors.subtitle': 'Find the right doctor for your healthcare needs',
            'doctors.searchPlaceholder': 'Search by name...',
            'doctors.filters': 'Filters',
            'doctors.specialtyAll': 'All specialties',
            'doctors.yearsExp': 'yrs experience',
            'doctors.viewProfile': 'View profile',
            'doctors.accepting': 'Accepting new patients',
            'doctors.notAccepting': 'Not currently accepting',
            'doctors.empty': 'No matching doctors found',
            'doctors.error': 'Could not load the doctors list',

            // Doctor profile
            'doctor.notFound': 'Doctor not found',
            'doctor.about': 'About',
            'doctor.availability': 'Weekly Schedule',
            'doctor.clinics': 'Clinics',
            'doctor.reviews': 'Reviews',
            'doctor.noReviews': 'No reviews yet',
            'doctor.noAvailability': 'No availability set right now',
            'doctor.consultationFee': 'Consultation fee',
            'doctor.experience': 'Experience',
            'doctor.license': 'License number',
            'doctor.closed': 'Closed',
            'doctor.backToList': 'Back to doctors',

            // Find Clinics
            'clinics.title': 'Clinics & Medical Centers',
            'clinics.subtitle': 'Find the nearest medical facility to you',
            'clinics.searchPlaceholder': 'Search by name...',
            'clinics.nearMe': 'Near me',
            'clinics.locating': 'Locating you...',
            'clinics.viewDetails': 'View details',
            'clinics.empty': 'No results found',
            'clinics.error': 'Could not load the clinics list',
            'clinics.typeAll': 'All',

            // Clinic profile
            'clinic.notFound': 'Clinic not found',
            'clinic.hours': 'Working Hours',
            'clinic.services': 'Services',
            'clinic.insurance': 'Accepted Insurance',
            'clinic.doctors': 'Doctors',
            'clinic.getDirections': 'Get Directions',
            'clinic.noDoctors': 'No doctors registered yet',
            'clinic.backToList': 'Back to clinics',
            'clinic.verified': 'Verified',

            // Days of week
            'day.sun': 'Sunday',
            'day.mon': 'Monday',
            'day.tue': 'Tuesday',
            'day.wed': 'Wednesday',
            'day.thu': 'Thursday',
            'day.fri': 'Friday',
            'day.sat': 'Saturday',

            // Common
            'common.loading': 'Loading...',
            'common.retry': 'Retry',
            'common.page': 'Page',

            // AI Tools — shared
            'aitools.disclaimer': 'This tool does not provide a medical diagnosis and is not a substitute for seeing a doctor. If you have severe symptoms or a medical emergency, go to the nearest emergency room or call an ambulance immediately.',
            'aitools.loginPrompt': 'Log in to save your history for this tool',
            'aitools.serverError': 'Could not reach the AI service. Make sure it is running, then try again.',

            // Symptom Checker
            'symptomChecker.title': 'Symptom Checker',
            'symptomChecker.subtitle': 'Enter your symptoms and we\'ll help you find the right specialty',
            'symptomChecker.inputPlaceholder': 'Type a symptom and press Enter, e.g. headache',
            'symptomChecker.addBtn': 'Add',
            'symptomChecker.quickChipsLabel': 'Common symptoms',
            'symptomChecker.submit': 'Check symptoms',
            'symptomChecker.loadingText': 'Analyzing your symptoms...',
            'symptomChecker.errorMinSymptoms': 'Please add at least one symptom',
            'symptomChecker.emergencyTitle': 'Possible emergency',
            'symptomChecker.emergencyMsg': 'Go to the nearest emergency room or call an ambulance immediately. Do not wait.',
            'symptomChecker.urgentTitle': 'Urgent appointment recommended',
            'symptomChecker.routineTitle': 'Routine appointment recommended',
            'symptomChecker.recommendedSpecialty': 'Recommended specialty',
            'symptomChecker.confidence': 'Confidence',
            'symptomChecker.recommendations': 'Recommendations',
            'symptomChecker.findSpecialist': 'Find doctors in this specialty',
            'symptomChecker.checkAnother': 'Check other symptoms',

            // Drug Interaction Checker
            'drugChecker.title': 'Drug Interaction Checker',
            'drugChecker.subtitle': 'Add the medications you take to check for potential interactions between them',
            'drugChecker.inputPlaceholder': 'Type a medication name and press Enter',
            'drugChecker.quickChipsLabel': 'Common medications',
            'drugChecker.submit': 'Check interactions',
            'drugChecker.loadingText': 'Checking for interactions...',
            'drugChecker.errorMinMeds': 'Please add at least two medications to compare',
            'drugChecker.noInteractionsTitle': 'No known interactions',
            'drugChecker.noInteractionsDesc': 'No known interactions were found between the entered medications',
            'drugChecker.severitySevere': 'Severe',
            'drugChecker.severityModerate': 'Moderate',
            'drugChecker.severityMild': 'Mild',
            'drugChecker.severityUnknown': 'Unknown',
            'drugChecker.checkAnother': 'Check other medications',
            'drugChecker.disclaimer': 'Always consult a pharmacist or doctor before making any change to your medications.',

            // Report Summarizer
            'reportSummary.title': 'Medical Report Summarizer',
            'reportSummary.subtitle': 'Upload your medical report (PDF or image) for an instant bilingual summary',
            'reportSummary.dropzoneTitle': 'Drag a file here or click to choose',
            'reportSummary.dropzoneHint': 'PDF or image (JPG, PNG) — up to 10MB',
            'reportSummary.chooseFile': 'Choose file',
            'reportSummary.remove': 'Remove',
            'reportSummary.submit': 'Summarize report',
            'reportSummary.loadingText': 'Extracting text and generating summary...',
            'reportSummary.loadingHint': 'This can take 30-60 seconds',
            'reportSummary.tabAr': 'Arabic',
            'reportSummary.tabEn': 'English',
            'reportSummary.extractedTextToggle': 'Show extracted text',
            'reportSummary.summarizeAnother': 'Summarize another report',
            'reportSummary.errorFileType': 'Unsupported file type. Supported: PDF, JPG, PNG',
            'reportSummary.errorFileSize': 'File is too large (10MB max)',
            'reportSummary.disclaimer': 'This summary is for guidance only and does not replace your doctor\'s review of the original report.',

            // Profile page
            'profile.title': 'My Account',
            'profile.subtitle': 'Manage your personal information and account settings',
            'profile.memberSince': 'Member since',
            'profile.changePhoto': 'Change photo',
            'profile.avatarHint': 'JPG or PNG — up to 2MB',
            'profile.avatarError': 'Could not upload the photo. Make sure it is under 2MB.',
            'profile.sectionInfo': 'Personal Information',
            'profile.address': 'Address',
            'profile.addressPlaceholder': 'Neighborhood, street...',
            'profile.city': 'City',
            'profile.cityPlaceholder': 'Nablus',
            'profile.saveChanges': 'Save changes',
            'profile.saveSuccess': 'Changes saved successfully',
            'profile.saveError': 'Could not save changes, please try again',
            'profile.sectionLanguage': 'Interface Language',
            'profile.languageDesc': 'Applied immediately and saved to your account',
            'profile.languageAr': 'العربية',
            'profile.languageEn': 'English',
            'profile.sectionPassword': 'Change Password',
            'profile.passwordDesc': 'You will be signed out of all devices after changing your password, and will need to log in again.',
            'profile.currentPassword': 'Current password',
            'profile.newPassword': 'New password',
            'profile.changePassword': 'Change password',
            'profile.passwordChanged': 'Password changed successfully. Redirecting you to log in again...',
            'profile.errorRequired': 'Please fill in all required fields',
            'profile.loadError': 'Could not load your account data',

            // Dashboard
            'dashboard.welcomeBack': 'Welcome back,',
            'dashboard.subtitle': "Here's a quick look at your account",
            'dashboard.quickActions': 'Quick actions',
            'dashboard.recentConversations': 'Recent conversations',
            'dashboard.newChat': 'New chat',
            'dashboard.profileCompleteness': 'Profile completeness',
            'dashboard.completeProfile': 'Complete your profile',
            'dashboard.savedPlaces': 'Saved places',
            'dashboard.comingSoon': 'Coming soon',
            'dashboard.appointments': 'Appointments',
            'dashboard.prescriptions': 'Prescriptions',
            'dashboard.medicalRecords': 'Medical records',
            'dashboard.errorLoad': 'Could not load your dashboard data'
        }
    };

    let current = Store.getLang() || 'ar';

    function t(key) {
        return (dict[current] && dict[current][key]) || key;
    }

    function apply() {
        document.documentElement.lang = current;
        document.documentElement.dir = current === 'ar' ? 'rtl' : 'ltr';
        document.body.lang = current;

        const setText = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
        const setPlaceholder = (id, val) => { const el = document.getElementById(id); if (el) el.placeholder = val; };
        const setTitle = (id, val) => { const el = document.getElementById(id); if (el) el.title = val; };

        setText('chatTitle', t('chat.title'));
        setText('chatSubtitle', t('chat.subtitle'));
        setPlaceholder('chatInput', t('chat.placeholder'));
        setPlaceholder('quickSearch', t('search.placeholder'));

        ['sendBtn', 'locateBtn', 'themeToggle', 'langToggle', 'clearChatBtn', 'locationBtn', 'recenterBtn', 'layerBtn', 'fitAllBtn']
            .forEach(id => setTitle(id, t(document.getElementById(id)?.dataset?.i18nTitle || id)));

        // Translate all data-i18n elements
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            const text = t(key);
            if (text) el.textContent = text;
        });

        // Translate placeholders
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            const text = t(key);
            if (text) el.placeholder = text;
        });

        // Translate rich-text elements (dictionary value may contain inline markup,
        // e.g. a styled <span> inside a heading) — developer-controlled, not user input.
        document.querySelectorAll('[data-i18n-html]').forEach(el => {
            const key = el.getAttribute('data-i18n-html');
            const html = t(key);
            if (html) el.innerHTML = html;
        });

        const langLabel = document.getElementById('langLabel');
        if (langLabel) langLabel.textContent = current === 'ar' ? 'EN' : 'AR';

        Store.setLang(current);
        window.dispatchEvent(new CustomEvent('languageChanged', { detail: { lang: current } }));
    }

    function toggle() {
        current = current === 'ar' ? 'en' : 'ar';
        apply();
    }

    function setLang(lang) {
        current = lang === 'en' ? 'en' : 'ar';
        apply();
    }

    function getLang() {
        return current;
    }

    return { apply, toggle, setLang, getLang, t };
})();
