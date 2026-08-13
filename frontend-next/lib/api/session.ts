/**
 * BROWSER-ONLY. The one module in lib/api allowed to touch
 * localStorage/window — every function here guards `typeof window` so
 * accidentally importing this into a Server Component degrades safely
 * (getters return null/false; setters no-op) instead of crashing, since
 * Next.js's server has no access to the browser-stored session at all
 * (see lib/api/client.ts's request() — that's exactly why auth-required
 * calls can't be meaningfully made from the server in this phase).
 *
 * Storage keys and the 'auth:changed' event name are the EXACT strings
 * frontend/src/js/api.js already uses. This is load-bearing, not
 * cosmetic: the migration plan puts the legacy app and this app on the
 * same origin during coexistence, sharing one localStorage session —
 * different key names here would silently break that.
 */
import type { AuthTokens, SessionUser } from "./types";

const ACCESS_KEY = "accessToken";
const REFRESH_KEY = "refreshToken";
const USER_KEY = "user";
const AUTH_CHANGED_EVENT = "auth:changed";

function isBrowser(): boolean {
  return typeof window !== "undefined";
}

export function getAccessToken(): string | null {
  if (!isBrowser()) return null;
  return window.localStorage.getItem(ACCESS_KEY);
}

export function getRefreshToken(): string | null {
  if (!isBrowser()) return null;
  return window.localStorage.getItem(REFRESH_KEY);
}

export function getUser(): SessionUser | null {
  if (!isBrowser()) return null;
  const raw = window.localStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as SessionUser;
  } catch {
    return null;
  }
}

export function isAuthenticated(): boolean {
  return getAccessToken() !== null;
}

export function setSession(session: Partial<AuthTokens> & { user?: SessionUser }): void {
  if (!isBrowser()) {
    if (process.env.NODE_ENV !== "production") {
      console.warn("[medorbit] setSession() called outside the browser — ignored.");
    }
    return;
  }
  if (session.accessToken) window.localStorage.setItem(ACCESS_KEY, session.accessToken);
  if (session.refreshToken) window.localStorage.setItem(REFRESH_KEY, session.refreshToken);
  if (session.user) window.localStorage.setItem(USER_KEY, JSON.stringify(session.user));
  window.dispatchEvent(new CustomEvent(AUTH_CHANGED_EVENT));
}

export function clearSession(): void {
  if (!isBrowser()) return;
  window.localStorage.removeItem(ACCESS_KEY);
  window.localStorage.removeItem(REFRESH_KEY);
  window.localStorage.removeItem(USER_KEY);
  window.dispatchEvent(new CustomEvent(AUTH_CHANGED_EVENT));
}
