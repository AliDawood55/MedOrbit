-- 09_clinics_nablus_cleanup.sql
-- Gap-fill / defect repair for pre-existing Nablus clinic rows inserted by the
-- old, unfixed save_to_db.py (same OSM source, before osm_collector.py was fixed).
-- Matched on exact (latitude, longitude). NEVER overwrites a real existing value —
-- each UPDATE's WHERE clause requires the specific defect signature it repairs:
--   type        : only if currently NULL
--   name_ar/en  : only if they are currently IDENTICAL (the old script's
--                 duplicate-generic-name bug) — proper ar/en split otherwise left alone
--   address_*   : only if currently 'N/A' (fabricated placeholder) or '' — replaced
--                 with a real OSM address if we have one, else '' (honest blank)
--   phone       : only if currently NULL and OSM has a real phone
-- All other columns (services, operating_hours, insurance, is_active, id) untouched.

BEGIN;

-- osm_node:431897069 -- https://www.openstreetmap.org/node/431897069
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الحكمة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الحكمة' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2509096 AND longitude = 35.2693013
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431908879 -- https://www.openstreetmap.org/node/431908879
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مختير ابوخلف الطبي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مختير ابوخلف الطبي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.222535 AND longitude = 35.2627939
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431911387 -- https://www.openstreetmap.org/node/431911387
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الخليل الجديدة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الخليل الجديدة' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2208854 AND longitude = 35.2505042
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431913799 -- https://www.openstreetmap.org/node/431913799
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة هاشم' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة هاشم' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2525629 AND longitude = 35.2694396
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431915153 -- https://www.openstreetmap.org/node/431915153
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مختبر احلام' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مختبر احلام' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2180387 AND longitude = 35.2647514
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431915395 -- https://www.openstreetmap.org/node/431915395
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية سفير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Shqer' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2225474 AND longitude = 35.2416137
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431919833 -- https://www.openstreetmap.org/node/431919833
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الزيتونة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الزيتونة' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2522434 AND longitude = 35.2690866
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431920698 -- https://www.openstreetmap.org/node/431920698
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستشفى رفيديا' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مستشفى رفيديا' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2255247 AND longitude = 35.2416936
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431923237 -- https://www.openstreetmap.org/node/431923237
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية سنا' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Amanda Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2263293 AND longitude = 35.3031367
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431927304 -- https://www.openstreetmap.org/node/431927304
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية المصري' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية المصري' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2210613 AND longitude = 35.2528757
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431935495 -- https://www.openstreetmap.org/node/431935495
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عمارة الرازي للاطباء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عمارة الرازي للاطباء' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2258168 AND longitude = 35.2438848
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431935516 -- https://www.openstreetmap.org/node/431935516
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدليه عبير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدليه عبير' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2175719 AND longitude = 35.2693226
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431937595 -- https://www.openstreetmap.org/node/431937595
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية دعاء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al Maha Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'شارع الاتحاد' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'شارع الاتحاد' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092370647' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2292033 AND longitude = 35.2567632
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092370647' IS NOT NULL)
  );

-- osm_node:431941611 -- https://www.openstreetmap.org/node/431941611
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الامير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الامير' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2376753 AND longitude = 35.2436554
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431943687 -- https://www.openstreetmap.org/node/431943687
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية رفيديا' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية رفيديا' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2212705 AND longitude = 35.2383943
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431945002 -- https://www.openstreetmap.org/node/431945002
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الشخشير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الشخشير' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2210595 AND longitude = 35.2314923
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431955801 -- https://www.openstreetmap.org/node/431955801
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية راس العين' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية راس العين' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2168171 AND longitude = 35.2599845
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431964362 -- https://www.openstreetmap.org/node/431964362
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الزهراء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الزهراء' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2156356 AND longitude = 35.2569566
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431967941 -- https://www.openstreetmap.org/node/431967941
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الاتحاد' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الاتحاد' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2287198 AND longitude = 35.2572975
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431970468 -- https://www.openstreetmap.org/node/431970468
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدليه فادي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدليه فادي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'isso street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'isso street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2188001 AND longitude = 35.2731688
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431972689 -- https://www.openstreetmap.org/node/431972689
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية بيت ايبا' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية بيت ايبا' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.238526 AND longitude = 35.2128725
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431975130 -- https://www.openstreetmap.org/node/431975130
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'منزل الدكتور هيثم عيسى' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'منزل الدكتور هيثم عيسى' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.1999764 AND longitude = 35.2124598
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431976389 -- https://www.openstreetmap.org/node/431976389
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية حواء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Hawa''a' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.218522 AND longitude = 35.2669576
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431977294 -- https://www.openstreetmap.org/node/431977294
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'المستشفى العربي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'The Specialized Arabic Hospital' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2233879 AND longitude = 35.2398405
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431981177 -- https://www.openstreetmap.org/node/431981177
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية عمر' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية عمر' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2220767 AND longitude = 35.2626237
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431989567 -- https://www.openstreetmap.org/node/431989567
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'منزل وعيادة الدكتور مرزوق محمد الصالحي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'منزل وعيادة الدكتور مرزوق محمد الصالحي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2233277 AND longitude = 35.2978401
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:431993699 -- https://www.openstreetmap.org/node/431993699
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة طبية' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة طبية' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2518239 AND longitude = 35.2711321
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432004724 -- https://www.openstreetmap.org/node/432004724
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الكندي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الكندي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2146155 AND longitude = 35.2716798
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432038524 -- https://www.openstreetmap.org/node/432038524
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الادهم للاشعه' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الادهم للاشعه' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2237087 AND longitude = 35.2593954
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432044460 -- https://www.openstreetmap.org/node/432044460
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الدكتور صلاح' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الدكتور صلاح' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2195923 AND longitude = 35.2657767
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432047335 -- https://www.openstreetmap.org/node/432047335
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'ابن النفيس' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'ابن النفيس' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2249043 AND longitude = 35.2313375
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432052667 -- https://www.openstreetmap.org/node/432052667
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور محمد الشوبكي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور محمد الشوبكي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.213429 AND longitude = 35.3030347
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432054557 -- https://www.openstreetmap.org/node/432054557
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية مكه' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Mecca Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2077823 AND longitude = 35.2838194
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432063158 -- https://www.openstreetmap.org/node/432063158
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية ساهر.' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Saher Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2106731 AND longitude = 35.2824143
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432063402 -- https://www.openstreetmap.org/node/432063402
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'سمير القادري' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'سمير القادري' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2178844 AND longitude = 35.2720008
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432065448 -- https://www.openstreetmap.org/node/432065448
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'النابلسي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'النابلسي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2192816 AND longitude = 35.2434858
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432073463 -- https://www.openstreetmap.org/node/432073463
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية سامر' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية سامر' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2254215 AND longitude = 35.24552
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432076168 -- https://www.openstreetmap.org/node/432076168
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة المستقبل' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة المستقبل' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2213687 AND longitude = 35.2293912
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432083390 -- https://www.openstreetmap.org/node/432083390
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدليه عرفات' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدليه عرفات' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2166031 AND longitude = 35.2700844
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432084904 -- https://www.openstreetmap.org/node/432084904
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية المخفية' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية المخفية' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Ibrahim Hashim Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Ibrahim Hashim Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2191774 AND longitude = 35.2367911
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432092238 -- https://www.openstreetmap.org/node/432092238
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الضاحية' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الضاحية' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2109894 AND longitude = 35.27917
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432094064 -- https://www.openstreetmap.org/node/432094064
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الدكتور عبد الحافظ' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الدكتور عبد الحافظ' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2222288 AND longitude = 35.2630443
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432110244 -- https://www.openstreetmap.org/node/432110244
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الدكتور جمال ابو حجلة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الدكتور جمال ابو حجلة' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2232661 AND longitude = 35.2445238
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432115123 -- https://www.openstreetmap.org/node/432115123
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية اسامة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Osama Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2222007 AND longitude = 35.2616395
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432124125 -- https://www.openstreetmap.org/node/432124125
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'أطبّاء بلا حدود' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'أطبّاء بلا حدود' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.223225 AND longitude = 35.2430766
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432132006 -- https://www.openstreetmap.org/node/432132006
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية السرايا' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية السرايا' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2157181 AND longitude = 35.2740043
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432137163 -- https://www.openstreetmap.org/node/432137163
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية غازي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية غازي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.224663 AND longitude = 35.2588477
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432138954 -- https://www.openstreetmap.org/node/432138954
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية المستقبل' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al-Mostaqbal Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2177575 AND longitude = 35.293013
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432147461 -- https://www.openstreetmap.org/node/432147461
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية العرندي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية العرندي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2513251 AND longitude = 35.2682093
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432151180 -- https://www.openstreetmap.org/node/432151180
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية نابلس' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Nablus' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2179482 AND longitude = 35.2670849
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432161656 -- https://www.openstreetmap.org/node/432161656
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مركز طبي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مركز طبي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2493818 AND longitude = 35.2681402
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432164716 -- https://www.openstreetmap.org/node/432164716
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الجامعه' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الجامعه' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Omar Ibn Al-Khattab Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Omar Ibn Al-Khattab Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.220833 AND longitude = 35.2466422
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432172425 -- https://www.openstreetmap.org/node/432172425
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستشفى الأمل للعلاج الطبيعي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al Amal For Physical Therapy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2065201 AND longitude = 35.2643352
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432173619 -- https://www.openstreetmap.org/node/432173619
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية فراس' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية فراس' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2216023 AND longitude = 35.2369157
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432174878 -- https://www.openstreetmap.org/node/432174878
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الهلال الاحمر' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الهلال الاحمر' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2259224 AND longitude = 35.2306719
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432183938 -- https://www.openstreetmap.org/node/432183938
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مختبر طبي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مختبر طبي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2513557 AND longitude = 35.2691771
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432184451 -- https://www.openstreetmap.org/node/432184451
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'المستشفى الوطني' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'المستشفى الوطني' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2227088 AND longitude = 35.2624703
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432185284 -- https://www.openstreetmap.org/node/432185284
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية تبارك' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية تبارك' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2244324 AND longitude = 35.2452774
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:432191026 -- https://www.openstreetmap.org/node/432191026
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستشفى الاتحاد' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مستشفى الاتحاد' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2286617 AND longitude = 35.2572065
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4114284190 -- https://www.openstreetmap.org/node/4114284190
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور علام الشنار' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور علام الشنار' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Al-Adel Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Al-Adel Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2221467 AND longitude = 35.260475
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4117028002 -- https://www.openstreetmap.org/node/4117028002
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Dr. Najeh Numoor' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr. Najeh Numoor' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Amman Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Amman Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '+970599702158' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2150634 AND longitude = 35.2834985
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '+970599702158' IS NOT NULL)
  );

-- osm_node:4297074605 -- https://www.openstreetmap.org/node/4297074605
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مديرية الصحة المخفية' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مديرية الصحة المخفية' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Al-Mkhfya Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Al-Mkhfya Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2207133 AND longitude = 35.2315003
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4311444891 -- https://www.openstreetmap.org/node/4311444891
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية النور الجديدة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية النور الجديدة' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '0097092370618, al-adel street, نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '0097092370618, al-adel street, نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2222228 AND longitude = 35.2598617
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4317842391 -- https://www.openstreetmap.org/node/4317842391
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مركز الهلال الأحمر' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مركز الهلال الأحمر' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Khalit Al-Amoud Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Khalit Al-Amoud Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092380215' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2124759 AND longitude = 35.2725611
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092380215' IS NOT NULL)
  );

-- osm_node:4317864289 -- https://www.openstreetmap.org/node/4317864289
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Ambulance station' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Ambulance station' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Khalit Al-Amoud Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Khalit Al-Amoud Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092380399' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2124704 AND longitude = 35.2726276
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092380399' IS NOT NULL)
  );

-- osm_node:4319784900 -- https://www.openstreetmap.org/node/4319784900
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية صبري' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Sabri Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Prince Mohammad Street, نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Prince Mohammad Street, نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2245946 AND longitude = 35.2539483
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4405292289 -- https://www.openstreetmap.org/node/4405292289
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مركز صحي بلاطة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Balata Health Centre' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'مخيم بلاطة' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'مخيم بلاطة' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2080215 AND longitude = 35.2862201
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4433190689 -- https://www.openstreetmap.org/node/4433190689
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستشفى جامعة النجاح' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مستشفى جامعة النجاح' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2389101 AND longitude = 35.2452907
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4522520492 -- https://www.openstreetmap.org/node/4522520492
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Dr. Naji Arandi' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr. Naji Arandi' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Al-Adel Street, نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Al-Adel Street, نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '0097092388443' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2220458 AND longitude = 35.2601882
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '0097092388443' IS NOT NULL)
  );

-- osm_node:4522530890 -- https://www.openstreetmap.org/node/4522530890
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Dr. Ziad Arandi' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr. Ziad Arandi' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '0097092378333' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2213527 AND longitude = 35.2605094
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '0097092378333' IS NOT NULL)
  );

-- osm_node:4526873589 -- https://www.openstreetmap.org/node/4526873589
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية العريض' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Areed Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2152458 AND longitude = 35.2776342
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4532702589 -- https://www.openstreetmap.org/node/4532702589
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الأقصى' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al-Aqsa Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.221593 AND longitude = 35.2978655
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4636074989 -- https://www.openstreetmap.org/node/4636074989
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Dr Mohammed Hajhamad Clinic' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr Mohammed Hajhamad Clinic' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Al-Quds Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Al-Quds Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2058844 AND longitude = 35.2835964
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4648760390 -- https://www.openstreetmap.org/node/4648760390
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستوصف التضامن الخيري' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مستوصف التضامن الخيري' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Rafedya Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Rafedya Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '09 238 9070' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.224649 AND longitude = 35.247208
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '09 238 9070' IS NOT NULL)
  );

-- osm_node:4653230493 -- https://www.openstreetmap.org/node/4653230493
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستودع صيدليته العريض' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al areed pharmacy warehouse' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2159161 AND longitude = 35.2769472
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4654162292 -- https://www.openstreetmap.org/node/4654162292
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الشخشير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Aslan Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2213173 AND longitude = 35.2603866
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4654162293 -- https://www.openstreetmap.org/node/4654162293
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية بلسم' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Balsam Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Sufian Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Sufian Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092335122' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2241628 AND longitude = 35.2575332
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092335122' IS NOT NULL)
  );

-- osm_node:4665647290 -- https://www.openstreetmap.org/node/4665647290
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية عصيرة الشمالية' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية عصيرة الشمالية' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2514208 AND longitude = 35.2667355
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4694652889 -- https://www.openstreetmap.org/node/4694652889
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Dr-Othman Othman' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr-Othman Othman' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2241552 AND longitude = 35.227668
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4699269690 -- https://www.openstreetmap.org/node/4699269690
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور عثمان عثمان' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr-Othman Othman' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2225142 AND longitude = 35.2571716
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4708713490 -- https://www.openstreetmap.org/node/4708713490
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الفيحاء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al-Faiha'' Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Omar Ibn Al-Khattab Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Omar Ibn Al-Khattab Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092341391' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2207828 AND longitude = 35.2455004
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092341391' IS NOT NULL)
  );

-- osm_node:4755252221 -- https://www.openstreetmap.org/node/4755252221
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'المستشفى الانجيلي العربي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'saint Luke''s hospital' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.222953 AND longitude = 35.2551483
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4788974925 -- https://www.openstreetmap.org/node/4788974925
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'منزل الدكتور حازم ابوالحلاوة' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'منزل الدكتور حازم ابوالحلاوة' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '0568343509' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2532111 AND longitude = 35.264973
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '0568343509' IS NOT NULL)
  );

-- osm_node:4798304621 -- https://www.openstreetmap.org/node/4798304621
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'فاروق عزت الزربا' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr Farouq Izzat Al-Zurba' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Al-Makhfeyah Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Al-Makhfeyah Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2181205 AND longitude = 35.2381531
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4843420021 -- https://www.openstreetmap.org/node/4843420021
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'منزل الدكتور عثمان عثمان' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Home of Dr. Othman Othman' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2242442 AND longitude = 35.2327213
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4901729823 -- https://www.openstreetmap.org/node/4901729823
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة ابراهيم جبر للاسنان' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Ibrahim jabir dentist' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2203231 AND longitude = 35.2617569
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4919923621 -- https://www.openstreetmap.org/node/4919923621
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Alrahmah patients friends' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Alrahmah patients friends' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'King Faisal stereetشارع فيصل' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'King Faisal stereetشارع فيصل' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2182312 AND longitude = 35.2691193
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4921706121 -- https://www.openstreetmap.org/node/4921706121
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'وزارة الصحة - بلاطة البلد' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Ministry of Health - Tile Country' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2118149 AND longitude = 35.2848936
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4955149321 -- https://www.openstreetmap.org/node/4955149321
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الدكتور هاني النابلسي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr. Hani Nabulsi' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Hitteen Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Hitteen Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2204308 AND longitude = 35.263052
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:4976767621 -- https://www.openstreetmap.org/node/4976767621
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مركز علاج لطب الأسنان' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Elaj Dental Center' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2242588 AND longitude = 35.257618
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5181447222 -- https://www.openstreetmap.org/node/5181447222
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية مكه' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Mecca Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Al-Quds Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Al-Quds Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2068423 AND longitude = 35.2836983
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5181767222 -- https://www.openstreetmap.org/node/5181767222
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Noora pharmacy' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Noora pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2154955 AND longitude = 35.2738683
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5185586921 -- https://www.openstreetmap.org/node/5185586921
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة د احسان جيطان' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة د احسان جيطان' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2228103 AND longitude = 35.2589586
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5185586922 -- https://www.openstreetmap.org/node/5185586922
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'د.احسان جيطان' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dr Ihsan Jitan' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '18, AL-Iqleeme Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '18, AL-Iqleeme Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.1976554 AND longitude = 35.2947496
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5200693023 -- https://www.openstreetmap.org/node/5200693023
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'المستشفى العربي التخصصي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Specialized arab hospital' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'شارع رفيديا' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'شارع رفيديا' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092353000' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2233015 AND longitude = 35.2398105
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092353000' IS NOT NULL)
  );

-- osm_node:5226005021 -- https://www.openstreetmap.org/node/5226005021
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية سناء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية سناء' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Sufyan Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Sufyan Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2231927 AND longitude = 35.2591955
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5226005022 -- https://www.openstreetmap.org/node/5226005022
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستودع المستقبل' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مستودع المستقبل' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'Sufian Street, نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'Sufian Street, نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2230212 AND longitude = 35.2585592
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5233744421 -- https://www.openstreetmap.org/node/5233744421
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور محمد رامز الخياط' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة الدكتور محمد رامز الخياط' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2216753 AND longitude = 35.2599976
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5285813826 -- https://www.openstreetmap.org/node/5285813826
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'الدكتور شجيع ياسين - Dr. Shaji''e Yasin' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'الدكتور شجيع ياسين - Dr. Shaji''e Yasin' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2520728 AND longitude = 35.2690303
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5313975723 -- https://www.openstreetmap.org/node/5313975723
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الأكاديمية' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الأكاديمية' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2274899 AND longitude = 35.2197937
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5352473342 -- https://www.openstreetmap.org/node/5352473342
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Majdi' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Majdi' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2185228 AND longitude = 35.2652348
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5352490122 -- https://www.openstreetmap.org/node/5352490122
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Al Kamal' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al Kamal' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2206778 AND longitude = 35.2634217
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5367809664 -- https://www.openstreetmap.org/node/5367809664
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Hassan Pharmacy' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Hassan Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2209987 AND longitude = 35.2601539
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5405639426 -- https://www.openstreetmap.org/node/5405639426
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'jeriatric house red crescent' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'jeriatric house red crescent' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '16 th Street' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '16 th Street' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092386606' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2220969 AND longitude = 35.248182
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092386606' IS NOT NULL)
  );

-- osm_node:5582520722 -- https://www.openstreetmap.org/node/5582520722
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Tabanjeh Pharmacy' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Tabanjeh Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092351570' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2210026 AND longitude = 35.2421352
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092351570' IS NOT NULL)
  );

-- osm_node:5743634721 -- https://www.openstreetmap.org/node/5743634721
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Dima IVF Center' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Dima IVF Center' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'عمارة الصفوه 4, Sufyan Street, نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'عمارة الصفوه 4, Sufyan Street, نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092389292' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2230967 AND longitude = 35.257747
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092389292' IS NOT NULL)
  );

-- osm_node:5999964388 -- https://www.openstreetmap.org/node/5999964388
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية المخفيه' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية المخفيه' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2192346 AND longitude = 35.2366165
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5999965286 -- https://www.openstreetmap.org/node/5999965286
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الشخشير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الشخشير' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2213524 AND longitude = 35.2598101
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5999965287 -- https://www.openstreetmap.org/node/5999965287
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية خورشيد' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية خورشيد' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2211258 AND longitude = 35.2582297
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:5999966385 -- https://www.openstreetmap.org/node/5999966385
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية دار الدواء' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية دار الدواء' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2322247 AND longitude = 35.2427668
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6012423385 -- https://www.openstreetmap.org/node/6012423385
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الوليد' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2215852 AND longitude = 35.2593492
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6013018585 -- https://www.openstreetmap.org/node/6013018585
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية شرف' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية شرف' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2210994 AND longitude = 35.2592697
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6013018586 -- https://www.openstreetmap.org/node/6013018586
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Al-Rahma Pharmacy' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Al-Rahma Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2291206 AND longitude = 35.2502783
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6013018687 -- https://www.openstreetmap.org/node/6013018687
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Fawaz Pharmacy' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Fawaz Pharmacy' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2239335 AND longitude = 35.2501516
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6013018688 -- https://www.openstreetmap.org/node/6013018688
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الحنبلي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الحنبلي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2207845 AND longitude = 35.2646142
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6274201585 -- https://www.openstreetmap.org/node/6274201585
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية المعتصم' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية المعتصم' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2255385 AND longitude = 35.2418155
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6390534085 -- https://www.openstreetmap.org/node/6390534085
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية الغدير' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية الغدير' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2326714 AND longitude = 35.2502543
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6597003885 -- https://www.openstreetmap.org/node/6597003885
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مستشفى الأمل للتأهيل' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مستشفى الأمل للتأهيل' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2106997 AND longitude = 35.253177
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6811975985 -- https://www.openstreetmap.org/node/6811975985
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Derma clinic' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Derma clinic' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'شارع البساتين' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'شارع البساتين' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2239524 AND longitude = 35.2555775
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6811978287 -- https://www.openstreetmap.org/node/6811978287
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية انعام' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية انعام' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2210125 AND longitude = 35.2596791
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:6966245122 -- https://www.openstreetmap.org/node/6966245122
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'grand center' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'grand center' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'شارع رفيديا' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'شارع رفيديا' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092353724' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2230858 AND longitude = 35.2346378
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092353724' IS NOT NULL)
  );

-- osm_node:7570887985 -- https://www.openstreetmap.org/node/7570887985
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Demaidi Pharm' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Demaidi Pharm' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'نابلس الجديدة' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'نابلس الجديدة' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092377701' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2152504 AND longitude = 35.2393712
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092377701' IS NOT NULL)
  );

-- osm_node:7600038793 -- https://www.openstreetmap.org/node/7600038793
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'pharmacy' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'صيدلية المها' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'صيدلية المها' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '09/2370647, شارع الاتحاد' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '09/2370647, شارع الاتحاد' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '2370647' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2292729 AND longitude = 35.2567287
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '2370647' IS NOT NULL)
  );

-- osm_node:7794300485 -- https://www.openstreetmap.org/node/7794300485
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Nwaiser dental clinic' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Nwaiser dental clinic' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2240932 AND longitude = 35.2437381
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:7830446586 -- https://www.openstreetmap.org/node/7830446586
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Rafedia hospital' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Rafedia hospital' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2257329 AND longitude = 35.2409873
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:8341497204 -- https://www.openstreetmap.org/node/8341497204
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'Hamza Kids Clinic' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Hamza Kids Clinic' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'عصيره الشماليّه' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'عصيره الشماليّه' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '+97 0597 181616' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2515712 AND longitude = 35.268477
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '+97 0597 181616' IS NOT NULL)
  );

-- osm_node:8391971717 -- https://www.openstreetmap.org/node/8391971717
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مركز إسعاف غرب نابلس' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'Ambulance Center' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2367374 AND longitude = 35.2327041
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:10872143306 -- https://www.openstreetmap.org/node/10872143306
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'مجمع الحكيم الطبي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'مجمع الحكيم الطبي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2358706 AND longitude = 35.2324804
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

-- osm_node:11764767469 -- https://www.openstreetmap.org/node/11764767469
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'clinic' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'عيادة العقاد لطب وجراحة العيون' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'عيادة العقاد لطب وجراحة العيون' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN 'شارع فلسطين' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN 'شارع فلسطين' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN '092379721' ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2222627 AND longitude = 35.2582551
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND '092379721' IS NOT NULL)
  );

-- osm_way:433076784 -- https://www.openstreetmap.org/way/433076784
UPDATE medorbit.clinics SET
  type = CASE WHEN type IS NULL THEN 'hospital' ELSE type END,
  name_ar = CASE WHEN name_ar = name_en THEN 'نابلس التخصصي' ELSE name_ar END,
  name_en = CASE WHEN name_ar = name_en THEN 'نابلس التخصصي' ELSE name_en END,
  address_ar = CASE WHEN address_ar IN ('N/A', '') THEN '' ELSE address_ar END,
  address_en = CASE WHEN address_en IN ('N/A', '') THEN '' ELSE address_en END,
  phone = CASE WHEN phone IS NULL THEN NULL ELSE phone END,
  updated_at = NOW()
WHERE latitude = 32.2205405 AND longitude = 35.246816
  AND (
    type IS NULL
    OR name_ar = name_en
    OR address_ar IN ('N/A', '')
    OR address_en IN ('N/A', '')
    OR (phone IS NULL AND NULL IS NOT NULL)
  );

COMMIT;
