import express from "express";
import rateLimit from "express-rate-limit";
import { createProxyMiddleware } from "http-proxy-middleware";
import jwt from "jsonwebtoken";

const JWT_SECRET = process.env.JWT_SECRET || "dev_jwt_secret_change_me";

const PUBLIC_ROUTES = [
  { method: "POST", pattern: /^\/api\/v1\/auth\// },
  { method: "GET", pattern: /^\/api\/v1\/doctors(\/|$)/ },
  { method: "GET", pattern: /^\/api\/v1\/specialties$/ },
];

function isPublic(req) {
  return PUBLIC_ROUTES.some((r) => r.method === req.method && r.pattern.test(req.path));
}

export function authenticate(req, res, next) {
  if (isPublic(req)) return next();
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: "missing bearer token" });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: "invalid or expired token" });
  }
}

export function createApp({
  authServiceUrl = process.env.AUTH_SERVICE_URL || "http://localhost:3001",
  userServiceUrl = process.env.USER_SERVICE_URL || "http://localhost:3002",
  doctorServiceUrl = process.env.DOCTOR_SERVICE_URL || "http://localhost:3003",
} = {}) {
  const app = express();
  app.set("trust proxy", 1);

  app.use(
    rateLimit({
      windowMs: 60 * 1000,
      max: Number(process.env.RATE_LIMIT_MAX) || 100,
      standardHeaders: true,
      legacyHeaders: false,
      message: { error: "rate limit exceeded" },
    })
  );

  app.get("/health", (_req, res) => res.json({ status: "ok", service: "api-gateway" }));

  app.use(authenticate);

  app.use("/api/v1/auth", createProxyMiddleware({ target: authServiceUrl, changeOrigin: true, pathRewrite: (p) => `/api/v1/auth${p}` }));
  app.use("/api/v1/users", createProxyMiddleware({ target: userServiceUrl, changeOrigin: true, pathRewrite: (p) => `/api/v1/users${p}` }));
  app.use("/api/v1/doctors", createProxyMiddleware({ target: doctorServiceUrl, changeOrigin: true, pathRewrite: (p) => `/api/v1/doctors${p}` }));
  app.use("/api/v1/specialties", createProxyMiddleware({ target: doctorServiceUrl, changeOrigin: true, pathRewrite: (p) => `/api/v1/specialties${p}` }));

  app.use((_req, res) => res.status(404).json({ error: "route not found" }));

  return app;
}
