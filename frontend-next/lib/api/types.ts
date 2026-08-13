/**
 * Wire types for the Express backend's response envelope
 * (backend/src/utils/response.js — verified against source, not assumed):
 *   success: { success: true,  data, message, timestamp }
 *   error:   { success: false, error: { code, message, details, timestamp } }
 */
export interface ApiSuccessBody<T> {
  success: true;
  data: T;
  message: string;
  timestamp: string;
}

export interface ApiErrorBody {
  success: false;
  error: {
    code?: string;
    message: string;
    details?: unknown;
    timestamp: string;
  };
}

export interface ApiErrorInit {
  code?: string;
  status: number;
  retryAfterSeconds: number | null;
}

/** Normalized client-side error — same fields legacy's api.js attached
 *  to its thrown Error (`err.code`, `err.status`, `err.retryAfterSeconds`),
 *  now first-class instead of loose properties on a generic Error. */
export class ApiError extends Error {
  code?: string;
  status: number;
  retryAfterSeconds: number | null;

  constructor(message: string, init: ApiErrorInit) {
    super(message);
    this.name = "ApiError";
    this.code = init.code;
    this.status = init.status;
    this.retryAfterSeconds = init.retryAfterSeconds;
  }
}

/** Real roles observed in backend/src/middleware/auth.js (authorize()
 *  calls) and auth.service.js — public registration only ever creates
 *  'patient' (auth.controller.js rejects any other role). */
export type UserRole = "patient" | "doctor" | "admin" | "super_admin";

/**
 * Cached in localStorage after login/register+login. Matches
 * auth.service.js's login()/googleLogin() `user` object exactly — do NOT
 * conflate with CurrentUserProfile below, the backend returns a
 * materially different (smaller) shape here.
 */
export interface SessionUser {
  id: number;
  email: string;
  role: UserRole;
  name: string | null;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

/** POST /api/auth/login, /api/auth/google — auth.service.js `login()` /
 *  `googleLogin()` both return exactly this shape. */
export interface LoginResult extends AuthTokens {
  user: SessionUser;
}

/** POST /api/auth/register — auth.service.js's INSERT ... RETURNING
 *  id,email,role. No tokens: the account still needs email verification
 *  before it can log in (register() never calls issueSession()). */
export interface RegisterResult {
  id: number;
  email: string;
  role: UserRole;
}

/** GET /api/users/me — verified against backend/src/routes/user.routes.js's
 *  inline handler. Distinct from SessionUser; richer, snake_case (raw DB
 *  row shape), and not what gets cached as the session user. */
export interface CurrentUserProfile {
  id: number;
  email: string;
  role: UserRole;
  preferred_language: string;
  created_at: string;
  first_name_ar: string | null;
  last_name_ar: string | null;
  first_name_en: string | null;
  last_name_en: string | null;
  phone: string | null;
  gender: string | null;
  avatar_url: string | null;
  address: string | null;
  city: string | null;
}
