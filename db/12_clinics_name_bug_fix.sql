-- 12_clinics_name_bug_fix.sql
-- Corrects a bug in the shared name-resolution helper: when a record had
-- exactly one of name:ar/name:en from OSM, the missing side was backfilled
-- from the PRESENT side instead of the generic name tag, discarding a real,
-- better value that was available. This retroactively fixes every row that
-- steps 09/10/11 wrote using the buggy logic.
--
-- Safety: only touches a row if its CURRENT name_ar/name_en EXACTLY matches
-- what the buggy logic would have produced for that exact OSM record — i.e.
-- provably written by our own prior cleanup, not any other legitimate value.

BEGIN;

-- 32.2509096,35.2693013: 'صيدلية الحكمة' / 'صيدلية الحكمة' -> 'صيدلية الحكمة' / 'Al Hikmah'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الحكمة',
  name_en = 'Al Hikmah',
  updated_at = NOW()
WHERE latitude = 32.2509096 AND longitude = 35.2693013
  AND name_ar = 'صيدلية الحكمة' AND name_en = 'صيدلية الحكمة';

-- 32.222535,35.2627939: 'مختير ابوخلف الطبي' / 'مختير ابوخلف الطبي' -> 'مختير ابوخلف الطبي' / 'Abu Khalaf Lab'
UPDATE medorbit.clinics SET
  name_ar = 'مختير ابوخلف الطبي',
  name_en = 'Abu Khalaf Lab',
  updated_at = NOW()
WHERE latitude = 32.222535 AND longitude = 35.2627939
  AND name_ar = 'مختير ابوخلف الطبي' AND name_en = 'مختير ابوخلف الطبي';

-- 32.2208854,35.2505042: 'الخليل الجديدة' / 'الخليل الجديدة' -> 'الخليل الجديدة' / 'New Hebron'
UPDATE medorbit.clinics SET
  name_ar = 'الخليل الجديدة',
  name_en = 'New Hebron',
  updated_at = NOW()
WHERE latitude = 32.2208854 AND longitude = 35.2505042
  AND name_ar = 'الخليل الجديدة' AND name_en = 'الخليل الجديدة';

-- 32.2525629,35.2694396: 'عيادة هاشم' / 'عيادة هاشم' -> 'عيادة هاشم' / 'Dr Hasim'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة هاشم',
  name_en = 'Dr Hasim',
  updated_at = NOW()
WHERE latitude = 32.2525629 AND longitude = 35.2694396
  AND name_ar = 'عيادة هاشم' AND name_en = 'عيادة هاشم';

-- 32.2180387,35.2647514: 'مختبر احلام' / 'مختبر احلام' -> 'مختبر احلام' / 'Ahlam Lab'
UPDATE medorbit.clinics SET
  name_ar = 'مختبر احلام',
  name_en = 'Ahlam Lab',
  updated_at = NOW()
WHERE latitude = 32.2180387 AND longitude = 35.2647514
  AND name_ar = 'مختبر احلام' AND name_en = 'مختبر احلام';

-- 32.2522434,35.2690866: 'صيدلية الزيتونة' / 'صيدلية الزيتونة' -> 'صيدلية الزيتونة' / 'Al Zaitona'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الزيتونة',
  name_en = 'Al Zaitona',
  updated_at = NOW()
WHERE latitude = 32.2522434 AND longitude = 35.2690866
  AND name_ar = 'صيدلية الزيتونة' AND name_en = 'صيدلية الزيتونة';

-- 32.2255247,35.2416936: 'مستشفى رفيديا' / 'مستشفى رفيديا' -> 'مستشفى رفيديا' / 'Rafidia Hospital'
UPDATE medorbit.clinics SET
  name_ar = 'مستشفى رفيديا',
  name_en = 'Rafidia Hospital',
  updated_at = NOW()
WHERE latitude = 32.2255247 AND longitude = 35.2416936
  AND name_ar = 'مستشفى رفيديا' AND name_en = 'مستشفى رفيديا';

-- 32.2210613,35.2528757: 'صيدلية المصري' / 'صيدلية المصري' -> 'صيدلية المصري' / 'Al Masri'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية المصري',
  name_en = 'Al Masri',
  updated_at = NOW()
WHERE latitude = 32.2210613 AND longitude = 35.2528757
  AND name_ar = 'صيدلية المصري' AND name_en = 'صيدلية المصري';

-- 32.2258168,35.2438848: 'عمارة الرازي للاطباء' / 'عمارة الرازي للاطباء' -> 'عمارة الرازي للاطباء' / 'Al Razi'
UPDATE medorbit.clinics SET
  name_ar = 'عمارة الرازي للاطباء',
  name_en = 'Al Razi',
  updated_at = NOW()
WHERE latitude = 32.2258168 AND longitude = 35.2438848
  AND name_ar = 'عمارة الرازي للاطباء' AND name_en = 'عمارة الرازي للاطباء';

-- 32.2175719,35.2693226: 'صيدليه عبير' / 'صيدليه عبير' -> 'صيدليه عبير' / 'Abeer'
UPDATE medorbit.clinics SET
  name_ar = 'صيدليه عبير',
  name_en = 'Abeer',
  updated_at = NOW()
WHERE latitude = 32.2175719 AND longitude = 35.2693226
  AND name_ar = 'صيدليه عبير' AND name_en = 'صيدليه عبير';

-- 32.2376753,35.2436554: 'صيدلية الامير' / 'صيدلية الامير' -> 'صيدلية الامير' / 'Al Amier'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الامير',
  name_en = 'Al Amier',
  updated_at = NOW()
WHERE latitude = 32.2376753 AND longitude = 35.2436554
  AND name_ar = 'صيدلية الامير' AND name_en = 'صيدلية الامير';

-- 32.2212705,35.2383943: 'صيدلية رفيديا' / 'صيدلية رفيديا' -> 'صيدلية رفيديا' / 'Rafedia'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية رفيديا',
  name_en = 'Rafedia',
  updated_at = NOW()
WHERE latitude = 32.2212705 AND longitude = 35.2383943
  AND name_ar = 'صيدلية رفيديا' AND name_en = 'صيدلية رفيديا';

-- 32.2210595,35.2314923: 'الشخشير' / 'الشخشير' -> 'الشخشير' / 'Al Shakhsher'
UPDATE medorbit.clinics SET
  name_ar = 'الشخشير',
  name_en = 'Al Shakhsher',
  updated_at = NOW()
WHERE latitude = 32.2210595 AND longitude = 35.2314923
  AND name_ar = 'الشخشير' AND name_en = 'الشخشير';

-- 32.2168171,35.2599845: 'صيدلية راس العين' / 'صيدلية راس العين' -> 'صيدلية راس العين' / 'Ras Alain'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية راس العين',
  name_en = 'Ras Alain',
  updated_at = NOW()
WHERE latitude = 32.2168171 AND longitude = 35.2599845
  AND name_ar = 'صيدلية راس العين' AND name_en = 'صيدلية راس العين';

-- 32.2156356,35.2569566: 'صيدلية الزهراء' / 'صيدلية الزهراء' -> 'صيدلية الزهراء' / 'Al Zahra''
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الزهراء',
  name_en = 'Al Zahra''',
  updated_at = NOW()
WHERE latitude = 32.2156356 AND longitude = 35.2569566
  AND name_ar = 'صيدلية الزهراء' AND name_en = 'صيدلية الزهراء';

-- 32.2287198,35.2572975: 'صيدلية الاتحاد' / 'صيدلية الاتحاد' -> 'صيدلية الاتحاد' / 'Al Itihad Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الاتحاد',
  name_en = 'Al Itihad Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2287198 AND longitude = 35.2572975
  AND name_ar = 'صيدلية الاتحاد' AND name_en = 'صيدلية الاتحاد';

-- 32.2188001,35.2731688: 'صيدليه فادي' / 'صيدليه فادي' -> 'صيدليه فادي' / 'Fadi'
UPDATE medorbit.clinics SET
  name_ar = 'صيدليه فادي',
  name_en = 'Fadi',
  updated_at = NOW()
WHERE latitude = 32.2188001 AND longitude = 35.2731688
  AND name_ar = 'صيدليه فادي' AND name_en = 'صيدليه فادي';

-- 32.238526,35.2128725: 'صيدلية بيت ايبا' / 'صيدلية بيت ايبا' -> 'صيدلية بيت ايبا' / 'Bait Iba'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية بيت ايبا',
  name_en = 'Bait Iba',
  updated_at = NOW()
WHERE latitude = 32.238526 AND longitude = 35.2128725
  AND name_ar = 'صيدلية بيت ايبا' AND name_en = 'صيدلية بيت ايبا';

-- 32.1999764,35.2124598: 'منزل الدكتور هيثم عيسى' / 'منزل الدكتور هيثم عيسى' -> 'منزل الدكتور هيثم عيسى' / 'Dr.Haitham Isa'
UPDATE medorbit.clinics SET
  name_ar = 'منزل الدكتور هيثم عيسى',
  name_en = 'Dr.Haitham Isa',
  updated_at = NOW()
WHERE latitude = 32.1999764 AND longitude = 35.2124598
  AND name_ar = 'منزل الدكتور هيثم عيسى' AND name_en = 'منزل الدكتور هيثم عيسى';

-- 32.2220767,35.2626237: 'صيدلية عمر' / 'صيدلية عمر' -> 'صيدلية عمر' / 'Omar'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية عمر',
  name_en = 'Omar',
  updated_at = NOW()
WHERE latitude = 32.2220767 AND longitude = 35.2626237
  AND name_ar = 'صيدلية عمر' AND name_en = 'صيدلية عمر';

-- 32.2233277,35.2978401: 'منزل وعيادة الدكتور مرزوق محمد الصالحي' / 'منزل وعيادة الدكتور مرزوق محمد الصالحي' -> 'منزل وعيادة الدكتور مرزوق محمد الصالحي' / 'Marzoq Mohammad Al Sahili'
UPDATE medorbit.clinics SET
  name_ar = 'منزل وعيادة الدكتور مرزوق محمد الصالحي',
  name_en = 'Marzoq Mohammad Al Sahili',
  updated_at = NOW()
WHERE latitude = 32.2233277 AND longitude = 35.2978401
  AND name_ar = 'منزل وعيادة الدكتور مرزوق محمد الصالحي' AND name_en = 'منزل وعيادة الدكتور مرزوق محمد الصالحي';

-- 32.2518239,35.2711321: 'عيادة طبية' / 'عيادة طبية' -> 'عيادة طبية' / 'Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة طبية',
  name_en = 'Clinic',
  updated_at = NOW()
WHERE latitude = 32.2518239 AND longitude = 35.2711321
  AND name_ar = 'عيادة طبية' AND name_en = 'عيادة طبية';

-- 32.2237087,35.2593954: 'الادهم للاشعه' / 'الادهم للاشعه' -> 'الادهم للاشعه' / 'Al Adham X-ray'
UPDATE medorbit.clinics SET
  name_ar = 'الادهم للاشعه',
  name_en = 'Al Adham X-ray',
  updated_at = NOW()
WHERE latitude = 32.2237087 AND longitude = 35.2593954
  AND name_ar = 'الادهم للاشعه' AND name_en = 'الادهم للاشعه';

-- 32.2195923,35.2657767: 'الدكتور صلاح' / 'الدكتور صلاح' -> 'الدكتور صلاح' / 'Dr. Salah'
UPDATE medorbit.clinics SET
  name_ar = 'الدكتور صلاح',
  name_en = 'Dr. Salah',
  updated_at = NOW()
WHERE latitude = 32.2195923 AND longitude = 35.2657767
  AND name_ar = 'الدكتور صلاح' AND name_en = 'الدكتور صلاح';

-- 32.2249043,35.2313375: 'ابن النفيس' / 'ابن النفيس' -> 'ابن النفيس' / 'Ibn Al Nafis'
UPDATE medorbit.clinics SET
  name_ar = 'ابن النفيس',
  name_en = 'Ibn Al Nafis',
  updated_at = NOW()
WHERE latitude = 32.2249043 AND longitude = 35.2313375
  AND name_ar = 'ابن النفيس' AND name_en = 'ابن النفيس';

-- 32.213429,35.3030347: 'عيادة الدكتور محمد الشوبكي' / 'عيادة الدكتور محمد الشوبكي' -> 'عيادة الدكتور محمد الشوبكي' / 'Dr. Mohammed Al-Shobaki clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور محمد الشوبكي',
  name_en = 'Dr. Mohammed Al-Shobaki clinic',
  updated_at = NOW()
WHERE latitude = 32.213429 AND longitude = 35.3030347
  AND name_ar = 'عيادة الدكتور محمد الشوبكي' AND name_en = 'عيادة الدكتور محمد الشوبكي';

-- 32.2192816,35.2434858: 'النابلسي' / 'النابلسي' -> 'النابلسي' / 'Al Nabulsi'
UPDATE medorbit.clinics SET
  name_ar = 'النابلسي',
  name_en = 'Al Nabulsi',
  updated_at = NOW()
WHERE latitude = 32.2192816 AND longitude = 35.2434858
  AND name_ar = 'النابلسي' AND name_en = 'النابلسي';

-- 32.2254215,35.24552: 'صيدلية سامر' / 'صيدلية سامر' -> 'صيدلية سامر' / 'Samir'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية سامر',
  name_en = 'Samir',
  updated_at = NOW()
WHERE latitude = 32.2254215 AND longitude = 35.24552
  AND name_ar = 'صيدلية سامر' AND name_en = 'صيدلية سامر';

-- 32.2213687,35.2293912: 'عيادة المستقبل' / 'عيادة المستقبل' -> 'عيادة المستقبل' / 'Future Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة المستقبل',
  name_en = 'Future Clinic',
  updated_at = NOW()
WHERE latitude = 32.2213687 AND longitude = 35.2293912
  AND name_ar = 'عيادة المستقبل' AND name_en = 'عيادة المستقبل';

-- 32.2166031,35.2700844: 'صيدليه عرفات' / 'صيدليه عرفات' -> 'صيدليه عرفات' / 'Arafat'
UPDATE medorbit.clinics SET
  name_ar = 'صيدليه عرفات',
  name_en = 'Arafat',
  updated_at = NOW()
WHERE latitude = 32.2166031 AND longitude = 35.2700844
  AND name_ar = 'صيدليه عرفات' AND name_en = 'صيدليه عرفات';

-- 32.2191774,35.2367911: 'صيدلية المخفية' / 'صيدلية المخفية' -> 'صيدلية المخفية' / 'Al Makhfiyah'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية المخفية',
  name_en = 'Al Makhfiyah',
  updated_at = NOW()
WHERE latitude = 32.2191774 AND longitude = 35.2367911
  AND name_ar = 'صيدلية المخفية' AND name_en = 'صيدلية المخفية';

-- 32.2109894,35.27917: 'الضاحية' / 'الضاحية' -> 'الضاحية' / 'Al Dahia'
UPDATE medorbit.clinics SET
  name_ar = 'الضاحية',
  name_en = 'Al Dahia',
  updated_at = NOW()
WHERE latitude = 32.2109894 AND longitude = 35.27917
  AND name_ar = 'الضاحية' AND name_en = 'الضاحية';

-- 32.2222288,35.2630443: 'الدكتور عبد الحافظ' / 'الدكتور عبد الحافظ' -> 'الدكتور عبد الحافظ' / 'Dr Abd Al Hafiz'
UPDATE medorbit.clinics SET
  name_ar = 'الدكتور عبد الحافظ',
  name_en = 'Dr Abd Al Hafiz',
  updated_at = NOW()
WHERE latitude = 32.2222288 AND longitude = 35.2630443
  AND name_ar = 'الدكتور عبد الحافظ' AND name_en = 'الدكتور عبد الحافظ';

-- 32.2232661,35.2445238: 'الدكتور جمال ابو حجلة' / 'الدكتور جمال ابو حجلة' -> 'الدكتور جمال ابو حجلة' / 'Dr Jmal Abu Hajleh'
UPDATE medorbit.clinics SET
  name_ar = 'الدكتور جمال ابو حجلة',
  name_en = 'Dr Jmal Abu Hajleh',
  updated_at = NOW()
WHERE latitude = 32.2232661 AND longitude = 35.2445238
  AND name_ar = 'الدكتور جمال ابو حجلة' AND name_en = 'الدكتور جمال ابو حجلة';

-- 32.223225,35.2430766: 'أطبّاء بلا حدود' / 'أطبّاء بلا حدود' -> 'أطبّاء بلا حدود' / 'Medecins Sans Frontieres'
UPDATE medorbit.clinics SET
  name_ar = 'أطبّاء بلا حدود',
  name_en = 'Medecins Sans Frontieres',
  updated_at = NOW()
WHERE latitude = 32.223225 AND longitude = 35.2430766
  AND name_ar = 'أطبّاء بلا حدود' AND name_en = 'أطبّاء بلا حدود';

-- 32.2157181,35.2740043: 'صيدلية السرايا' / 'صيدلية السرايا' -> 'صيدلية السرايا' / 'Al Saraya Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية السرايا',
  name_en = 'Al Saraya Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2157181 AND longitude = 35.2740043
  AND name_ar = 'صيدلية السرايا' AND name_en = 'صيدلية السرايا';

-- 32.224663,35.2588477: 'صيدلية غازي' / 'صيدلية غازي' -> 'صيدلية غازي' / 'Ghazi Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية غازي',
  name_en = 'Ghazi Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.224663 AND longitude = 35.2588477
  AND name_ar = 'صيدلية غازي' AND name_en = 'صيدلية غازي';

-- 32.2513251,35.2682093: 'صيدلية العرندي' / 'صيدلية العرندي' -> 'صيدلية العرندي' / 'Asirah'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية العرندي',
  name_en = 'Asirah',
  updated_at = NOW()
WHERE latitude = 32.2513251 AND longitude = 35.2682093
  AND name_ar = 'صيدلية العرندي' AND name_en = 'صيدلية العرندي';

-- 32.2493818,35.2681402: 'مركز طبي' / 'مركز طبي' -> 'مركز طبي' / 'Medical Center'
UPDATE medorbit.clinics SET
  name_ar = 'مركز طبي',
  name_en = 'Medical Center',
  updated_at = NOW()
WHERE latitude = 32.2493818 AND longitude = 35.2681402
  AND name_ar = 'مركز طبي' AND name_en = 'مركز طبي';

-- 32.2216023,35.2369157: 'صيدلية فراس' / 'صيدلية فراس' -> 'صيدلية فراس' / 'Firas'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية فراس',
  name_en = 'Firas',
  updated_at = NOW()
WHERE latitude = 32.2216023 AND longitude = 35.2369157
  AND name_ar = 'صيدلية فراس' AND name_en = 'صيدلية فراس';

-- 32.2259224,35.2306719: 'الهلال الاحمر' / 'الهلال الاحمر' -> 'الهلال الاحمر' / 'Red Crescent'
UPDATE medorbit.clinics SET
  name_ar = 'الهلال الاحمر',
  name_en = 'Red Crescent',
  updated_at = NOW()
WHERE latitude = 32.2259224 AND longitude = 35.2306719
  AND name_ar = 'الهلال الاحمر' AND name_en = 'الهلال الاحمر';

-- 32.2513557,35.2691771: 'مختبر طبي' / 'مختبر طبي' -> 'مختبر طبي' / 'Medical Lab'
UPDATE medorbit.clinics SET
  name_ar = 'مختبر طبي',
  name_en = 'Medical Lab',
  updated_at = NOW()
WHERE latitude = 32.2513557 AND longitude = 35.2691771
  AND name_ar = 'مختبر طبي' AND name_en = 'مختبر طبي';

-- 32.2227088,35.2624703: 'المستشفى الوطني' / 'المستشفى الوطني' -> 'المستشفى الوطني' / 'Al Watani Hospital'
UPDATE medorbit.clinics SET
  name_ar = 'المستشفى الوطني',
  name_en = 'Al Watani Hospital',
  updated_at = NOW()
WHERE latitude = 32.2227088 AND longitude = 35.2624703
  AND name_ar = 'المستشفى الوطني' AND name_en = 'المستشفى الوطني';

-- 32.2244324,35.2452774: 'صيدلية تبارك' / 'صيدلية تبارك' -> 'صيدلية تبارك' / 'Tabark Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية تبارك',
  name_en = 'Tabark Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2244324 AND longitude = 35.2452774
  AND name_ar = 'صيدلية تبارك' AND name_en = 'صيدلية تبارك';

-- 32.2286617,35.2572065: 'مستشفى الاتحاد' / 'مستشفى الاتحاد' -> 'مستشفى الاتحاد' / 'Al Itihad Hospital'
UPDATE medorbit.clinics SET
  name_ar = 'مستشفى الاتحاد',
  name_en = 'Al Itihad Hospital',
  updated_at = NOW()
WHERE latitude = 32.2286617 AND longitude = 35.2572065
  AND name_ar = 'مستشفى الاتحاد' AND name_en = 'مستشفى الاتحاد';

-- 32.2222228,35.2598617: 'صيدلية النور الجديدة' / 'صيدلية النور الجديدة' -> 'صيدلية النور الجديدة' / 'AnNour Aljadeda'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية النور الجديدة',
  name_en = 'AnNour Aljadeda',
  updated_at = NOW()
WHERE latitude = 32.2222228 AND longitude = 35.2598617
  AND name_ar = 'صيدلية النور الجديدة' AND name_en = 'صيدلية النور الجديدة';

-- 32.2220458,35.2601882: 'Dr. Naji Arandi' / 'Dr. Naji Arandi' -> 'الدكتور ناجي العرندي' / 'Dr. Naji Arandi'
UPDATE medorbit.clinics SET
  name_ar = 'الدكتور ناجي العرندي',
  name_en = 'Dr. Naji Arandi',
  updated_at = NOW()
WHERE latitude = 32.2220458 AND longitude = 35.2601882
  AND name_ar = 'Dr. Naji Arandi' AND name_en = 'Dr. Naji Arandi';

-- 32.2213527,35.2605094: 'Dr. Ziad Arandi' / 'Dr. Ziad Arandi' -> 'الدكتور زياد العرندي' / 'Dr. Ziad Arandi'
UPDATE medorbit.clinics SET
  name_ar = 'الدكتور زياد العرندي',
  name_en = 'Dr. Ziad Arandi',
  updated_at = NOW()
WHERE latitude = 32.2213527 AND longitude = 35.2605094
  AND name_ar = 'Dr. Ziad Arandi' AND name_en = 'Dr. Ziad Arandi';

-- 32.2058844,35.2835964: 'Dr Mohammed Hajhamad Clinic' / 'Dr Mohammed Hajhamad Clinic' -> 'عيادة الدكتور محمد حاج حمد' / 'Dr Mohammed Hajhamad Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور محمد حاج حمد',
  name_en = 'Dr Mohammed Hajhamad Clinic',
  updated_at = NOW()
WHERE latitude = 32.2058844 AND longitude = 35.2835964
  AND name_ar = 'Dr Mohammed Hajhamad Clinic' AND name_en = 'Dr Mohammed Hajhamad Clinic';

-- 32.2182312,35.2691193: 'Alrahmah patients friends' / 'Alrahmah patients friends' -> 'مستوصف الرحمه' / 'Alrahmah patients friends'
UPDATE medorbit.clinics SET
  name_ar = 'مستوصف الرحمه',
  name_en = 'Alrahmah patients friends',
  updated_at = NOW()
WHERE latitude = 32.2182312 AND longitude = 35.2691193
  AND name_ar = 'Alrahmah patients friends' AND name_en = 'Alrahmah patients friends';

-- 32.2154955,35.2738683: 'Noora pharmacy' / 'Noora pharmacy' -> 'صيدلية نورة' / 'Noora pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية نورة',
  name_en = 'Noora pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2154955 AND longitude = 35.2738683
  AND name_ar = 'Noora pharmacy' AND name_en = 'Noora pharmacy';

-- 32.2209987,35.2601539: 'Hassan Pharmacy' / 'Hassan Pharmacy' -> 'صيدلية حسن' / 'Hassan Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية حسن',
  name_en = 'Hassan Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2209987 AND longitude = 35.2601539
  AND name_ar = 'Hassan Pharmacy' AND name_en = 'Hassan Pharmacy';

-- 32.2220969,35.248182: 'jeriatric house red crescent' / 'jeriatric house red crescent' -> 'بيت المسنين الهلال الأحمر' / 'jeriatric house red crescent'
UPDATE medorbit.clinics SET
  name_ar = 'بيت المسنين الهلال الأحمر',
  name_en = 'jeriatric house red crescent',
  updated_at = NOW()
WHERE latitude = 32.2220969 AND longitude = 35.248182
  AND name_ar = 'jeriatric house red crescent' AND name_en = 'jeriatric house red crescent';

-- 32.2210026,35.2421352: 'Tabanjeh Pharmacy' / 'Tabanjeh Pharmacy' -> 'صيدلية طبنجة' / 'Tabanjeh Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية طبنجة',
  name_en = 'Tabanjeh Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2210026 AND longitude = 35.2421352
  AND name_ar = 'Tabanjeh Pharmacy' AND name_en = 'Tabanjeh Pharmacy';

-- 32.2230967,35.257747: 'Dima IVF Center' / 'Dima IVF Center' -> 'مركز ديما للإخصاب' / 'Dima IVF Center'
UPDATE medorbit.clinics SET
  name_ar = 'مركز ديما للإخصاب',
  name_en = 'Dima IVF Center',
  updated_at = NOW()
WHERE latitude = 32.2230967 AND longitude = 35.257747
  AND name_ar = 'Dima IVF Center' AND name_en = 'Dima IVF Center';

-- 32.2291206,35.2502783: 'Al-Rahma Pharmacy' / 'Al-Rahma Pharmacy' -> 'صيدلية الرحمة' / 'Al-Rahma Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الرحمة',
  name_en = 'Al-Rahma Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2291206 AND longitude = 35.2502783
  AND name_ar = 'Al-Rahma Pharmacy' AND name_en = 'Al-Rahma Pharmacy';

-- 32.2239335,35.2501516: 'Fawaz Pharmacy' / 'Fawaz Pharmacy' -> 'صيدلية فواز' / 'Fawaz Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية فواز',
  name_en = 'Fawaz Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2239335 AND longitude = 35.2501516
  AND name_ar = 'Fawaz Pharmacy' AND name_en = 'Fawaz Pharmacy';

-- 32.2239524,35.2555775: 'Derma clinic' / 'Derma clinic' -> 'عيادة الدكتورة ولاء سعد الدين' / 'Derma clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتورة ولاء سعد الدين',
  name_en = 'Derma clinic',
  updated_at = NOW()
WHERE latitude = 32.2239524 AND longitude = 35.2555775
  AND name_ar = 'Derma clinic' AND name_en = 'Derma clinic';

-- 32.2230858,35.2346378: 'grand center' / 'grand center' -> 'غراند سنتر' / 'grand center'
UPDATE medorbit.clinics SET
  name_ar = 'غراند سنتر',
  name_en = 'grand center',
  updated_at = NOW()
WHERE latitude = 32.2230858 AND longitude = 35.2346378
  AND name_ar = 'grand center' AND name_en = 'grand center';

-- 32.2152504,35.2393712: 'Demaidi Pharm' / 'Demaidi Pharm' -> 'صيدلية الضميدي' / 'Demaidi Pharm'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الضميدي',
  name_en = 'Demaidi Pharm',
  updated_at = NOW()
WHERE latitude = 32.2152504 AND longitude = 35.2393712
  AND name_ar = 'Demaidi Pharm' AND name_en = 'Demaidi Pharm';

-- 32.2240932,35.2437381: 'Nwaiser dental clinic' / 'Nwaiser dental clinic' -> 'عياده نويصر للأسنان' / 'Nwaiser dental clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عياده نويصر للأسنان',
  name_en = 'Nwaiser dental clinic',
  updated_at = NOW()
WHERE latitude = 32.2240932 AND longitude = 35.2437381
  AND name_ar = 'Nwaiser dental clinic' AND name_en = 'Nwaiser dental clinic';

-- 32.2257329,35.2409873: 'Rafedia hospital' / 'Rafedia hospital' -> 'مستشفى رفيديا' / 'Rafedia hospital'
UPDATE medorbit.clinics SET
  name_ar = 'مستشفى رفيديا',
  name_en = 'Rafedia hospital',
  updated_at = NOW()
WHERE latitude = 32.2257329 AND longitude = 35.2409873
  AND name_ar = 'Rafedia hospital' AND name_en = 'Rafedia hospital';

-- 32.2515712,35.268477: 'Hamza Kids Clinic' / 'Hamza Kids Clinic' -> 'عيادة الدكتور حمزة للأطفال' / 'Hamza Kids Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور حمزة للأطفال',
  name_en = 'Hamza Kids Clinic',
  updated_at = NOW()
WHERE latitude = 32.2515712 AND longitude = 35.268477
  AND name_ar = 'Hamza Kids Clinic' AND name_en = 'Hamza Kids Clinic';

-- 32.2604408,35.1973847: 'منزل الدكتور جميل' / 'منزل الدكتور جميل' -> 'منزل الدكتور جميل' / 'Dr Jamil'
UPDATE medorbit.clinics SET
  name_ar = 'منزل الدكتور جميل',
  name_en = 'Dr Jamil',
  updated_at = NOW()
WHERE latitude = 32.2604408 AND longitude = 35.1973847
  AND name_ar = 'منزل الدكتور جميل' AND name_en = 'منزل الدكتور جميل';

-- 32.1759458,35.3381261: 'منزل الدكتور منير شريف' / 'منزل الدكتور منير شريف' -> 'منزل الدكتور منير شريف' / 'Muneer Sharif'
UPDATE medorbit.clinics SET
  name_ar = 'منزل الدكتور منير شريف',
  name_en = 'Muneer Sharif',
  updated_at = NOW()
WHERE latitude = 32.1759458 AND longitude = 35.3381261
  AND name_ar = 'منزل الدكتور منير شريف' AND name_en = 'منزل الدكتور منير شريف';

-- 32.2228117,35.3139552: 'مركز صحي' / 'مركز صحي' -> 'مركز صحي' / 'Health Center'
UPDATE medorbit.clinics SET
  name_ar = 'مركز صحي',
  name_en = 'Health Center',
  updated_at = NOW()
WHERE latitude = 32.2228117 AND longitude = 35.3139552
  AND name_ar = 'مركز صحي' AND name_en = 'مركز صحي';

-- 32.1793279,35.2496759: 'صيدلية بورين' / 'صيدلية بورين' -> 'صيدلية بورين' / 'Bourin'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية بورين',
  name_en = 'Bourin',
  updated_at = NOW()
WHERE latitude = 32.1793279 AND longitude = 35.2496759
  AND name_ar = 'صيدلية بورين' AND name_en = 'صيدلية بورين';

-- 32.2108963,35.1891731: 'عيادة الدكتور عبد الناصر' / 'عيادة الدكتور عبد الناصر' -> 'عيادة الدكتور عبد الناصر' / 'Dr Abd Al Nasir'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور عبد الناصر',
  name_en = 'Dr Abd Al Nasir',
  updated_at = NOW()
WHERE latitude = 32.2108963 AND longitude = 35.1891731
  AND name_ar = 'عيادة الدكتور عبد الناصر' AND name_en = 'عيادة الدكتور عبد الناصر';

-- 32.1777503,35.3359302: 'صيدلية المنار' / 'صيدلية المنار' -> 'صيدلية المنار' / 'Al Manar'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية المنار',
  name_en = 'Al Manar',
  updated_at = NOW()
WHERE latitude = 32.1777503 AND longitude = 35.3359302
  AND name_ar = 'صيدلية المنار' AND name_en = 'صيدلية المنار';

-- 32.162307,35.2864698: 'صيدلية عورتا' / 'صيدلية عورتا' -> 'صيدلية عورتا' / 'Awarta'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية عورتا',
  name_en = 'Awarta',
  updated_at = NOW()
WHERE latitude = 32.162307 AND longitude = 35.2864698
  AND name_ar = 'صيدلية عورتا' AND name_en = 'صيدلية عورتا';

-- 32.1763089,35.3355399: 'صيدلية الترياق' / 'صيدلية الترياق' -> 'صيدلية الترياق' / 'Al Toryak'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الترياق',
  name_en = 'Al Toryak',
  updated_at = NOW()
WHERE latitude = 32.1763089 AND longitude = 35.3355399
  AND name_ar = 'صيدلية الترياق' AND name_en = 'صيدلية الترياق';

-- 32.2769387,35.1958586: 'عيادة سبسطية' / 'عيادة سبسطية' -> 'عيادة سبسطية' / 'Sabastia Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة سبسطية',
  name_en = 'Sabastia Clinic',
  updated_at = NOW()
WHERE latitude = 32.2769387 AND longitude = 35.1958586
  AND name_ar = 'عيادة سبسطية' AND name_en = 'عيادة سبسطية';

-- 32.1779186,35.3352351: 'الهلال الاحمر' / 'الهلال الاحمر' -> 'الهلال الاحمر' / 'Red Crescent'
UPDATE medorbit.clinics SET
  name_ar = 'الهلال الاحمر',
  name_en = 'Red Crescent',
  updated_at = NOW()
WHERE latitude = 32.1779186 AND longitude = 35.3352351
  AND name_ar = 'الهلال الاحمر' AND name_en = 'الهلال الاحمر';

-- 32.1763075,35.3354324: 'عيادة بيت فوريك' / 'عيادة بيت فوريك' -> 'عيادة بيت فوريك' / 'Bait Fourik Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة بيت فوريك',
  name_en = 'Bait Fourik Clinic',
  updated_at = NOW()
WHERE latitude = 32.1763075 AND longitude = 35.3354324
  AND name_ar = 'عيادة بيت فوريك' AND name_en = 'عيادة بيت فوريك';

-- 32.2099842,35.1913044: 'صيدلية الهلال' / 'صيدلية الهلال' -> 'صيدلية الهلال' / 'Al Hilal'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الهلال',
  name_en = 'Al Hilal',
  updated_at = NOW()
WHERE latitude = 32.2099842 AND longitude = 35.1913044
  AND name_ar = 'صيدلية الهلال' AND name_en = 'صيدلية الهلال';

-- 32.2771508,35.1937802: 'عيادة طبية' / 'عيادة طبية' -> 'عيادة طبية' / 'Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة طبية',
  name_en = 'Clinic',
  updated_at = NOW()
WHERE latitude = 32.2771508 AND longitude = 35.1937802
  AND name_ar = 'عيادة طبية' AND name_en = 'عيادة طبية';

-- 32.2088895,35.3296484: 'مستوصف قريه سالم' / 'مستوصف قريه سالم' -> 'مستوصف قريه سالم' / 'Salem Emregence Point'
UPDATE medorbit.clinics SET
  name_ar = 'مستوصف قريه سالم',
  name_en = 'Salem Emregence Point',
  updated_at = NOW()
WHERE latitude = 32.2088895 AND longitude = 35.3296484
  AND name_ar = 'مستوصف قريه سالم' AND name_en = 'مستوصف قريه سالم';

-- 32.2779809,35.2056054: 'مركز ابن سينا ( الاغاثه )' / 'مركز ابن سينا ( الاغاثه )' -> 'مركز ابن سينا ( الاغاثه )' / 'Ibn Sina Center'
UPDATE medorbit.clinics SET
  name_ar = 'مركز ابن سينا ( الاغاثه )',
  name_en = 'Ibn Sina Center',
  updated_at = NOW()
WHERE latitude = 32.2779809 AND longitude = 35.2056054
  AND name_ar = 'مركز ابن سينا ( الاغاثه )' AND name_en = 'مركز ابن سينا ( الاغاثه )';

-- 32.1541823,35.2768805: 'العيادة الصحية' / 'العيادة الصحية' -> 'العيادة الصحية' / 'Health Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'العيادة الصحية',
  name_en = 'Health Clinic',
  updated_at = NOW()
WHERE latitude = 32.1541823 AND longitude = 35.2768805
  AND name_ar = 'العيادة الصحية' AND name_en = 'العيادة الصحية';

-- 32.2100918,35.3307423: 'عيادة الدكتور سالم' / 'عيادة الدكتور سالم' -> 'عيادة الدكتور سالم' / 'Doctor Salem Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور سالم',
  name_en = 'Doctor Salem Clinic',
  updated_at = NOW()
WHERE latitude = 32.2100918 AND longitude = 35.3307423
  AND name_ar = 'عيادة الدكتور سالم' AND name_en = 'عيادة الدكتور سالم';

-- 32.1522163,35.2588448: 'صيدلية حوارة' / 'صيدلية حوارة' -> 'صيدلية حوارة' / 'Hawwarah'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية حوارة',
  name_en = 'Hawwarah',
  updated_at = NOW()
WHERE latitude = 32.1522163 AND longitude = 35.2588448
  AND name_ar = 'صيدلية حوارة' AND name_en = 'صيدلية حوارة';

-- 32.1577714,35.2249053: 'صيدلية عوريف' / 'صيدلية عوريف' -> 'صيدلية عوريف' / 'Orif'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية عوريف',
  name_en = 'Orif',
  updated_at = NOW()
WHERE latitude = 32.1577714 AND longitude = 35.2249053
  AND name_ar = 'صيدلية عوريف' AND name_en = 'صيدلية عوريف';

-- 32.2757406,35.1984574: 'مركز سبسطية الصحي' / 'مركز سبسطية الصحي' -> 'مركز سبسطية الصحي' / 'Sabastia Helth Center'
UPDATE medorbit.clinics SET
  name_ar = 'مركز سبسطية الصحي',
  name_en = 'Sabastia Helth Center',
  updated_at = NOW()
WHERE latitude = 32.2757406 AND longitude = 35.1984574
  AND name_ar = 'مركز سبسطية الصحي' AND name_en = 'مركز سبسطية الصحي';

-- 32.2091193,35.3306942: 'صيدلية الاسره' / 'صيدلية الاسره' -> 'صيدلية الاسره' / 'Family'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الاسره',
  name_en = 'Family',
  updated_at = NOW()
WHERE latitude = 32.2091193 AND longitude = 35.3306942
  AND name_ar = 'صيدلية الاسره' AND name_en = 'صيدلية الاسره';

-- 32.2157255,35.1705679: 'عيادة امومة' / 'عيادة امومة' -> 'عيادة امومة' / 'Jit Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة امومة',
  name_en = 'Jit Clinic',
  updated_at = NOW()
WHERE latitude = 32.2157255 AND longitude = 35.1705679
  AND name_ar = 'عيادة امومة' AND name_en = 'عيادة امومة';

-- 32.1577889,35.2249029: 'Dr.atef clinic' / 'Dr.atef clinic' -> 'عيادة الدكتور عاطف الصفدي' / 'Dr.atef clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور عاطف الصفدي',
  name_en = 'Dr.atef clinic',
  updated_at = NOW()
WHERE latitude = 32.1577889 AND longitude = 35.2249029
  AND name_ar = 'Dr.atef clinic' AND name_en = 'Dr.atef clinic';

-- 32.178586,35.215278: 'Ali Khalifa's Clinic' / 'Ali Khalifa's Clinic' -> 'عيادة الدكتور علي خليفة' / 'Ali Khalifa's Clinic'
UPDATE medorbit.clinics SET
  name_ar = 'عيادة الدكتور علي خليفة',
  name_en = 'Ali Khalifa''s Clinic',
  updated_at = NOW()
WHERE latitude = 32.178586 AND longitude = 35.215278
  AND name_ar = 'Ali Khalifa''s Clinic' AND name_en = 'Ali Khalifa''s Clinic';

-- 32.2873657,35.2169441: 'صيدلية هادي' / 'صيدلية هادي' -> 'صيدلية هادي الجديدة' / 'صيدلية هادي'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية هادي الجديدة',
  name_en = 'صيدلية هادي',
  updated_at = NOW()
WHERE latitude = 32.2873657 AND longitude = 35.2169441
  AND name_ar = 'صيدلية هادي' AND name_en = 'صيدلية هادي';

-- 32.1920321,35.1585792: 'Al-Zahra Pharmacy' / 'Al-Zahra Pharmacy' -> 'صيدلية الزهراء' / 'Al-Zahra Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية الزهراء',
  name_en = 'Al-Zahra Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.1920321 AND longitude = 35.1585792
  AND name_ar = 'Al-Zahra Pharmacy' AND name_en = 'Al-Zahra Pharmacy';

-- 32.2911133,35.3453395: 'rawan pharmacy' / 'rawan pharmacy' -> 'صيدلية روان' / 'rawan pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية روان',
  name_en = 'rawan pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2911133 AND longitude = 35.3453395
  AND name_ar = 'rawan pharmacy' AND name_en = 'rawan pharmacy';

-- 32.2902525,35.3437785: 'Rawan pharmacy' / 'Rawan pharmacy' -> 'صيدلية روان' / 'Rawan pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية روان',
  name_en = 'Rawan pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2902525 AND longitude = 35.3437785
  AND name_ar = 'Rawan pharmacy' AND name_en = 'Rawan pharmacy';

-- 32.2921498,35.3451928: 'Al Ayed Pharmacy' / 'Al Ayed Pharmacy' -> 'صيدلية العايد' / 'Al Ayed Pharmacy'
UPDATE medorbit.clinics SET
  name_ar = 'صيدلية العايد',
  name_en = 'Al Ayed Pharmacy',
  updated_at = NOW()
WHERE latitude = 32.2921498 AND longitude = 35.3451928
  AND name_ar = 'Al Ayed Pharmacy' AND name_en = 'Al Ayed Pharmacy';

COMMIT;
