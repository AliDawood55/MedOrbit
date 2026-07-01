import { jest } from "@jest/globals";
import jwt from "jsonwebtoken";
import { requireAuth, requireRole } from "../src/auth.js";

const JWT_SECRET = process.env.JWT_SECRET || "dev_jwt_secret_change_me";

function mockRes() {
  const res = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

describe("requireAuth", () => {
  it("rejects missing token", () => {
    const res = mockRes();
    const next = jest.fn();
    requireAuth({ headers: {} }, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("rejects invalid token", () => {
    const res = mockRes();
    const next = jest.fn();
    requireAuth({ headers: { authorization: "Bearer bad" } }, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
  });

  it("accepts valid token and attaches user", () => {
    const token = jwt.sign({ sub: "u1", role: "patient" }, JWT_SECRET);
    const req = { headers: { authorization: `Bearer ${token}` } };
    const next = jest.fn();
    requireAuth(req, mockRes(), next);
    expect(next).toHaveBeenCalled();
    expect(req.user.sub).toBe("u1");
  });
});

describe("requireRole", () => {
  it("allows matching role", () => {
    const next = jest.fn();
    requireRole("admin")({ user: { role: "admin" } }, mockRes(), next);
    expect(next).toHaveBeenCalled();
  });

  it("forbids non-matching role", () => {
    const res = mockRes();
    const next = jest.fn();
    requireRole("admin")({ user: { role: "patient" } }, res, next);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(next).not.toHaveBeenCalled();
  });
});
