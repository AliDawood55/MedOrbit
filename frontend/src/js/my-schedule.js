const MySchedule = (() => {
    let schedule = null;
    let activeAppointmentTab = 'today';
    const byId = (id) => document.getElementById(id);
    const isAr = () => I18n.getLang() === 'ar';
    const copy = (ar, en) => (isAr() ? ar : en);
    const dayKeys = ['sun','mon','tue','wed','thu','fri','sat'];

    function setCopy(id, ar, en) { byId(id).textContent = copy(ar, en); }

    function localize() {
        const labels = {
            scheduleTitle:['جدولي','My Schedule'],scheduleSubtitle:['أدر ساعات العمل والاستثناءات والمواعيد القادمة.','Manage working hours, date exceptions, and upcoming appointments.'],editProfileLabel:['ملفي المهني','My Profile'],addAvailabilityLabel:['إضافة توفر','Add Availability'],bookingSettingsTitle:['إعدادات الحجز','Booking settings'],bookingSettingsHint:['تؤثر التغييرات على الفترات الجديدة والحجوزات المستقبلية فقط.','Changes affect new availability and future bookings only.'],scheduleAcceptingLabel:['استقبال مواعيد جديدة','Accepting new appointments'],scheduleAcceptingHelp:['عند الإيقاف لن تظهر أوقات قابلة للحجز.','When off, no bookable times are shown.'],scheduleDurationLabel:['مدة الموعد','Appointment duration'],scheduleFeeLabel:['رسوم الاستشارة','Consultation fee'],saveSettingsLabel:['حفظ الإعدادات','Save settings'],weeklyTitle:['الساعات الأسبوعية','Weekly availability'],weeklyHint:['يمكنك إضافة أكثر من فترة في اليوم.','Add multiple non-overlapping periods on a day.'],weeklyAddLabel:['إضافة فترة','Add period'],exceptionsTitle:['الاستثناءات القادمة','Upcoming exceptions'],exceptionsHint:['يوم إجازة أو وقت محظور أو توفر إضافي.','Day off, blocked time, or special additional availability.'],addSpecialLabel:['توفر إضافي','Additional availability'],blockTimeLabel:['حظر وقت','Block Time'],dayOffLabel:['يوم إجازة','Day Off'],scheduleAppointmentsTitle:['مواعيدي','My appointments'],scheduleAppointmentsHint:['المواعيد الحالية منفصلة عن تغييرات ساعات التوفر.','Existing appointments remain separate from availability changes.'],todayTab:['اليوم','Today'],upcomingTab:['القادمة','Upcoming'],pastTab:['السابقة','Past'],ruleWeekdayLabel:['اليوم','Weekday'],ruleDateLabel:['التاريخ','Date'],ruleClinicLabel:['العيادة','Clinic'],ruleModeLabel:['نوع الموعد','Appointment type'],ruleStartLabel:['من','Start'],ruleEndLabel:['إلى','End'],ruleDurationLabel:['مدة الموعد','Appointment duration'],ruleActiveLabel:['مفعّل','Enabled'],cancelRuleButton:['إلغاء','Cancel'],saveRuleLabel:['حفظ','Save']
        };
        Object.entries(labels).forEach(([id, values]) => setCopy(id, values[0], values[1]));
        const mode = byId('ruleMode');
        mode.options[0].textContent = copy('في العيادة','In person');
        mode.options[1].textContent = copy('استشارة عبر الإنترنت','Online Consultation');
        populateWeekdays();
        if (schedule) renderAll();
    }

    function feedback(message, type = 'error', target = 'scheduleFeedback') {
        const node = byId(target);
        node.textContent = message;
        node.className = `page-feedback ${type}`;
    }

    function clearFeedback(target = 'scheduleFeedback') {
        const node = byId(target);
        node.textContent = '';
        node.className = 'page-feedback hidden';
    }

    function scheduleError(err, arFallback, enFallback) {
        const localized = {
            AVAILABILITY_OVERLAP: ['هذه الفترة تتداخل مع فترة توفر أخرى.','This time overlaps another availability period.'],
            BOOKED_APPOINTMENT_CONFLICT: ['يوجد موعد حالي في هذه الفترة. أدر الموعد قبل تغيير التوفر.','An existing appointment uses this time. Manage the appointment before changing availability.'],
            INVALID_TIME_RANGE: ['يجب أن يكون وقت الانتهاء بعد وقت البدء.','End time must be after start time.'],
            INVALID_WEEKDAY: ['اليوم المحدد غير صالح.','The selected weekday is invalid.'],
            CLINIC_NOT_ASSIGNED: ['العيادة غير مخصصة لهذا الحساب.','This clinic is not assigned to your account.'],
            CLINIC_REQUIRED: ['العيادة مطلوبة فقط للتوفر الحضوري. اختر استشارة عبر الإنترنت أو عيادة مخصصة.','A clinic is required only for in-person availability. Choose Online Consultation or an assigned clinic.'],
            DATE_OUTSIDE_HORIZON: ['التاريخ خارج النطاق المسموح.','The date is outside the allowed range.'],
            PAST_DATE: ['لا يمكن إضافة استثناء في تاريخ سابق.','A past-date exception cannot be added.']
        };
        const pair = localized[err?.code];
        return pair ? copy(pair[0], pair[1]) : (isAr() ? arFallback : (err?.message || enFallback));
    }

    function populateWeekdays() {
        const select = byId('ruleWeekday');
        const selected = select.value;
        select.replaceChildren(...dayKeys.map((key, index) => {
            const option = document.createElement('option');
            option.value = String(index);
            option.textContent = I18n.t(`day.${key}`);
            return option;
        }));
        if (selected) select.value = selected;
    }

    function clinicName(id) {
        const clinic = schedule.clinics.find((item) => item.id === id);
        return clinic
            ? ((isAr() ? clinic.name_ar : clinic.name_en) || clinic.name_en || clinic.name_ar || '')
            : '';
    }

    function timeLabel(value) { return String(value || '').slice(0, 5); }

    function iconButton(iconClass, label, action, danger = false) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = danger ? 'danger-icon' : 'icon-btn';
        button.setAttribute('aria-label', label);
        button.title = label;
        const icon = document.createElement('i');
        icon.className = `fas ${iconClass}`;
        button.appendChild(icon);
        button.addEventListener('click', action);
        return button;
    }

    function ruleElement(rule) {
        const row = document.createElement('div');
        row.className = `schedule-rule${rule.is_active ? '' : ' inactive'}`;
        const time = document.createElement('span');
        time.className = 'schedule-rule-time';
        time.textContent = `${timeLabel(rule.start_time)}–${timeLabel(rule.end_time)}`;
        const meta = document.createElement('span');
        meta.className = 'schedule-rule-meta';
        meta.textContent = [clinicName(rule.clinic_id), `${rule.slot_duration} ${copy('د','min')}`, rule.is_telemedicine ? copy('عبر الإنترنت','Online') : copy('في العيادة','In person'), rule.is_active ? '' : copy('متوقف','Disabled')].filter(Boolean).join(' · ');
        const actions = document.createElement('span');
        actions.className = 'schedule-rule-actions';
        actions.append(
            iconButton(rule.is_active ? 'fa-toggle-on' : 'fa-toggle-off', rule.is_active ? copy('تعطيل','Disable') : copy('تفعيل','Enable'), () => toggleRule(rule)),
            iconButton('fa-pen', copy('تعديل','Edit'), () => openRule(rule.availability_type, rule)),
            iconButton('fa-trash', copy('حذف','Delete'), () => removeRule(rule), true)
        );
        row.append(time, meta, actions);
        return row;
    }

    function renderWeekly() {
        const root = byId('weeklySchedule');
        root.replaceChildren(...dayKeys.map((key, index) => {
            const day = document.createElement('div');
            day.className = 'weekday-row';
            const name = document.createElement('div');
            name.className = 'weekday-name';
            name.textContent = I18n.t(`day.${key}`);
            const periods = document.createElement('div');
            periods.className = 'weekday-periods';
            const rules = schedule.weekly.filter((rule) => Number(rule.day_of_week) === index);
            if (rules.length) periods.append(...rules.map(ruleElement));
            else {
                const empty = document.createElement('div');
                empty.className = 'empty-schedule';
                empty.textContent = copy('غير متاح','Not available');
                periods.appendChild(empty);
            }
            day.append(name, periods);
            return day;
        }));
    }

    function dateLabel(value) {
        const date = new Date(`${String(value).slice(0, 10)}T00:00:00`);
        return date.toLocaleDateString(isAr() ? 'ar-EG' : 'en-US', { weekday:'short', year:'numeric', month:'short', day:'numeric' });
    }

    function renderExceptions() {
        const root = byId('exceptionsList');
        const today = new Date();
        today.setHours(0,0,0,0);
        const rules = schedule.overrides.filter((rule) => new Date(`${String(rule.specific_date).slice(0,10)}T00:00:00`) >= today);
        if (!rules.length) {
            const empty = document.createElement('div');
            empty.className = 'empty-schedule';
            empty.textContent = copy('لا توجد استثناءات قادمة.','No upcoming exceptions.');
            root.replaceChildren(empty);
            return;
        }
        root.replaceChildren(...rules.map((rule) => {
            const card = document.createElement('div');
            card.className = `exception-card${rule.is_active ? '' : ' inactive'}`;
            const icon = document.createElement('span');
            icon.className = 'exception-icon';
            const iconNode = document.createElement('i');
            iconNode.className = `fas ${rule.availability_type === 'day_off' ? 'fa-calendar-xmark' : rule.availability_type === 'blocked' ? 'fa-ban' : 'fa-calendar-plus'}`;
            icon.appendChild(iconNode);
            const detail = document.createElement('span');
            detail.className = 'exception-copy';
            const title = document.createElement('strong');
            title.textContent = dateLabel(rule.specific_date);
            const meta = document.createElement('small');
            const type = rule.availability_type === 'day_off' ? copy('يوم إجازة','Day off') : rule.availability_type === 'blocked' ? copy('غير متاح','Unavailable') : copy('توفر إضافي','Additional availability');
            meta.textContent = [type, rule.availability_type === 'day_off' ? '' : `${timeLabel(rule.start_time)}–${timeLabel(rule.end_time)}`, clinicName(rule.clinic_id), rule.is_active ? '' : copy('متوقف','Disabled')].filter(Boolean).join(' · ');
            detail.append(title, meta);
            const actions = document.createElement('span');
            actions.className = 'schedule-rule-actions';
            actions.append(
                iconButton(rule.is_active ? 'fa-toggle-on' : 'fa-toggle-off', rule.is_active ? copy('تعطيل','Disable') : copy('تفعيل','Enable'), () => toggleRule(rule)),
                iconButton('fa-pen', copy('تعديل','Edit'), () => openRule(rule.availability_type, rule)),
                iconButton('fa-trash', copy('حذف','Delete'), () => removeRule(rule), true)
            );
            card.append(icon, detail, actions);
            return card;
        }));
    }

    function dateKey(value) { return String(value).slice(0, 10); }

    function appointmentBucket(appointment) {
        const today = new Date();
        const todayKey = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,'0')}-${String(today.getDate()).padStart(2,'0')}`;
        const date = dateKey(appointment.scheduled_date);
        if (date === todayKey && !['completed','cancelled','no_show'].includes(appointment.status)) return 'today';
        if (date > todayKey && !['completed','cancelled','no_show'].includes(appointment.status)) return 'upcoming';
        return 'past';
    }

    function patientName(appointment) {
        const preferred = isAr()
            ? [appointment.first_name_ar, appointment.last_name_ar]
            : [appointment.first_name_en, appointment.last_name_en];
        const fallback = isAr()
            ? [appointment.first_name_en, appointment.last_name_en]
            : [appointment.first_name_ar, appointment.last_name_ar];
        return preferred.filter(Boolean).join(' ').trim() || fallback.filter(Boolean).join(' ').trim() || copy('مريض','Patient');
    }

    function renderAppointments() {
        document.querySelectorAll('[data-appointment-tab]').forEach((button) => button.classList.toggle('active', button.dataset.appointmentTab === activeAppointmentTab));
        const items = schedule.appointments.filter((item) => appointmentBucket(item) === activeAppointmentTab);
        const root = byId('scheduleAppointments');
        if (!items.length) {
            const empty = document.createElement('div');
            empty.className = 'empty-schedule';
            empty.textContent = copy('لا توجد مواعيد في هذا القسم.','No appointments in this section.');
            root.replaceChildren(empty);
            return;
        }
        root.replaceChildren(...items.map((appointment) => {
            const card = document.createElement('article');
            card.className = 'appointment-card';
            const detail = document.createElement('div');
            const name = document.createElement('strong');
            name.textContent = patientName(appointment);
            const meta = document.createElement('div');
            meta.className = 'appointment-meta';
            meta.textContent = `${dateLabel(appointment.scheduled_date)} · ${timeLabel(appointment.start_time)}–${timeLabel(appointment.end_time)} · ${appointment.appointment_type === 'telemedicine' ? copy('استشارة عبر الإنترنت','Online Consultation') : copy('في العيادة','In person')}`;
            const status = document.createElement('span');
            status.className = 'appointment-status';
            status.textContent = appointment.status;
            detail.append(name, meta, status);
            const actions = document.createElement('div');
            actions.className = 'appointment-actions';
            if (appointment.status === 'scheduled') actions.append(actionButton(copy('تأكيد','Confirm'), () => updateAppointment(appointment.id, 'confirm')));
            if (['confirmed','in_progress'].includes(appointment.status)) actions.append(actionButton(copy('إكمال','Complete'), () => updateAppointment(appointment.id, 'complete')));
            if (appointment.patient_profile_id) {
                const message = document.createElement('a');
                message.className = 'btn btn-secondary btn-sm';
                message.href = `direct-messages.html?counterpart=${encodeURIComponent(appointment.patient_profile_id)}`;
                message.textContent = copy('مراسلة المريض','Message Patient');
                actions.appendChild(message);
            }
            card.append(detail, actions);
            return card;
        }));
    }

    function actionButton(label, action) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'btn btn-primary btn-sm';
        button.textContent = label;
        button.addEventListener('click', action);
        return button;
    }

    function renderAll() {
        byId('scheduleAccepting').checked = Boolean(schedule.doctor.is_accepting_patients);
        byId('scheduleDuration').value = String(schedule.doctor.consultation_duration || 30);
        byId('scheduleFee').value = schedule.doctor.consultation_fee ?? 0;
        renderWeekly();
        renderExceptions();
        renderAppointments();
    }

    function minDate() {
        const now = new Date();
        return `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
    }

    function populateClinicOptions() {
        const select = byId('ruleClinic');
        const noClinic = document.createElement('option');
        noClinic.value = '';
        noClinic.textContent = copy('بدون عيادة — استشارة عبر الإنترنت','No clinic — Online Consultation');
        const options = (schedule?.clinics || []).map((clinic) => {
            const option = document.createElement('option');
            option.value = clinic.id;
            option.textContent = (isAr() ? clinic.name_ar : clinic.name_en) || clinic.name_en || clinic.name_ar || '';
            return option;
        });
        select.replaceChildren(noClinic, ...options);
    }

    function syncClinicRequirement() {
        const available = byId('ruleType').value === 'available';
        const online = byId('ruleMode').value === 'telemedicine';
        const hasClinics = Boolean(schedule?.clinics?.length);
        byId('ruleClinicField').classList.toggle('hidden', !available || (online && !hasClinics));
        byId('ruleClinic').required = available && !online;
        if (available && !online && !byId('ruleClinic').value && hasClinics) {
            byId('ruleClinic').value = schedule.clinics[0].id;
        }
    }

    function openRule(type = 'available', rule = null, dateSpecific = false) {
        clearFeedback('ruleFeedback');
        const isDateRule = dateSpecific || type !== 'available' || Boolean(rule?.specific_date);
        byId('ruleId').value = rule?.id || '';
        byId('ruleType').value = type;
        byId('ruleWeekdayField').classList.toggle('hidden', isDateRule);
        byId('ruleDateField').classList.toggle('hidden', !isDateRule);
        const dayOff = type === 'day_off';
        const available = type === 'available';
        byId('ruleModeField').classList.toggle('hidden', !available);
        byId('ruleStartField').classList.toggle('hidden', dayOff);
        byId('ruleEndField').classList.toggle('hidden', dayOff);
        byId('ruleDurationField').classList.toggle('hidden', !available);
        byId('ruleActiveField').classList.toggle('hidden', !rule);
        byId('ruleWeekday').value = String(rule?.day_of_week ?? 0);
        byId('ruleDate').min = minDate();
        byId('ruleDate').value = rule?.specific_date ? dateKey(rule.specific_date) : minDate();
        byId('ruleClinic').value = rule?.clinic_id || schedule.clinics[0]?.id || '';
        byId('ruleMode').value = rule?.is_telemedicine || (!rule && !schedule.clinics.length) ? 'telemedicine' : 'in_person';
        syncClinicRequirement();
        byId('ruleStart').value = timeLabel(rule?.start_time || '09:00');
        byId('ruleEnd').value = timeLabel(rule?.end_time || '13:00');
        byId('ruleDuration').value = String(rule?.slot_duration || schedule.doctor.consultation_duration || 30);
        byId('ruleActive').checked = rule?.is_active ?? true;
        setCopy('ruleDialogTitle', rule ? 'تعديل الفترة' : type === 'blocked' ? 'حظر وقت' : type === 'day_off' ? 'إضافة يوم إجازة' : isDateRule ? 'توفر إضافي' : 'إضافة توفر', rule ? 'Edit period' : type === 'blocked' ? 'Block time' : type === 'day_off' ? 'Add day off' : isDateRule ? 'Additional availability' : 'Add availability');
        byId('scheduleModal').classList.remove('hidden');
        (isDateRule ? byId('ruleDate') : byId('ruleWeekday')).focus();
    }

    function closeRule() { byId('scheduleModal').classList.add('hidden'); }

    async function saveRule(event) {
        event.preventDefault();
        const id = byId('ruleId').value;
        const type = byId('ruleType').value;
        const dateSpecific = !byId('ruleDateField').classList.contains('hidden');
        const isTelemedicine = byId('ruleMode').value === 'telemedicine';
        const clinicId = byId('ruleClinic').value;
        if (type === 'available' && !isTelemedicine && !clinicId) {
            feedback(copy('التوفر الحضوري يتطلب عيادة نشطة مخصصة. اختر استشارة عبر الإنترنت أو تواصل مع الإدارة.','In-person availability requires an assigned active clinic. Choose Online Consultation or contact administration.'), 'error', 'ruleFeedback');
            return;
        }
        const payload = {
            availability_type: type,
            ...(dateSpecific ? { specific_date: byId('ruleDate').value } : { day_of_week: Number(byId('ruleWeekday').value) }),
            ...(type === 'day_off' ? {} : { start_time: byId('ruleStart').value, end_time: byId('ruleEnd').value }),
            ...(type === 'available' ? { ...(clinicId ? { clinic_id: clinicId } : { clinic_id: null }), slot_duration: Number(byId('ruleDuration').value), is_telemedicine: isTelemedicine } : {}),
            ...(id ? { is_active: byId('ruleActive').checked } : {})
        };
        byId('saveRuleButton').disabled = true;
        try {
            if (id) await API.doctors.updateAvailability(id, payload);
            else await API.doctors.addAvailability(payload);
            closeRule();
            await load();
        } catch (err) {
            feedback(scheduleError(err, 'تعذر حفظ الفترة.', 'Unable to save period.'), 'error', 'ruleFeedback');
        } finally {
            byId('saveRuleButton').disabled = false;
        }
    }

    async function toggleRule(rule) {
        try {
            await API.doctors.updateAvailability(rule.id, { is_active: !rule.is_active });
            await load();
        } catch (err) { feedback(scheduleError(err, 'تعذر تحديث الفترة.', 'Unable to update period.')); }
    }

    async function removeRule(rule) {
        if (!window.confirm(copy('هل تريد حذف هذه الفترة؟','Delete this availability period?'))) return;
        try {
            await API.doctors.deleteAvailability(rule.id);
            await load();
        } catch (err) { feedback(scheduleError(err, 'تعذر حذف الفترة.', 'Unable to delete period.')); }
    }

    async function saveSettings() {
        const button = byId('saveScheduleSettings');
        button.disabled = true;
        clearFeedback();
        try {
            await API.doctors.updateMyProfile({
                isAcceptingPatients: byId('scheduleAccepting').checked,
                consultationDuration: Number(byId('scheduleDuration').value),
                consultationFee: Number(byId('scheduleFee').value || 0)
            });
            feedback(copy('تم حفظ إعدادات الحجز.','Booking settings saved.'), 'success');
            await load(false);
        } catch (err) { feedback(scheduleError(err, 'تعذر حفظ الإعدادات.', 'Unable to save settings.')); }
        finally { button.disabled = false; }
    }

    async function updateAppointment(id, action) {
        try {
            if (action === 'confirm') await API.appointments.confirm(id);
            else await API.appointments.complete(id);
            await load();
        } catch (err) { feedback(scheduleError(err, 'تعذر تحديث الموعد.', 'Unable to update appointment.')); }
    }

    async function load(showLoading = true) {
        if (showLoading) {
            byId('scheduleLoading').classList.remove('hidden');
            byId('scheduleContent').classList.add('hidden');
        }
        try {
            schedule = (await API.doctors.mySchedule()).data;
            populateClinicOptions();
            renderAll();
            byId('scheduleContent').classList.remove('hidden');
        } catch (err) {
            feedback(scheduleError(err, 'تعذر تحميل الجدول.', 'Unable to load schedule.'));
        } finally { byId('scheduleLoading').classList.add('hidden'); }
    }

    async function init() {
        if (!API.requireAuth()) return;
        if (API.getUser()?.role !== 'doctor') { location.href = 'dashboard.html'; return; }
        localize();
        window.addEventListener('languageChanged', localize);
        byId('addAvailabilityButton').addEventListener('click', () => openRule('available'));
        byId('weeklyAddButton').addEventListener('click', () => openRule('available'));
        byId('addSpecialButton').addEventListener('click', () => openRule('available', null, true));
        byId('blockTimeButton').addEventListener('click', () => openRule('blocked', null, true));
        byId('dayOffButton').addEventListener('click', () => openRule('day_off', null, true));
        byId('closeScheduleModal').addEventListener('click', closeRule);
        byId('cancelRuleButton').addEventListener('click', closeRule);
        byId('scheduleModal').addEventListener('click', (event) => { if (event.target === byId('scheduleModal')) closeRule(); });
        document.addEventListener('keydown', (event) => { if (event.key === 'Escape') closeRule(); });
        byId('scheduleRuleForm').addEventListener('submit', saveRule);
        byId('ruleMode').addEventListener('change', syncClinicRequirement);
        byId('saveScheduleSettings').addEventListener('click', saveSettings);
        document.querySelectorAll('[data-appointment-tab]').forEach((button) => button.addEventListener('click', () => { activeAppointmentTab = button.dataset.appointmentTab; renderAppointments(); }));
        await load();
    }

    return { init };
})();
