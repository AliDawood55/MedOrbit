import { pool } from "./pool.js";

const SQL = `
CREATE TABLE IF NOT EXISTS specialties (
  id SERIAL PRIMARY KEY,
  name_en TEXT UNIQUE NOT NULL,
  name_ar TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS doctors (
  user_id UUID PRIMARY KEY,
  full_name TEXT NOT NULL,
  specialty_id INT REFERENCES specialties(id),
  license_number TEXT NOT NULL,
  bio TEXT,
  years_of_experience INT NOT NULL DEFAULT 0,
  consultation_fee NUMERIC(10,2) NOT NULL DEFAULT 0,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at TIMESTAMPTZ,
  verified_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS doctor_ratings (
  id UUID PRIMARY KEY,
  doctor_id UUID NOT NULL REFERENCES doctors(user_id) ON DELETE CASCADE,
  patient_id UUID NOT NULL,
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (doctor_id, patient_id)
);

INSERT INTO specialties (name_en, name_ar) VALUES
  ('General Medicine', 'الطب العام'),
  ('Cardiology', 'أمراض القلب'),
  ('Dermatology', 'الأمراض الجلدية'),
  ('Pediatrics', 'طب الأطفال'),
  ('Orthopedics', 'جراحة العظام'),
  ('Neurology', 'طب الأعصاب'),
  ('Psychiatry', 'الطب النفسي'),
  ('Ophthalmology', 'طب العيون'),
  ('Dentistry', 'طب الأسنان'),
  ('Gynecology', 'أمراض النساء')
ON CONFLICT (name_en) DO NOTHING;
`;

export async function migrate() {
  await pool.query(SQL);
}

if (process.argv[1] && process.argv[1].endsWith("migrate.js")) {
  migrate()
    .then(() => {
      console.log("doctor-service migrations applied");
      return pool.end();
    })
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
