import {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
  hashToken,
} from "../src/tokens.js";

const user = { id: "11111111-1111-1111-1111-111111111111", email: "a@b.com", role: "patient" };

describe("tokens", () => {
  it("signs and verifies access tokens with role claim", () => {
    const token = signAccessToken(user);
    const payload = verifyAccessToken(token);
    expect(payload.sub).toBe(user.id);
    expect(payload.role).toBe("patient");
  });

  it("signs and verifies refresh tokens with jti", () => {
    const token = signRefreshToken(user, "token-id-1");
    const payload = verifyRefreshToken(token);
    expect(payload.jti).toBe("token-id-1");
  });

  it("access token cannot be verified as refresh token", () => {
    const token = signAccessToken(user);
    expect(() => verifyRefreshToken(token)).toThrow();
  });

  it("hashToken is deterministic", () => {
    expect(hashToken("abc")).toBe(hashToken("abc"));
    expect(hashToken("abc")).not.toBe(hashToken("abd"));
  });
});
