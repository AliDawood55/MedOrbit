/**
 * Auth domain — ported from frontend/src/js/auth.js, verified field-for-
 * field against backend/src/controllers/auth.controller.js and
 * auth.service.js (not the legacy comments). One real behavioral note:
 * legacy never grouped auth under a domain object (auth.js called
 * `API.post('/auth/login', ...)` directly) — grouping it here matches
 * every other domain's shape without changing any endpoint, field, or
 * order of operations.
 */
import { api } from "./client";
import { clearSession, getRefreshToken, setSession } from "./session";
import type { AuthTokens, LoginResult, RegisterResult } from "./types";

export interface RegisterInput {
  email: string;
  password: string;
  firstNameAr: string;
  lastNameAr: string;
  firstNameEn: string;
  lastNameEn: string;
  phone?: string;
  gender?: string;
}

/** POST /api/auth/register — public registration only ever creates a
 *  'patient' account; auth.controller.js rejects any other `role`. No
 *  session is issued (register() never calls issueSession()) — the
 *  account still needs email verification before it can log in. */
export function register(input: RegisterInput) {
  return api.post<RegisterResult>(
    "/auth/register",
    { ...input, role: "patient" },
    { auth: false }
  );
}

/** POST /api/auth/login. Persists the session on success, same as
 *  legacy's handleLogin() -> API.setSession(res.data). */
export async function login(email: string, password: string): Promise<LoginResult> {
  const result = await api.post<LoginResult>("/auth/login", { email, password }, { auth: false });
  setSession(result);
  return result;
}

/** POST /api/auth/google — backend expects { idToken } (verified against
 *  auth.controller.js's google()); issues the same session shape as
 *  password login. Obtaining the idToken itself (Google Identity
 *  Services) is a UI concern for a later phase, not this client. */
export async function loginWithGoogle(idToken: string): Promise<LoginResult> {
  const result = await api.post<LoginResult>("/auth/google", { idToken }, { auth: false });
  setSession(result);
  return result;
}

/** POST /api/auth/refresh — exposed for completeness; lib/api/client.ts
 *  already calls this internally on a 401, callers should not normally
 *  need to call it directly. */
export function refresh(refreshToken: string) {
  return api.post<AuthTokens>("/auth/refresh", { refreshToken }, { auth: false });
}

/** POST /api/auth/logout — best-effort revoke, then always clear the
 *  local session regardless of whether the request succeeds (matches
 *  legacy's API.logout() exactly). */
export async function logout(): Promise<void> {
  const refreshToken = getRefreshToken();
  if (refreshToken) {
    try {
      await api.post<null>("/auth/logout", { refreshToken }, { auth: false });
    } catch {
      // Best-effort — clear the local session regardless.
    }
  }
  clearSession();
}

/** POST /api/auth/change-password — requires an access token
 *  (backend/src/routes/auth.routes.js: authenticate middleware), so this
 *  is the one auth.ts call that keeps the client's default `auth: true`. */
export function changePassword(currentPassword: string, newPassword: string) {
  return api.post<null>("/auth/change-password", { currentPassword, newPassword });
}

export function forgotPassword(email: string) {
  return api.post<null>("/auth/forgot-password", { email }, { auth: false });
}

export function resetPassword(token: string, newPassword: string) {
  return api.post<null>("/auth/reset-password", { token, newPassword }, { auth: false });
}

/** POST /api/auth/verify-email — `email` is only required when `token`
 *  is a 6-digit OTP rather than a link token (auth.service.js verifyEmail:
 *  `isOtp` branch); optional otherwise. */
export function verifyEmail(token: string, email?: string) {
  return api.post<null>("/auth/verify-email", { token, email }, { auth: false });
}

export function resendVerification(email: string) {
  return api.post<null>("/auth/resend-verification", { email }, { auth: false });
}
