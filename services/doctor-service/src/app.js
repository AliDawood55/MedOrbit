import express from "express";
import { v4 as uuid } from "uuid";
import swaggerUi from "swagger-ui-express";
import { pool } from "./db/pool.js";
import { requireAuth, requireRole } from "./auth.js";
import { openapi } from "./openapi.js";

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => res.json({ status: "ok", service: "doctor-service" }));
  app.get("/ready", async (_req, res) => {
    try {
      await pool.query("SELECT 1");
      res.json({ status: "ready" });
    } catch {
      res.status(503).json({ status: "not ready" });
    }
  });
  app.use("/docs", swaggerUi.serve, swaggerUi.setup(openapi));

  app.get("/api/v1/specialties", async (_req, res) => {
    const r = await pool.query("SELECT * FROM specialties ORDER BY name_en");
    res.json(r.rows);
  });

  // Public catalog: only verified doctors are listed
  app.get("/api/v1/doctors", async (req, res) => {
    const { search, specialtyId, page = 1, limit = 20 } = req.query;
    const conditions = ["d.is_verified = TRUE"];
    const params = [];
    if (search) {
      params.push(`%${search}%`);
      conditions.push(`d.full_name ILIKE $${params.length}`);
    }
    if (specialtyId) {
      params.push(Number(specialtyId));
      conditions.push(`d.specialty_id = $${params.length}`);
    }
    params.push(Math.min(Number(limit) || 20, 100));
    params.push((Math.max(Number(page) || 1, 1) - 1) * (Number(limit) || 20));
    const r = await pool.query(
      `SELECT d.user_id, d.full_name, d.bio, d.years_of_experience, d.consultation_fee,
              s.name_en AS specialty_en, s.name_ar AS specialty_ar,
              COALESCE(AVG(r.rating), 0)::NUMERIC(3,2) AS avg_rating,
              COUNT(r.id)::INT AS rating_count
       FROM doctors d
       LEFT JOIN specialties s ON s.id = d.specialty_id
       LEFT JOIN doctor_ratings r ON r.doctor_id = d.user_id
       WHERE ${conditions.join(" AND ")}
       GROUP BY d.user_id, s.name_en, s.name_ar
       ORDER BY avg_rating DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    res.json({ doctors: r.rows, page: Number(page) });
  });

  app.get("/api/v1/doctors/:id", async (req, res) => {
    const r = await pool.query(
      `SELECT d.*, s.name_en AS specialty_en, s.name_ar AS specialty_ar,
              (SELECT COALESCE(AVG(rating), 0)::NUMERIC(3,2) FROM doctor_ratings WHERE doctor_id = d.user_id) AS avg_rating
       FROM doctors d LEFT JOIN specialties s ON s.id = d.specialty_id
       WHERE d.user_id = $1 AND d.is_verified = TRUE`,
      [req.params.id]
    );
    if (!r.rowCount) return res.status(404).json({ error: "doctor not found" });
    res.json(r.rows[0]);
  });

  app.put("/api/v1/doctors/me", requireAuth, requireRole("doctor"), async (req, res) => {
    const { fullName, specialtyId, licenseNumber, bio, yearsOfExperience, consultationFee } = req.body;
    if (!licenseNumber) return res.status(400).json({ error: "licenseNumber is required" });
    const r = await pool.query(
      `INSERT INTO doctors (user_id, full_name, specialty_id, license_number, bio, years_of_experience, consultation_fee)
       VALUES ($1, $2, $3, $4, $5, COALESCE($6, 0), COALESCE($7, 0))
       ON CONFLICT (user_id) DO UPDATE SET
         full_name = COALESCE($2, doctors.full_name),
         specialty_id = COALESCE($3, doctors.specialty_id),
         license_number = COALESCE($4, doctors.license_number),
         bio = COALESCE($5, doctors.bio),
         years_of_experience = COALESCE($6, doctors.years_of_experience),
         consultation_fee = COALESCE($7, doctors.consultation_fee),
         updated_at = NOW()
       RETURNING *`,
      [
        req.user.sub,
        fullName || "Dr. Unnamed",
        specialtyId || null,
        licenseNumber,
        bio || null,
        yearsOfExperience ?? null,
        consultationFee ?? null,
      ]
    );
    res.json(r.rows[0]);
  });

  app.get("/api/v1/doctors/admin/pending", requireAuth, requireRole("admin"), async (_req, res) => {
    const r = await pool.query("SELECT * FROM doctors WHERE is_verified = FALSE ORDER BY created_at");
    res.json(r.rows);
  });

  app.post("/api/v1/doctors/:id/verify", requireAuth, requireRole("admin"), async (req, res) => {
    const r = await pool.query(
      `UPDATE doctors SET is_verified = TRUE, verified_at = NOW(), verified_by = $2, updated_at = NOW()
       WHERE user_id = $1 RETURNING *`,
      [req.params.id, req.user.sub]
    );
    if (!r.rowCount) return res.status(404).json({ error: "doctor not found" });
    res.json(r.rows[0]);
  });

  app.post("/api/v1/doctors/:id/ratings", requireAuth, requireRole("patient"), async (req, res) => {
    const { rating, review } = req.body;
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      return res.status(400).json({ error: "rating must be an integer 1-5" });
    }
    const doctor = await pool.query("SELECT user_id FROM doctors WHERE user_id = $1 AND is_verified = TRUE", [
      req.params.id,
    ]);
    if (!doctor.rowCount) return res.status(404).json({ error: "doctor not found" });
    const r = await pool.query(
      `INSERT INTO doctor_ratings (id, doctor_id, patient_id, rating, review)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (doctor_id, patient_id) DO UPDATE SET rating = $4, review = $5, created_at = NOW()
       RETURNING *`,
      [uuid(), req.params.id, req.user.sub, rating, review || null]
    );
    res.status(201).json(r.rows[0]);
  });

  app.get("/api/v1/doctors/:id/ratings", async (req, res) => {
    const r = await pool.query(
      "SELECT rating, review, created_at FROM doctor_ratings WHERE doctor_id = $1 ORDER BY created_at DESC",
      [req.params.id]
    );
    res.json(r.rows);
  });

  app.use((err, _req, res, _next) => {
    console.error(err);
    res.status(500).json({ error: "internal server error" });
  });

  return app;
}
