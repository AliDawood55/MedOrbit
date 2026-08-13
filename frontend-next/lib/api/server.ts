/**
 * Server-safe public API boundary — for Server Components and other
 * server-side code that needs to call PUBLIC (unauthenticated) Express
 * endpoints (e.g. doctor/clinic listings, specialties).
 *
 * Deliberately does NOT import lib/api/client.ts or lib/api/session.ts,
 * even transitively, and duplicates the small amount of request/error
 * logic that's genuinely shared — that's what makes "no server-rendered
 * module imports browser-only session code" true by construction here,
 * not by convention. There is no `auth` option and no refresh-on-401:
 * both are meaningless for public endpoints and both would require the
 * browser-only session this file must never import.
 *
 * Authenticated data belongs in a Client Component using
 * lib/api/client.ts + useSession() (hooks/use-session.ts) instead:
 *
 *   Public data:         Server Component -> lib/api/server.ts  -> Express public endpoint
 *   Authenticated data:  Client Component -> useSession() -> lib/api/client.ts -> JWT/localStorage -> Express protected endpoint
 */
import { getApiBaseUrl } from "./env";
import { ApiError, type ApiErrorBody, type ApiSuccessBody } from "./types";

type QueryValue = string | number | boolean | undefined | null;

export interface PublicRequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, QueryValue>;
  signal?: AbortSignal;
  /** Passed straight through to fetch's Next.js `next` extension (e.g.
   *  `{ revalidate: 60 }`) for server-side caching. Optional — omitting
   *  it changes nothing. */
  next?: NextFetchRequestConfig;
}

function buildUrl(path: string, query?: PublicRequestOptions["query"]): string {
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
  const message = isRateLimited
    ? "Too many requests. Please try again shortly."
    : body?.error?.message || fallback;

  return new ApiError(message, {
    code: body?.error?.code,
    status: response.status,
    retryAfterSeconds: isRateLimited ? retryAfterSeconds(response) : null,
  });
}

/** Always unauthenticated — no Authorization header is ever attached. */
export async function publicRequest<T>(path: string, options: PublicRequestOptions = {}): Promise<T> {
  const { method = "GET", body, query, signal, next } = options;

  const response = await fetch(buildUrl(path, query), {
    method,
    headers: { "Content-Type": "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal,
    next,
  });

  let parsed: ApiSuccessBody<T> | ApiErrorBody | null = null;
  try {
    parsed = await response.json();
  } catch {
    parsed = null;
  }

  if (!response.ok) {
    throw toApiError(response, parsed as ApiErrorBody | null, "Request failed");
  }

  return (parsed as ApiSuccessBody<T> | null)?.data as T;
}

type BodyOptions = Omit<PublicRequestOptions, "method" | "body">;

export const publicApi = {
  get: <T>(path: string, query?: PublicRequestOptions["query"], options: Omit<PublicRequestOptions, "method" | "query"> = {}) =>
    publicRequest<T>(path, { ...options, method: "GET", query }),
  post: <T>(path: string, body?: unknown, options: BodyOptions = {}) =>
    publicRequest<T>(path, { ...options, method: "POST", body }),
};
