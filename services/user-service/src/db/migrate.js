import { pool } from "./pool.js";

const SQL = `
CREATE TABLE IF NOT EXISTS profiles (
  user_id UUID PRIMARY KEY,
  full_name TEXT NOT NULL,
  photo_url TEXT,
  phone TEXT,
  address TEXT,
  preferred_language TEXT NOT NULL DEFAULT 'en' CHECK (preferred_language IN ('en', 'ar')),
  role TEXT NOT NULL CHECK (role IN ('admin', 'doctor', 'patient')),
  is_suspended BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patient_medical_info (
  user_id UUID PRIMARY KEY REFERENCES profiles(user_id) ON DELETE CASCADE,
  blood_type TEXT CHECK (blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  allergies JSONB NOT NULL DEFAULT '[]',
  chronic_diseases JSONB NOT NULL DEFAULT '[]',
  current_medications JSONB NOT NULL DEFAULT '[]',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

export async function migrate() {
  await pool.query(SQL);
}

if (process.argv[1] && process.argv[1].endsWith("migrate.js")) {
  migrate()
    .then(() => {
      console.log("user-service migrations applied");
      return pool.end();
    })
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
