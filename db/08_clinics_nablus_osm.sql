-- 08_clinics_nablus_osm.sql
-- Real clinic/pharmacy/hospital data for Nablus, collected from OpenStreetMap
-- (amenity=hospital|clinic|doctors|pharmacy and healthcare=*, bbox 32.18-32.26 lat / 35.21-35.31 lng).
-- Every row traces to a real OSM node/way (see osm_id comment above each INSERT);
-- verify any row at https://www.openstreetmap.org/<node|way>/<osm_id>.
--
-- Idempotency note: medorbit.clinics has no unique constraint on coordinates and
-- no osm_id column (adding one would be a schema change, out of scope here), so
-- ON CONFLICT can't target osm_id directly. Each INSERT instead guards itself with
-- WHERE NOT EXISTS on the exact (latitude, longitude) pair we are writing — since
-- those are literal constants in this file (not floating computed values), re-running
-- this script is a safe no-op for rows already inserted.
--
-- address_ar/address_en are NOT NULL on this table, so rows where OSM had no addr:*
-- tags at all use '' (empty string) rather than a fabricated address. This is
-- deliberate — treat '' as "no address" everywhere it's read, same as NULL.

BEGIN;

-- osm_node:431897069 -- https://www.openstreetmap.org/node/431897069
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الحكمة', 'صيدلية الحكمة', '', '', 'Nablus', 32.2509096, 35.2693013, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2509096 AND longitude = 35.2693013
);

-- osm_node:431908879 -- https://www.openstreetmap.org/node/431908879
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مختير ابوخلف الطبي', 'مختير ابوخلف الطبي', '', '', 'Nablus', 32.222535, 35.2627939, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.222535 AND longitude = 35.2627939
);

-- osm_node:431911387 -- https://www.openstreetmap.org/node/431911387
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الخليل الجديدة', 'الخليل الجديدة', 'نابلس', 'نابلس', 'Nablus', 32.2208854, 35.2505042, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2208854 AND longitude = 35.2505042
);

-- osm_node:431913799 -- https://www.openstreetmap.org/node/431913799
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة هاشم', 'عيادة هاشم', '', '', 'Nablus', 32.2525629, 35.2694396, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2525629 AND longitude = 35.2694396
);

-- osm_node:431915153 -- https://www.openstreetmap.org/node/431915153
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مختبر احلام', 'مختبر احلام', '', '', 'Nablus', 32.2180387, 35.2647514, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2180387 AND longitude = 35.2647514
);

-- osm_node:431915395 -- https://www.openstreetmap.org/node/431915395
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية سفير', 'Shqer', '', '', 'Nablus', 32.2225474, 35.2416137, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2225474 AND longitude = 35.2416137
);

-- osm_node:431919833 -- https://www.openstreetmap.org/node/431919833
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الزيتونة', 'صيدلية الزيتونة', '', '', 'Nablus', 32.2522434, 35.2690866, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2522434 AND longitude = 35.2690866
);

-- osm_node:431920698 -- https://www.openstreetmap.org/node/431920698
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستشفى رفيديا', 'مستشفى رفيديا', '', '', 'Nablus', 32.2255247, 35.2416936, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2255247 AND longitude = 35.2416936
);

-- osm_node:431923237 -- https://www.openstreetmap.org/node/431923237
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية سنا', 'Amanda Pharmacy', '', '', 'Nablus', 32.2263293, 35.3031367, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2263293 AND longitude = 35.3031367
);

-- osm_node:431927304 -- https://www.openstreetmap.org/node/431927304
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية المصري', 'صيدلية المصري', '', '', 'Nablus', 32.2210613, 35.2528757, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2210613 AND longitude = 35.2528757
);

-- osm_node:431935495 -- https://www.openstreetmap.org/node/431935495
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عمارة الرازي للاطباء', 'عمارة الرازي للاطباء', '', '', 'Nablus', 32.2258168, 35.2438848, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2258168 AND longitude = 35.2438848
);

-- osm_node:431935516 -- https://www.openstreetmap.org/node/431935516
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدليه عبير', 'صيدليه عبير', '', '', 'Nablus', 32.2175719, 35.2693226, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2175719 AND longitude = 35.2693226
);

-- osm_node:431937595 -- https://www.openstreetmap.org/node/431937595
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية دعاء', 'Al Maha Pharmacy', 'شارع الاتحاد', 'شارع الاتحاد', 'Nablus', 32.2292033, 35.2567632, '092370647', 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2292033 AND longitude = 35.2567632
);

-- osm_node:431941611 -- https://www.openstreetmap.org/node/431941611
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الامير', 'صيدلية الامير', '', '', 'Nablus', 32.2376753, 35.2436554, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2376753 AND longitude = 35.2436554
);

-- osm_node:431943687 -- https://www.openstreetmap.org/node/431943687
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية رفيديا', 'صيدلية رفيديا', '', '', 'Nablus', 32.2212705, 35.2383943, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2212705 AND longitude = 35.2383943
);

-- osm_node:431945002 -- https://www.openstreetmap.org/node/431945002
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الشخشير', 'الشخشير', '', '', 'Nablus', 32.2210595, 35.2314923, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2210595 AND longitude = 35.2314923
);

-- osm_node:431955801 -- https://www.openstreetmap.org/node/431955801
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية راس العين', 'صيدلية راس العين', '', '', 'Nablus', 32.2168171, 35.2599845, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2168171 AND longitude = 35.2599845
);

-- osm_node:431964362 -- https://www.openstreetmap.org/node/431964362
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الزهراء', 'صيدلية الزهراء', '', '', 'Nablus', 32.2156356, 35.2569566, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2156356 AND longitude = 35.2569566
);

-- osm_node:431967941 -- https://www.openstreetmap.org/node/431967941
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الاتحاد', 'صيدلية الاتحاد', '', '', 'Nablus', 32.2287198, 35.2572975, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2287198 AND longitude = 35.2572975
);

-- osm_node:431970468 -- https://www.openstreetmap.org/node/431970468
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدليه فادي', 'صيدليه فادي', 'isso street', 'isso street', 'Nablus', 32.2188001, 35.2731688, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2188001 AND longitude = 35.2731688
);

-- osm_node:431972689 -- https://www.openstreetmap.org/node/431972689
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية بيت ايبا', 'صيدلية بيت ايبا', '', '', 'Nablus', 32.238526, 35.2128725, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.238526 AND longitude = 35.2128725
);

-- osm_node:431975130 -- https://www.openstreetmap.org/node/431975130
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'منزل الدكتور هيثم عيسى', 'منزل الدكتور هيثم عيسى', '', '', 'Nablus', 32.1999764, 35.2124598, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.1999764 AND longitude = 35.2124598
);

-- osm_node:431976389 -- https://www.openstreetmap.org/node/431976389
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية حواء', 'Hawa''a', 'نابلس', 'نابلس', 'Nablus', 32.218522, 35.2669576, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.218522 AND longitude = 35.2669576
);

-- osm_node:431977294 -- https://www.openstreetmap.org/node/431977294
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'المستشفى العربي', 'The Specialized Arabic Hospital', '', '', 'Nablus', 32.2233879, 35.2398405, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2233879 AND longitude = 35.2398405
);

-- osm_node:431981177 -- https://www.openstreetmap.org/node/431981177
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية عمر', 'صيدلية عمر', '', '', 'Nablus', 32.2220767, 35.2626237, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2220767 AND longitude = 35.2626237
);

-- osm_node:431989567 -- https://www.openstreetmap.org/node/431989567
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'منزل وعيادة الدكتور مرزوق محمد الصالحي', 'منزل وعيادة الدكتور مرزوق محمد الصالحي', '', '', 'Nablus', 32.2233277, 35.2978401, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2233277 AND longitude = 35.2978401
);

-- osm_node:431993699 -- https://www.openstreetmap.org/node/431993699
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة طبية', 'عيادة طبية', '', '', 'Nablus', 32.2518239, 35.2711321, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2518239 AND longitude = 35.2711321
);

-- osm_node:432004724 -- https://www.openstreetmap.org/node/432004724
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الكندي', 'صيدلية الكندي', '', '', 'Nablus', 32.2146155, 35.2716798, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2146155 AND longitude = 35.2716798
);

-- osm_node:432038524 -- https://www.openstreetmap.org/node/432038524
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الادهم للاشعه', 'الادهم للاشعه', '', '', 'Nablus', 32.2237087, 35.2593954, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2237087 AND longitude = 35.2593954
);

-- osm_node:432044460 -- https://www.openstreetmap.org/node/432044460
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الدكتور صلاح', 'الدكتور صلاح', '', '', 'Nablus', 32.2195923, 35.2657767, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2195923 AND longitude = 35.2657767
);

-- osm_node:432047335 -- https://www.openstreetmap.org/node/432047335
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'ابن النفيس', 'ابن النفيس', '', '', 'Nablus', 32.2249043, 35.2313375, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2249043 AND longitude = 35.2313375
);

-- osm_node:432052667 -- https://www.openstreetmap.org/node/432052667
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة الدكتور محمد الشوبكي', 'عيادة الدكتور محمد الشوبكي', '', '', 'Nablus', 32.213429, 35.3030347, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.213429 AND longitude = 35.3030347
);

-- osm_node:432054557 -- https://www.openstreetmap.org/node/432054557
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية مكه', 'Mecca Pharmacy', '', '', 'Nablus', 32.2077823, 35.2838194, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2077823 AND longitude = 35.2838194
);

-- osm_node:432063158 -- https://www.openstreetmap.org/node/432063158
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية ساهر.', 'Saher Pharmacy', '', '', 'Nablus', 32.2106731, 35.2824143, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2106731 AND longitude = 35.2824143
);

-- osm_node:432063402 -- https://www.openstreetmap.org/node/432063402
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'سمير القادري', 'سمير القادري', '', '', 'Nablus', 32.2178844, 35.2720008, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2178844 AND longitude = 35.2720008
);

-- osm_node:432065448 -- https://www.openstreetmap.org/node/432065448
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'النابلسي', 'النابلسي', '', '', 'Nablus', 32.2192816, 35.2434858, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2192816 AND longitude = 35.2434858
);

-- osm_node:432073463 -- https://www.openstreetmap.org/node/432073463
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية سامر', 'صيدلية سامر', '', '', 'Nablus', 32.2254215, 35.24552, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2254215 AND longitude = 35.24552
);

-- osm_node:432076168 -- https://www.openstreetmap.org/node/432076168
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة المستقبل', 'عيادة المستقبل', '', '', 'Nablus', 32.2213687, 35.2293912, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2213687 AND longitude = 35.2293912
);

-- osm_node:432083390 -- https://www.openstreetmap.org/node/432083390
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدليه عرفات', 'صيدليه عرفات', '', '', 'Nablus', 32.2166031, 35.2700844, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2166031 AND longitude = 35.2700844
);

-- osm_node:432084904 -- https://www.openstreetmap.org/node/432084904
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية المخفية', 'صيدلية المخفية', 'Ibrahim Hashim Street', 'Ibrahim Hashim Street', 'Nablus', 32.2191774, 35.2367911, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2191774 AND longitude = 35.2367911
);

-- osm_node:432092238 -- https://www.openstreetmap.org/node/432092238
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الضاحية', 'الضاحية', '', '', 'Nablus', 32.2109894, 35.27917, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2109894 AND longitude = 35.27917
);

-- osm_node:432094064 -- https://www.openstreetmap.org/node/432094064
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الدكتور عبد الحافظ', 'الدكتور عبد الحافظ', '', '', 'Nablus', 32.2222288, 35.2630443, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2222288 AND longitude = 35.2630443
);

-- osm_node:432110244 -- https://www.openstreetmap.org/node/432110244
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الدكتور جمال ابو حجلة', 'الدكتور جمال ابو حجلة', '', '', 'Nablus', 32.2232661, 35.2445238, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2232661 AND longitude = 35.2445238
);

-- osm_node:432115123 -- https://www.openstreetmap.org/node/432115123
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية اسامة', 'Osama Pharmacy', '', '', 'Nablus', 32.2222007, 35.2616395, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2222007 AND longitude = 35.2616395
);

-- osm_node:432124125 -- https://www.openstreetmap.org/node/432124125
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'أطبّاء بلا حدود', 'أطبّاء بلا حدود', '', '', 'Nablus', 32.223225, 35.2430766, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.223225 AND longitude = 35.2430766
);

-- osm_node:432132006 -- https://www.openstreetmap.org/node/432132006
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية السرايا', 'صيدلية السرايا', '', '', 'Nablus', 32.2157181, 35.2740043, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2157181 AND longitude = 35.2740043
);

-- osm_node:432137163 -- https://www.openstreetmap.org/node/432137163
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية غازي', 'صيدلية غازي', '', '', 'Nablus', 32.224663, 35.2588477, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.224663 AND longitude = 35.2588477
);

-- osm_node:432138954 -- https://www.openstreetmap.org/node/432138954
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية المستقبل', 'Al-Mostaqbal Pharmacy', '', '', 'Nablus', 32.2177575, 35.293013, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2177575 AND longitude = 35.293013
);

-- osm_node:432147461 -- https://www.openstreetmap.org/node/432147461
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية العرندي', 'صيدلية العرندي', '', '', 'Nablus', 32.2513251, 35.2682093, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2513251 AND longitude = 35.2682093
);

-- osm_node:432151180 -- https://www.openstreetmap.org/node/432151180
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية نابلس', 'Nablus', 'نابلس', 'نابلس', 'Nablus', 32.2179482, 35.2670849, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2179482 AND longitude = 35.2670849
);

-- osm_node:432161656 -- https://www.openstreetmap.org/node/432161656
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مركز طبي', 'مركز طبي', '', '', 'Nablus', 32.2493818, 35.2681402, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2493818 AND longitude = 35.2681402
);

-- osm_node:432164716 -- https://www.openstreetmap.org/node/432164716
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الجامعه', 'صيدلية الجامعه', 'Omar Ibn Al-Khattab Street', 'Omar Ibn Al-Khattab Street', 'Nablus', 32.220833, 35.2466422, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.220833 AND longitude = 35.2466422
);

-- osm_node:432172425 -- https://www.openstreetmap.org/node/432172425
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستشفى الأمل للعلاج الطبيعي', 'Al Amal For Physical Therapy', '', '', 'Nablus', 32.2065201, 35.2643352, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2065201 AND longitude = 35.2643352
);

-- osm_node:432173619 -- https://www.openstreetmap.org/node/432173619
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية فراس', 'صيدلية فراس', '', '', 'Nablus', 32.2216023, 35.2369157, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2216023 AND longitude = 35.2369157
);

-- osm_node:432174878 -- https://www.openstreetmap.org/node/432174878
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الهلال الاحمر', 'الهلال الاحمر', '', '', 'Nablus', 32.2259224, 35.2306719, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2259224 AND longitude = 35.2306719
);

-- osm_node:432183938 -- https://www.openstreetmap.org/node/432183938
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مختبر طبي', 'مختبر طبي', '', '', 'Nablus', 32.2513557, 35.2691771, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2513557 AND longitude = 35.2691771
);

-- osm_node:432184451 -- https://www.openstreetmap.org/node/432184451
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'المستشفى الوطني', 'المستشفى الوطني', '', '', 'Nablus', 32.2227088, 35.2624703, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2227088 AND longitude = 35.2624703
);

-- osm_node:432185284 -- https://www.openstreetmap.org/node/432185284
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية تبارك', 'صيدلية تبارك', '', '', 'Nablus', 32.2244324, 35.2452774, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2244324 AND longitude = 35.2452774
);

-- osm_node:432191026 -- https://www.openstreetmap.org/node/432191026
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستشفى الاتحاد', 'مستشفى الاتحاد', '', '', 'Nablus', 32.2286617, 35.2572065, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2286617 AND longitude = 35.2572065
);

-- osm_node:4114284190 -- https://www.openstreetmap.org/node/4114284190
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة الدكتور علام الشنار', 'عيادة الدكتور علام الشنار', 'Al-Adel Street', 'Al-Adel Street', 'Nablus', 32.2221467, 35.260475, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2221467 AND longitude = 35.260475
);

-- osm_node:4117028002 -- https://www.openstreetmap.org/node/4117028002
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Dr. Najeh Numoor', 'Dr. Najeh Numoor', 'Amman Street', 'Amman Street', 'Nablus', 32.2150634, 35.2834985, '+970599702158', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2150634 AND longitude = 35.2834985
);

-- osm_node:4297074605 -- https://www.openstreetmap.org/node/4297074605
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مديرية الصحة المخفية', 'مديرية الصحة المخفية', 'Al-Mkhfya Street', 'Al-Mkhfya Street', 'Nablus', 32.2207133, 35.2315003, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2207133 AND longitude = 35.2315003
);

-- osm_node:4311444891 -- https://www.openstreetmap.org/node/4311444891
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية النور الجديدة', 'صيدلية النور الجديدة', '0097092370618, al-adel street, نابلس', '0097092370618, al-adel street, نابلس', 'Nablus', 32.2222228, 35.2598617, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2222228 AND longitude = 35.2598617
);

-- osm_node:4317842391 -- https://www.openstreetmap.org/node/4317842391
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مركز الهلال الأحمر', 'مركز الهلال الأحمر', 'Khalit Al-Amoud Street', 'Khalit Al-Amoud Street', 'Nablus', 32.2124759, 35.2725611, '092380215', 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2124759 AND longitude = 35.2725611
);

-- osm_node:4317864289 -- https://www.openstreetmap.org/node/4317864289
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Ambulance station', 'Ambulance station', 'Khalit Al-Amoud Street', 'Khalit Al-Amoud Street', 'Nablus', 32.2124704, 35.2726276, '092380399', 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2124704 AND longitude = 35.2726276
);

-- osm_node:4319784900 -- https://www.openstreetmap.org/node/4319784900
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية صبري', 'Sabri Pharmacy', 'Prince Mohammad Street, نابلس', 'Prince Mohammad Street, نابلس', 'Nablus', 32.2245946, 35.2539483, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2245946 AND longitude = 35.2539483
);

-- osm_node:4405292289 -- https://www.openstreetmap.org/node/4405292289
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مركز صحي بلاطة', 'Balata Health Centre', 'مخيم بلاطة', 'مخيم بلاطة', 'Nablus', 32.2080215, 35.2862201, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2080215 AND longitude = 35.2862201
);

-- osm_node:4433190689 -- https://www.openstreetmap.org/node/4433190689
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستشفى جامعة النجاح', 'مستشفى جامعة النجاح', '', '', 'Nablus', 32.2389101, 35.2452907, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2389101 AND longitude = 35.2452907
);

-- osm_node:4522520492 -- https://www.openstreetmap.org/node/4522520492
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Dr. Naji Arandi', 'Dr. Naji Arandi', 'Al-Adel Street, نابلس', 'Al-Adel Street, نابلس', 'Nablus', 32.2220458, 35.2601882, '0097092388443', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2220458 AND longitude = 35.2601882
);

-- osm_node:4522530890 -- https://www.openstreetmap.org/node/4522530890
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Dr. Ziad Arandi', 'Dr. Ziad Arandi', 'نابلس', 'نابلس', 'Nablus', 32.2213527, 35.2605094, '0097092378333', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2213527 AND longitude = 35.2605094
);

-- osm_node:4526873589 -- https://www.openstreetmap.org/node/4526873589
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية العريض', 'Areed Pharmacy', '', '', 'Nablus', 32.2152458, 35.2776342, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2152458 AND longitude = 35.2776342
);

-- osm_node:4532702589 -- https://www.openstreetmap.org/node/4532702589
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الأقصى', 'Al-Aqsa Pharmacy', '', '', 'Nablus', 32.221593, 35.2978655, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.221593 AND longitude = 35.2978655
);

-- osm_node:4636074989 -- https://www.openstreetmap.org/node/4636074989
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Dr Mohammed Hajhamad Clinic', 'Dr Mohammed Hajhamad Clinic', 'Al-Quds Street', 'Al-Quds Street', 'Nablus', 32.2058844, 35.2835964, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2058844 AND longitude = 35.2835964
);

-- osm_node:4648760390 -- https://www.openstreetmap.org/node/4648760390
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستوصف التضامن الخيري', 'مستوصف التضامن الخيري', 'Rafedya Street', 'Rafedya Street', 'Nablus', 32.224649, 35.247208, '09 238 9070', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.224649 AND longitude = 35.247208
);

-- osm_node:4653230493 -- https://www.openstreetmap.org/node/4653230493
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستودع صيدليته العريض', 'Al areed pharmacy warehouse', '', '', 'Nablus', 32.2159161, 35.2769472, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2159161 AND longitude = 35.2769472
);

-- osm_node:4654162292 -- https://www.openstreetmap.org/node/4654162292
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الشخشير', 'Aslan Pharmacy', '', '', 'Nablus', 32.2213173, 35.2603866, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2213173 AND longitude = 35.2603866
);

-- osm_node:4654162293 -- https://www.openstreetmap.org/node/4654162293
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية بلسم', 'Balsam Pharmacy', 'Sufian Street', 'Sufian Street', 'Nablus', 32.2241628, 35.2575332, '092335122', 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2241628 AND longitude = 35.2575332
);

-- osm_node:4665647290 -- https://www.openstreetmap.org/node/4665647290
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية عصيرة الشمالية', 'صيدلية عصيرة الشمالية', '', '', 'Nablus', 32.2514208, 35.2667355, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2514208 AND longitude = 35.2667355
);

-- osm_node:4694652889 -- https://www.openstreetmap.org/node/4694652889
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Dr-Othman Othman', 'Dr-Othman Othman', '', '', 'Nablus', 32.2241552, 35.227668, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2241552 AND longitude = 35.227668
);

-- osm_node:4699269690 -- https://www.openstreetmap.org/node/4699269690
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة الدكتور عثمان عثمان', 'Dr-Othman Othman', '', '', 'Nablus', 32.2225142, 35.2571716, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2225142 AND longitude = 35.2571716
);

-- osm_node:4708713490 -- https://www.openstreetmap.org/node/4708713490
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الفيحاء', 'Al-Faiha'' Pharmacy', 'Omar Ibn Al-Khattab Street', 'Omar Ibn Al-Khattab Street', 'Nablus', 32.2207828, 35.2455004, '092341391', 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2207828 AND longitude = 35.2455004
);

-- osm_node:4755252221 -- https://www.openstreetmap.org/node/4755252221
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'المستشفى الانجيلي العربي', 'saint Luke''s hospital', 'نابلس', 'نابلس', 'Nablus', 32.222953, 35.2551483, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.222953 AND longitude = 35.2551483
);

-- osm_node:4788974925 -- https://www.openstreetmap.org/node/4788974925
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'منزل الدكتور حازم ابوالحلاوة', 'منزل الدكتور حازم ابوالحلاوة', '', '', 'Nablus', 32.2532111, 35.264973, '0568343509', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2532111 AND longitude = 35.264973
);

-- osm_node:4798304621 -- https://www.openstreetmap.org/node/4798304621
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'فاروق عزت الزربا', 'Dr Farouq Izzat Al-Zurba', 'Al-Makhfeyah Street', 'Al-Makhfeyah Street', 'Nablus', 32.2181205, 35.2381531, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2181205 AND longitude = 35.2381531
);

-- osm_node:4843420021 -- https://www.openstreetmap.org/node/4843420021
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'منزل الدكتور عثمان عثمان', 'Home of Dr. Othman Othman', '', '', 'Nablus', 32.2242442, 35.2327213, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2242442 AND longitude = 35.2327213
);

-- osm_node:4901729823 -- https://www.openstreetmap.org/node/4901729823
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة ابراهيم جبر للاسنان', 'Ibrahim jabir dentist', '', '', 'Nablus', 32.2203231, 35.2617569, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2203231 AND longitude = 35.2617569
);

-- osm_node:4919923621 -- https://www.openstreetmap.org/node/4919923621
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Alrahmah patients friends', 'Alrahmah patients friends', 'King Faisal stereetشارع فيصل', 'King Faisal stereetشارع فيصل', 'Nablus', 32.2182312, 35.2691193, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2182312 AND longitude = 35.2691193
);

-- osm_node:4921706121 -- https://www.openstreetmap.org/node/4921706121
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'وزارة الصحة - بلاطة البلد', 'Ministry of Health - Tile Country', '', '', 'Nablus', 32.2118149, 35.2848936, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2118149 AND longitude = 35.2848936
);

-- osm_node:4955149321 -- https://www.openstreetmap.org/node/4955149321
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الدكتور هاني النابلسي', 'Dr. Hani Nabulsi', 'Hitteen Street', 'Hitteen Street', 'Nablus', 32.2204308, 35.263052, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2204308 AND longitude = 35.263052
);

-- osm_node:4976767621 -- https://www.openstreetmap.org/node/4976767621
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مركز علاج لطب الأسنان', 'Elaj Dental Center', '', '', 'Nablus', 32.2242588, 35.257618, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2242588 AND longitude = 35.257618
);

-- osm_node:5181447222 -- https://www.openstreetmap.org/node/5181447222
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية مكه', 'Mecca Pharmacy', 'Al-Quds Street', 'Al-Quds Street', 'Nablus', 32.2068423, 35.2836983, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2068423 AND longitude = 35.2836983
);

-- osm_node:5181767222 -- https://www.openstreetmap.org/node/5181767222
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Noora pharmacy', 'Noora pharmacy', '', '', 'Nablus', 32.2154955, 35.2738683, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2154955 AND longitude = 35.2738683
);

-- osm_node:5185586921 -- https://www.openstreetmap.org/node/5185586921
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة د احسان جيطان', 'عيادة د احسان جيطان', 'نابلس', 'نابلس', 'Nablus', 32.2228103, 35.2589586, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2228103 AND longitude = 35.2589586
);

-- osm_node:5185586922 -- https://www.openstreetmap.org/node/5185586922
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'د.احسان جيطان', 'Dr Ihsan Jitan', '18, AL-Iqleeme Street', '18, AL-Iqleeme Street', 'Nablus', 32.1976554, 35.2947496, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.1976554 AND longitude = 35.2947496
);

-- osm_node:5200693023 -- https://www.openstreetmap.org/node/5200693023
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'المستشفى العربي التخصصي', 'Specialized arab hospital', 'شارع رفيديا', 'شارع رفيديا', 'Nablus', 32.2233015, 35.2398105, '092353000', 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2233015 AND longitude = 35.2398105
);

-- osm_node:5226005021 -- https://www.openstreetmap.org/node/5226005021
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية سناء', 'صيدلية سناء', 'Sufyan Street', 'Sufyan Street', 'Nablus', 32.2231927, 35.2591955, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2231927 AND longitude = 35.2591955
);

-- osm_node:5226005022 -- https://www.openstreetmap.org/node/5226005022
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستودع المستقبل', 'مستودع المستقبل', 'Sufian Street, نابلس', 'Sufian Street, نابلس', 'Nablus', 32.2230212, 35.2585592, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2230212 AND longitude = 35.2585592
);

-- osm_node:5233744421 -- https://www.openstreetmap.org/node/5233744421
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة الدكتور محمد رامز الخياط', 'عيادة الدكتور محمد رامز الخياط', 'نابلس', 'نابلس', 'Nablus', 32.2216753, 35.2599976, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2216753 AND longitude = 35.2599976
);

-- osm_node:5285813826 -- https://www.openstreetmap.org/node/5285813826
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'الدكتور شجيع ياسين - Dr. Shaji''e Yasin', 'الدكتور شجيع ياسين - Dr. Shaji''e Yasin', '', '', 'Nablus', 32.2520728, 35.2690303, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2520728 AND longitude = 35.2690303
);

-- osm_node:5313975723 -- https://www.openstreetmap.org/node/5313975723
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الأكاديمية', 'صيدلية الأكاديمية', '', '', 'Nablus', 32.2274899, 35.2197937, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2274899 AND longitude = 35.2197937
);

-- osm_node:5352473342 -- https://www.openstreetmap.org/node/5352473342
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Majdi', 'Majdi', '', '', 'Nablus', 32.2185228, 35.2652348, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2185228 AND longitude = 35.2652348
);

-- osm_node:5352490122 -- https://www.openstreetmap.org/node/5352490122
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Al Kamal', 'Al Kamal', '', '', 'Nablus', 32.2206778, 35.2634217, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2206778 AND longitude = 35.2634217
);

-- osm_node:5367809664 -- https://www.openstreetmap.org/node/5367809664
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Hassan Pharmacy', 'Hassan Pharmacy', '', '', 'Nablus', 32.2209987, 35.2601539, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2209987 AND longitude = 35.2601539
);

-- osm_node:5405639426 -- https://www.openstreetmap.org/node/5405639426
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'jeriatric house red crescent', 'jeriatric house red crescent', '16 th Street', '16 th Street', 'Nablus', 32.2220969, 35.248182, '092386606', 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2220969 AND longitude = 35.248182
);

-- osm_node:5582520722 -- https://www.openstreetmap.org/node/5582520722
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Tabanjeh Pharmacy', 'Tabanjeh Pharmacy', '', '', 'Nablus', 32.2210026, 35.2421352, '092351570', 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2210026 AND longitude = 35.2421352
);

-- osm_node:5743634721 -- https://www.openstreetmap.org/node/5743634721
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Dima IVF Center', 'Dima IVF Center', 'عمارة الصفوه 4, Sufyan Street, نابلس', 'عمارة الصفوه 4, Sufyan Street, نابلس', 'Nablus', 32.2230967, 35.257747, '092389292', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2230967 AND longitude = 35.257747
);

-- osm_node:5999964388 -- https://www.openstreetmap.org/node/5999964388
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية المخفيه', 'صيدلية المخفيه', '', '', 'Nablus', 32.2192346, 35.2366165, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2192346 AND longitude = 35.2366165
);

-- osm_node:5999965286 -- https://www.openstreetmap.org/node/5999965286
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الشخشير', 'صيدلية الشخشير', 'نابلس', 'نابلس', 'Nablus', 32.2213524, 35.2598101, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2213524 AND longitude = 35.2598101
);

-- osm_node:5999965287 -- https://www.openstreetmap.org/node/5999965287
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية خورشيد', 'صيدلية خورشيد', 'نابلس', 'نابلس', 'Nablus', 32.2211258, 35.2582297, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2211258 AND longitude = 35.2582297
);

-- osm_node:5999966385 -- https://www.openstreetmap.org/node/5999966385
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية دار الدواء', 'صيدلية دار الدواء', '', '', 'Nablus', 32.2322247, 35.2427668, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2322247 AND longitude = 35.2427668
);

-- osm_node:6012423385 -- https://www.openstreetmap.org/node/6012423385
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الوليد', 'Pharmacy', '', '', 'Nablus', 32.2215852, 35.2593492, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2215852 AND longitude = 35.2593492
);

-- osm_node:6013018585 -- https://www.openstreetmap.org/node/6013018585
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية شرف', 'صيدلية شرف', 'نابلس', 'نابلس', 'Nablus', 32.2210994, 35.2592697, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2210994 AND longitude = 35.2592697
);

-- osm_node:6013018586 -- https://www.openstreetmap.org/node/6013018586
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Al-Rahma Pharmacy', 'Al-Rahma Pharmacy', '', '', 'Nablus', 32.2291206, 35.2502783, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2291206 AND longitude = 35.2502783
);

-- osm_node:6013018687 -- https://www.openstreetmap.org/node/6013018687
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Fawaz Pharmacy', 'Fawaz Pharmacy', '', '', 'Nablus', 32.2239335, 35.2501516, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2239335 AND longitude = 35.2501516
);

-- osm_node:6013018688 -- https://www.openstreetmap.org/node/6013018688
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الحنبلي', 'صيدلية الحنبلي', '', '', 'Nablus', 32.2207845, 35.2646142, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2207845 AND longitude = 35.2646142
);

-- osm_node:6274201585 -- https://www.openstreetmap.org/node/6274201585
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية المعتصم', 'صيدلية المعتصم', '', '', 'Nablus', 32.2255385, 35.2418155, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2255385 AND longitude = 35.2418155
);

-- osm_node:6390534085 -- https://www.openstreetmap.org/node/6390534085
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية الغدير', 'صيدلية الغدير', '', '', 'Nablus', 32.2326714, 35.2502543, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2326714 AND longitude = 35.2502543
);

-- osm_node:6597003885 -- https://www.openstreetmap.org/node/6597003885
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مستشفى الأمل للتأهيل', 'مستشفى الأمل للتأهيل', '', '', 'Nablus', 32.2106997, 35.253177, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2106997 AND longitude = 35.253177
);

-- osm_node:6811975985 -- https://www.openstreetmap.org/node/6811975985
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Derma clinic', 'Derma clinic', 'شارع البساتين', 'شارع البساتين', 'Nablus', 32.2239524, 35.2555775, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2239524 AND longitude = 35.2555775
);

-- osm_node:6811978287 -- https://www.openstreetmap.org/node/6811978287
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية انعام', 'صيدلية انعام', 'نابلس', 'نابلس', 'Nablus', 32.2210125, 35.2596791, NULL, 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2210125 AND longitude = 35.2596791
);

-- osm_node:6966245122 -- https://www.openstreetmap.org/node/6966245122
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'grand center', 'grand center', 'شارع رفيديا', 'شارع رفيديا', 'Nablus', 32.2230858, 35.2346378, '092353724', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2230858 AND longitude = 35.2346378
);

-- osm_node:7570887985 -- https://www.openstreetmap.org/node/7570887985
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Demaidi Pharm', 'Demaidi Pharm', 'نابلس الجديدة', 'نابلس الجديدة', 'Nablus', 32.2152504, 35.2393712, '092377701', 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2152504 AND longitude = 35.2393712
);

-- osm_node:7600038793 -- https://www.openstreetmap.org/node/7600038793
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'صيدلية المها', 'صيدلية المها', '09/2370647, شارع الاتحاد', '09/2370647, شارع الاتحاد', 'Nablus', 32.2292729, 35.2567287, '2370647', 'pharmacy', ARRAY['pharmacy'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2292729 AND longitude = 35.2567287
);

-- osm_node:7794300485 -- https://www.openstreetmap.org/node/7794300485
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Nwaiser dental clinic', 'Nwaiser dental clinic', '', '', 'Nablus', 32.2240932, 35.2437381, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2240932 AND longitude = 35.2437381
);

-- osm_node:7830446586 -- https://www.openstreetmap.org/node/7830446586
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Rafedia hospital', 'Rafedia hospital', '', '', 'Nablus', 32.2257329, 35.2409873, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2257329 AND longitude = 35.2409873
);

-- osm_node:8341497204 -- https://www.openstreetmap.org/node/8341497204
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'Hamza Kids Clinic', 'Hamza Kids Clinic', 'عصيره الشماليّه', 'عصيره الشماليّه', 'Nablus', 32.2515712, 35.268477, '+97 0597 181616', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2515712 AND longitude = 35.268477
);

-- osm_node:8391971717 -- https://www.openstreetmap.org/node/8391971717
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مركز إسعاف غرب نابلس', 'Ambulance Center', '', '', 'Nablus', 32.2367374, 35.2327041, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2367374 AND longitude = 35.2327041
);

-- osm_node:10872143306 -- https://www.openstreetmap.org/node/10872143306
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'مجمع الحكيم الطبي', 'مجمع الحكيم الطبي', '', '', 'Nablus', 32.2358706, 35.2324804, NULL, 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2358706 AND longitude = 35.2324804
);

-- osm_node:11764767469 -- https://www.openstreetmap.org/node/11764767469
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'عيادة العقاد لطب وجراحة العيون', 'عيادة العقاد لطب وجراحة العيون', 'شارع فلسطين', 'شارع فلسطين', 'Nablus', 32.2222627, 35.2582551, '092379721', 'clinic', ARRAY['clinic'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2222627 AND longitude = 35.2582551
);

-- osm_way:433076784 -- https://www.openstreetmap.org/way/433076784
INSERT INTO medorbit.clinics (name_ar, name_en, address_ar, address_en, city, latitude, longitude, phone, type, services, is_active, verification_status)
SELECT 'نابلس التخصصي', 'نابلس التخصصي', '', '', 'Nablus', 32.2205405, 35.246816, NULL, 'hospital', ARRAY['hospital'], true, 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM medorbit.clinics
  WHERE latitude = 32.2205405 AND longitude = 35.246816
);

COMMIT;
