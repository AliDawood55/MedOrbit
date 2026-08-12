/**
 * MedOrbit v2 - Book Appointment
 * 3-step wizard: doctor -> time slot -> confirm.
 * GET /api/doctors/:id (profile + clinics), GET /api/appointments/available-slots
 * (returns exact server-derived slots after blocks/bookings are removed), and
 * POST /api/appointments to book. Submit is revalidated transactionally and
 * SLOT_BUSY refreshes the selected date when another patient wins the slot.
 */
const BookAppointment = (() => {

    const state = {
        doctorId: null,
        doctor: null,
        clinics: [],
        clinic: null,
        date: null,
        slot: null
    };

    let searchTimeout = null;
    let searchAbort = null;
    let lastSlots = [];

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function name(d, arKey, enKey) {
        const ar = isAr();
        return ((ar ? d[arKey] : d[enKey]) || d[arKey] || d[enKey] || '').trim();
    }

    function doctorName(d) {
        const full = (name(d, 'first_name_ar', 'first_name_en') + ' ' + name(d, 'last_name_ar', 'last_name_en')).trim();
        return full || d.email || '';
    }

    function getDoctorIdFromUrl() {
        return new URLSearchParams(window.location.search).get('doctorId');
    }

    // ================= DATE/TIME HELPERS =================

    function pad2(n) {
        return String(n).padStart(2, '0');
    }

    function dateKey(d) {
        return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    }

    function todayKey() {
        return dateKey(new Date());
    }

    function timeToMinutes(t) {
        const parts = String(t).split(':').map(Number);
        return parts[0] * 60 + (parts[1] || 0);
    }

    function minutesToHHMM(mins) {
        return pad2(Math.floor(mins / 60)) + ':' + pad2(mins % 60);
    }

    function normalizeServerSlots(rows) {
        const seen = new Set();
        const slots = [];

        (rows || []).forEach((row) => {
            const startM = timeToMinutes(row.start_time);
            const endM = timeToMinutes(row.end_time);
            const duration = Number(row.duration_minutes ?? row.slot_duration);
            if (!Number.isInteger(startM) || !Number.isInteger(endM)
                || !Number.isInteger(duration) || duration <= 0
                || endM - startM !== duration) return;

            const telemedicine = row.appointment_type
                ? row.appointment_type === 'telemedicine'
                : Boolean(row.is_telemedicine);
            const key = startM + '|' + endM + '|' + duration + '|' + (telemedicine ? 1 : 0);
            if (seen.has(key)) return;
            seen.add(key);

            slots.push({
                startMinutes: startM,
                startDisplay: minutesToHHMM(startM),
                endDisplay: minutesToHHMM(endM),
                startFull: minutesToHHMM(startM) + ':00',
                endFull: minutesToHHMM(endM) + ':00',
                duration,
                telemedicine,
                clinicId: row.clinic_id || null
            });
        });

        slots.sort((a, b) => a.startMinutes - b.startMinutes);
        return slots;
    }

    // ================= STEP NAVIGATION =================

    function goToStep(n) {
        document.querySelectorAll('.wizard-step').forEach((el) => {
            const step = Number(el.dataset.step);
            el.classList.toggle('active', step === n);
            el.classList.toggle('done', step < n);
        });
        document.querySelectorAll('.wizard-panel').forEach((el) => {
            el.classList.toggle('active', Number(el.dataset.panel) === n);
        });
    }

    // ================= STEP 1: DOCTOR =================

    async function loadDoctorById(id) {
        state.doctorId = id;

        document.getElementById('wizardLoading').classList.remove('hidden');
        document.getElementById('wizardError').classList.add('hidden');
        document.getElementById('wizardNotFound').classList.add('hidden');
        document.getElementById('wizardBody').classList.add('hidden');

        try {
            const res = await API.doctors.get(id, { auth: false });
            setDoctor(res.data.doctor, res.data.clinics || []);
            document.getElementById('wizardLoading').classList.add('hidden');
            document.getElementById('wizardBody').classList.remove('hidden');
        } catch (err) {
            console.error('BookAppointment: failed to load doctor', err);
            document.getElementById('wizardLoading').classList.add('hidden');
            if (err.status === 404) {
                document.getElementById('wizardNotFound').classList.remove('hidden');
            } else {
                document.getElementById('wizardError').classList.remove('hidden');
            }
        }
    }

    function setDoctor(doctor, clinics) {
        state.doctor = doctor;
        state.clinics = clinics;
        state.clinic = null;
        state.slot = null;

        document.getElementById('doctorPickerWrap').classList.add('hidden');
        document.getElementById('selectedDoctorWrap').classList.remove('hidden');
        renderSelectedDoctor();
    }

    function renderSelectedDoctor() {
        const d = state.doctor;
        if (!d) return;

        const initial = (doctorName(d) || '?').trim().charAt(0).toUpperCase();
        document.getElementById('selectedDoctorAvatar').innerHTML = d.profile_image_url
            ? '<img src="' + escapeHtml(API.assetUrl(d.profile_image_url)) + '" alt="">'
            : escapeHtml(initial);
        document.getElementById('selectedDoctorName').textContent = doctorName(d);
        document.getElementById('selectedDoctorSpecialty').textContent = name(d, 'specialty_ar', 'specialty_en');
        const accepting = d.is_accepting_patients !== false;
        const closedNote = document.getElementById('bookingClosedNote');
        closedNote.textContent = isAr()
            ? 'هذا الطبيب لا يستقبل حجوزات جديدة حالياً.'
            : 'This doctor is not accepting new bookings right now.';
        closedNote.classList.toggle('hidden', accepting);
        document.getElementById('step1NextBtn').disabled = !accepting;
    }

    function onChangeDoctor() {
        state.doctor = null;
        state.doctorId = null;
        state.clinics = [];
        state.clinic = null;
        state.slot = null;

        document.getElementById('selectedDoctorWrap').classList.add('hidden');
        document.getElementById('bookingClosedNote').classList.add('hidden');
        document.getElementById('doctorPickerWrap').classList.remove('hidden');
        document.getElementById('step1NextBtn').disabled = true;

        const input = document.getElementById('doctorSearchInput');
        if (input) input.value = '';
        renderPickList([]);
    }

    function renderPickItem(d) {
        const initial = (doctorName(d) || '?').trim().charAt(0).toUpperCase();
        const specialty = name(d, 'specialty_ar', 'specialty_en');

        return (
            '<button type="button" class="doctor-pick-item">' +
                '<div class="entity-avatar">' +
                    (d.profile_image_url ? '<img src="' + escapeHtml(API.assetUrl(d.profile_image_url)) + '" alt="">' : escapeHtml(initial)) +
                '</div>' +
                '<div class="doctor-pick-item-body">' +
                    '<div class="doctor-pick-item-name">' + escapeHtml(doctorName(d)) + '</div>' +
                    (specialty ? '<div class="doctor-pick-item-meta">' + escapeHtml(specialty) + '</div>' : '') +
                '</div>' +
            '</button>'
        );
    }

    function renderPickList(doctors) {
        const list = document.getElementById('doctorPickList');
        const empty = document.getElementById('doctorPickEmpty');
        const query = document.getElementById('doctorSearchInput')?.value.trim() || '';

        if (!doctors.length) {
            list.innerHTML = '';
            empty.classList.toggle('hidden', !query);
            return;
        }

        empty.classList.add('hidden');
        list.innerHTML = doctors.map(renderPickItem).join('');
        list.querySelectorAll('.doctor-pick-item').forEach((btn, i) => {
            btn.addEventListener('click', () => loadDoctorById(doctors[i].id));
        });
    }

    async function runDoctorSearch(query) {
        if (searchAbort) searchAbort.abort();
        searchAbort = new AbortController();

        try {
            const res = await API.doctors.list({ search: query, limit: 8 }, { auth: false, signal: searchAbort.signal });
            renderPickList(res?.data?.doctors || []);
        } catch (err) {
            if (err.name === 'AbortError') return;
            console.error('BookAppointment: doctor search failed', err);
            renderPickList([]);
        }
    }

    function onSearchInput(e) {
        clearTimeout(searchTimeout);
        const query = e.target.value.trim();

        if (!query) {
            renderPickList([]);
            return;
        }

        searchTimeout = setTimeout(() => runDoctorSearch(query), 300);
    }

    // ================= STEP 2: TIME SLOT =================

    function setupClinicSelect() {
        const wrap = document.getElementById('clinicFieldBlock');
        const select = document.getElementById('clinicSelect');

        if (state.clinics.length <= 1) {
            state.clinic = state.clinics[0] || null;
            wrap.classList.add('hidden');
            return;
        }

        wrap.classList.remove('hidden');
        select.innerHTML = state.clinics.map((c) =>
            '<option value="' + escapeHtml(c.id) + '">' + escapeHtml(name(c, 'name_ar', 'name_en')) + '</option>'
        ).join('');

        state.clinic = state.clinics[0];
        select.value = state.clinic.id;
        select.onchange = () => {
            state.clinic = state.clinics.find((c) => c.id === select.value) || null;
            loadSlots();
        };
    }

    function renderDatePills() {
        const scroller = document.getElementById('dateScroller');
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        let html = '';
        for (let i = 0; i < 21; i++) {
            const d = new Date(today);
            d.setDate(d.getDate() + i);
            const key = dateKey(d);
            const weekday = d.toLocaleDateString(isAr() ? 'ar' : 'en-US', { weekday: 'short' });
            const active = key === state.date ? ' active' : '';

            html +=
                '<button type="button" class="date-pill' + active + '" data-date="' + key + '">' +
                    '<span>' + escapeHtml(weekday) + '</span>' +
                    '<span class="date-pill-day">' + d.getDate() + '</span>' +
                '</button>';
        }

        scroller.innerHTML = html;
        scroller.querySelectorAll('.date-pill').forEach((btn) => {
            btn.addEventListener('click', () => pickDate(btn.dataset.date));
        });
    }

    function pickDate(key) {
        state.date = key;
        document.querySelectorAll('.date-pill').forEach((btn) => {
            btn.classList.toggle('active', btn.dataset.date === key);
        });
        loadSlots();
    }

    function renderSlotBtn(s) {
        const active = state.slot && state.slot.startMinutes === s.startMinutes ? ' active' : '';
        return (
            '<button type="button" class="slot-btn' + active + '">' +
                '<span>' + s.startDisplay + '</span>' +
                '<span class="slot-btn-type">' + escapeHtml(t(s.telemedicine ? 'appt.typeTelemedicine' : 'appt.typeInPerson')) + '</span>' +
            '</button>'
        );
    }

    function selectSlot(slot, btnEl) {
        state.slot = slot;
        document.querySelectorAll('.slot-btn').forEach((b) => b.classList.remove('active'));
        btnEl.classList.add('active');
        document.getElementById('step2NextBtn').disabled = false;
    }

    // Rebuilds the slot grid markup from already-fetched data (no network
    // call) — used both after a fresh fetch and to re-translate slot labels
    // on a language change without losing the current selection.
    function renderSlotGrid(slots) {
        const grid = document.getElementById('slotGrid');
        grid.innerHTML = slots.map(renderSlotBtn).join('');
        grid.querySelectorAll('.slot-btn').forEach((btn, i) => {
            btn.addEventListener('click', () => selectSlot(slots[i], btn));
        });
    }

    async function loadSlots() {
        state.slot = null;
        lastSlots = [];
        document.getElementById('step2NextBtn').disabled = true;

        if (!state.doctorId || !state.date) return;

        const grid = document.getElementById('slotGrid');
        const empty = document.getElementById('slotsEmpty');
        const loading = document.getElementById('slotsLoading');

        grid.innerHTML = '';
        empty.classList.add('hidden');
        loading.classList.remove('hidden');

        try {
            const res = await API.appointments.availableSlots({
                doctor_id: state.doctorId,
                ...(state.clinic ? { clinic_id: state.clinic.id } : {}),
                date: state.date
            });

            const slots = normalizeServerSlots(res?.data || []);
            loading.classList.add('hidden');

            if (!slots.length) {
                empty.classList.remove('hidden');
                return;
            }

            lastSlots = slots;
            renderSlotGrid(slots);
        } catch (err) {
            console.error('BookAppointment: failed to load available slots', err);
            loading.classList.add('hidden');
            empty.classList.remove('hidden');
        }
    }

    function setupStep2() {
        state.slot = null;
        document.getElementById('step2NextBtn').disabled = true;

        document.getElementById('noClinicsState').classList.add('hidden');
        document.getElementById('dateFieldBlock').classList.remove('hidden');

        setupClinicSelect();
        if (!state.date) state.date = todayKey();
        renderDatePills();
        loadSlots();
    }

    // ================= STEP 3: CONFIRM =================

    function summaryRow(label, value) {
        return '<div class="booking-summary-row"><span class="label">' + escapeHtml(label) + '</span><span class="value">' + value + '</span></div>';
    }

    function renderSummary() {
        const box = document.getElementById('bookingSummary');
        const d = state.doctor;
        const c = state.clinic;
        const s = state.slot;
        if (!d || !s) return;

        const dateObj = new Date(state.date + 'T00:00:00');
        const dateDisplay = dateObj.toLocaleDateString(isAr() ? 'ar' : 'en-US', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
        });

        box.innerHTML =
            summaryRow(t('appt.doctorLabel'), escapeHtml(doctorName(d))) +
            (c && s.clinicId ? summaryRow(t('appt.clinicLabel'), escapeHtml(name(c, 'name_ar', 'name_en'))) : '') +
            summaryRow(t('appt.dateLabel'), escapeHtml(dateDisplay)) +
            summaryRow(t('appt.timeLabel'), escapeHtml(s.startDisplay + ' – ' + s.endDisplay)) +
            summaryRow(t('appt.typeLabel'), escapeHtml(t(s.telemedicine ? 'appt.typeTelemedicine' : 'appt.typeInPerson')));
    }

    async function submit() {
        const btn = document.getElementById('confirmBookBtn');
        const alertBox = document.getElementById('confirmAlert');
        alertBox.className = 'alert';
        alertBox.textContent = '';
        btn.classList.add('loading');

        const body = {
            doctor_id: state.doctorId,
            clinic_id: state.slot.clinicId,
            scheduled_date: state.date,
            start_time: state.slot.startFull,
            end_time: state.slot.endFull,
            duration_minutes: state.slot.duration,
            appointment_type: state.slot.telemedicine ? 'telemedicine' : 'in_person',
            reason_for_visit: document.getElementById('reasonInput').value.trim() || null,
            notes: document.getElementById('notesInput').value.trim() || null
        };

        try {
            const res = await API.appointments.create(body);
            showSuccess(res.data);
        } catch (err) {
            console.error('BookAppointment: booking failed', err);

            if (err.code === 'SLOT_BUSY') {
                if (typeof Toast !== 'undefined') Toast.error(t('bookAppt.errorSlotBusy'));
                goToStep(2);
                loadSlots();
            } else {
                alertBox.classList.add('error');
                alertBox.textContent = t(err.code === 'PATIENT_NOT_FOUND' ? 'bookAppt.errorPatientNotFound' : 'bookAppt.errorGeneric');
            }
        } finally {
            btn.classList.remove('loading');
        }
    }

    function showSuccess(appointment) {
        document.getElementById('wizardBody').classList.add('hidden');
        document.getElementById('wizardSuccess').classList.remove('hidden');
        document.getElementById('successApptNumber').textContent = appointment?.appointment_number || '';
    }

    // ================= INIT =================

    function wireEvents() {
        document.getElementById('doctorSearchInput')?.addEventListener('input', onSearchInput);
        document.getElementById('changeDoctorBtn')?.addEventListener('click', onChangeDoctor);

        document.getElementById('step1NextBtn')?.addEventListener('click', () => {
            goToStep(2);
            setupStep2();
        });

        document.getElementById('step2BackBtn')?.addEventListener('click', () => goToStep(1));

        document.getElementById('step2NextBtn')?.addEventListener('click', () => {
            goToStep(3);
            renderSummary();
        });

        document.getElementById('step3BackBtn')?.addEventListener('click', () => goToStep(2));
        document.getElementById('confirmBookBtn')?.addEventListener('click', submit);

        document.getElementById('wizardRetryBtn')?.addEventListener('click', () => {
            if (state.doctorId) loadDoctorById(state.doctorId);
        });

        document.getElementById('bookAnotherBtn')?.addEventListener('click', () => {
            window.location.href = 'book-appointment.html';
        });
    }

    function init() {
        if (!API.requireAuth()) return;

        wireEvents();

        const doctorId = getDoctorIdFromUrl();
        if (doctorId) {
            loadDoctorById(doctorId);
        } else {
            document.getElementById('wizardLoading').classList.add('hidden');
            document.getElementById('wizardBody').classList.remove('hidden');
        }

        window.addEventListener('languageChanged', () => {
            if (state.doctor) renderSelectedDoctor();

            const step2Active = document.querySelector('.wizard-panel[data-panel="2"]')?.classList.contains('active');
            if (step2Active) {
                renderDatePills();
                if (lastSlots.length) renderSlotGrid(lastSlots);
            }

            const step3Active = document.querySelector('.wizard-panel[data-panel="3"]')?.classList.contains('active');
            if (step3Active && state.slot) renderSummary();
        });
    }

    return { init };

})();
