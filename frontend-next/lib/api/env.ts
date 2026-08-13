/**
 * Resolves the MedOrbit Express backend's base URL for both server and
 * browser contexts — the one piece of client.ts that genuinely differs
 * between the two, so it's isolated here instead of scattered.
 *
 * Client-side, this mirrors frontend/src/js/api.js's resolveServiceOrigin()
 * exactly: derive the origin from wherever the page was actually opened
 * from (protocol + hostname) on port 3001, unless an override env var is
 * set — so localhost, loopback, and LAN IP access all call the matching
 * backend, same as the legacy app.
 *
 * Server-side, there is no page origin to derive from (no `window`), so
 * this falls back to an explicit env var: API_URL for a server-to-server
 * base (e.g. an internal Docker hostname), then NEXT_PUBLIC_API_URL, then
 * a local-dev default. Nothing here reads `window` unless `window` has
 * already been confirmed to exist.
 */
const DEFAULT_PORT = 3001;

function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, "");
}

function stripApiSuffix(origin: string): string {
  return origin.replace(/\/api\/?$/, "");
}

function resolveBrowserOrigin(): string {
  const override = trimTrailingSlash(process.env.NEXT_PUBLIC_API_URL ?? "");
  if (override) return stripApiSuffix(override);

  if (!window.location.hostname) {
    throw new Error("Cannot resolve the MedOrbit API without an HTTP(S) hostname");
  }

  const protocol = window.location.protocol === "https:" ? "https:" : "http:";
  return `${protocol}//${window.location.hostname}:${DEFAULT_PORT}`;
}

function resolveServerOrigin(): string {
  const override = trimTrailingSlash(process.env.API_URL ?? process.env.NEXT_PUBLIC_API_URL ?? "");
  if (override) return stripApiSuffix(override);
  return `http://localhost:${DEFAULT_PORT}`;
}

export function getApiBaseUrl(): string {
  const origin = typeof window === "undefined" ? resolveServerOrigin() : resolveBrowserOrigin();
  return `${origin}/api`;
}
