import pg from "pg";

export const pool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ||
    "postgres://medorbit:medorbit@localhost:5432/doctor_db",
});
