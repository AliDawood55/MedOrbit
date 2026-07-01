import express from "express";
import bcrypt from "bcryptjs";
import { v4 as uuid } from "uuid";
import swaggerUi from "swagger-ui-express";
import { pool } from "./db/pool.js";
import { validateRegistration } from "./validation.js";
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
  hashToken,
  REFRESH_TOKEN_TTL_DAYS,
} from "./tokens.js";
import { openapi } from "./openapi.js";
import { publishEvent } from "./events.js";

const BCRYPT_COST = 12;
const MAX_FAILED_ATTEMPTS = 5;
const LOCK_MINUTES = 15;
const OTP_TTL_MINUTES = 10;

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => res.json({ status: "ok", service: "auth-service" }));
  app.get("/ready", async (_req, res) => {
    try {
      await pool.query("SELECT 1");
      res.json({ status: "ready" });
    } catch {
      res.status(503).json({ status: "not ready" });
    }
  });
  app.use("/docs", swaggerUi.serve, swaggerUi.setup(openapi));

  app.post("/api/v1/auth/register", async (req, res) => {
    const errors = validateRegistration(req.body);
    if (errors.length) return res.status(400).json({ errors });

    const { email, password, phone, fullName, role, preferredLanguage = "en" } = req.body;
    const existing = await pool.query("SELECT id FROM users WHERE email = $1", [email]);
    if (existing.rowCount) return res.status(409).json({ error: "email already registered" });

    const passwordHash = await bcrypt.hash(password, BCRYPT_COST);
    const id = uuid();
    await pool.query(
      `INSERT INTO users (id, email, password_hash, phone, full_name, role, preferred_language)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, email, passwordHash, phone || null, fullName, role, preferredLanguage]
    );

    const otp = await issueOtp(id, "email_verification");
    await publishEvent("user.registered", { userId: id, email, role });

    res.status(201).json({
      id,
      email,
      role,
      message: "registered; verify email with OTP",
      // OTP returned in response for development; delivered via email in production
      devOtp: process.env.NODE_ENV === "production" ? undefined : otp,
    });
  });

  app.post("/api/v1/auth/verify-otp", async (req, res) => {
    const { email, code } = req.body;
    if (!email || !code) return res.status(400).json({ error: "email and code required" });

    const user = await findUserByEmail(email);
    if (!user) return res.status(404).json({ error: "user not found" });

    const result = await pool.query(
      `UPDATE otp_codes SET consumed_at = NOW()
       WHERE user_id = $1 AND code = $2 AND purpose = 'email_verification'
         AND consumed_at IS NULL AND expires_at > NOW()
       RETURNING id`,
      [user.id, code]
    );
    if (!result.rowCount) return res.status(400).json({ error: "invalid or expired OTP" });

    await pool.query("UPDATE users SET is_verified = TRUE, updated_at = NOW() WHERE id = $1", [user.id]);
    res.json({ message: "email verified" });
  });

  app.post("/api/v1/auth/login", async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ error: "email and password required" });

    const user = await findUserByEmail(email);
    if (!user || !user.is_active) return res.status(401).json({ error: "invalid credentials" });

    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      return res.status(423).json({ error: "account locked; try again later" });
    }

    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      const attempts = user.failed_login_attempts + 1;
      const lock = attempts >= MAX_FAILED_ATTEMPTS;
      await pool.query(
        `UPDATE users SET failed_login_attempts = $2,
           locked_until = ${lock ? `NOW() + INTERVAL '${LOCK_MINUTES} minutes'` : "NULL"},
           updated_at = NOW()
         WHERE id = $1`,
        [user.id, lock ? 0 : attempts]
      );
      return res.status(401).json({ error: "invalid credentials" });
    }

    if (!user.is_verified) return res.status(403).json({ error: "email not verified" });

    await pool.query(
      "UPDATE users SET failed_login_attempts = 0, locked_until = NULL, updated_at = NOW() WHERE id = $1",
      [user.id]
    );

    const tokens = await issueTokenPair(user);
    res.json({
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      user: publicUser(user),
    });
  });

  app.post("/api/v1/auth/refresh", async (req, res) => {
    const { refreshToken } = req.body;
    if (!refreshToken) return res.status(400).json({ error: "refreshToken required" });

    let payload;
    try {
      payload = verifyRefreshToken(refreshToken);
    } catch {
      return res.status(401).json({ error: "invalid refresh token" });
    }

    const row = await pool.query(
      `UPDATE refresh_tokens SET revoked_at = NOW()
       WHERE id = $1 AND token_hash = $2 AND revoked_at IS NULL AND expires_at > NOW()
       RETURNING user_id`,
      [payload.jti, hashToken(refreshToken)]
    );
    if (!row.rowCount) return res.status(401).json({ error: "refresh token revoked or expired" });

    const user = await findUserById(row.rows[0].user_id);
    if (!user || !user.is_active) return res.status(401).json({ error: "user inactive" });

    const tokens = await issueTokenPair(user);
    res.json(tokens);
  });

  app.post("/api/v1/auth/logout", async (req, res) => {
    const { refreshToken } = req.body;
    if (!refreshToken) return res.status(400).json({ error: "refreshToken required" });
    try {
      const payload = verifyRefreshToken(refreshToken);
      await pool.query("UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1", [payload.jti]);
    } catch {
      // token already invalid; logout is idempotent
    }
    res.json({ message: "logged out" });
  });

  app.post("/api/v1/auth/forgot-password", async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "email required" });
    const user = await findUserByEmail(email);
    let devOtp;
    if (user) devOtp = await issueOtp(user.id, "password_reset");
    res.json({
      message: "if the email exists, a reset code was sent",
      devOtp: process.env.NODE_ENV === "production" ? undefined : devOtp,
    });
  });

  app.post("/api/v1/auth/reset-password", async (req, res) => {
    const { email, code, newPassword } = req.body;
    if (!email || !code || !newPassword) {
      return res.status(400).json({ error: "email, code, and newPassword required" });
    }
    const errors = validateRegistration({
      email,
      password: newPassword,
      fullName: "xx",
      role: "patient",
    });
    if (errors.length) return res.status(400).json({ errors });

    const user = await findUserByEmail(email);
    if (!user) return res.status(404).json({ error: "user not found" });

    const result = await pool.query(
      `UPDATE otp_codes SET consumed_at = NOW()
       WHERE user_id = $1 AND code = $2 AND purpose = 'password_reset'
         AND consumed_at IS NULL AND expires_at > NOW()
       RETURNING id`,
      [user.id, code]
    );
    if (!result.rowCount) return res.status(400).json({ error: "invalid or expired code" });

    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_COST);
    await pool.query("UPDATE users SET password_hash = $2, updated_at = NOW() WHERE id = $1", [
      user.id,
      passwordHash,
    ]);
    await pool.query("UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL", [
      user.id,
    ]);
    res.json({ message: "password reset" });
  });

  app.use((err, _req, res, _next) => {
    console.error(err);
    res.status(500).json({ error: "internal server error" });
  });

  return app;
}

async function issueTokenPair(user) {
  const tokenId = uuid();
  const accessToken = signAccessToken(user);
  const refreshToken = signRefreshToken(user, tokenId);
  await pool.query(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '${REFRESH_TOKEN_TTL_DAYS} days')`,
    [tokenId, user.id, hashToken(refreshToken)]
  );
  return { accessToken, refreshToken };
}

async function issueOtp(userId, purpose) {
  const code = String(Math.floor(100000 + Math.random() * 900000));
  await pool.query(
    `INSERT INTO otp_codes (id, user_id, code, purpose, expires_at)
     VALUES ($1, $2, $3, $4, NOW() + INTERVAL '${OTP_TTL_MINUTES} minutes')`,
    [uuid(), userId, code, purpose]
  );
  return code;
}

async function findUserByEmail(email) {
  const r = await pool.query("SELECT * FROM users WHERE email = $1", [email]);
  return r.rows[0];
}

async function findUserById(id) {
  const r = await pool.query("SELECT * FROM users WHERE id = $1", [id]);
  return r.rows[0];
}

function publicUser(user) {
  return {
    id: user.id,
    email: user.email,
    fullName: user.full_name,
    role: user.role,
    preferredLanguage: user.preferred_language,
  };
}
