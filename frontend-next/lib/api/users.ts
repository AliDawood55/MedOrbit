/**
 * Small representative domain proving the client/auth abstraction end to
 * end with a real authenticated call. Only `me()` — the rest of the users
 * domain (avatar upload, preferences, saved places, account deletion)
 * belongs to whichever later phase actually builds a page that needs it.
 */
import { api } from "./client";
import type { CurrentUserProfile } from "./types";

/** GET /api/users/me — the authoritative role/profile source (the
 *  session's cached SessionUser is deliberately smaller; see
 *  lib/api/types.ts). Requires an access token — uses the client's
 *  default `auth: true`. */
export function me() {
  return api.get<CurrentUserProfile>("/users/me");
}
