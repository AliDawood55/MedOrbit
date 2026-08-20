const fs = require('fs');
const path = require('path');

let passed = 0;
let failed = 0;
const read = (relativePath) => fs.readFileSync(path.resolve(__dirname, '..', relativePath), 'utf8');
function check(name, condition) {
    if (condition) { passed += 1; console.log(`  PASS ${name}`); }
    else { failed += 1; console.error(`  FAIL ${name}`); }
}

const html = read('public/my-schedule.html');
const schedule = read('src/js/my-schedule.js');
const scheduleCss = read('src/css/schedule.css');
const api = read('src/js/api.js');
const layout = read('src/js/layout.js');
const dashboard = read('src/js/dashboard.js');
const profileHtml = read('public/doctor-profile-edit.html');
const profile = read('src/js/doctor-profile-edit.js');
const bookingHtml = read('public/book-appointment.html');
const booking = read('src/js/book-appointment.js');
const i18n = read('src/js/i18n.js');

console.log('\nDoctor scheduling UI structural tests\n');
check('dedicated My Schedule page loads the shared design system and controller', /schedule\.css/.test(html) && /my-schedule\.js/.test(html));
check('schedule page is guarded to authenticated doctors', /API\.requireAuth\(\)/.test(schedule) && /role !== 'doctor'/.test(schedule));
check('weekly view renders all seven days and multiple periods', /dayKeys = \['sun','mon','tue','wed','thu','fri','sat'\]/.test(schedule) && /schedule\.weekly\.filter/.test(schedule));
check('availability add edit enable disable and delete controls are wired', /addAvailabilityButton/.test(schedule) && /toggleRule/.test(schedule) && /updateAvailability/.test(schedule) && /deleteAvailability/.test(schedule));
check('clinicless doctors can open online availability while in-person remains clinic-gated',
    !/No active clinic is assigned to your account\. Contact administration before adding bookable times\./.test(schedule)
    && /!rule && !schedule\.clinics\.length[\s\S]{0,80}'telemedicine'/.test(schedule)
    && /CLINIC_REQUIRED/.test(schedule) && /clinic_id: null/.test(schedule));
check('date exceptions expose additional availability block time and day off', /addSpecialButton/.test(html) && /blockTimeButton/.test(html) && /dayOffButton/.test(html));
check('appointment tabs cover today upcoming and past', /data-appointment-tab="today"/.test(html) && /data-appointment-tab="upcoming"/.test(html) && /data-appointment-tab="past"/.test(html));
check('doctor appointment actions are text-only', /Message Patient/.test(schedule) && /direct-messages\.html\?counterpart=/.test(schedule) && !/\b(?:voice|video|webrtc|call)\b/i.test(schedule));
check('patient and clinic display content uses safe DOM text APIs', /name\.textContent = patientName/.test(schedule) && /option\.textContent/.test(schedule) && !/innerHTML/.test(schedule));
check('loading empty conflict and booked-conflict states are implemented', /scheduleLoading/.test(html) && /empty-schedule/.test(schedule) && /AVAILABILITY_OVERLAP/.test(schedule) && /BOOKED_APPOINTMENT_CONFLICT/.test(schedule));
check('schedule copy has Arabic and English localized paths', /هذه الفترة تتداخل/.test(schedule) && /This time overlaps/.test(schedule) && /I18n\.getLang/.test(schedule));
check('responsive layout has desktop tablet and mobile breakpoints', /@media\(max-width:900px\)/.test(scheduleCss) && /@media\(max-width:600px\)/.test(scheduleCss));
check('doctor navigation exposes schedule appointments profile posts messages notifications', /nav\.mySchedule/.test(layout) && /nav\.doctorAppointments/.test(layout) && /nav\.professionalProfile/.test(layout) && /nav\.doctorPosts/.test(layout) && /nav\.messages/.test(layout) && /nav\.notifications/.test(layout));
check('doctor dashboard makes scheduling a direct action', /my-schedule\.html/.test(dashboard) && /doctorOnly/.test(dashboard));
check('professional profile displays verified credentials read-only', /id="verifiedSpecialty" readonly/.test(profileHtml) && /id="verifiedLicense" readonly/.test(profileHtml));
check('professional profile supports avatar and canonical editable fields', /doctorAvatarInput/.test(profileHtml) && /API\.users\.uploadAvatar/.test(profile) && /professionalBio/.test(profile) && /areasOfExpertise/.test(profile));
check('profile and schedule expose bounded duration fee and accepting state', /consultationDuration/.test(profile) && /consultationFee/.test(profile) && /isAcceptingPatients/.test(profile) && /scheduleDuration/.test(html) && /scheduleFee/.test(html));
check('patient booking clearly blocks doctors not accepting appointments', /bookingClosedNote/.test(bookingHtml) && /not accepting new bookings/.test(booking) && /step1NextBtn/.test(booking));
check('patient booking preserves exact server slots without client-side generation', /normalizeServerSlots/.test(booking) && /endM - startM !== duration/.test(booking) && !/for \(let cur/.test(booking));
check('patient booking supports backend-derived clinicless online slots',
    /clinicId: row\.clinic_id \|\| null/.test(booking)
    && /\.\.\.\(state\.clinic \? \{ clinic_id: state\.clinic\.id \} : \{\}\)/.test(booking)
    && /clinic_id: state\.slot\.clinicId/.test(booking)
    && !/if \(!state\.clinics\.length\) \{[\s\S]{0,300}return;/.test(booking));
check('doctor dashboard loads and renders its schedule appointments', /API\.doctors\.mySchedule\(\)/.test(dashboard) && /patientLabel/.test(dashboard) && /my-schedule\.html#appointments/.test(dashboard));
check('frontend API uses only authenticated self-service scheduling endpoints', /\/doctors\/me\/schedule/.test(api) && /\/doctors\/me\/availability/.test(api) && !/doctorId.*me\/availability/.test(api));
check('Arabic and English navigation labels exist for schedule and appointments', (i18n.match(/'nav\.mySchedule'/g) || []).length === 2 && (i18n.match(/'nav\.doctorAppointments'/g) || []).length === 2);

console.log(`\nDoctor scheduling UI: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
