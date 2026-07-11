--
-- PostgreSQL database dump
--

-- Dumped from database version 17.0
-- Dumped by pg_dump version 17.0

-- Started on 2026-07-11 18:59:08

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5154 (class 0 OID 34501)
-- Dependencies: 226
-- Data for Name: clinics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clinics (id, name_ar, name_en, address_ar, address_en, city, region, latitude, longitude, phone, email, website, operating_hours, services, insurance_accepted, images, logo_url, is_active, verification_status, created_at, updated_at) FROM stdin;
f2bd289b-34f4-4a30-9dbe-fcc67d87cb7d	مستشفى نابلس الطبي	Nablus Medical Hospital	شارع رقم 60، نابلس	60 Street, Nablus	Nablus	شارع رقم 60	32.22340000	35.25780000	+970-9-2381000	info@nablusmed.ps	\N	{"fri": {"open": "08:00", "close": "12:00", "is_off": false}, "mon": {"open": "08:00", "close": "17:00", "is_off": false}, "sat": {"open": "00:00", "close": "00:00", "is_off": true}, "sun": {"open": "08:00", "close": "17:00", "is_off": false}, "thu": {"open": "08:00", "close": "17:00", "is_off": false}, "tue": {"open": "08:00", "close": "17:00", "is_off": false}, "wed": {"open": "08:00", "close": "17:00", "is_off": false}}	{طوارئ,"عناية مركزة",عمليات,أشعة,مختبر}	{"الأردنية للتأمين","التأمين الصحي الحكومي","التأمين الصحي الخاص"}	{}	\N	t	verified	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
3198c9d1-e964-4dff-b151-3de677a607af	عيادة القلب المتميزة	Elite Cardiac Clinic	رفيديا، شارع المستشفى القديم	Rafidia, Old Hospital Street	Nablus	رفيديا	32.22560000	35.25230000	+970-9-2345671	cardio@eliteclinic.ps	\N	{"fri": {"open": "08:00", "close": "12:00", "is_off": false}, "mon": {"open": "08:00", "close": "17:00", "is_off": false}, "sat": {"open": "00:00", "close": "00:00", "is_off": true}, "sun": {"open": "08:00", "close": "17:00", "is_off": false}, "thu": {"open": "08:00", "close": "17:00", "is_off": false}, "tue": {"open": "08:00", "close": "17:00", "is_off": false}, "wed": {"open": "08:00", "close": "17:00", "is_off": false}}	{"تخطيط القلب",إيكو,"اختبار الإجهاد"}	{"الأردنية للتأمين","التأمين الصحي الخاص"}	{}	\N	t	verified	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
33043cfa-b65a-4ae5-a701-22b27025a66d	مركز الرعاية الصحية الأولية	Primary Healthcare Center	المدينة القديمة، قرب السوق	Old City, Near the Market	Nablus	المدينة القديمة	32.21980000	35.25120000	+970-9-2381234	phc@nablus.ps	\N	{"fri": {"open": "08:00", "close": "12:00", "is_off": false}, "mon": {"open": "08:00", "close": "17:00", "is_off": false}, "sat": {"open": "00:00", "close": "00:00", "is_off": true}, "sun": {"open": "08:00", "close": "17:00", "is_off": false}, "thu": {"open": "08:00", "close": "17:00", "is_off": false}, "tue": {"open": "08:00", "close": "17:00", "is_off": false}, "wed": {"open": "08:00", "close": "17:00", "is_off": false}}	{"طب عام",تطعيمات,"رعاية الأم والطفل"}	{"التأمين الصحي الحكومي"}	{}	\N	t	verified	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
18ace0e8-7e31-41ff-b837-a30011b6494b	عيادة الأطفال السعيدة	Happy Kids Clinic	عين بيت الماء، قرب مدرسة بنات	Ein Beit El Ma, Near Girls School	Nablus	عين بيت الماء	32.22150000	35.24890000	+970-9-2345673	kids@happyclinic.ps	\N	{"fri": {"open": "08:00", "close": "12:00", "is_off": false}, "mon": {"open": "08:00", "close": "17:00", "is_off": false}, "sat": {"open": "00:00", "close": "00:00", "is_off": true}, "sun": {"open": "08:00", "close": "17:00", "is_off": false}, "thu": {"open": "08:00", "close": "17:00", "is_off": false}, "tue": {"open": "08:00", "close": "17:00", "is_off": false}, "wed": {"open": "08:00", "close": "17:00", "is_off": false}}	{"طب أطفال",تطعيمات,"فحص نمو"}	{"الأردنية للتأمين","التأمين الصحي الحكومي","التأمين الصحي الخاص"}	{}	\N	t	verified	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
025fa604-510d-41c5-a273-5a21f592a454	مركز المستقبل للأشعة	Future Radiology Center	الخالدية، بجوار البنك الإسلامي	Al-Khalidiyah, Next to Islamic Bank	Nablus	الخالدية	32.22780000	35.25900000	+970-9-2345674	radio@future.ps	\N	{"fri": {"open": "08:00", "close": "12:00", "is_off": false}, "mon": {"open": "08:00", "close": "17:00", "is_off": false}, "sat": {"open": "00:00", "close": "00:00", "is_off": true}, "sun": {"open": "08:00", "close": "17:00", "is_off": false}, "thu": {"open": "08:00", "close": "17:00", "is_off": false}, "tue": {"open": "08:00", "close": "17:00", "is_off": false}, "wed": {"open": "08:00", "close": "17:00", "is_off": false}}	{"أشعة عادية",سونار,"رنين مغناطيسي","أشعة مقطعية"}	{"الأردنية للتأمين","التأمين الصحي الخاص"}	{}	\N	t	verified	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5150 (class 0 OID 34432)
-- Dependencies: 222
-- Data for Name: specialties; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.specialties (id, name_ar, name_en, description_ar, description_en, icon, is_active, created_at) FROM stdin;
f341b171-7888-4be5-8443-03bbfc8a0fc9	طب عام	General Practice	طب الأسرة والطب العام	Family and general medicine	stethoscope	t	2026-07-11 16:32:26.181149+03
f035614b-08e1-451c-b3ab-6ecffc176fdc	طب القلب	Cardiology	أمراض القلب والأوعية الدموية	Heart and cardiovascular diseases	heart-pulse	t	2026-07-11 16:32:26.181149+03
4cddf958-ccb9-44f3-92b6-09dde7845d1f	طب الأطفال	Pediatrics	طب الأطفال وحديثي الولادة	Pediatrics and neonatology	baby	t	2026-07-11 16:32:26.181149+03
020aa03a-b81d-47b0-9d3f-d732310ca134	طب النساء والتوليد	Obstetrics & Gynecology	صحة المرأة والحمل والولادة	Women health, pregnancy and childbirth	person-pregnant	t	2026-07-11 16:32:26.181149+03
18c27fa6-5b95-40b2-9800-49f571e360e3	جراحة العظام	Orthopedics	جراحة العظام والمفاصل	Orthopedic and joint surgery	bone	t	2026-07-11 16:32:26.181149+03
622d2db6-eb27-4f82-bcfa-a98658f6e768	طب العيون	Ophthalmology	أمراض العيون وجراحتها	Eye diseases and surgery	eye	t	2026-07-11 16:32:26.181149+03
beb56852-5f9f-48f9-be0d-710947e0404c	طب الأنف والأذن والحنجرة	ENT	أمراض الأنف والأذن والحنجرة	Ear, nose and throat diseases	ear	t	2026-07-11 16:32:26.181149+03
b6cd78e2-4fa1-4d99-a927-30ba2194d532	طب الجلدية	Dermatology	أمراض الجلد والشعر والأظافر	Skin, hair and nail diseases	hand-sparkles	t	2026-07-11 16:32:26.181149+03
e94411f5-323a-4bbb-8d2f-e36421072823	طب الأسنان	Dentistry	طب الأسنان العام	General dentistry	tooth	t	2026-07-11 16:32:26.181149+03
4893d6f6-5c2b-4365-bc63-77680b361c4e	طب الأعصاب	Neurology	أمراض الجهاز العصبي	Nervous system diseases	brain	t	2026-07-11 16:32:26.181149+03
ae3319bd-7175-40f0-8e93-03238ee22c3c	طب نفسي	Psychiatry	الصحة النفسية والأمراض النفسية	Mental health and psychiatric disorders	brain	t	2026-07-11 16:32:26.181149+03
beba7a2f-fab6-4425-9635-cafda59a7870	طب الجهاز الهضمي	Gastroenterology	أمراض الجهاز الهضمي	Digestive system diseases	stomach	t	2026-07-11 16:32:26.181149+03
53a974c8-f0b6-4ab3-8794-0942349d40e3	طب الغدد الصماء	Endocrinology	أمراض الغدد والتمثيل الغذائي	Endocrine and metabolic diseases	chart-line	t	2026-07-11 16:32:26.181149+03
5e6d5307-7ac8-4a19-8f7d-cff8f734b20f	طب الكلى	Nephrology	أمراض الكلى والمسالك البولية	Kidney and urinary tract diseases	droplet	t	2026-07-11 16:32:26.181149+03
798983e5-30ce-4c0b-b533-81c40f1153bf	طب الدم	Hematology	أمراض الدم	Blood diseases	tint	t	2026-07-11 16:32:26.181149+03
3ff22707-9e27-4957-a044-cfed8ac6d677	طب الأورام	Oncology	علاج الأورام والسرطان	Tumor and cancer treatment	ribbon	t	2026-07-11 16:32:26.181149+03
150e298e-5055-4352-b36b-3850f479af93	طب الرئة	Pulmonology	أمراض الجهاز التنفسي	Respiratory system diseases	lungs	t	2026-07-11 16:32:26.181149+03
41621db7-2128-4a42-90bb-fef7bf6f2c6a	طب الروماتيزم	Rheumatology	أمراض المفاصل والروماتيزم	Joint and rheumatism diseases	hands-bubbles	t	2026-07-11 16:32:26.181149+03
fda6f73e-3bbf-4ee7-8ebb-70fb50bfb458	جراحة عامة	General Surgery	الجراحة العامة	General surgery	scissors	t	2026-07-11 16:32:26.181149+03
493f59e1-5fc7-4c3d-8b87-d26f81368116	جراحة المسالك البولية	Urology	جراحة المسالك البولية	Urology surgery	kidney	t	2026-07-11 16:32:26.181149+03
4c65b864-5a09-4ea0-805f-0f3e132631c0	طب الشيخوخة	Geriatrics	طب كبار السن	Elderly medicine	person-cane	t	2026-07-11 16:32:26.181149+03
5d0a18c7-b48a-4b2b-b38a-f7528e8a22c0	طب الطوارئ	Emergency Medicine	طب الطوارئ والإسعافات	Emergency and first aid	truck-medical	t	2026-07-11 16:32:26.181149+03
a9ae4138-e032-4f77-a547-cbaac6e51009	التخدير	Anesthesiology	التخدير والعناية المركزة	Anesthesia and ICU	syringe	t	2026-07-11 16:32:26.181149+03
4f62124b-47ba-4b21-ad17-1ab895a44566	الأشعة	Radiology	الأشعة التشخيصية والعلاجية	Diagnostic and therapeutic radiology	radio	t	2026-07-11 16:32:26.181149+03
8804476c-b892-420e-b3a5-d0d585d7a53c	طب إعادة التأهيل	Physiotherapy	العلاج الطبيعي والتأهيلي	Physical therapy and rehabilitation	person-walking	t	2026-07-11 16:32:26.181149+03
\.


--
-- TOC entry 5147 (class 0 OID 34375)
-- Dependencies: 219
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, email, password_hash, role, is_active, email_verified, preferred_language, failed_login_attempts, locked_until, created_at, updated_at, deleted_at) FROM stdin;
a1111111-1111-1111-1111-111111111111	admin@medorbit.ps	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	admin	t	t	ar	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
d2222222-2222-2222-2222-222222222221	dr.smith@medorbit.ps	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	doctor	t	t	en	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
d2222222-2222-2222-2222-222222222222	dr.johnson@medorbit.ps	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	doctor	t	t	ar	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
d2222222-2222-2222-2222-222222222223	dr.williams@medorbit.ps	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	doctor	t	t	en	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
a3333333-3333-3333-3333-333333333331	mahmoud@example.com	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	patient	t	t	ar	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
a3333333-3333-3333-3333-333333333332	fatima@example.com	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	patient	t	t	ar	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
a3333333-3333-3333-3333-333333333333	john@example.com	$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa	patient	t	t	en	0	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03	\N
fabb3794-cf82-4a64-8d63-84d4f365da08	omar.patient@test.com	$2b$12$upfb9pR2rwRIMZ/yWEuXgebshwrWx/5g2h7QJjjYNRuVEAuaKER4y	patient	t	t	ar	0	\N	2026-07-11 17:03:19.11906+03	2026-07-11 17:51:05.2533+03	\N
8773be49-0538-4343-b78b-8e03144fa51d	test.user@gmail.com	$2b$12$x81lI4LyDbzvceBLk2421OLcuel6Ek6x4SKUbxd8ocHs0M7xdyeCO	patient	t	t	ar	0	\N	2026-07-11 18:09:43.504634+03	2026-07-11 18:30:10.593764+03	\N
\.


--
-- TOC entry 5152 (class 0 OID 34453)
-- Dependencies: 224
-- Data for Name: doctors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.doctors (id, user_id, medical_license_number, specialty_id, sub_specialty, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings, created_at, updated_at) FROM stdin;
9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	d2222222-2222-2222-2222-222222222221	ML-2020-001	f035614b-08e1-451c-b3ab-6ecffc176fdc	\N	15	100.00	30	{"MD - University of Jordan","Fellowship - Cleveland Clinic"}	{"Jordan Medical Board Certified","American Board Eligible"}	دكتور محمد أحمد هو طبيب قلب معتمد بخبرة 15 عاماً في تشخيص وعلاج أمراض القلب. متخصص في علاج ارتفاع ضغط الدم وأمراض الشرايين.	Dr. Mohammad Smith is a certified cardiologist with 15 years of experience in diagnosing and treating heart diseases. Specialized in hypertension and arterial disease treatment.	t	4.80	45	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
144be161-a3bd-4d71-a128-b409cfc179e8	d2222222-2222-2222-2222-222222222222	ML-2020-002	f341b171-7888-4be5-8443-03bbfc8a0fc9	\N	20	80.00	30	{"MD - An-Najah National University","Specialty - Damascus University"}	{"Palestinian Medical Board"}	دكتور أحمد عبدالله هو طبيب عام متمرس يقدم خدمات الرعاية الصحية الأولية لجميع أفراد العائلة.	Dr. Ahmad Abdullah is an experienced general practitioner providing primary healthcare services for all family members.	t	4.50	120	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
9f697484-4cf3-497d-bcff-e005551e3d80	d2222222-2222-2222-2222-222222222223	ML-2020-003	4cddf958-ccb9-44f3-92b6-09dde7845d1f	\N	12	150.00	45	{"MD - Harvard Medical School","Fellowship - Boston Children Hospital"}	{"American Board of Pediatrics","Neonatal Resuscitation Program"}	دكتورة سارة ويليامز هي طبيبة أطفال متخصصة في رعاية المواليد والأطفال. تقدم خدمات التطعيم والفحوصات الدورية.	Dr. Sarah Williams is a pediatrician specialized in neonatal and child care. Provides vaccination and regular checkup services.	t	4.90	78	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5149 (class 0 OID 34414)
-- Dependencies: 221
-- Data for Name: patients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.patients (id, user_id, blood_type, allergies, chronic_conditions, emergency_contact_name, emergency_contact_phone, insurance_provider, insurance_policy_number, created_at, updated_at) FROM stdin;
e7be7d1a-b42c-4d50-bc9b-4bd11a538701	a3333333-3333-3333-3333-333333333331	O+	{البنسلين}	{"لا يوجد"}	خالد الخالدي	+970-59-9876543	الأردنية للتأمين	INS-001234	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
dfcfc565-c703-478b-9af3-c3f028021899	a3333333-3333-3333-3333-333333333332	A+	{}	{السكري}	عبدالله الزيود	+970-59-8765432	التأمين الصحي الحكومي	GOV-005678	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
98877efe-34b0-4001-a9ce-6512142a2d6c	a3333333-3333-3333-3333-333333333333	B+	{}	{}	ماريا سميث	+970-59-7654321	\N	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
59d8c27f-39e4-4ff4-8294-6556391627d3	fabb3794-cf82-4a64-8d63-84d4f365da08	\N	\N	\N	\N	\N	\N	\N	2026-07-11 17:03:19.131819+03	2026-07-11 17:03:19.131819+03
2e537282-369f-4a49-8a5a-bd84c428378e	8773be49-0538-4343-b78b-8e03144fa51d	\N	\N	\N	\N	\N	\N	\N	2026-07-11 18:09:43.545538+03	2026-07-11 18:09:43.545538+03
\.


--
-- TOC entry 5158 (class 0 OID 34576)
-- Dependencies: 230
-- Data for Name: appointments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.appointments (id, appointment_number, patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit, notes, meeting_link, cancelled_at, cancelled_by, cancellation_reason, created_at, updated_at) FROM stdin;
ca642b1b-bb32-4b5b-b19c-97dd2d3ac7a5	APT-2026-000001	e7be7d1a-b42c-4d50-bc9b-4bd11a538701	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	3198c9d1-e964-4dff-b151-3de677a607af	2026-07-04	09:00:00	09:30:00	30	in_person	completed	فحص دوري للقلب	\N	\N	\N	\N	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
68cb390e-d3fb-453c-80c7-c57e9faec732	APT-2026-000002	e7be7d1a-b42c-4d50-bc9b-4bd11a538701	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	2026-07-14	10:00:00	10:30:00	30	in_person	confirmed	صداع مستمر	\N	\N	\N	\N	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
155c6a17-4924-419a-9b10-9a8343b97905	APT-2026-000003	dfcfc565-c703-478b-9af3-c3f028021899	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	2026-07-12	11:00:00	11:30:00	30	in_person	scheduled	متابعة السكري	\N	\N	\N	\N	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
234023c3-ec74-4d16-a77a-f17f729f2dfb	APT-2026-000004	98877efe-34b0-4001-a9ce-6512142a2d6c	9f697484-4cf3-497d-bcff-e005551e3d80	\N	2026-07-16	14:00:00	14:45:00	45	telemedicine	confirmed	استشارة حول تطعيمات الطفل	\N	\N	\N	\N	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5170 (class 0 OID 34853)
-- Dependencies: 242
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_logs (id, user_id, user_role, action, entity_type, entity_id, old_values, new_values, ip_address, user_agent, created_at) FROM stdin;
\.


--
-- TOC entry 5165 (class 0 OID 34747)
-- Dependencies: 237
-- Data for Name: chatbot_conversations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chatbot_conversations (id, session_id, user_id, language, platform, is_active, last_message_at, started_at, ended_at) FROM stdin;
\.


--
-- TOC entry 5166 (class 0 OID 34765)
-- Dependencies: 238
-- Data for Name: chatbot_messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chatbot_messages (id, conversation_id, message_text, message_type, intent, confidence_score, response_text, metadata, created_at) FROM stdin;
\.


--
-- TOC entry 5157 (class 0 OID 34553)
-- Dependencies: 229
-- Data for Name: doctor_availability; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.doctor_availability (id, doctor_id, clinic_id, day_of_week, specific_date, start_time, end_time, slot_duration, is_telemedicine, is_active, created_at) FROM stdin;
39a878ce-9af4-47b3-a1b8-a15c0f393225	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	3198c9d1-e964-4dff-b151-3de677a607af	0	\N	08:00:00	12:00:00	30	f	t	2026-07-11 16:32:47.906288+03
95977745-4504-4173-bb61-6f0c8b7a237d	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	3198c9d1-e964-4dff-b151-3de677a607af	2	\N	08:00:00	12:00:00	30	f	t	2026-07-11 16:32:47.906288+03
cfce3755-aaf3-427c-b4e3-13dd7a51558e	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	3198c9d1-e964-4dff-b151-3de677a607af	4	\N	08:00:00	12:00:00	30	f	t	2026-07-11 16:32:47.906288+03
a3e0556c-bf76-4357-bab7-57e2605d035f	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	\N	6	\N	09:00:00	13:00:00	30	t	t	2026-07-11 16:32:47.906288+03
c072c66e-3ccc-4bc1-8907-e67c1f996d1e	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	1	\N	08:00:00	15:00:00	30	f	t	2026-07-11 16:32:47.906288+03
8a482739-c857-43c4-8927-e847b1d74032	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	2	\N	08:00:00	15:00:00	30	f	t	2026-07-11 16:32:47.906288+03
16128974-49ea-4dae-a385-998b1eee5868	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	3	\N	08:00:00	15:00:00	30	f	t	2026-07-11 16:32:47.906288+03
d05b8254-35fd-48d4-a716-5084398d0bd8	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	4	\N	08:00:00	15:00:00	30	f	t	2026-07-11 16:32:47.906288+03
87073960-2871-4851-8fdf-f7fc2a34ca5f	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	5	\N	08:00:00	12:00:00	30	f	t	2026-07-11 16:32:47.906288+03
4edd80e5-3dc3-4741-9f19-c6da0ff9926d	9f697484-4cf3-497d-bcff-e005551e3d80	18ace0e8-7e31-41ff-b837-a30011b6494b	0	\N	09:00:00	17:00:00	30	f	t	2026-07-11 16:32:47.906288+03
5f47c105-6f38-4f0f-8008-e799e16d4658	9f697484-4cf3-497d-bcff-e005551e3d80	18ace0e8-7e31-41ff-b837-a30011b6494b	1	\N	09:00:00	17:00:00	30	f	t	2026-07-11 16:32:47.906288+03
a369fdff-b218-4cfa-a270-f0bcea084d11	9f697484-4cf3-497d-bcff-e005551e3d80	18ace0e8-7e31-41ff-b837-a30011b6494b	3	\N	09:00:00	17:00:00	30	f	t	2026-07-11 16:32:47.906288+03
a3b7ff88-72bb-4fd0-8600-7354f8014b86	9f697484-4cf3-497d-bcff-e005551e3d80	18ace0e8-7e31-41ff-b837-a30011b6494b	5	\N	09:00:00	13:00:00	30	f	t	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5155 (class 0 OID 34519)
-- Dependencies: 227
-- Data for Name: doctor_clinic_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.doctor_clinic_assignments (id, doctor_id, clinic_id, consultation_fee_override, schedule, is_primary, is_active, created_at) FROM stdin;
c649aae7-552a-4fbb-83d3-747efb4ddaca	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	f2bd289b-34f4-4a30-9dbe-fcc67d87cb7d	150.00	\N	t	t	2026-07-11 16:32:47.906288+03
ca594c39-1c2f-42ba-b014-fdcc9c5cb926	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	3198c9d1-e964-4dff-b151-3de677a607af	100.00	\N	f	t	2026-07-11 16:32:47.906288+03
c551817d-6689-45b1-8381-629c0218d2c3	144be161-a3bd-4d71-a128-b409cfc179e8	33043cfa-b65a-4ae5-a701-22b27025a66d	50.00	\N	t	t	2026-07-11 16:32:47.906288+03
6db7111f-c4dd-49d1-b819-9a6f1acd832c	9f697484-4cf3-497d-bcff-e005551e3d80	f2bd289b-34f4-4a30-9dbe-fcc67d87cb7d	180.00	\N	t	t	2026-07-11 16:32:47.906288+03
02181358-3673-4e39-92ef-ec96686a81e2	9f697484-4cf3-497d-bcff-e005551e3d80	18ace0e8-7e31-41ff-b837-a30011b6494b	120.00	\N	f	t	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5168 (class 0 OID 34801)
-- Dependencies: 240
-- Data for Name: doctor_reviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.doctor_reviews (id, appointment_id, patient_id, doctor_id, rating, review_text_ar, review_text_en, professionalism_rating, treatment_rating, communication_rating, is_visible, is_approved, created_at) FROM stdin;
92def174-5a2f-4689-9dce-c9bff2ef1b11	ca642b1b-bb32-4b5b-b19c-97dd2d3ac7a5	e7be7d1a-b42c-4d50-bc9b-4bd11a538701	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	5	دكتور ممتاز وفريق العمل جداً محترفين. شرح لي الحالة بوضوح.	Excellent doctor and very professional staff. Explained my condition clearly.	5	5	5	t	t	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5164 (class 0 OID 34734)
-- Dependencies: 236
-- Data for Name: email_queue; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.email_queue (id, recipient_email, recipient_name, subject, body_html, body_text, status, attempts, last_attempt_at, sent_at, error_message, scheduled_for, priority, created_at) FROM stdin;
\.


--
-- TOC entry 5171 (class 0 OID 34870)
-- Dependencies: 243
-- Data for Name: generated_reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.generated_reports (id, template_id, generated_by, report_title, report_type, report_data, format, file_path, generated_at, expires_at) FROM stdin;
\.


--
-- TOC entry 5159 (class 0 OID 34615)
-- Dependencies: 231
-- Data for Name: medical_records; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medical_records (id, record_number, patient_id, doctor_id, appointment_id, record_type, chief_complaint, symptoms, diagnosis, diagnosis_codes, treatment_plan, prognosis, vitals, clinical_notes, doctor_notes, is_draft, created_at, updated_at) FROM stdin;
6b3ee502-ee03-41ff-a17e-7243c106d6b1	MR-2026-000001	e7be7d1a-b42c-4d50-bc9b-4bd11a538701	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	\N	consultation	فحص دوري للقلب	{"ألم خفيف في الصدر","ضيق تنفس عند المجهود"}	ارتفاع طفيف في ضغط الدم مع معدل ضربات قلب طبيعي	\N	استمرار الأدوية الحالية مع متابعة ضغط الدم يومياً. تقليل الملح في الطعام.	\N	{"weight": 85, "heart_rate": 72, "temperature": 36.8, "blood_pressure": "130/85"}	\N	\N	f	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
f4ce335d-a190-4884-b008-38b78c51398d	MR-2026-000002	e7be7d1a-b42c-4d50-bc9b-4bd11a538701	144be161-a3bd-4d71-a128-b409cfc179e8	\N	consultation	صداع مستمر	{"صداع في مقدمة الرأس",دوخة,أرق}	توتر وصداع توتري	\N	راحة وتجنب التوتر. مسكن للصداع عند الحاجة. متابعة في حال استمرار الأعراض.	\N	{"heart_rate": 75, "blood_pressure": "125/80"}	\N	\N	f	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5160 (class 0 OID 34648)
-- Dependencies: 232
-- Data for Name: medical_record_attachments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medical_record_attachments (id, record_id, file_name, file_type, file_path, file_size_bytes, mime_type, uploaded_by, created_at) FROM stdin;
\.


--
-- TOC entry 5151 (class 0 OID 34442)
-- Dependencies: 223
-- Data for Name: medications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medications (id, name_ar, name_en, generic_name, brand_names, drug_class, active_ingredients, contraindications, side_effects, known_interactions, is_active, created_at) FROM stdin;
2f453ed2-30a9-487e-9598-e24f2aff59b3	باراسيتامول	Paracetamol	Acetaminophen	\N	Analgesic	{Acetaminophen}	{"Liver disease","Alcohol use"}	{Nausea,"Allergic reactions"}	\N	t	2026-07-11 16:32:47.906288+03
84a0a608-8433-4a6f-a9b0-6d6cd5b5a214	أوميبرازول	Omeprazole	Omeprazole	\N	Proton Pump Inhibitor	{Omeprazole}	{Hypersensitivity}	{Headache,Nausea}	\N	t	2026-07-11 16:32:47.906288+03
c11465dc-cb30-4149-93bf-b0bdad119773	أملوديبين	Amlodipine	Amlodipine Besylate	\N	Calcium Channel Blocker	{Amlodipine}	{"Cardiogenic shock","Severe hypotension"}	{Edema,Fatigue,Dizziness}	\N	t	2026-07-11 16:32:47.906288+03
d6263ea3-c772-40a1-a77b-42d7fd071b0c	ميتفورمين	Metformin	Metformin Hydrochloride	\N	Biguanide	{Metformin}	{"Kidney disease","Liver disease"}	{Nausea,Diarrhea,"Stomach pain"}	\N	t	2026-07-11 16:32:47.906288+03
4047f25b-c6ea-4ce3-a57b-12bdec76242b	لورنوكسيكام	Lornoxicam	Lornoxicam	\N	NSAID	{Lornoxicam}	{"Peptic ulcer",Asthma}	{Nausea,"Stomach pain",Dizziness}	\N	t	2026-07-11 16:32:47.906288+03
7808f72b-2603-44f9-8a58-c2962dd50c64	أزيثرومايسين	Azithromycin	Azithromycin Dihydrate	\N	Macrolide Antibiotic	{Azithromycin}	{"Liver problems"}	{Nausea,Diarrhea,"Abdominal pain"}	\N	t	2026-07-11 16:32:47.906288+03
0724c7b0-faf6-47cd-95a6-c7d5db2957ed	ديكلوفيناك	Diclofenac	Diclofenac Sodium	\N	NSAID	{Diclofenac}	{"Active peptic ulcer",Asthma}	{"Stomach pain",Nausea,Headache}	\N	t	2026-07-11 16:32:47.906288+03
c8ef3246-1748-4e70-956c-47559e0f5b8e	كانديسارتان	Candesartan	Candesartan Cilexetil	\N	ARB	{Candesartan}	{Pregnancy,"Biliary obstruction"}	{Dizziness,Headache,"Back pain"}	\N	t	2026-07-11 16:32:47.906288+03
3f59ced8-680b-4bdd-9c64-312d0608540e	أسبرين	Aspirin	Acetylsalicylic Acid	\N	NSAID	{Aspirin}	{"Peptic ulcer","Bleeding disorders"}	{"Stomach irritation",Nausea}	\N	t	2026-07-11 16:32:47.906288+03
a4a09f35-1be5-4b84-a703-b7b244f5438f	وارفارين	Warfarin	Warfarin Sodium	\N	Anticoagulant	{Warfarin}	{"Active bleeding",Pregnancy}	{Bleeding,Bruising}	\N	t	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5156 (class 0 OID 34544)
-- Dependencies: 228
-- Data for Name: nablus_regions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.nablus_regions (id, name_ar, name_en, boundary_geojson, is_active) FROM stdin;
9b48a4e5-a1d8-4f3f-bcf8-b001da16c9db	المدينة القديمة	Old City	{"type": "Polygon", "coordinates": [[[35.26, 32.22], [35.27, 32.22], [35.27, 32.21], [35.26, 32.21], [35.26, 32.22]]]}	t
74b14f5c-5867-4d24-8478-d92dc25ebcf0	رفيديا	Rafidia	{"type": "Polygon", "coordinates": [[[35.25, 32.23], [35.26, 32.23], [35.26, 32.22], [35.25, 32.22], [35.25, 32.23]]]}	t
36ec56b5-2802-40fe-9338-4860da3a1491	عين بيت الماء	Ein Beit El Ma	{"type": "Polygon", "coordinates": [[[35.24, 32.22], [35.25, 32.22], [35.25, 32.21], [35.24, 32.21], [35.24, 32.22]]]}	t
c06ef30b-d087-4f2e-a721-5886f540a6d0	الباذنجان	Al-Batin	{"type": "Polygon", "coordinates": [[[35.23, 32.21], [35.24, 32.21], [35.24, 32.20], [35.23, 32.20], [35.23, 32.21]]]}	t
c1b8bd6d-a99b-46f4-b4ca-588d9b55fd88	الخالدية	Al-Khalidiyah	{"type": "Polygon", "coordinates": [[[35.27, 32.23], [35.28, 32.23], [35.28, 32.22], [35.27, 32.22], [35.27, 32.23]]]}	t
587257d1-137f-4af9-aaac-63a2cfad13ec	النزهة	Al-Nazha	{"type": "Polygon", "coordinates": [[[35.26, 32.24], [35.27, 32.24], [35.27, 32.23], [35.26, 32.23], [35.26, 32.24]]]}	t
bebacb01-a340-447a-86e0-9bc6ba218f7c	الإسكان	Al-Iskan	{"type": "Polygon", "coordinates": [[[35.25, 32.24], [35.26, 32.24], [35.26, 32.23], [35.25, 32.23], [35.25, 32.24]]]}	t
2613c5c4-57e1-4200-9361-dbf4ffdd09f6	شارع رقم 60	60 Street	{"type": "Polygon", "coordinates": [[[35.28, 32.21], [35.29, 32.21], [35.29, 32.20], [35.28, 32.20], [35.28, 32.21]]]}	t
\.


--
-- TOC entry 5163 (class 0 OID 34716)
-- Dependencies: 235
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.notifications (id, user_id, title_ar, title_en, message_ar, message_en, notification_type, reference_id, reference_type, channel, is_read, read_at, email_sent_at, created_at) FROM stdin;
0169bbf0-3d86-4908-8c62-c556ff37b1d6	a3333333-3333-3333-3333-333333333331	تأكيد الموعد	Appointment Confirmed	تم تأكيد موعدك مع دكتور أحمد عبدالله يوم غد الساعة 10:00 صباحاً	Your appointment with Dr. Ahmad Abdullah has been confirmed for tomorrow at 10:00 AM	appointment	\N	appointments	in_app	t	\N	\N	2026-07-11 16:32:47.906288+03
0ed5e770-36dd-406e-98e7-27a1ba9b7695	a3333333-3333-3333-3333-333333333331	تذكير	Reminder	لا تنسَ موعدك غداً الساعة 10:00 صباحاً مع دكتور أحمد عبدالله	Don't forget your appointment tomorrow at 10:00 AM with Dr. Ahmad Abdullah	reminder	\N	appointments	in_app	f	\N	\N	2026-07-11 16:32:47.906288+03
52436d71-2af0-4b33-9f5c-cf5420571caf	a1111111-1111-1111-1111-111111111111	مستخدم جديد	New User	تم تسجيل مستخدم جديد: محمود الخالدي	New user registered: Mahmoud Al-Khalidi	system	\N	users	in_app	f	\N	\N	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5161 (class 0 OID 34668)
-- Dependencies: 233
-- Data for Name: prescriptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.prescriptions (id, prescription_number, patient_id, doctor_id, appointment_id, prescription_date, valid_until, status, diagnosis, instructions, doctor_notes, created_at, updated_at) FROM stdin;
911e9b7b-a8d3-46d4-a3a9-7608ccc95fd6	RX-2026-000001	e7be7d1a-b42c-4d50-bc9b-4bd11a538701	9a1d2b29-cb56-414b-94cc-d8b38e54e1a1	\N	2026-07-11	\N	active	ارتفاع ضغط الدم الخفيف	اتباع نظام غذائي صحي وتقليل الملح	\N	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5162 (class 0 OID 34698)
-- Dependencies: 234
-- Data for Name: prescription_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.prescription_items (id, prescription_id, medication_name_ar, medication_name_en, dosage, frequency, duration, quantity, instructions, refills_allowed, refills_used, is_active, created_at) FROM stdin;
aca4f4d2-eecc-41b4-a9e5-b403784d36cd	911e9b7b-a8d3-46d4-a3a9-7608ccc95fd6	أملوديبين	Amlodipine	5mg	مرة واحدة يومياً	30 يوم	30	يُؤخذ في الصباح مع الطعام	0	0	t	2026-07-11 16:32:47.906288+03
\.


--
-- TOC entry 5167 (class 0 OID 34781)
-- Dependencies: 239
-- Data for Name: symptom_triage_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.symptom_triage_sessions (id, user_id, session_id, reported_symptoms, triage_level, recommended_specialty_id, recommended_specialty_name_ar, recommended_specialty_name_en, confidence_score, recommendations, follow_up_action, created_at) FROM stdin;
\.


--
-- TOC entry 5169 (class 0 OID 34835)
-- Dependencies: 241
-- Data for Name: system_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_settings (id, setting_key, setting_value, description, is_public, requires_restart, updated_at, updated_by) FROM stdin;
17e8a409-71e6-4acd-86e1-0a592b47a416	app_name	"MedOrbit"	Application name	t	f	2026-07-11 16:32:26.181149+03	\N
fc8b2718-a1f3-4c4d-a3be-905a14862691	app_version	"1.0.0"	Current version	t	f	2026-07-11 16:32:26.181149+03	\N
c5e2138a-6fac-4061-80ea-fe5d27fbb84f	support_email	"support@medorbit.ps"	Support email address	t	f	2026-07-11 16:32:26.181149+03	\N
48ccf46a-683a-4f94-a1cd-74feb155d8f9	clinic_default_lat	32.2211	Default latitude for Nablus	t	f	2026-07-11 16:32:26.181149+03	\N
d2d8aeae-3e42-43ed-9f7d-d6e5c8c53b3a	clinic_default_lng	35.2544	Default longitude for Nablus	t	f	2026-07-11 16:32:26.181149+03	\N
0f117167-cf71-4a36-b255-0a215ccd0995	appointment_default_duration	30	Default appointment duration in minutes	t	f	2026-07-11 16:32:26.181149+03	\N
827a2444-ad87-4f7d-b28e-d25acf4cbda5	max_login_attempts	5	Maximum failed login attempts before lockout	f	f	2026-07-11 16:32:26.181149+03	\N
f0da6041-e028-4dad-b7f3-712e7cba288e	token_expiry_minutes	15	Access token expiry in minutes	f	f	2026-07-11 16:32:26.181149+03	\N
0c1668fd-bf30-4b17-a975-c8b814118120	refresh_token_expiry_days	7	Refresh token expiry in days	f	f	2026-07-11 16:32:26.181149+03	\N
\.


--
-- TOC entry 5148 (class 0 OID 34394)
-- Dependencies: 220
-- Data for Name: user_profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_profiles (id, user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, date_of_birth, gender, profile_image_url, address, city, created_at, updated_at) FROM stdin;
ea94061d-d852-4330-8c64-4f97edd35af9	a1111111-1111-1111-1111-111111111111	أحمد	الأministrator	Ahmad	Administrator	+970-9-2345678	1985-05-15	male	\N	شارع الرئيسي، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
bf971577-668c-4e92-9b01-50b187e7a3cf	d2222222-2222-2222-2222-222222222221	محمد	أحمد	Mohammad	Smith	+970-9-2345671	1980-03-20	male	\N	رفيديا، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
1b3bfffe-b6f2-4984-aeb8-effe0f8ae42f	d2222222-2222-2222-2222-222222222222	أحمد	عبدالله	Ahmad	Johnson	+970-9-2345672	1978-07-15	male	\N	المدينة القديمة، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
704b651b-5060-47f6-9b45-d1d54d36df91	d2222222-2222-2222-2222-222222222223	سارة	يونيس	Sarah	Williams	+970-9-2345673	1985-11-25	female	\N	عين بيت الماء، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
3a7bab7b-8861-46c5-8133-44c7218d943c	a3333333-3333-3333-3333-333333333331	محمود	الخالدي	Mahmoud	Al-Khalidi	+970-59-1234567	1990-08-10	male	\N	شارع رقم 60، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
ffc1e806-d27e-415f-a6d9-1bd15a5201ed	a3333333-3333-3333-3333-333333333332	فاطمة	الزيود	Fatima	Al-Zioud	+970-59-2345678	1985-12-20	female	\N	الخالدية، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
c7ef0fcb-eab2-4ed6-afd5-a944898c2a67	a3333333-3333-3333-3333-333333333333	جون	سميث	John	Smith	+970-59-3456789	1995-04-15	male	\N	الإسكان، نابلس	Nablus	2026-07-11 16:32:47.906288+03	2026-07-11 16:32:47.906288+03
92556619-7866-4c61-9074-2ec234663c3b	fabb3794-cf82-4a64-8d63-84d4f365da08	عمر	أبو مازن	Omar	Abumazen	0599999999	\N	male	\N	\N	Nablus	2026-07-11 17:03:19.129749+03	2026-07-11 17:03:19.129749+03
94350b59-1358-4984-adba-ecca2b33f22e	8773be49-0538-4343-b78b-8e03144fa51d	محمد	علي	Mohammad	Ali	0599999999	\N	male	\N	\N	Nablus	2026-07-11 18:09:43.53858+03	2026-07-11 18:09:43.53858+03
\.


--
-- TOC entry 5153 (class 0 OID 34485)
-- Dependencies: 225
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_sessions (id, user_id, refresh_token, device_info, ip_address, user_agent, expires_at, created_at) FROM stdin;
1dde3037-6788-46fe-a141-d18e51f1a18c	8773be49-0538-4343-b78b-8e03144fa51d	eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4NzczYmU0OS0wNTM4LTQzNDMtYjc4Yi04ZTAzMTQ0ZmE1MWQiLCJ0eXBlIjoicmVmcmVzaCIsImp0aSI6ImIyNjlhZDg5LWQ0YmItNDk5My05OWFmLTNlNjA0OTQxNzFkMiIsImlhdCI6MTc4Mzc4MzcxMCwiZXhwIjoxNzg0Mzg4NTEwfQ.qx4MclwpDqVpkqzHLtJSy6xlPVGcsoWxQdvVVcPIvKg	\N	::1	PostmanRuntime/7.54.0	2026-07-18 18:28:30.653853+03	2026-07-11 18:28:30.653853+03
\.


--
-- TOC entry 5180 (class 0 OID 0)
-- Dependencies: 244
-- Name: appointment_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.appointment_seq', 5, true);


--
-- TOC entry 5181 (class 0 OID 0)
-- Dependencies: 246
-- Name: prescription_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.prescription_seq', 2, true);


--
-- TOC entry 5182 (class 0 OID 0)
-- Dependencies: 245
-- Name: record_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.record_seq', 3, true);


-- Completed on 2026-07-11 18:59:09

--
-- PostgreSQL database dump complete
--

