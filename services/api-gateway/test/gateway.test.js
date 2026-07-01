import request from "supertest";
import jwt from "jsonwebtoken";
import { createApp } from "../src/app.js";

const JWT_SECRET = process.env.JWT_SECRET || "dev_jwt_secret_change_me";
const app = createApp();

describe("api-gateway", () => {
  it("exposes /health", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.service).toBe("api-gateway");
  });

  it("rejects protected routes without a token", async () => {
    const res = await request(app).get("/api/v1/users/me");
    expect(res.status).toBe(401);
  });

  it("rejects invalid tokens", async () => {
    const res = await request(app)
      .get("/api/v1/users/me")
      .set("Authorization", "Bearer not-a-token");
    expect(res.status).toBe(401);
  });

  it("allows public auth routes without a token (passes auth layer)", async () => {
    const res = await request(app).post("/api/v1/auth/login").send({});
    // 401 would mean gateway blocked it; 5xx means it tried to proxy (auth service down in tests)
    expect(res.status).not.toBe(401);
  });

  it("allows public doctor catalog without a token (passes auth layer)", async () => {
    const res = await request(app).get("/api/v1/doctors");
    expect(res.status).not.toBe(401);
  });

  it("accepts valid JWT for protected routes (passes auth layer)", async () => {
    const token = jwt.sign({ sub: "u1", role: "patient" }, JWT_SECRET, { expiresIn: "5m" });
    const res = await request(app)
      .get("/api/v1/users/me")
      .set("Authorization", `Bearer ${token}`);
    expect(res.status).not.toBe(401);
  });

  it("returns 404 for unknown routes with a valid token", async () => {
    const token = jwt.sign({ sub: "u1", role: "patient" }, JWT_SECRET, { expiresIn: "5m" });
    const res = await request(app).get("/nope").set("Authorization", `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});
