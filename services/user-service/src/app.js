import express from "express";
import swaggerUi from "swagger-ui-express";
import { pool } from "./db/pool.js";
import { requireAuth, requireRole } from "./auth.js";
import { openapi } from "./openapi.js";

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => res.json({ status: "ok", service: "user-service" }));
  app.get("/ready", async (_req, res) => {
    try {
      await pool.query("SELECT 1");
      res.json({ status: "ready" });
    } catch {
      res.status(503).json({ status: "not ready" });
    }
  });
  app.use("/docs", swaggerUi.serve, swaggerUi.setup(openapi));

  app.get("/api/v1/users/me", requireAuth, async (req, res) => {
    const r = await pool.query("SELECT * FROM profiles WHERE user_id = $1 AND deleted_at IS NULL", [
      req.user.sub,
    ]);
    if (!r.rowCount) return res.status(404).json({ error: "profile not found" });
    res.json(r.rows[0]);
  });

  app.put("/api/v1/users/me", requireAuth, async (req, res) => {
    const { fullName, photoUrl, phone, address, preferredLanguage } = req.body;
    if (preferredLanguage && !["en", "ar"].includes(preferredLanguage)) {
      return res.status(400).json({ error: "preferredLanguage must be en or ar" });
    }
    const r = await pool.query(
      `INSERT INTO profiles (user_id, full_name, photo_url, phone, address, preferred_language, role)
       VALUES ($1, $2, $3, $4, $5, COALESCE($6, 'en'), $7)
       ON CONFLICT (user_id) DO UPDATE SET
         full_name = COALESCE($2, profiles.full_name),
         photo_url = COALESCE($3, profiles.photo_url),
         phone = COALESCE($4, profiles.phone),
         address = COALESCE($5, profiles.address),
         preferred_language = COALESCE($6, profiles.preferred_language),
         updated_at = NOW()
       RETURNING *`,
      [req.user.sub, fullName || "Unnamed", photoUrl || null, phone || null, address || null, preferredLanguage || null, req.user.role]
    );
    res.json(r.rows[0]);
  });

  app.get("/api/v1/users/me/medical-info", requireAuth, requireRole("patient"), async (req, res) => {
    const r = await pool.query("SELECT * FROM patient_medical_info WHERE user_id = $1", [req.user.sub]);
    res.json(r.rows[0] || { user_id: req.user.sub, blood_type: null, allergies: [], chronic_diseases: [], current_medications: [] });
  });

  app.put("/api/v1/users/me/medical-info", requireAuth, requireRole("patient"), async (req, res) => {
    const { bloodType, allergies, chronicDiseases, currentMedications } = req.body;
    await pool.query(
      `INSERT INTO profiles (user_id, full_name, role) VALUES ($1, 'Unnamed', 'patient')
       ON CONFLICT (user_id) DO NOTHING`,
      [req.user.sub]
    );
    const r = await pool.query(
      `INSERT INTO patient_medical_info (user_id, blood_type, allergies, chronic_diseases, current_medications)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id) DO UPDATE SET
         blood_type = COALESCE($2, patient_medical_info.blood_type),
         allergies = COALESCE($3, patient_medical_info.allergies),
         chronic_diseases = COALESCE($4, patient_medical_info.chronic_diseases),
         current_medications = COALESCE($5, patient_medical_info.current_medications),
         updated_at = NOW()
       RETURNING *`,
      [
        req.user.sub,
        bloodType || null,
        allergies ? JSON.stringify(allergies) : null,
        chronicDiseases ? JSON.stringify(chronicDiseases) : null,
        currentMedications ? JSON.stringify(currentMedications) : null,
      ]
    );
    res.json(r.rows[0]);
  });

  app.delete("/api/v1/users/me", requireAuth, async (req, res) => {
    await pool.query("UPDATE profiles SET deleted_at = NOW(), updated_at = NOW() WHERE user_id = $1", [
      req.user.sub,
    ]);
    res.json({ message: "account soft-deleted; medical records preserved for compliance" });
  });

  app.get("/api/v1/users", requireAuth, requireRole("admin"), async (req, res) => {
    const { search, role, page = 1, limit = 20 } = req.query;
    const conditions = ["deleted_at IS NULL"];
    const params = [];
    if (search) {
      params.push(`%${search}%`);
      conditions.push(`full_name ILIKE $${params.length}`);
    }
    if (role) {
      params.push(role);
      conditions.push(`role = $${params.length}`);
    }
    params.push(Math.min(Number(limit) || 20, 100));
    params.push((Math.max(Number(page) || 1, 1) - 1) * (Number(limit) || 20));
    const r = await pool.query(
      `SELECT * FROM profiles WHERE ${conditions.join(" AND ")}
       ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    res.json({ users: r.rows, page: Number(page) });
  });

  app.post("/api/v1/users/:id/suspend", requireAuth, requireRole("admin"), async (req, res) => {
    const r = await pool.query(
      "UPDATE profiles SET is_suspended = TRUE, updated_at = NOW() WHERE user_id = $1 RETURNING *",
      [req.params.id]
    );
    if (!r.rowCount) return res.status(404).json({ error: "user not found" });
    res.json(r.rows[0]);
  });

  app.post("/api/v1/users/:id/unsuspend", requireAuth, requireRole("admin"), async (req, res) => {
    const r = await pool.query(
      "UPDATE profiles SET is_suspended = FALSE, updated_at = NOW() WHERE user_id = $1 RETURNING *",
      [req.params.id]
    );
    if (!r.rowCount) return res.status(404).json({ error: "user not found" });
    res.json(r.rows[0]);
  });

  app.delete("/api/v1/users/:id", requireAuth, requireRole("admin"), async (req, res) => {
    const r = await pool.query(
      "UPDATE profiles SET deleted_at = NOW(), updated_at = NOW() WHERE user_id = $1 RETURNING user_id",
      [req.params.id]
    );
    if (!r.rowCount) return res.status(404).json({ error: "user not found" });
    res.json({ message: "user soft-deleted" });
  });

  app.use((err, _req, res, _next) => {
    console.error(err);
    res.status(500).json({ error: "internal server error" });
  });

  return app;
}
