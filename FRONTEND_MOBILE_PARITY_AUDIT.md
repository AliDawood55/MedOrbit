# MedOrbit Frontend vs Flutter Mobile Parity Audit

## 1. Executive Summary

**Audit date:** 2026-08-05  
**Scope:** read-only comparison of the static web frontend (the stated source of truth), Flutter mobile implementation, and the backend/AI contracts that those clients use. No runtime server, build, database, or external OAuth validation was performed.

The Flutter app has a strong patient-facing foundation: secure token storage and refresh, Arabic/English locale persistence, a shared theme token system, clinic and doctor discovery with OpenStreetMap, chatbot/conversation history with map results, feedback submission, prescriptions, combined records timeline, appointment list/cancellation, and a comparatively mature Virtual Doctor flow.

It is **not yet web-parity complete**. The largest patient-facing gaps are appointment **booking/available slots**, full **notifications**, **profile/settings** editing, the standalone AI symptom/drug/report tools, and the personal **My Reports** view. Entire web role areas are absent on mobile: Patient My Doctor/shared notes, Doctor My Patients/patient detail/notes/posts, and Admin Analytics. There is also no public landing/home route equivalent to `home.html`, and current mobile navigation is patient-only and not role-aware.

The most urgent release blockers are not cosmetic: a hard-coded HTTP LAN address, Android cleartext traffic, debug signing, absent iOS microphone usage text, no AI health preflight, no app-router auth/role redirect, and the chatbot's default 15-second mobile timeout versus the backend's AI-client default 60-second timeout. These must be closed or verified before adding more medical workflows.

Status counts in this report use feature areas rather than files: **18 Missing**, **11 Partial**, **7 Done**, and **1 Different by design / Needs verification combination**. The current code contains **29 web pages**, **41 frontend `src/js` files**, **23 frontend CSS files**, **23 mobile implementation modules**, **25 mobile test files**, and **62 relevant method/path API contracts** (47 backend and 15 AI-service contracts) reviewed.

## 2. Table of Contents

- [1. Executive Summary](#1-executive-summary)
- [2. Table of Contents](#2-table-of-contents)
- [3. Scope and Methodology](#3-scope-and-methodology)
- [4. Web Architecture Summary](#4-web-architecture-summary)
- [5. Web Design System Analysis](#5-web-design-system-analysis)
- [6. Web Page Inventory](#6-web-page-inventory)
- [7. Web API Contract Table](#7-web-api-contract-table)
- [8. Flutter Mobile Implementation Inventory](#8-flutter-mobile-implementation-inventory)
- [9. Feature Parity Matrix](#9-feature-parity-matrix)
- [10. Design Parity Audit](#10-design-parity-audit)
- [11. Missing Mobile Features by Priority](#11-missing-mobile-features-by-priority)
- [12. Required Backend or AI Changes](#12-required-backend-or-ai-changes)
- [13. Recommended Mobile Implementation Phases](#13-recommended-mobile-implementation-phases)
- [14. Testing Strategy](#14-testing-strategy)
- [15. Manual Verification Checklist](#15-manual-verification-checklist)
- [16. Risks and Blockers](#16-risks-and-blockers)
- [17. Final Recommended Execution Order](#17-final-recommended-execution-order)
- [18. Appendix](#18-appendix)

## 3. Scope and Methodology

### Files inspected

The web source-of-truth files, all Flutter library/test Dart files, relevant Android/iOS text/config files, backend route/controller/service files, and AI-service endpoint/schema files were read or source-scanned. Exact files are enumerated in the Appendix. This includes the requested frontend assets, `frontend/README.md`, `frontend/Dockerfile`, `frontend/nginx.conf`, `mobile/pubspec.yaml`, `mobile/lib/**`, `mobile/test/**`, Android/iOS platform configuration, `backend/src/routes/**`, relevant controllers/services, and `ai-service/**` endpoint code.

### Method

1. Inventory static pages, linked JS/CSS, route guards, state rendering, and direct/shared API calls.
2. Trace client payloads and consumed response fields to backend route/controller and AI schema evidence.
3. Inventory Flutter routes, data clients, models, Riverpod controllers, widgets, platform permissions, and tests.
4. Compare behavioral and visual evidence. A feature is never marked Done solely because a similarly named file exists.

### Areas not runtime-verified

- Real PostgreSQL data, account roles, CORS/firewall reachability, API availability, and AI model performance.
- Google OAuth console configuration and release credentials.
- Physical Android/iOS behavior, iOS signing, or release builds.
- Rendering at specific device sizes. The report identifies test/verification work instead.

### Assumptions and uncertainty

- The requested web folder is treated as the functional/design source of truth even where its comments are stale or conflict with backend code.
- **Needs verification** means source evidence cannot establish the behavior in a deployed environment.
- `frontend/README.md` still says the default backend is `localhost:3000`; `frontend/src/js/api.js` actually derives `host:3001/api`. The code, not the stale README, is used for parity conclusions.
- Existing uncommitted application changes were present before this audit. They were read as audit input and were not changed by this audit.

## 4. Web Architecture Summary

### Technology and hosting

| Area | Verified implementation |
|---|---|
| UI | Plain HTML5, CSS3, and Vanilla JavaScript; no frontend package/build step. |
| Maps | Leaflet 1.9.4 + OpenStreetMap tiles; marker clustering on `index.html`/`find-clinics.html`; OSRM is permitted by Nginx CSP for route use. |
| Charts | Chart.js 4.4.4 for `analytics.html` and the public feedback dashboard on `home.html`. |
| Icons/fonts | Font Awesome 6.4.0, Google Cairo (Arabic) and Inter (English). |
| Static hosting | Nginx 1.27 Alpine. `Dockerfile` copies the whole frontend tree; Nginx listens on 8080, redirects `/` to `/public/index.html`, serves static files with revalidation, CSP, Permissions-Policy, Referrer-Policy, and `nosniff`. |

### Static page structure

`frontend/public/` holds 29 standalone pages. Pages consistently load shared `dom.js`, `format.js`, `store.js`, `api.js`, `i18n.js`, `theme.js`, `toast.js`, and `layout.js` as appropriate, then page-specific modules. `index.html` is the chat/map shell; other pages use normal document scrolling with a sticky site header.

### Shared CSS design system

| CSS file(s) | Purpose verified |
|---|---|
| `main.css` | reset, token system, typography, light/dark variables, loading shell, global breakpoints (1024/768/480), app-shell/document-scroll distinction. |
| `components.css` | cards, buttons, badges, spinners, skeletons, empty/error states, toast/modal primitives. |
| `layout.css` | sticky header, role-aware navigation/dropdowns, user menu, footer, mobile header/drawer behavior. |
| `forms.css`, `auth.css` | form controls, password meter, radio choices and auth-page treatment. |
| `listing.css`, `map.css`, `sidebar.css`, `chat.css` | discovery cards/filters, Leaflet/map/location sheets, conversation sidebar/drawer, chat/map shell. |
| `appointments.css`, `dashboard.css`, `records.css`, `reports.css`, `care.css`, `notifications.css` | workflow-specific layouts. |
| `ai-tools.css`, `avatar-preview.css` | symptom/drug/report tools and Virtual Doctor voice/avatar UI. |
| `home.css`, `feedback.css`, `feedback-dashboard.css`, `analytics.css`, `animation.css`, `profile.css` | public landing, feedback, analytics, motion, and account pages. |

### Shared JS infrastructure

| File(s) | Verified responsibility |
|---|---|
| `api.js` | JSON/multipart REST client, TTL GET cache, bearer attachment, single-flight refresh-on-401, session operations, grouped endpoint helpers, dynamic backend/AI origin. |
| `i18n.js`, `theme.js`, `store.js` | Arabic default/RTL and English/LTR switching; persisted language/theme; namespaced storage wrapper. |
| `layout.js`, `toast.js`, `redirect-guard.js` | site header/footer/user menu, mobile drawer, toasts, and legacy reset/verification query redirect from `index.html`. |
| `location.js`, `location-picker.js`, `map.js`, `mini-map.js` | GPS/manual map/district selection, Leaflet maps, marker clusters, directions/popup interaction and detail mini maps. |
| `sidebar.js`, `chat.js`, `app.js`, `components/chatUI.js`, `components/mapUI.js` | authenticated conversation sidebar, chat state/result rendering, page bootstrapping. |
| `chip-input.js`, `virtual-doctor-session.js`, `virtual-doctor-stt.js`, `virtual-doctor-tts.js` | reusable token inputs plus direct AI voice-consultation/STT/TTS lifecycle. |
| `utils/dom.js`, `format.js`, `helpers.js`, `motion.js` | scroll locks, formatting/escaping helpers, and reduced-motion-aware entrance motion. |

### Auth and session behavior

- Web session keys are raw `localStorage` keys `accessToken`, `refreshToken`, and `user`; they are not in `sessionStorage`.
- App preferences use `localStorage` keys `medorbit_v2_theme`, `medorbit_v2_lang`, and `medorbit_v2_recentSearches` through `Store`.
- Every authenticated request adds `Authorization: Bearer <accessToken>`. On one 401 (other than refresh), `api.js` calls `POST /auth/refresh` with `{refreshToken}`, stores the returned pair, and retries once. A failed refresh clears session/cache and emits `auth:changed`.
- `API.requireAuth()` redirects to `login.html?redirect=<page-and-query>` when there is no access token. Role pages additionally fetch `/users/me` and show their local access-denied state; server authorization remains the real control.
- Navigation is role-aware using the cached local `user.role`: doctor and admin links are conditionally displayed. Logout is best-effort `POST /auth/logout` followed by local clear and event dispatch.

### Backend/AI origin behavior

- Backend: `api.js` resolves `http(s)://<current-page-host>:3001/api`, unless `window.MEDORBIT_API_URL` overrides it. A supplied override ending in `/api` is normalized.
- AI: `http(s)://<current-page-host>:8001`, unless `window.MEDORBIT_AI_URL` overrides it. It has no `/api` prefix.
- Nginx CSP permits current-host ports 3001/8001 and localhost/loopback variants. **Needs verification:** CSP does not by itself make a LAN physical device able to reach those ports.

### Locale, theme, responsiveness, and shared UX

- `I18n` defaults to Arabic, persists to `medorbit_v2_lang`, sets `html.lang`, `html.dir`, and emits `languageChanged`; English becomes LTR.
- `Theme` defaults light, writes `data-theme` to `<body>`, persists `medorbit_v2_theme`, and toggles an icon. Both themes are token-based.
- Web breakpoints are deliberately standardized at 1024px, 768px, and 480px. Desktop has a header/site navigation and chat/sidebar/map grids; tablet/phone collapses grids, turns the conversation sidebar into a drawer/bottom-sheet style interaction, and changes map/chat proportions.
- Pages use page-specific skeletons/loading spinners, explicit empty and error/retry states, toast notifications, confirm dialogs/modals, native/browser validation plus JS checks, cards/badges/filter controls. Coverage is not perfectly uniform; it is documented per page below.

## 5. Web Design System Analysis

The web has a mature, coherent token system: blue `#2563EB` primary; green `#10B981` secondary; amber `#F59E0B` accent; violet `#7C3AED` in the primary gradient; semantic danger/warning/success/info colors; 4/6/10/14/18/24px radii; and 150/250/400ms motion. Cairo is the default font and Inter is applied for English. Cards have bordered light/dark surfaces, modest elevation and hover lift; form focus uses primary border/ring; badges are pill-shaped semantic labels.

Accessibility-positive web evidence includes `prefers-reduced-motion` rules, RTL-aware directional CSS, sticky-header scroll margins, keyboard-friendly native controls, visible focus styles on many components, and permissions/CSP headers. **Needs verification:** no automated accessibility audit or assistive-technology test suite was found.

## 6. Web Page Inventory

Shared assets in every row are omitted only when repeated: base pages commonly include `main.css`, `components.css`, `layout.css`, `api.js`, `i18n.js`, `theme.js`, `toast.js`, `layout.js`, and `utils/{dom,format,store}.js`. CSS/JS names below are exact page-specific references; all linked assets are listed in the Appendix.

| Web page / URL | Page JS and extra CSS | Role | Verified API use / key UI states and patterns | Flutter equivalent status |
|---|---|---|---|---|
| `home.html` | `feedback-dashboard.js`; `home.css`, `feedback-dashboard.css`; Chart.js | Public | landing hero, benefits, discovery/AI calls-to-action; `GET /feedback/stats`; loading/empty/fallback dashboard cards | **Missing** public landing and feedback-stat visualisation. |
| `login.html` | `auth.js`, `google-signin.js`; `forms.css`, `auth.css` | Public | email/password login, Google button, validation/alert/loading/redirect | **Partial**: Flutter login and Google button exist; deployment OAuth needs verification. |
| `register.html` | `auth.js`, `google-signin.js`; `forms.css`, `auth.css` | Public | patient registration, bilingual names/phone/gender/password strength, verification routing | **Partial**: mobile supports patient fields but no explicit web-equivalent public landing flow. |
| `forgot-password.html` | `auth.js`; `forms.css`, `auth.css` | Public | email submission, friendly anti-enumeration response, loading/error | **Done**. |
| `reset-password.html` | `auth.js`; `forms.css`, `auth.css` | Public | token query + password validation/reset | **Partial**: Flutter accepts a token query, but mobile deep-link delivery is **Needs verification**. |
| `verify-email.html` | `auth.js`; `forms.css`, `auth.css` | Public | token verification and resend state | **Partial**: Flutter code verification/resend exists; email deep-link/OTP contract is **Needs verification**. |
| Google sign-in integration | `google-signin.js`, `login.html`, `register.html` | Public | `GET /config`, Google Identity credential, `POST /auth/google` | **Partial**: `google_sign_in` implementation exists but static mobile client configuration is not runtime-proven. |
| `dashboard.html` | `dashboard.js`; `dashboard.css`, `listing.css`, `forms.css`, `animation.css` | Authenticated patient/doctor (role-sensitive) | profile, counts, quick actions, upcoming appointments, recent conversations, notifications, profile completeness; skeleton/empty/error/retry | **Partial**: patient home has profile/counts/actions, appointment/prescription/record previews; lacks conversation/notification/profile-completeness and role dashboard. |
| `profile.html` | `profile.js`; `profile.css`, `forms.css`, `ai-tools.css` | Authenticated | fetch/update profile, avatar upload, language sync, change password; alert/loading | **Missing** editable profile/settings route and clients. |
| `notifications.html` | `notifications.js`; `notifications.css`, `dashboard.css`, `animation.css` | Authenticated | list, unread filter/style, mark one/all read, delete; skeleton/empty/error/retry | **Missing**. |
| `feedback.html` | `feedback.js`; `feedback.css`, `forms.css`, `animation.css` | Authenticated patient/doctor | overall/category stars, optional recommendation/comment, validation/success/error retry | **Done** submission parity. |
| `find-clinics.html` | `find-clinics.js`, `location.js`, `map.js`, `location-picker.js`; `listing.css`, `map.css`; Leaflet/cluster | Public | paged/search/filter list, nearby GPS/manual district/map point, markers/directions; loading/empty/error/retry | **Done** in Flutter with `flutter_map`, filters, pagination and location alternatives; routing line parity is Partial. |
| `clinic.html?id=` | `clinic.js`, `mini-map.js`; `listing.css`; Leaflet | Public | facility detail, doctors, contacts/services, mini-map; loading/not-found/error | **Done** (detail sections and mini-map). |
| `find-doctors.html` | `find-doctors.js`; `listing.css` | Public | specialty/region/rating/fee/search/pagination; loading/empty/error/retry | **Done** directory/filter/pagination. |
| `doctor.html?id=` | `doctor.js`, `mini-map.js`; `listing.css`, `records.css`, `animation.css`; Leaflet | Public | doctor profile, clinics/reviews, availability, public posts tab; loading/empty/error | **Partial**: profile/clinics/reviews/availability exist; doctor posts tab/action and booking launch are absent. |
| `book-appointment.html` | `book-appointment.js`; `forms.css`, `listing.css`, `appointments.css` | Authenticated patient | 3 steps: doctor, clinic/date/generated availability slots, reason/notes confirmation; `SLOT_BUSY` recovery; loading/empty/error/success | **Missing** create wizard and `available-slots`; mobile only lists/cancels. |
| `my-appointments.html` | `my-appointments.js`; `forms.css`, `listing.css`, `appointments.css` | Authenticated patient | filters, doctor/clinic enrichment, status groups, cancellation-reason modal; loading/empty/error/retry | **Partial**: rich list/filter/detail/cancel reason are present; no booking handoff/wizard. |
| `my-prescriptions.html` | `my-prescriptions.js`; `listing.css`, `records.css`, `animation.css` | Authenticated patient | safe patient-scoped list, search/status/date filters and selected detail | **Done**: equivalent model, filters/details/bottom sheet and API are present. |
| `my-records.html` | `my-records.js`; `listing.css`, `records.css`, `animation.css` | Authenticated patient | ownership-scoped combined appointment/record/prescription timeline, filters and detail panes | **Done**: Flutter timeline/detail/filter equivalent. |
| `my-reports.html` | `my-reports.js`; `listing.css`, `reports.css`, `animation.css` | Authenticated patient | personal printable summary from profile, appointments, conversations, saved places; records/prescription area explicitly unavailable in this view | **Missing**. |
| `my-doctor.html` | `my-doctor.js`; `listing.css`, `records.css`, `care.css`, `animation.css` | Authenticated patient | treating doctors, upcoming appointments, patient-visible shared notes; role gate/loading/empty/error | **Missing**. |
| `my-patients.html` | `my-patients.js`; `listing.css`, `records.css`, `care.css`, `animation.css` | Authenticated doctor | doctor patient list/search/filter and role gate | **Missing**. |
| `patient-detail.html?id=` | `patient-detail.js`; `listing.css`, `forms.css`, `records.css`, `care.css`, `feedback.css`, `animation.css` | Authenticated doctor | scoped patient profile/history/prescriptions and add draft/shareable note; states for no ID/not related/loading/error | **Missing**. |
| `doctor-posts.html` | `doctor-posts.js`; `listing.css`, `forms.css`, `records.css`, `care.css`, `feedback.css`, `animation.css` | Authenticated doctor | doctor’s post list/create/edit/delete/publish state + role gate | **Missing**. |
| `index.html` (chatbot) | `app.js`, `chat.js`, `sidebar.js`, `location.js`, `map.js`, `location-picker.js`, `components/{chatUI,mapUI}.js`; `chat.css`, `map.css`, `sidebar.css`; Leaflet/cluster | Public chat; conversation history authenticated | cancellable chat, optional coordinates, rich place extraction/map/results, responsive conversation drawer, conversation CRUD/search | **Done** as a mobile-native chat/map experience; mobile deliberately uses screens rather than a desktop side pane. |
| `symptom-checker.html` | `symptom-checker.js`, `chip-input.js`; `ai-tools.css`, `listing.css` | Public | chips, `POST /triage`, emergency/urgent/routine banner, specialty handoff, loading/error/retry | **Missing**. |
| `drug-checker.html` | `drug-checker.js`, `chip-input.js`; `ai-tools.css`, `listing.css` | Public | medications chip input/quick picks, direct interaction result/severity UI, loading/error/retry | **Missing**. |
| `report-summary.html` | `report-summary.js`; `ai-tools.css`, `listing.css` | Public | PDF/JPG/JPEG/PNG upload up to 10 MB; bilingual summary/extracted text; validation/loading/error/retry | **Missing**. |
| `avatar-preview.html` (Virtual Doctor) | `virtual-doctor-session.js`, `virtual-doctor-stt.js`, `virtual-doctor-tts.js`; `ai-tools.css`, `avatar-preview.css` | Public | hands-free voice consultation, mic diagnostics/status/warmup, transcript, urgency summary, PDF report fallback | **Partial / Different by design**: Flutter is push-to-talk with voice orb, native recording/playback and report download; it lacks web hands-free VAD/avatar presentation but improves native permission/retry handling. |
| `analytics.html` | `analytics.js`; `analytics.css`, `listing.css`, `animation.css`; Chart.js | Authenticated admin | admin role check, dashboard aggregate stats, six chart areas with per-area awaiting-data/error state | **Missing**. |

No additional `.html` pages were found beyond the 29 rows above.

## 7. Web API Contract Table

`API` response envelopes are generally `{ success, data, message }`. “Flutter surface” names concrete evidence; `—` means no implementation found. Status refers to Flutter parity, not backend existence. The table also includes explicitly requested endpoints that are not directly called by a web page (marked accordingly).

### Backend API contracts

| Feature | Web file using it | Method | Endpoint | Auth / role | Request fields | Response fields consumed by UI | Existing Flutter API client? | Existing Flutter model? | Existing Flutter provider/controller? | Existing Flutter UI? | Existing Flutter tests? | Mobile status | Missing mobile work / backend blocker |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Login | `auth.js` | POST | `/auth/login` | Public | `email,password` | `accessToken,refreshToken,user` | `AuthApi.login` | `AuthResultModel,UserModel` | `AuthController` | `LoginScreen` | no auth tests | Done | Runtime email-verification/error mapping needs verification. |
| Register | `auth.js` | POST | `/auth/register` | Public | email,password,role,bilingual names,phone,gender | user | `AuthApi.register` | `UserModel` | `AuthController` | `RegisterScreen` | no auth tests | Partial | Mobile is patient-only by design; add auth API/widget tests. |
| Forgot password | `auth.js` | POST | `/auth/forgot-password` | Public | `email` | acknowledgement | `AuthApi.forgotPassword` | — | `AuthController` | `ForgotPasswordScreen` | no | Done | Verify delivery/deep links. |
| Reset password | `auth.js` | POST | `/auth/reset-password` | Public | `token,newPassword` | acknowledgement | `AuthApi.resetPassword` | — | `AuthController` | `ResetPasswordScreen` | no | Partial | Needs mobile deep-link contract verification. |
| Verify email | `auth.js` | POST | `/auth/verify-email` | Public | `token,email?` | acknowledgement | `AuthApi.verifyEmail` | — | `AuthController` | `VerifyCodeScreen` | no | Partial | Web uses email-link token; mobile screen name implies code. Confirm actual email link / OTP UX. |
| Resend verification | `auth.js` | POST | `/auth/resend-verification` | Public | `email` | acknowledgement | `AuthApi.resendVerification` | — | `AuthController` | `VerifyCodeScreen` | no | Done | Add tests. |
| Google sign-in | `google-signin.js` | POST | `/auth/google` | Public | `idToken` | token pair,user | `AuthApi.googleLogin` | auth models | `AuthController` | Google button | no | Partial | Google Cloud Android/iOS client setup needs verification. |
| Token refresh | `api.js` | POST | `/auth/refresh` | Public with refresh token | `refreshToken` | token pair | `AuthInterceptor` | internal refresh result | interceptor | transparent | interceptor test only indirectly | Done | Add refresh success/failure/retry tests. |
| Logout | `api.js`,`layout.js` | POST | `/auth/logout` | Public with refresh token | `refreshToken` | acknowledgement | `AuthApi.logout` | — | `AuthController` | shell/home logout | no | Done | Router does not globally react to expiry. |
| Change password | `profile.js` | POST | `/auth/change-password` | JWT | `currentPassword,newPassword` | acknowledgement | — | — | — | — | — | Missing | Add profile/settings flow. |
| Google config | `google-signin.js` | GET | `/config` | Public | — | `googleClientId` | — (static client ID instead) | — | — | — | — | Needs verification | Static mobile OAuth audience may be correct, but no config synchronization. |
| Current user | dashboard/profile/analytics/reports | GET | `/users/me` | JWT | — | id,email,role,language,names,phone,gender,avatar,address,city | `UserApi` | `UserProfileModel` | `currentUserProfileProvider` | `HomeScreen` | no home tests | Partial | Reads only a subset; no profile edit screen or role navigation. |
| Update profile | `profile.js` | PUT | `/users/me` | JWT | bilingual names,phone,gender,address,city | acknowledgement | — | — | — | — | — | Missing | Add mutation/client/form/avatar refresh. |
| Preferences | `profile.js` | PUT | `/users/me/preferences` | JWT | `language` | acknowledgement | — | — | locale controller only local | language menu | no | Partial | Persist locale locally only; add server preference sync/load. |
| Avatar | `profile.js` | POST multipart | `/users/me/avatar` | JWT | `avatar` | `avatar` URL | — | profile model has URL | — | read-only avatar | — | Missing | File picker/image validation/upload and cache refresh. |
| Saved places | `my-reports.js` | GET | `/users/me/saved-places` | JWT | — | `places[]` fields including coordinates | `ChatbotApi` has conversation-place methods only | `ChatConversationPlace` | — | — | no | Missing | Add user-level list, privacy notice and report use. |
| Chat message | `chat.js` | POST | `/chat/message` | Optional JWT | `message,conversationId?,latitude?,longitude?` | reply,intent,confidence,entities/places/doctors/routes/suggestions | `ChatbotApi.sendMessage` | chat models | `ChatbotController` | `ChatbotScreen` | API/model/provider/screen/integration tests | Partial | REST default receive timeout is 15s while backend AI client defaults to 60s. |
| Conversations list/create | sidebar/dashboard/chat | GET/POST | `/conversations` | JWT | pagination/search; create `language?` | conversations,pagination / conversation | `ChatbotApi` | conversation models | `ConversationsController` | history/chat | provider/screen tests | Done | Add create/pagination edge tests. |
| Conversation search | sidebar | GET | `/conversations/search` | JWT | `q` | `conversations[]` | `ChatbotApi.searchConversations` | summary | controller | history | provider tests | Done | — |
| Conversation detail | `chat.js` | GET | `/conversations/:id` | JWT | `limit,offset` | conversation,messages,places,count | `ChatbotApi.getConversation` | detail/message/place | chatbot/conversation controllers | chat screen | integration tests | Done | — |
| Rename/delete conversation | sidebar/dashboard | PUT/DELETE | `/conversations/:id` | JWT | `title` / — | renamed conversation / acknowledgement | client methods | summary | controller | history menu | screen/provider tests | Done | — |
| Auto title | API helper only | POST | `/conversations/:id/title` | JWT | — | id,title | client method | summary | no caller found | — | no | Partial | Expose only if product needs it; not a current web UI gap. |
| Conversation places | API helper only | GET/POST | `/conversations/:id/places` | JWT | placeName,type,lat,lng,address?,phone?,distance?,rating? | places/place | client methods | place model | no caller found | results map only, no save/list UI | map tests only | Partial | Add explicit save/manage place controls; coordinate consent. |
| Clinic directory | `find-clinics.js` | GET | `/clinics` | Public | region,service,insurance,search,type,page,limit | clinics,pagination | `DiscoveryApi.listClinics` | clinic models | `DiscoveryController` | discovery screen | API/model/provider/widget tests | Done | — |
| Nearby clinics | `find-clinics.js` | GET | `/clinics/nearby` | Public | lat,lng,radius,type | clinics with `distance_km` | `nearbyClinics` | clinic models | discovery controller | map/discovery | tests | Done | Verify on physical devices. |
| Clinic detail | `clinic.js` | GET | `/clinics/:id` | Public | id | clinic,doctors | `getClinic` | detail models | controller | detail screen | widget test | Done | — |
| Doctor directory | `find-doctors.js`,`book-appointment.js` | GET | `/doctors` | Public | specialty,region,minRating,minFee,maxFee,search,page,limit | doctors,pagination | `listDoctors` | doctor models | controller | directory | tests | Done | — |
| Doctor detail | doctor/booking/dashboard | GET | `/doctors/:id` | Public | id | doctor,clinics,reviews | `getDoctor` | detail model | controller | detail | widget tests | Done | Booking CTA absent. |
| Doctor availability | `doctor.js` | GET | `/doctors/:id/availability` | Public | `date?` | availability slots | `getDoctorAvailability` | availability model | controller | detail section | discovery tests | Partial | Displays raw availability but cannot select/book. |
| Public doctor posts | `doctor.js` | GET | `/doctors/:id/posts` | Public | id | published posts | — | — | — | — | — | Missing | Add only after doctor portal/clinical review policy is ready. |
| Appointment list/detail | dashboard/my appointments/reports | GET | `/appointments`, `/appointments/:id` | JWT patient | id for detail | appointment rows | `AppointmentsApi.list`; no detail client | appointment model | `AppointmentsController` | list/detail sheet | no appointment tests | Partial | List works; add detail client only if navigation needs it. |
| Available slots | `book-appointment.js` | GET | `/appointments/available-slots` | Source route is public | doctor_id,clinic_id,date | active availability windows | — | — | — | — | — | Missing | Mobile must generate discrete slots like web and handle `SLOT_BUSY`. |
| Create appointment | `book-appointment.js` | POST | `/appointments` | JWT patient | doctor_id,clinic_id,date,start/end,duration,type,reason,notes | appointment number/status | — | — | — | — | — | Missing | Booking wizard. |
| Cancel appointment | `my-appointments.js` | PUT | `/appointments/:id/cancel` | JWT patient | `reason?` | updated appointment | `AppointmentsApi.cancel` | appointment model | controller | cancellation dialog/list | no | Done | Add cancellation/reason/error tests. |
| Notifications | dashboard/notifications | GET | `/notifications` | JWT | — | bilingual title/message,type,is_read,dates | — | — | — | — | — | Missing | Add module/list/read/delete actions. |
| Notification read | dashboard/notifications | PUT | `/notifications/:id/read` | JWT | — | notification | — | — | — | — | — | Missing | Add optimistic single read action. |
| Mark all read | dashboard/notifications | PATCH | `/notifications/read-all` | JWT | — | `updated` | — | — | — | — | — | Missing | Add optimistic/all action. |
| Delete notification | notifications | DELETE | `/notifications/:id` | JWT | — | acknowledgement | — | — | — | — | — | Missing | Confirm behavior/design. |
| Feedback submit | `feedback.js` | POST | `/feedback` | JWT patient/doctor | overallRating,categoryRatings,comment?,wouldRecommend? | id,rating,created_at | `FeedbackApi` | form state | `FeedbackController` | feedback screen | no feedback tests | Done | Add tests. |
| Feedback statistics | `home.html` | GET | `/feedback/stats` | Public | — | totals,avg,distribution,category averages,recommend,user name/avatar | — | — | — | — | — | Missing | Separate public/optional dashboard phase. |
| Admin dashboard stats | `analytics.js` | GET | `/dashboard/stats` | JWT admin | — | user/appointment/record/prescription/chart aggregates | — | — | — | — | — | Missing | Backend route exists via `report.routes.js`; add admin-only module. |
| Patient doctors | `my-doctor.js` | GET | `/patients/me/doctors` | JWT patient | — | treating doctor/profile/specialty/visit fields | — | — | — | — | — | Missing | Patient My Doctor module. |
| Shared patient notes | `my-doctor.js` | GET | `/patients/me/doctors/:doctorId/notes` | JWT patient | doctorId | patient-visible notes only | — | — | — | — | — | Missing | Must preserve share/draft privacy boundary. |
| Patient timeline | `my-records.js` | GET | `/patients/me/records` | JWT patient | `limit?` | `timeline[]` polymorphic fields | `RecordsApi` | `RecordEntryModel` | provider | records screen | no record tests | Done | Add tests. |
| Patient prescriptions | `my-prescriptions.js` | GET | `/patients/me/prescriptions` | JWT patient | limit,offset (web default) | prescriptions/items | `PrescriptionsApi` | model/item | provider | screen/detail sheet | no prescription tests | Done | Add tests. |
| Patient medical records | API helper only | GET/GET | `/patients/me/medical-records`, `/patients/me/medical-records/:id` | JWT patient | pagination/id | records/record | — | — | — | — | — | Needs verification | Web currently uses combined timeline instead; no mobile parity requirement until a dedicated screen is designed. |
| Doctor patient list | `my-patients.js` | GET | `/doctors/me/patients` | JWT doctor | search/filter query as applicable | patients/visit fields | — | — | — | — | — | Missing | Doctor module. |
| Doctor patient detail | `patient-detail.js` | GET | `/doctors/me/patients/:patientId` | JWT doctor | patientId | patient,appointments,notes,prescriptions | — | — | — | — | — | Missing | Role/relationship guard and sensitive-data tests. |
| Add patient note | `patient-detail.js` | POST | `/doctors/me/patients/:patientId/notes` | JWT doctor | record_type,diagnosis,chief_complaint,clinical_notes,is_draft,visible_to_patient | created note | — | — | — | — | — | Missing | Explicit draft/share confirmation and audit-safe UX. |
| Doctor posts | `doctor-posts.js` | GET/POST | `/doctors/me/posts` | JWT doctor | post fields (title/content/status) | own posts/post | — | — | — | — | — | Missing | Doctor publishing module. |
| Update/delete post | `doctor-posts.js` | PUT/DELETE | `/doctors/me/posts/:postId` | JWT doctor | editable post fields / — | post/acknowledgement | — | — | — | — | — | Missing | Add ownership and moderation-state UX. |

### AI-service contracts

| Feature | Web file using it | Method | Endpoint | Auth / role | Request fields | Response fields consumed by UI | Existing Flutter API client? | Existing Flutter model? | Existing Flutter provider/controller? | Existing Flutter UI? | Existing Flutter tests? | Mobile status | Missing mobile work / blocker |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Health | none directly | GET | `/health` | Unauthenticated | — | health status | no AI health probe | — | — | — | — | Missing | Add non-sensitive AI health/preflight; backend host probe is not AI probe. |
| Direct AI chat | backend `ai-client.service.js`, not browser direct | POST | `/chat` | Unauthenticated service | message/context/type/medications/record/lat/lng | reply,intent,confidence,entities | no direct client (correctly uses backend `/chat/message`) | chat models for backend response | chatbot controller | chat UI | extensive chat tests | Different by design | Keep backend mediation; mobile should not call this direct endpoint. |
| Symptom triage | `symptom-checker.js` | POST | `/triage` | Unauthenticated | `symptoms[]`, user_id?,session_id? | id,symptoms,triage_level,specialty,confidence,recommendations,follow_up | — | — | — | — | — | Missing | Medical safety UI, emergency escalation, long timeout/error policy. |
| Drug interactions | `drug-checker.js` | POST | `/drug-interactions` | Unauthenticated | medication_ids? or `medication_names[]` | interactions,count,severity summary | — | — | — | — | — | Missing | Include disclaimers and severe-interaction emphasis. |
| Report summarizer | `report-summary.js` | POST multipart | `/summarize` | Unauthenticated | file or text,user_id?,record_id? | id,summary_ar,summary_en,extracted_text,time,model | — | — | — | — | — | Missing | File picker/size/type/privacy/error handling. |
| Virtual Doctor start | `virtual-doctor-session.js` | POST | `/virtual-doctor/start` | Unauthenticated | language,user_id? | session_id,reply,phase,language | `VirtualDoctorApi.start` | `StartResult` | `VirtualDoctorController` | screen/orb | provider/screen/model tests | Done | iOS microphone/AI reachability remains blocker. |
| Virtual Doctor message | session JS | POST | `/virtual-doctor/message` | Unauthenticated | session_id,message | reply,phase,complaint,urgency,profile,specialty,differential | `sendMessage` | `MessageResult` | controller | transcript/summary | tests | Done | 120s timeout evidence present. |
| Restore session | not used by web | GET | `/virtual-doctor/session/:session_id` | Unauthenticated | id | session transcript/state | `getSession` | restored session model | controller | recovery capability | provider tests | Partial | Screen has no user-facing session-ID recovery route; exposing IDs needs privacy design. |
| STT | `virtual-doctor-stt.js` | POST multipart | `/virtual-doctor/transcribe` | Unauthenticated | audio,language? | text,language,probability,audio seconds,timed_out | `transcribe` | transcription model | controller | voice flow | voice/provider tests | Done | iOS `NSMicrophoneUsageDescription` missing. |
| STT status/warmup | STT JS | GET/POST | `/virtual-doctor/transcribe/status`, `/virtual-doctor/transcribe/warmup` | Unauthenticated | language? for warmup | model/device/load state | warmup only (no status UI) | — | controller invokes warmup | not exposed | no status test | Partial | Add health/status diagnostics only if useful; do not expose internals to patients. |
| TTS | `virtual-doctor-tts.js` | POST | `/virtual-doctor/speak` | Unauthenticated | text,language? | WAV bytes | `speak` via `TtsPlayer` | bytes | controller | voice flow | tests | Done | graceful fallback exists. |
| TTS status/warmup | TTS JS | GET/POST | `/virtual-doctor/speak/status`, `/virtual-doctor/speak/warmup` | Unauthenticated | — | voice/load state | warmup only | — | controller invokes warmup | not exposed | no | Partial | Same diagnostics recommendation. |
| Virtual Doctor report | session JS | POST | `/virtual-doctor/report/:session_id` | Unauthenticated | session ID | report_id,download_url,urgency,specialty | `createReport` | `ReportResult` | controller | report action | provider/screen tests | Done | 503 renderer fallback displayed. |
| Report download | session JS | GET | `/virtual-doctor/report/:report_id/download` | Unauthenticated | report ID | PDF bytes | `downloadReport` | bytes | controller | opens local file | screen/provider tests | Done | User-visible error must not reveal IDs/paths. |

## 8. Flutter Mobile Implementation Inventory

| Module | Evidence: files/routes/models/APIs/controllers/UI/tests | Status | Matching web feature(s) and limitation |
|---|---|---|---|
| Auth and OTP/verification | `features/auth/**`; `/login,/register,/forgot-password,/verify-code,/reset-password`; `AuthApi`, repository, `AuthController`, auth models/screens/widgets. No auth-specific tests. | Partial | Core email/password, reset, verify/resend and Google code exist. Deep links, verification semantics, OAuth config and auth tests need verification. |
| Dashboard/home | `features/home/**`, `/home`, user profile provider, patient home cards/actions. | Partial | Good patient overview from user/appointments/prescriptions/records. No conversation/notification preview, public landing, profile completeness, or role dashboard. |
| Appointments | `features/appointments/**`, `/appointments`, list/cancel/enrichment/card filters. | Partial | List/cancel parity; no availability API/create model/wizard. No appointment tests. |
| Prescriptions | `features/prescriptions/**`, model/provider/list/detail sheet. | Complete | Patient-scoped list/detail/filter design is equivalent; add coverage. |
| Records | `features/records/**`, polymorphic timeline/detail sheet. | Complete | Equivalent safe combined timeline and details; add coverage. |
| Feedback | `features/feedback/**`, `/feedback`, star control/form state. | Partial | Submission parity complete; feedback statistics/public visual dashboard absent and no tests. |
| Profile/settings | Read-only `features/home/{data,models,providers}` profile card. | Missing | No route/client/model mutation/avatar/password/preferences screen. |
| Notifications | No feature directory, route, client, model, provider, screen, or tests. | Missing | Full web notifications absent. |
| Clinic discovery/detail | `features/discovery/**`, `/clinics`, `/clinics/:id`, filters, maps, detail sections. | Complete | Strong parity, including pagination and empty/error/retry. |
| Doctor directory/detail | discovery API/models/screens/widgets, `/doctors`, `/doctors/:id`, availability. | Partial | Directory/detail/availability exist. Public doctor posts and booking handoff do not. |
| Map/location | `flutter_map`, marker cluster, `LocationService`/provider/manual district/map selection; Android location permissions; iOS location text. | Complete | Mobile is purposefully native rather than Leaflet. No mobile turn-by-turn/OSRM route polyline. |
| Chatbot | `features/chatbot/**`, `/chatbot`, models/API/provider/message and result widgets. | Partial | Rich chat/map/results and retry exist, but 15s default REST timeout is shorter than backend AI default 60s; text localization is incomplete. |
| Conversation history | chatbot API/controller, `/chatbot/conversations`, rename/delete/search/load-more. | Complete | Native screen replaces web sidebar; create/title/place management is not fully surfaced. |
| Chatbot map integration | `ChatResultsMap`, map result sheet, location banner/map/district picker. | Complete | Better touch-native presentation; route is a summary, not web's full OSRM route treatment. |
| Virtual Doctor | `features/virtual_doctor/**`, `/virtual-doctor`, API/controller, record/TTS, voice orb, model tests. | Partial / Different by design | Native push-to-talk, 45s STT / 120s message / 60s report budgets, warmup and report download are strong. No web hands-free VAD/avatar visual; missing iOS microphone use string. |
| Standalone AI tools | No symptom/drug/summarizer feature, route, client, model, provider, UI, tests. | Missing | Web has three distinct tools. |
| Patient My Doctor/shared notes | No implementation. | Missing | Web care API contracts exist. |
| Doctor portal | No implementation. | Missing | My Patients, patient detail/note sharing, and posts all absent. |
| Admin analytics | No implementation. | Missing | No route/client/chart/test. |
| Routing/navigation | `routes/{route_paths,app_router,main_shell}.dart`; GoRouter, 5 patient bottom-navigation branches. | Partial | Well structured patient navigation, but no public home, profile/settings, notifications, AI-tool routes, doctor/admin branches, or global auth/role redirect. |
| Localization | `locale_controller.dart`, `app_strings.dart`, Flutter localization delegates, persisted secure-storage language code. | Partial | Arabic/English and RTL direction work. Many chatbot/discovery literals are English, and account preference does not sync. |
| Theming | `AppTheme` has matching tokens/light/dark themes, gradients, Material 3 component themes and reduced-motion helper. | Partial | No theme controller, explicit toggle, persistence, or `themeMode` selection in `MaterialApp.router`; system default only. |
| Network/API/session | Dio, host resolver, auth/error/debug-safe logging interceptors, secure storage. | Partial | Strong refresh/storage/error handling. Hard-coded LAN HTTP primary, cleartext release traffic, chatbot timeout mismatch, and no automatic navigation after expiration remain. |
| Platform permissions/release | Android Internet/mic/location and cleartext; iOS location message; debug signing. | Partial | iOS microphone permission text absent; package/display identity is generic; release signing TODO. |

### Existing test coverage

25 test files cover network log redaction, chatbot API/models/provider/screen/history/map integration, discovery API/models/providers/location/maps/screens, and Virtual Doctor models/provider/screen/recording. There are no focused tests for auth, home/dashboard, appointments, prescriptions, records, feedback, profile, notifications, the future AI tools, doctor portal, admin analytics, full router guards, locale/theme persistence, platform release configuration, or release builds.

## 9. Feature Parity Matrix

| Web feature | Web files | User role | Exists in mobile? | Mobile evidence | Status | Priority | Reason / dependencies | Phase | Backend/AI requirement | Tests needed |
|---|---|---|---|---|---|---|---|---|---|---|
| Public landing | `home.html`,`home.css` | Public | No | — | Missing | Low | Brand/entry parity; after core care workflows | 14 | `/feedback/stats` if dashboard retained | widget/golden/navigation |
| Auth/session | auth pages/API | Public | Yes | auth/core network | Partial | High | deep links, OAuth, route guard need verification | 0 | auth endpoints | unit/widget/refresh |
| Patient dashboard | `dashboard.html` | Patient | Yes | home | Partial | Medium | notifications/conversations/role states missing | 14 | existing APIs | widget/provider |
| Profile/settings | `profile.html` | Authenticated | No | read-only user provider | Missing | High | account safety, language server sync | 4 | existing users/auth APIs | API/provider/widget |
| Notifications | `notifications.html` | Authenticated | No | — | Missing | High | appointment/clinical communication visibility | 3 | existing APIs | client/provider/widget |
| Clinic search/map | find/detail clinic | Public | Yes | discovery/location | Done | Medium | physical-device GPS/map verification | — | existing APIs | existing + device |
| Doctor directory/detail | find/detail doctor | Public | Yes | discovery | Partial | High | posts/booking CTA missing | 2/11 | availability/posts APIs | widget/API |
| Appointment booking | `book-appointment.html` | Patient | No | list/cancel only | Missing | Critical | core care path; handle slots and race | 2 | existing APIs | API/provider/wizard |
| Appointment cancellation | `my-appointments.html` | Patient | Yes | appointments | Done | High | retain reason/error/timing parity | 2 | existing endpoint | unit/widget |
| Prescriptions | `my-prescriptions.html` | Patient | Yes | prescriptions | Done | Medium | verify real payloads | — | existing endpoint | client/provider/widget |
| Records timeline | `my-records.html` | Patient | Yes | records | Done | Medium | verify attachments/data shape | — | existing endpoint | client/provider/widget |
| Personal My Reports | `my-reports.html` | Patient | No | — | Missing | Medium | depends profile, appointments, conversations, saved places | 8 | existing endpoints | aggregation/widget |
| My Doctor/shared notes | `my-doctor.html` | Patient | No | — | Missing | High | sensitive notes visibility | 9 | existing patient care APIs | authorization/widget |
| Chat/conversations/maps | `index.html`, chat/sidebar/map | Public/authenticated | Yes | chatbot | Done | High | harden timeout/localization | 1 | backend chat | timeout/navigation/RTL |
| Symptom Checker | `symptom-checker.html` | Public | No | — | Missing | Critical | medical urgency/escalation | 5 | `/triage` | safety/API/widget |
| Drug Checker | `drug-checker.html` | Public | No | — | Missing | High | safety severity/disclaimer | 6 | `/drug-interactions` | safety/API/widget |
| Report Summarizer | `report-summary.html` | Public | No | — | Missing | High | health documents/upload privacy | 7 | `/summarize` | upload/error/privacy |
| Virtual Doctor | `avatar-preview.html` | Public | Yes | virtual_doctor | Partial / Different by design | Critical | connectivity/iOS permission/release validation | 0 | direct AI endpoints | device/timeout/privacy |
| Doctor patients | `my-patients.html` | Doctor | No | — | Missing | High | after patient safety flows | 10 | existing doctor care APIs | role/relationship |
| Doctor patient detail/notes | `patient-detail.html` | Doctor | No | — | Missing | High | highly sensitive write/share behavior | 10 | existing doctor care APIs | authorization/share |
| Doctor posts | `doctor-posts.html`, doctor tab | Doctor/public | No | — | Missing | Medium | needs content/moderation decision | 11 | existing APIs | CRUD/role |
| Feedback statistics | `home.html` dashboard | Public | No | feedback submit only | Missing | Low | non-clinical, after patient care | 12 | `/feedback/stats` | API/widget/chart |
| Admin analytics | `analytics.html` | Admin | No | — | Missing | Low | separate admin scope | 13 | `/dashboard/stats` | authorization/chart |
| Role navigation | `layout.js`,`dashboard.js` | All | Patient only | `MainShell` | Missing | High | prevents wrong experience/route access | 14 | `/users/me` role | router/role tests |
| Theme parity | `theme.js`, CSS | All | system themes only | `AppTheme` | Partial | Medium | no user selection/persistence | 4 | none | persistence/dark widgets |
| RTL/LTR parity | `i18n.js`, CSS | All | Yes, incomplete text | locale strings/widgets | Partial | High | hard-coded English clinical UI undermines Arabic UX | 4/14 | preference API optional | RTL/string tests |

## 10. Design Parity Audit

### Matched design elements

- Exact brand color family, gradients, semantic colors, radii, spacing scale, Cairo/Inter fonts, and light/dark surfaces are encoded in `AppTheme` to match `main.css`.
- Material cards, inputs, buttons, chips, status badges, bottom sheets and snack bars represent the same system intent. Flutter provides a 48px minimum touch target.
- Flutter’s `EmptyState`, `ErrorRetryState`, `PrimaryButton`, `StatusBadge`, and `PageSections` provide reusable equivalents of core web states/components.
- RTL uses Flutter locale/directionality; localized-field helpers select Arabic or English values. Web and mobile both support manual location and foreground-only location intent.
- Flutter discovery maps, clustered markers, cards and native modal sheets are a credible mobile adaptation of Leaflet listings/maps.

### Partially matched / missing patterns

| Area | Finding |
|---|---|
| Dark mode | Themes exist but app has no user toggle/controller/persistence and `MaterialApp.router` does not set a theme mode. Web persists explicit light/dark selection. |
| Localization | Core string catalog is extensive, but chatbot/conversation and parts of discovery use literal English. Web UI strings are much more systematically bilingual. |
| Loading | Flutter often uses a spinner; it has no shared shimmer/skeleton equivalent to web `.skeleton` usage. |
| Toast | SnackBar theme exists, but feature-level success/error feedback is inconsistent compared with web `Toast`. |
| Navigation | Mobile’s patient bottom navigation is appropriately native, but it omits profile, notifications, chat/AI tools, and any role-specific surfaces. |
| Map directions | Web map supports richer route/popup interaction. Mobile chat only shows route distance/duration summary; no route polyline/navigation launch was found. |
| Forms | Auth/feedback are polished; profile, booking, standalone AI upload/forms, doctor notes/posts are absent. |
| Virtual Doctor | Flutter uses accessible states, voice orb, manual push-to-talk and local PDF open; web uses a hands-free visual avatar/VAD stage. This is **Different by design**, but parity decision (retain native mode vs add hands-free) needs product verification. |
| Motion | Web uses CSS reduced-motion broadly. Flutter exposes `motionDuration` honoring disable animations/accessibility, but not all animations can be proven to call it. **Needs verification.** |
| Semantics | Virtual Doctor/chat show thoughtful `Semantics`; completeness across pages/screens needs accessibility testing. |

### Mobile improvements already better than web

- Tokens enforce touch targets and Material text scaling behavior, including compact bottom-navigation adjustment.
- Secure storage replaces web’s raw localStorage tokens.
- Network debug logging deliberately redacts request bodies, headers, query fields, IDs and medical data.
- Location is described as message-only in chatbot UI and is cleared after sending; native permission states/settings help are clearer.
- Virtual Doctor has tailored CPU-safe STT/message/report timeouts, warmup, push-to-talk control, local temporary-audio deletion, TTS fallback and local report opening.

### Design debt/recommendations

1. Add a persisted theme controller and theme selector before calling dark-mode parity complete.
2. Replace all patient-visible hard-coded English literals with `AppStrings`; add Arabic overflow/large-text tests.
3. Create standard skeleton, async-error, confirmation sheet and medical-disclaimer widgets before the next feature batch.
4. Keep bottom navigation patient-focused, but add a role-aware “More”/drawer or role-specific shell instead of forcing desktop information architecture onto mobile.
5. Use a consistent urgency visual and emergency action pattern across Chatbot, Symptom Checker and Virtual Doctor.

## 11. Missing Mobile Features by Priority

| Priority | Exact missing/partial mobile work | Evidence |
|---|---|---|
| Critical | Appointment Booking Wizard: doctor/clinic/date/available-slot selection, reason/notes confirmation, `SLOT_BUSY` recovery | No create/slot client, model, route or widget; web `book-appointment.js` implements all. |
| Critical | Symptom Checker with emergency escalation and safe results | `symptom-checker.html/js` only. |
| Critical | Virtual Doctor release connectivity and iOS microphone readiness | hard-coded LAN HTTP config; iOS Info.plist lacks `NSMicrophoneUsageDescription`; release signing TODO. |
| High | Chatbot AI timeout/error hardening | `ChatbotApi.sendMessage` has no request options, so Dio’s 15s default can expire before backend 60s AI timeout. |
| High | Full notifications list/actions | No Flutter feature despite four live web-used endpoints. |
| High | Profile advanced parity | No update/avatar/change-password/preferences-sync/settings route. |
| High | Drug Interaction Checker | Web-only `drug-checker.js`/AI contract. |
| High | Report Summarizer PDF/image upload | Web-only `report-summary.js`; needs sensitive-file handling. |
| High | Patient My Doctor and shared notes | No module for scoped doctor relationship/shared notes. |
| High | Doctor portal: patient list, scoped detail and notes | Entire doctor role missing. |
| High | Role-based navigation/router guard | Flutter route tree has patient shell only; direct navigation auth/role protection is not evident. |
| Medium | My Reports and saved places | No report aggregation/user saved-place UI. |
| Medium | Public doctor posts on doctor detail and doctor post management | No mobile client/UI. |
| Medium | Theme choice/persistence and locale-preference sync | Theme code only; locale local-only. |
| Medium | Public home landing / feedback dashboard | No unauthenticated mobile landing or feedback stats chart. |
| Low | Admin Analytics | No isolated admin module/chart implementation. |

## 12. Required Backend or AI Changes

Most feature APIs already exist. The following are verification/operational requirements, not a request to change code in this audit:

| Requirement | Classification | Evidence and recommended resolution |
|---|---|---|
| Stable mobile API/AI base URLs | Production blocker | Flutter primary URL is `http://192.168.0.105:3001/api`; make environment/build-time or trusted runtime configuration available and use TLS in production. |
| AI service reachability on 8001 | Production/network blocker | Flutter derives port 8001 from resolved backend origin. Validate LAN firewall/Docker exposure and reverse-proxy/TLS design on Android/iOS. |
| Chat timeout alignment | API/client blocker | Backend AI client default is 60,000ms; mobile REST default is 15,000ms. Give `/chat/message` a bounded medical-safe budget and distinguish timeout from clinical advice. |
| iOS microphone declaration | Mobile platform blocker | `Info.plist` has location usage text but no `NSMicrophoneUsageDescription`; add it before Virtual Doctor iOS testing/release. |
| Direct AI endpoint security/privacy | Privacy/security blocker | AI FastAPI CORS allows `*` and AI endpoints have no JWT; web and mobile send medical text/audio/file content directly. Establish authentication, rate limits, retention, consent and production CORS policy before release. |
| Appointment slot semantics | API verification | `/appointments/available-slots` returns active availability windows, not booked-slot availability; client generates slots and only learns a conflict on POST. Confirm this intended race/UX or enhance API atomically. |
| OAuth/deep links | Needs verification | Source confirms client/server ID handling but cannot confirm Google console Android/iOS setup or reset/verify universal/app links. |
| Notification delivery | Needs verification | REST list/actions exist; no push-registration/device-token API was found. Full push parity cannot be assumed. |
| Admin analytics contract | Existing endpoint, verify payload | `/dashboard/stats` is mounted through `report.routes.js`; validate actual aggregate shape against `analytics.js` normalizer before implementing charts. |

## 13. Recommended Mobile Implementation Phases

The sequence puts reliability and medical-safety work before workflow expansion, keeps booking separate from notifications, keeps AI tools separate from doctor portal work, and keeps admin isolated. File lists are implementation recommendations only; no files were created or modified by this audit.

### Phase 0 — Connectivity, permission, session, and release gate

- **Goal / scope / user role:** make existing patient Chatbot and Virtual Doctor reliably reachable and safely recoverable for all roles.
- **Type / complexity:** mobile-only plus deployment verification; **Medium**.
- **Files to create:** `mobile/test/core/network/auth_interceptor_refresh_test.dart`, `mobile/test/core/config/app_config_test.dart`, `mobile/test/features/virtual_doctor/virtual_doctor_connectivity_test.dart`.
- **Files to modify:** `mobile/lib/core/config/app_config.dart`, `mobile/lib/core/network/dio_client.dart`, `mobile/lib/core/network/auth_interceptor.dart`, `mobile/lib/core/providers/core_providers.dart`, `mobile/lib/features/chatbot/data/chatbot_api.dart`, `mobile/lib/routes/app_router.dart`, `mobile/ios/Runner/Info.plist`, `mobile/android/app/build.gradle.kts`, `mobile/android/app/src/main/AndroidManifest.xml`.
- **APIs/models/controllers:** backend `/health`, `/auth/refresh`, `/chat/message`; AI `/health`, Virtual Doctor start/STT/TTS/report. Extend `ApiException`/auth state only as needed; add a session-aware router redirect mechanism.
- **UI:** non-sensitive offline/timeout/retry messages; permission/settings recovery; no leaked IPs, session IDs, report IDs or raw server errors.
- **Tests:** timeout budgets, refresh single-flight/failure logout, base-host selection, AI-unreachable Virtual Doctor, denial/permanent denial, router behavior after session clear.
- **Manual verification:** Android physical device and emulator on same Wi-Fi; backend/AI health; airplane/port-blocked scenarios; iOS microphone prompt; restart/refresh/logout; debug and release builds.
- **Privacy/safety:** no medical payload logs; use TLS/production configuration; do not surface diagnostic internals to patients.
- **Risks/blockers:** hard-coded LAN address, firewall, cleartext network policy, missing iOS microphone string, debug signing, unavailable AI/PDF renderer. This phase precedes all features because none are trustworthy if API/AI access fails.

### Phase 1 — Chatbot timeout hardening and localization completion

- **Goal / scope / user role:** preserve existing chatbot parity under AI latency and complete patient-visible Arabic/English text.
- **Type / complexity:** mobile-only; **Medium**.
- **Files to create:** `mobile/test/features/chatbot/chatbot_timeout_test.dart`, `mobile/test/features/chatbot/chatbot_rtl_test.dart`.
- **Files to modify:** `mobile/lib/features/chatbot/data/chatbot_api.dart`, `chatbot_provider.dart`, `chatbot_screen.dart`, all chatbot widget files with literals, `mobile/lib/core/localization/app_strings.dart`.
- **APIs/models/controllers:** `/chat/message`; existing chat models and `ChatbotController`; request-specific receive timeout aligned below backend ceiling and cancellable/retry policy.
- **UI:** distinguish unavailable, timeout, retryable failure and emergency intent; keep location consent visible.
- **Tests:** fake Dio delayed 200/timeout/500, retry once, Arabic RTL, map result semantics, no coordinate/text log regression.
- **Manual verification:** long AI response, attach/clear GPS/manual district, conversation restore/search, Arabic/English and text scale 2.0.
- **Privacy/safety:** never turn an uncertain timeout into medical guidance. **Depends on Phase 0** host validation.

### Phase 2 — Appointment booking and cancellation parity

- **Goal / scope / user role:** let a patient choose doctor, clinic, date and availability slot, confirm a booking, and retain cancellation-reason behavior.
- **Type / complexity:** existing backend required/verified; **Large**.
- **Files to create:** `mobile/lib/features/appointments/models/availability_slot_model.dart`, `booking_draft.dart`, `data/booking_api.dart`, `providers/booking_provider.dart`, `screens/book_appointment_screen.dart`, `widgets/{booking_doctor_step,booking_slot_step,booking_confirm_step,slot_grid}.dart`, and matching `mobile/test/features/appointments/*` tests.
- **Files to modify:** `appointments_api.dart`, `appointment_model.dart`, `appointments_screen.dart`, `appointment_card.dart`, `home_screen.dart`, `route_paths.dart`, `app_router.dart`, `app_strings.dart`.
- **APIs/models/controllers:** `GET /doctors`, `GET /doctors/:id`, `GET /appointments/available-slots`, `POST /appointments`, `PUT /appointments/:id/cancel`; `BookingController` plus existing appointments controller.
- **UI:** three native steps, clinic selector, date strip/calendar, generated discrete slots, reason/notes, type label, confirmation, success and `SLOT_BUSY` return-to-slot state.
- **Tests:** slot-window generation, past-slot exclusion, request payload, race/`SLOT_BUSY`, cancellation reason, validation, RTL/large text and navigation.
- **Manual verification:** booked/no-clinic/no-slot/telemedicine path, double-book race, cancel with/without reason, list refresh and real backend ownership error.
- **Privacy/safety:** do not persist reason/notes beyond needed draft state; clearly show appointment type. **Blocker:** verify that backend slot window behavior is an accepted optimistic contract. This comes before cosmetic/public work because booking is core care.

### Phase 3 — Notifications parity

- **Goal / scope / user role:** provide authenticated notification list, unread/read/delete actions and dashboard entry point.
- **Type / complexity:** existing backend; **Medium**.
- **Files to create:** `mobile/lib/features/notifications/{data/notifications_api.dart,models/notification_model.dart,providers/notifications_provider.dart,screens/notifications_screen.dart,widgets/notification_tile.dart}` and tests under `mobile/test/features/notifications/`.
- **Files to modify:** `route_paths.dart`, `app_router.dart`, `main_shell.dart` or a role-aware More surface, `home_screen.dart`, `app_strings.dart`.
- **APIs/models/controllers:** GET `/notifications`, PUT `/:id/read`, PATCH `/read-all`, DELETE `/:id`; `NotificationsController`.
- **UI:** unread badge/count, list/empty/error/retry, swipe/menu delete confirmation and mark-all action.
- **Tests/manual verification:** fake client pagination/order/read/delete/optimistic rollback; sign in with read/unread records, mark one/all, delete, offline retry, Arabic/dark/large text.
- **Privacy/safety:** notification previews may reveal health information; no sensitive message in OS/app logs. **Needs verification:** push delivery is out of scope until a device-token backend contract exists.

### Phase 4 — Profile, settings, theme, locale preference, and route roles

- **Goal / scope / user role:** complete authenticated account management and reliable patient/doctor/admin routing foundations.
- **Type / complexity:** existing backend plus mobile-only theme/router; **Large**.
- **Files to create:** `mobile/lib/features/profile/{data/profile_api.dart,models/profile_edit_model.dart,providers/profile_provider.dart,screens/profile_screen.dart,widgets/avatar_picker.dart,widgets/change_password_sheet.dart}`, `mobile/lib/core/theme/theme_controller.dart`, role-route tests.
- **Files to modify:** `user_api.dart`, `user_profile_model.dart`, `home_screen.dart`, `main.dart`, `main_shell.dart`, router/path files, `secure_storage_service.dart`, `locale_controller.dart`, `app_strings.dart`.
- **APIs/models/controllers:** GET/PUT `/users/me`, PUT `/users/me/preferences`, POST `/users/me/avatar`, POST `/auth/change-password`; `ProfileController`, `ThemeController`, locale synchronization and role guard.
- **UI:** account form, validated avatar picker/progress, password confirmation, explicit light/dark/system chooser, locale selection, safe logout/delete-account decision if product authorizes it.
- **Tests/manual verification:** upload error/success, refresh profile, server preference round-trip, theme/language persistence, denied role/deep route/expired session. Test Arabic RTL/English LTR at 320/360/411/600+ and scale 2.0.
- **Privacy/safety:** use secure storage; validate image type/size; do not echo password/server details. This phase enables later role portals safely.

### Phase 5 — AI Symptom Checker

- **Goal / scope / user role:** patient/public symptom triage with clinically safe emergency/urgent/routine presentation.
- **Type / complexity:** AI/service verification required; **Medium**.
- **Files to create:** `mobile/lib/features/symptom_checker/{data/symptom_checker_api.dart,models/triage_result_model.dart,providers/triage_provider.dart,screens/symptom_checker_screen.dart,widgets/symptom_chip_input.dart,widgets/triage_result_card.dart}` and tests.
- **Files to modify:** AI provider/config if per-endpoint timeout is needed, paths/router/home actions/localized strings.
- **APIs/models/controllers:** POST `/triage`; `TriageResultModel`, `TriageController`.
- **UI:** symptom chips/quick picks, progress/retry, clearly distinct emergency action/card, specialty handoff to doctor directory and an explicit non-diagnostic disclaimer.
- **Tests/manual verification:** validation, Arabic symptoms, emergency/urgent/routine fixtures, service 422/timeout, specialty link, TalkBack semantics.
- **Privacy/safety:** this is medical-safety-critical: emergency UI must prioritise immediate local emergency guidance; do not present a diagnosis or false certainty. Verify AI retention/auth before production.

### Phase 6 — AI Drug Interaction Checker

- **Goal / scope /user role:** let users enter medication names and understand interactions without implying prescribing advice.
- **Type / complexity:** AI/service verification required; **Medium**.
- **Files to create:** `mobile/lib/features/drug_checker/{data/drug_checker_api.dart,models/drug_interaction_model.dart,providers/drug_checker_provider.dart,screens/drug_checker_screen.dart,widgets/medication_chip_input.dart,widgets/interaction_result_card.dart}` plus tests.
- **Files to modify:** AI provider/config, routes/home actions/app strings.
- **APIs/models/controllers:** POST `/drug-interactions`; result/severity models and controller.
- **UI/tests/manual:** medication chips, severe/moderate cards, loading/error/retry and pharmacist/doctor disclaimer; test empty/duplicate/Arabic entries, severe response, timeout and RTL.
- **Privacy/safety/risk:** do not claim exhaustive interaction coverage; route severe risk to professional review. Keep separate from symptom tool to contain clinical logic.

### Phase 7 — AI Report Summarizer

- **Goal / scope / user role:** upload a supported report and render Arabic/English summary/extracted text safely.
- **Type / complexity:** AI/service and mobile file-picker dependency; **Large**.
- **Files to create:** `mobile/lib/features/report_summary/{data/report_summary_api.dart,models/report_summary_model.dart,providers/report_summary_provider.dart,screens/report_summary_screen.dart,widgets/report_file_picker.dart,widgets/summary_tabs.dart}` plus tests.
- **Files to modify:** `pubspec.yaml` only if a vetted file/image picker is selected, platform declarations as required, AI provider, router/actions/strings.
- **APIs/models/controllers:** multipart POST `/summarize`; summary model/controller.
- **UI/tests/manual:** PDF/JPG/JPEG/PNG type and 10 MB constraint, progress, summary language tabs, disclosure for extracted text, retry; test type/size/permission/network errors and a physical-device PDF/image flow.
- **Privacy/safety/risk:** medical documents are highly sensitive. Confirm encryption in transit, retention/deletion policy, permission scopes, diagnostic-error sanitization and production AI authentication before implementation.

### Phase 8 — Personal My Reports and saved places

- **Goal / scope / user role:** patient printable/shareable-in-app personal overview matching `my-reports.html` without fabricating unavailable data.
- **Type / complexity:** existing backend; **Medium**.
- **Files to create:** `mobile/lib/features/reports/{data/personal_reports_api.dart,models/personal_report_model.dart,providers/personal_report_provider.dart,screens/my_reports_screen.dart,widgets/report_section.dart}` and tests.
- **Files to modify:** chatbot saved-place state/UI if explicit save is approved, appointments/conversation clients, profile routing/strings.
- **APIs/models/controllers:** `/users/me`, `/appointments`, `/conversations`, `/users/me/saved-places`, public doctor lookups; aggregation controller.
- **UI/tests/manual:** profile, appointment, conversation and saved-place sections; show unavailable sections honestly; share/print only after privacy review. Test partial endpoint failure and no saved places.
- **Privacy/safety/risk:** do not include private chat/clinical text in a share action by default. This phase follows profile and booking so inputs are reliable.

### Phase 9 — Patient My Doctor and shared notes

- **Goal / scope / user role:** patient-only doctor relationship, upcoming appointments and explicitly shared notes.
- **Type / complexity:** existing backend; **Medium**.
- **Files to create:** `mobile/lib/features/care_patient/{data/my_doctor_api.dart,models/my_doctor_models.dart,providers/my_doctor_provider.dart,screens/my_doctor_screen.dart,widgets/{doctor_relationship_card,shared_note_card}.dart}` and authorization/widget tests.
- **Files to modify:** role router/navigation, appointments model integration, strings.
- **APIs/models/controllers:** GET `/patients/me/doctors`, GET `/patients/me/doctors/:doctorId/notes`, GET `/appointments`; controller/models.
- **UI/tests/manual:** treating-doctor cards, upcoming list, shared-note timeline, empty/error/retry. Test only visible-to-patient notes render and denied role never enters route.
- **Privacy/safety/risk:** never cache/display draft/private clinician notes. This patient feature precedes doctor portal to validate the sharing boundary from the receiving side.

### Phase 10 — Doctor Portal: My Patients, detail, and notes

- **Goal / scope / user role:** doctor-only patient search, scoped patient record, and note creation with explicit draft/share status.
- **Type / complexity:** existing backend; **Large**.
- **Files to create:** `mobile/lib/features/care_doctor/{data/doctor_patients_api.dart,models/doctor_patient_models.dart,providers/doctor_patients_provider.dart,screens/{my_patients_screen,patient_detail_screen}.dart,widgets/{patient_card,patient_history,patient_note_form,note_visibility_control}.dart}` plus tests.
- **Files to modify:** role router/navigation, strings and any reusable medical-record display.
- **APIs/models/controllers:** GET `/doctors/me/patients`, GET `/doctors/me/patients/:patientId`, POST `/:patientId/notes`; doctor controller/models.
- **UI/tests/manual:** doctor role shell, search/filter, relationship-aware not-found state, history, note form with a deliberate share toggle/confirmation. Test patient A/B isolation, draft vs shared note and network retry.
- **Privacy/safety/risk:** highest sensitivity. Backend relationship checks are necessary but add UI role guards and no sensitive debug logs. Do not combine with posts/analytics.

### Phase 11 — Doctor Posts

- **Goal /scope / user role:** doctor-owned post CRUD and then public doctor-detail rendering.
- **Type / complexity:** existing backend; **Medium**.
- **Files to create:** `mobile/lib/features/doctor_posts/{data/doctor_posts_api.dart,models/doctor_post_model.dart,providers/doctor_posts_provider.dart,screens/doctor_posts_screen.dart,widgets/{doctor_post_card,doctor_post_editor}.dart}` and tests.
- **Files to modify:** doctor detail screen/sections, route/navigation/strings.
- **APIs/models/controllers:** GET/POST `/doctors/me/posts`, PUT/DELETE `/doctors/me/posts/:postId`, GET `/doctors/:id/posts`.
- **UI/tests/manual:** list/editor/delete confirmation/status badges; public published-post tab. Test role ownership, publish/draft representation and XSS-safe plain text rendering.
- **Privacy/safety/risk:** content governance/moderation requirements are **Needs verification**. Kept separate from clinical patient data.

### Phase 12 — Feedback statistics

- **Goal / scope / user role:** optional public/home feedback aggregate matching web visual content.
- **Type / complexity:** existing backend; **Small**.
- **Files to create:** `mobile/lib/features/feedback_stats/{data/feedback_stats_api.dart,models/feedback_stats_model.dart,providers/feedback_stats_provider.dart,widgets/feedback_stats_section.dart}` and tests.
- **Files to modify:** `home_screen.dart` or future public landing, strings.
- **APIs/models/controllers:** GET `/feedback/stats`; stats model/provider.
- **UI/tests/manual:** accessible total/average/distribution/category/recommendation cards; do not expose comments/email. Test zero/partial data and Arabic/dark. |
- **Risks:** public user name/avatar display should be confirmed against consent policy.

### Phase 13 — Admin Analytics

- **Goal / scope / user role:** isolated admin dashboard equivalent to `analytics.html`.
- **Type / complexity:** existing backend payload verification; **Large**.
- **Files to create:** `mobile/lib/features/admin_analytics/{data/admin_analytics_api.dart,models/dashboard_stats_model.dart,providers/admin_analytics_provider.dart,screens/admin_analytics_screen.dart,widgets/{analytics_metric_grid,analytics_chart_card}.dart}` and tests.
- **Files to modify:** role router/navigation, chart dependency only if approved, strings.
- **APIs/models/controllers:** GET `/dashboard/stats`; strongly typed stats model/controller.
- **UI/tests/manual:** admin gate, metric grid, chart/empty-awaiting-data/error cards. Test 401/403, empty aggregate payload, 320/600+ layouts and refresh.
- **Privacy/safety/risk:** aggregate data only; chart labels must not expose individual clinical information. This is intentionally after patient/doctor care work.

### Phase 14 — Public landing polish, role navigation, and release readiness

- **Goal / scope / user role:** complete entry points and integrate patient/doctor/admin navigation without mixing their data surfaces.
- **Type / complexity:** mobile-only plus release verification; **Large**.
- **Files to create:** `mobile/lib/features/landing/screens/public_home_screen.dart`, role-shell widgets and comprehensive release/router/golden tests.
- **Files to modify:** `app_router.dart`, `route_paths.dart`, `main_shell.dart`, `main.dart`, home/actions/localization/theme configuration, Android/iOS branding/signing config as authorized.
- **APIs/models/controllers:** `/users/me`, optional `/feedback/stats`; role navigation controller/redirect only if needed.
- **UI/tests/manual:** public landing, sign-in/register entry, patient/doctor/admin shells, theme switch, accessibility sweep. Verify release builds and account access matrix.
- **Privacy/safety/risk:** do not make a route visible just because it is hidden in navigation; enforce router/backend authorization. This final phase comes last because it depends on the surfaces it exposes.

## 14. Testing Strategy

1. **Unit tests:** JSON parsing, availability-window slot generation, date/time/RTL formatting, medical severity mapping, file validation, status/color mapping, configuration/host resolution.
2. **Widget tests:** all async states (loading, skeleton-equivalent, empty, error/retry, success), booking steps, notifications, profile form, each AI tool result, patient/doctor role gates and dashboard cards.
3. **Provider/controller tests:** fake Dio/client timeout, cancellation and `SLOT_BUSY`; refresh single-flight and logout; optimistic notification/cancel rollback; note visibility; virtual doctor STT/TTS/report failures.
4. **API client tests:** mock Dio adapters for every request path, request body/query/multipart headers, envelope failure parsing, 401 refresh/retry and no medical/body log leakage.
5. **Navigation tests:** splash authenticated/unauthenticated route, return path/deep-link behavior, expired token, patient/doctor/admin permissions, unavailable feature route behavior.
6. **Responsive tests:** 320px, 360px, 411px, 600px+, landscape, text scale 1.5 and 2.0. Check bottom navigation, long Arabic labels, form keyboard avoidance and maps/sheets.
7. **RTL/LTR and theme tests:** Arabic RTL and English LTR for each new screen; light/dark/system behavior after the theme controller phase.
8. **Privacy regression tests:** assert log interceptor never prints medical text, authorization, headers, coordinates, report/session IDs or local paths; assert location clears after chat send; assert UI error strings are generic.
9. **Manual physical-device tests:** Android and iOS microphone/location/files, network loss/recovery, actual timeouts, audio/PDF and external map behavior.
10. **Backend/AI contract verification:** an integration suite against a controlled test environment for auth, appointment slot race, ownership, notes visibility, AI failure modes and report 503 fallback.
11. **Release build tests:** Android signed release install, network-security/TLS, iOS archive/TestFlight preparation, no debug logging, app name/icon/version/privacy manifests.

## 15. Manual Verification Checklist

- [ ] Android physical device: install debug and signed release candidate; test on same Wi-Fi/LAN and mobile network failure.
- [ ] iOS physical device: location and microphone permission text/prompt, voice recording/playback, report open.
- [ ] Backend `/api/health` and AI `/health` are reachable from device; port 8001/firewall/TLS validated.
- [ ] Authentication: register, verify, login, Google sign-in, forgot/reset link/code, refresh after forced 401, logout and app restart.
- [ ] Clinics: search/filter/pagination, GPS/manual district/manual map location, detail contacts/maps.
- [ ] Doctors: search/filter/detail/availability/associated clinics; public posts once implemented.
- [ ] Maps: foreground location denied/allowed/disabled, no background tracking, result marker selection and navigation behavior.
- [ ] Chatbot: Arabic/English, location attach/clear, long AI response/timeout/retry, conversation history/search/rename/delete and mapped results.
- [ ] Virtual Doctor: start, microphone denied/permanently denied, 45-second STT budget, TTS fallback, long final message, report generation/download/503 state.
- [ ] Appointment booking: clinic/date/slot, no slot, double-book `SLOT_BUSY`, telemedicine, cancel with reason, refresh list.
- [ ] Notifications: unread/read one/read all/delete/offline retry; no sensitive content in logs.
- [ ] Profile: update/avatar/password/language server sync/theme persistence once implemented.
- [ ] Prescriptions, records and My Reports: empty/data/error states and safe details/share behavior.
- [ ] Patient My Doctor/shared notes and doctor portal: patient/doctor/admin role isolation, draft vs shared notes, relationship not-found state.
- [ ] Admin analytics: admin-only route, no individual health data, empty/error stats.
- [ ] Dark mode, Arabic RTL, English LTR, 320/360/411/600+ widths, landscape, text scale 1.5/2.0, screen-reader semantics.
- [ ] Debug and release builds: no tokens, medical text, coordinates, report/session IDs or local paths in logs/errors.

## 16. Risks and Blockers

| Severity | Risk/blocker | Affected feature | Evidence | Impact | Mitigation | Blocks implementation? |
|---|---|---|---|---|---|---|
| Critical | Direct unauthenticated AI endpoints with wildcard CORS | triage, drugs, summaries, Virtual Doctor | `ai-service/chatbot/main.py` enables `allow_origins=["*"]`; AI route schemas lack auth | medical text/audio/files can be sent without app identity; production privacy/abuse exposure | Define authenticated gateway or AI auth, restrictive production CORS, rate limits, consent/retention/deletion controls | Blocks production release of AI features; does not block mock UI work |
| Critical | Hard-coded HTTP LAN endpoint | all mobile network calls | `AppConfig.baseUrl = http://192.168.0.105:3001/api` | fails off that LAN; unsuitable for production; insecure transport | environment/build config + TLS + device verification | Blocks release |
| Critical | iOS microphone declaration absent | Virtual Doctor | no `NSMicrophoneUsageDescription` in inspected `Info.plist` | iOS voice feature can be denied/crash/fail platform validation | add usage description and device test | Blocks iOS Virtual Doctor release |
| High | Chatbot mobile timeout shorter than backend AI client | chatbot | mobile defaults 15s; backend AI client defaults 60s | false “failed” state for valid slow answer | request-specific bounded timeout/retry/error category | Blocks reliable chatbot release |
| High | No router-level auth/role redirect | all protected routes/role portals | GoRouter routes have no redirect; splash chooses initial route only | stale/deep routes can show unauthorized UI until API fails | central auth/role redirect + tests; backend remains authority | Blocks safe portal rollout |
| High | Appointment available slots are optimistic windows | booking | backend returns availability windows; web generates slots; race resolves only at POST `SLOT_BUSY` | patient can select a now-booked slot | retain clear retry or add atomic backend availability/reservation | Blocks final booking UX until verified |
| High | No profile mutation/avatar/password/preferences sync | account | no Flutter profile feature/client | user cannot manage account or synchronize web language | Phase 4 | No, but high parity gap |
| High | Doctor/patient-note data is sensitive | care portal | web has scoped endpoints; mobile absent | accidental display/cache/share of notes would be harmful | role/relationship tests, explicit visibility control, no logs/caches | Blocks care portal until controls proven |
| High | Medical tool safety/disclaimer/escalation absent | symptom/drug/report tools | all web-only | unsafe UX if implemented superficially | shared medical safety component, triage tests, clinical review | Blocks tool release |
| Medium | Cleartext Android traffic allowed | network | `usesCleartextTraffic="true"` | weak transport in release if left enabled | production TLS/network security config | Blocks production release |
| Medium | Debug signing/generic application identity | release | Android build uses debug signing; `com.example.mobile`; display name Mobile | not store/release ready | app identity/version/icon/signing work | Blocks release |
| Medium | Localization is incomplete in Flutter | patient UX | hard-coded English in chatbot widgets/screens | Arabic-first platform has inconsistent clinical UI | move literals to `AppStrings`, RTL tests | Does not block prototyping; blocks polish/release gate |
| Medium | Theme selection not persisted | design parity | no theme controller/mode | web/mobile preference mismatch | theme controller/storage | No |
| Medium | Test gaps in patient care/auth | regression quality | no auth/appointments/records/prescriptions/feedback tests | high-risk workflows can regress | add phase-local test gates | Blocks release readiness |
| Medium | AI health/model status not surfaced | Virtual Doctor | AI warmup is best effort; no `/health` client | device cannot distinguish unreachable AI from a feature fault | preflight/diagnostic-safe retry | No, but complicates support |
| Low | README port drift | developer setup | README says 3000 while code uses 3001 | onboarding confusion | update as separately authorized documentation change | No |

## 17. Final Recommended Execution Order

1. **Phase 0:** reliability, permissions, session guard, TLS/config/release gate. It protects all existing medical paths.
2. **Phase 1:** chatbot timeout/localization hardening. Existing high-use AI path needs trustworthy failure behavior.
3. **Phase 2:** appointment booking/cancellation. Core patient care outcome before nonessential polish.
4. **Phase 3:** notifications. Do not mix with booking; implement after booking states are stable.
5. **Phase 4:** profile/settings/theme/role navigation. It establishes account and permission foundations for role portals.
6. **Phases 5–7:** Symptom Checker, Drug Checker, Report Summarizer, each separately with medical safety and privacy gates.
7. **Phase 8:** My Reports/saved places, aggregating already-stable patient data.
8. **Phase 9:** patient My Doctor/shared notes, validating visibility boundaries before clinician writes.
9. **Phase 10:** doctor patient portal/notes, then **Phase 11** doctor posts as a separate, lower-risk content feature.
10. **Phase 12:** feedback statistics, then **Phase 13** isolated admin analytics.
11. **Phase 14:** public landing, complete role navigation, final accessibility/privacy/release verification.

## 18. Appendix

### Frontend files inspected

**Pages (29):**

`frontend/public/analytics.html`, `avatar-preview.html`, `book-appointment.html`, `clinic.html`, `dashboard.html`, `doctor.html`, `doctor-posts.html`, `drug-checker.html`, `feedback.html`, `find-clinics.html`, `find-doctors.html`, `forgot-password.html`, `home.html`, `index.html`, `login.html`, `my-appointments.html`, `my-doctor.html`, `my-patients.html`, `my-prescriptions.html`, `my-records.html`, `my-reports.html`, `notifications.html`, `patient-detail.html`, `profile.html`, `register.html`, `report-summary.html`, `reset-password.html`, `symptom-checker.html`, `verify-email.html`.

**JavaScript (41 in `frontend/src/js/`):**

`analytics.js`, `api.js`, `app.js`, `auth.js`, `book-appointment.js`, `chat.js`, `chip-input.js`, `clinic.js`, `dashboard.js`, `doctor.js`, `doctor-posts.js`, `drug-checker.js`, `feedback.js`, `feedback-dashboard.js`, `find-clinics.js`, `find-doctors.js`, `google-signin.js`, `i18n.js`, `layout.js`, `location.js`, `location-picker.js`, `map.js`, `mini-map.js`, `my-appointments.js`, `my-doctor.js`, `my-patients.js`, `my-prescriptions.js`, `my-records.js`, `my-reports.js`, `notifications.js`, `patient-detail.js`, `profile.js`, `redirect-guard.js`, `report-summary.js`, `sidebar.js`, `symptom-checker.js`, `theme.js`, `toast.js`, `virtual-doctor-session.js`, `virtual-doctor-stt.js`, `virtual-doctor-tts.js`.

**Components/utilities:** `frontend/src/components/chatUI.js`, `mapUI.js`; `frontend/src/utils/dom.js`, `format.js`, `helpers.js`, `motion.js`, `store.js`.

**CSS (23):**

`ai-tools.css`, `analytics.css`, `animation.css`, `appointments.css`, `auth.css`, `avatar-preview.css`, `care.css`, `chat.css`, `components.css`, `dashboard.css`, `feedback.css`, `feedback-dashboard.css`, `forms.css`, `home.css`, `layout.css`, `listing.css`, `main.css`, `map.css`, `notifications.css`, `profile.css`, `records.css`, `reports.css`, `sidebar.css`.

**Hosting/documentation:** `frontend/README.md`, `frontend/Dockerfile`, `frontend/nginx.conf`.

### Mobile files inspected

**Core/routing/main:**

`mobile/lib/main.dart`; `core/config/app_config.dart`; `core/constants/storage_keys.dart`; `core/locale/locale_controller.dart`; `core/localization/app_strings.dart`; `core/network/{api_exception,api_host_resolver,auth_interceptor,dio_client,error_interceptor,network_log_interceptor}.dart`; `core/providers/core_providers.dart`; `core/storage/secure_storage_service.dart`; `core/theme/app_theme.dart`; `core/utils/{date_formatting,validators}.dart`; `routes/{app_router,main_shell,route_paths}.dart`.

**Feature files:**

- `features/appointments/{data/appointments_api.dart,models/appointment_model.dart,models/enriched_appointment.dart,providers/appointments_provider.dart,screens/appointments_screen.dart,utils/appointment_filters.dart,widgets/appointment_card.dart}`.
- `features/auth/{data/auth_api.dart,data/google_auth_service.dart,models/auth_result_model.dart,models/user_model.dart,providers/auth_provider.dart,repositories/auth_repository.dart,screens/forgot_password_screen.dart,screens/login_screen.dart,screens/register_screen.dart,screens/reset_password_screen.dart,screens/verify_code_screen.dart,widgets/auth_page_frame.dart,widgets/google_sign_in_button.dart,widgets/otp_code_input.dart,widgets/password_strength_meter.dart}`.
- `features/chatbot/{data/chatbot_api.dart,models/chatbot_models.dart,providers/chatbot_provider.dart,providers/conversations_provider.dart,screens/chatbot_screen.dart,screens/conversations_screen.dart,widgets/chat_input.dart,widgets/chat_location_banner.dart,widgets/chat_map_result_sheet.dart,widgets/chat_message_bubble.dart,widgets/chat_results_map.dart,widgets/chat_route_card.dart,widgets/chat_typing_indicator.dart,widgets/conversation_drawer.dart,widgets/conversation_list_item.dart,widgets/doctor_result_card.dart,widgets/place_result_card.dart,widgets/suggestion_chips.dart}`.
- `features/discovery/{data/discovery_api.dart,data/location_service.dart,models/clinic_models.dart,models/doctor_models.dart,models/location_models.dart,providers/discovery_provider.dart,providers/location_provider.dart,screens/clinic_detail_screen.dart,screens/clinic_discovery_screen.dart,screens/doctor_detail_screen.dart,screens/doctor_directory_screen.dart,screens/map_foundation_screen.dart,widgets/clinic_detail_sections.dart,widgets/clinic_filter_sheet.dart,widgets/clinic_mini_map.dart,widgets/clinic_result_card.dart,widgets/discovery_map.dart,widgets/doctor_detail_sections.dart,widgets/doctor_filter_sheet.dart,widgets/doctor_result_card.dart,widgets/location_picker_sheet.dart,widgets/place_marker.dart}`.
- `features/feedback/{data/feedback_api.dart,providers/feedback_provider.dart,screens/feedback_screen.dart,widgets/star_rating.dart}`.
- `features/home/{data/user_api.dart,models/user_profile_model.dart,providers/user_provider.dart,screens/home_screen.dart}`.
- `features/prescriptions/{data/prescriptions_api.dart,models/prescription_model.dart,providers/prescriptions_provider.dart,screens/prescriptions_screen.dart,widgets/prescription_detail_sheet.dart}`.
- `features/records/{data/records_api.dart,models/record_entry_model.dart,providers/records_provider.dart,screens/records_screen.dart,widgets/record_detail_sheet.dart}`.
- `features/splash/screens/splash_screen.dart`.
- `features/virtual_doctor/{data/tts_player.dart,data/virtual_doctor_api.dart,data/voice_recorder.dart,models/consultation_models.dart,providers/virtual_doctor_provider.dart,screens/virtual_doctor_screen.dart,widgets/voice_orb.dart}`.

**Shared:** `shared/models/prescription_item_model.dart`; `shared/utils/localized_field.dart`; `shared/widgets/{app_scaffold,app_text_field,empty_state,error_retry_state,page_sections,primary_button,status_badge}.dart`.

**Tests (25):**

`mobile/test/widget_test.dart`; `mobile/test/core/network/network_log_interceptor_test.dart`; `mobile/test/features/chatbot/chat_results_map_test.dart`, `chatbot_api_test.dart`, `chatbot_integration_test.dart`, `chatbot_models_test.dart`, `chatbot_provider_test.dart`, `chatbot_screen_test.dart`, `conversations_provider_test.dart`, `conversations_screen_test.dart`; `mobile/test/features/discovery/clinic_detail_screen_test.dart`, `clinic_discovery_screen_test.dart`, `clinic_models_test.dart`, `discovery_api_test.dart`, `discovery_map_test.dart`, `discovery_provider_test.dart`, `doctor_detail_screen_test.dart`, `doctor_directory_screen_test.dart`, `doctor_models_test.dart`, `location_provider_test.dart`, `location_service_test.dart`; `mobile/test/features/virtual_doctor/consultation_models_test.dart`, `virtual_doctor_provider_test.dart`, `virtual_doctor_screen_test.dart`, `voice_recorder_test.dart`.

**Platform/package configuration (exact textual source/config files scanned):** `mobile/pubspec.yaml`; `mobile/android/.gradle/9.1.0/gc.properties`, `.gradle/buildOutputCleanup/cache.properties`, `.gradle/vcs-1/gc.properties`, `app/build.gradle.kts`, `app/src/debug/AndroidManifest.xml`, `app/src/main/AndroidManifest.xml`, `app/src/main/kotlin/com/example/mobile/MainActivity.kt`, `app/src/main/res/drawable/launch_background.xml`, `app/src/main/res/drawable-v21/launch_background.xml`, `app/src/main/res/values/styles.xml`, `app/src/main/res/values-night/styles.xml`, `app/src/profile/AndroidManifest.xml`, `build.gradle.kts`, `gradle.properties`, `gradle/wrapper/gradle-wrapper.properties`, `local.properties`, `settings.gradle.kts`; `mobile/ios/Flutter/AppFrameworkInfo.plist`, `Debug.xcconfig`, `ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`, `ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Sources/FlutterGeneratedPluginSwiftPackage/FlutterGeneratedPluginSwiftPackage.swift`, `Generated.xcconfig`, `Release.xcconfig`; `mobile/ios/Runner.xcodeproj/project.pbxproj`, `Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist`, `Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist`, `Runner/AppDelegate.swift`, `Runner/Base.lproj/LaunchScreen.storyboard`, `Runner/Base.lproj/Main.storyboard`, `Runner/Info.plist`, `Runner/SceneDelegate.swift`, and `RunnerTests/RunnerTests.swift`. Generated image/icon assets were inventoried but not semantically relevant to parity.

### Endpoint index

**Backend:** `/api/health`, `/api/config`; `/api/auth/{register,login,google,refresh,logout,change-password,forgot-password,reset-password,verify-email,resend-verification}`; `/api/users/me`, `/api/users/me/preferences`, `/api/users/me/avatar`, `/api/users/me/saved-places`; `/api/chat/message`; `/api/conversations`, `/api/conversations/search`, `/api/conversations/:id`, `/api/conversations/:id/title`, `/api/conversations/:id/places`; `/api/clinics`, `/api/clinics/nearby`, `/api/clinics/:id`; `/api/doctors`, `/api/doctors/:id`, `/api/doctors/:id/availability`, `/api/doctors/:id/posts`, `/api/doctors/me/patients`, `/api/doctors/me/patients/:patientId`, `/api/doctors/me/patients/:patientId/notes`, `/api/doctors/me/posts`, `/api/doctors/me/posts/:postId`; `/api/appointments`, `/api/appointments/available-slots`, `/api/appointments/:id`, `/api/appointments/:id/cancel`; `/api/notifications`, `/api/notifications/:id/read`, `/api/notifications/read-all`, `/api/feedback`, `/api/feedback/stats`, `/api/dashboard/stats`; `/api/patients/me/doctors`, `/api/patients/me/doctors/:doctorId/notes`, `/api/patients/me/records`, `/api/patients/me/prescriptions`, `/api/patients/me/medical-records`, `/api/patients/me/medical-records/:id`.

**AI service:** `/health`, `/chat`, `/triage`, `/drug-interactions`, `/prescription-check` (found but not web-used), `/summarize`, `/virtual-doctor/start`, `/virtual-doctor/message`, `/virtual-doctor/session/:session_id`, `/virtual-doctor/transcribe`, `/virtual-doctor/transcribe/status`, `/virtual-doctor/transcribe/warmup`, `/virtual-doctor/speak`, `/virtual-doctor/speak/status`, `/virtual-doctor/speak/warmup`, `/virtual-doctor/report/:session_id`, `/virtual-doctor/report/:report_id/download`.

### Route index

Flutter routes currently verified: `/splash`, `/login`, `/register`, `/forgot-password`, `/verify-code`, `/reset-password`, `/home`, `/records`, `/prescriptions`, `/appointments`, `/feedback`, `/virtual-doctor`, `/map-foundation`, `/clinics`, `/clinics/:id`, `/doctors`, `/doctors/:id`, `/chatbot`, `/chatbot/conversations`, `/chatbot/conversations/:id`.

### Terms and status definitions

| Term | Meaning |
|---|---|
| Done | Evidence shows matching client, model/state, UI and principal workflow. Tests may still be a gap. |
| Partial | Mobile implements a material subset; the missing behavior is stated explicitly. |
| Missing | No sufficient Flutter route/client/model/controller/UI evidence was found. |
| Different by design | Same outcome is intentionally adapted to mobile interaction; difference is explained. |
| Needs verification | Source cannot confirm runtime, deployment, policy, or an ambiguous contract. |
| Critical / High / Medium / Low | Prioritization based on patient safety/privacy/release blocking, core care impact, and dependency order. |
