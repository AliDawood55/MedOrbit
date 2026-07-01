import request from "supertest";

const hasDb = Boolean(process.env.DATABASE_URL);
const d = hasDb ? describe : describe.skip;

d("auth flow (integration)", () => {
  let app;
  let pool;

  beforeAll(async () => {
    const { migrate } = await import("../src/db/migrate.js");
    const poolModule = await import("../src/db/pool.js");
    pool = poolModule.pool;
    await migrate();
    const { createApp } = await import("../src/app.js");
    app = createApp();
  });

  afterAll(async () => {
    if (pool) await pool.end();
  });

  const email = `it-${Date.now()}@example.com`;
  const password = "Str0ng!Pass";
  let otp;
  let refreshToken;

  it("registers a patient", async () => {
    const res = await request(app).post("/api/v1/auth/register").send({
      email,
      password,
      fullName: "Integration Tester",
      role: "patient",
      preferredLanguage: "ar",
    });
    expect(res.status).toBe(201);
    otp = res.body.devOtp;
    expect(otp).toMatch(/^\d{6}$/);
  });

  it("rejects duplicate email", async () => {
    const res = await request(app).post("/api/v1/auth/register").send({
      email,
      password,
      fullName: "Dup",
      role: "patient",
    });
    expect(res.status).toBe(409);
  });

  it("blocks login before verification", async () => {
    const res = await request(app).post("/api/v1/auth/login").send({ email, password });
    expect(res.status).toBe(403);
  });

  it("verifies email with OTP", async () => {
    const res = await request(app).post("/api/v1/auth/verify-otp").send({ email, code: otp });
    expect(res.status).toBe(200);
  });

  it("logs in and returns token pair", async () => {
    const res = await request(app).post("/api/v1/auth/login").send({ email, password });
    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();
    expect(res.body.user.role).toBe("patient");
    refreshToken = res.body.refreshToken;
  });

  it("rotates refresh tokens", async () => {
    const res = await request(app).post("/api/v1/auth/refresh").send({ refreshToken });
    expect(res.status).toBe(200);
    // old token is now revoked
    const reuse = await request(app).post("/api/v1/auth/refresh").send({ refreshToken });
    expect(reuse.status).toBe(401);
    refreshToken = res.body.refreshToken;
  });

  it("logs out and invalidates refresh token", async () => {
    const res = await request(app).post("/api/v1/auth/logout").send({ refreshToken });
    expect(res.status).toBe(200);
    const reuse = await request(app).post("/api/v1/auth/refresh").send({ refreshToken });
    expect(reuse.status).toBe(401);
  });

  it("rejects wrong password", async () => {
    const res = await request(app).post("/api/v1/auth/login").send({ email, password: "Wrong1!aa" });
    expect(res.status).toBe(401);
  });

  it("locks account after 5 failed attempts", async () => {
    const lockEmail = `lock-${Date.now()}@example.com`;
    const reg = await request(app).post("/api/v1/auth/register").send({
      email: lockEmail,
      password,
      fullName: "Lock Test",
      role: "patient",
    });
    await request(app).post("/api/v1/auth/verify-otp").send({ email: lockEmail, code: reg.body.devOtp });
    for (let i = 0; i < 5; i++) {
      await request(app).post("/api/v1/auth/login").send({ email: lockEmail, password: "Wrong1!aa" });
    }
    const res = await request(app).post("/api/v1/auth/login").send({ email: lockEmail, password });
    expect(res.status).toBe(423);
  });
});
