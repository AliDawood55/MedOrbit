/**
 * Core request layer — ported from frontend/src/js/api.js's request()/
 * refreshAccessToken(), same semantics:
 *   - Bearer header attached from the stored access token when `auth`
 *     is true (the default, matching legacy).
 *   - On a 401 from an `auth` request (and not already a retry, and not
 *     the refresh call itself), refresh once and retry the original
 *     request exactly once (`_retry`), never recursing further.
 *   - Concurrent 401s dedupe onto a single in-flight refresh via
 *     `refreshPromise`, so a burst of requests can't fire the refresh
 *     endpoint multiple times or leave the session in a torn state.
 *   - A failed refresh clears the session (forces re-login), same as
 *     legacy.
 *
 * Safe to import from a Server Component for `auth: false` calls — no
 * `window`/`localStorage` access happens on that path. For `auth: true`
 * calls, getAccessToken()/getRefreshToken() (lib/api/session.ts) simply
 * return null outside the browser, so the request goes out without a
 * session and a 401 is handled the normal way, not a crash.
 */
import { getApiBaseUrl } from "./env";
import { clearSession, getAccessToken, getRefreshToken, setSession } from "./session";
import { ApiError, type ApiErrorBody, type ApiSuccessBody, type AuthTokens } from "./types";

type QueryValue = string | number | boolean | undefined | null;

export interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, QueryValue>;
  signal?: AbortSignal;
  /** Attach the Bearer access token. Defaults to true, matching legacy. */
  auth?: boolean;
  /** Internal — marks a request as a post-refresh retry (or the refresh
   *  call itself) so it's never retried again. Not for external callers. */
  _retry?: boolean;
}

function buildUrl(path: string, query?: RequestOptions["query"]): string {
  let url = `${getApiBaseUrl()}${path}`;
  if (query) {
    const params = Object.entries(query)
      .filter(([, v]) => v !== undefined && v !== null && v !== "")
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
    if (params.length) url += (url.includes("?") ? "&" : "?") + params.join("&");
  }
  return url;
}

function retryAfterSeconds(response: Response): number | null {
  const value = response.headers.get("Retry-After");
  if (!value) return null;

  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, Math.ceil(seconds));

  const retryAt = Date.parse(value);
  return Number.isNaN(retryAt) ? null : Math.max(0, Math.ceil((retryAt - Date.now()) / 1000));
}

function toApiError(response: Response, body: ApiErrorBody | null, fallback: string): ApiError {
  const isRateLimited = response.status === 429;

  // The backend's own rate-limiter message (auth.routes.js's per-endpoint
  // limiters) is real and available via `code`/`status` either way — this
  // module has no locale context to localize copy with, so unlike legacy's
  // api.js (which special-cased a bilingual string here via the global
  // I18n singleton), that's left to the UI layer for this port.
  const message = isRateLimited
    ? "Too many requests. Please try again shortly."
    : body?.error?.message || fallback;

  return new ApiError(message, {
    code: body?.error?.code,
    status: response.status,
    retryAfterSeconds: isRateLimited ? retryAfterSeconds(response) : null,
  });
}

let refreshPromise: Promise<boolean> | null = null;

async function refreshAccessToken(): Promise<boolean> {
  const token = getRefreshToken();
  if (!token) {
    clearSession();
    return false;
  }

  if (!refreshPromise) {
    refreshPromise = request<AuthTokens>("/auth/refresh", {
      method: "POST",
      body: { refreshToken: token },
      auth: false,
      _retry: true,
    })
      .then((tokens) => {
        setSession(tokens);
        return true;
      })
      .catch(() => {
        // Refresh failed — only real way out is logging out (matches legacy).
        clearSession();
        return false;
      })
      .finally(() => {
        refreshPromise = null;
      });
  }

  return refreshPromise;
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = "GET", body, query, signal, auth = true, _retry = false } = options;

  const url = buildUrl(path, query);
  const headers: Record<string, string> = { "Content-Type": "application/json" };

  if (auth) {
    const token = getAccessToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal,
  });

  let parsed: ApiSuccessBody<T> | ApiErrorBody | null = null;
  try {
    parsed = await response.json();
  } catch {
    parsed = null;
  }

  if (response.status === 401 && auth && !_retry && path !== "/auth/refresh") {
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      return request<T>(path, { ...options, _retry: true });
    }
  }

  if (!response.ok) {
    throw toApiError(response, parsed as ApiErrorBody | null, "Request failed");
  }

  // Unwraps the envelope's `data` here (legacy returned the whole
  // `{success,data,message,timestamp}` body and left unwrapping to each
  // call site) — a deliberate ergonomics change for the typed client, not
  // a wire-contract change: HTTP behavior, auth, refresh, and error
  // normalization are all unchanged.
  return (parsed as ApiSuccessBody<T> | null)?.data as T;
}

type BodyOptions = Omit<RequestOptions, "method" | "body">;
type QueryOptions = Omit<RequestOptions, "method" | "query">;

export const api = {
  get: <T>(path: string, query?: RequestOptions["query"], options: QueryOptions = {}) =>
    request<T>(path, { ...options, method: "GET", query }),
  post: <T>(path: string, body?: unknown, options: BodyOptions = {}) =>
    request<T>(path, { ...options, method: "POST", body }),
  put: <T>(path: string, body?: unknown, options: BodyOptions = {}) =>
    request<T>(path, { ...options, method: "PUT", body }),
  patch: <T>(path: string, body?: unknown, options: BodyOptions = {}) =>
    request<T>(path, { ...options, method: "PATCH", body }),
  delete: <T>(path: string, options: Omit<RequestOptions, "method"> = {}) =>
    request<T>(path, { ...options, method: "DELETE" }),
};
