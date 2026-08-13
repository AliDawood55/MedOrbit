"use client";

/**
 * Client-side mirror of the browser session managed by lib/api/session.ts.
 * Does not implement login/logout/refresh itself — those already exist in
 * lib/api/auth.ts and lib/api/client.ts; this provider only observes the
 * localStorage-backed session those modules already mutate (via
 * setSession()/clearSession(), both of which dispatch 'auth:changed') and
 * mirrors it into React state so components can react to it.
 *
 *   localStorage / session.ts -> AuthProvider -> useSession() -> components
 *
 * Session reads only ever happen inside an effect (post-hydration), never
 * during render, so this never touches localStorage on the server and
 * never renders a guessed-authenticated state for the initial paint —
 * `status` starts at "loading" and only becomes "authenticated" or
 * "unauthenticated" once the effect has actually checked.
 */
import * as React from "react";
import * as session from "@/lib/api/session";
import type { SessionUser } from "@/lib/api/types";

export type SessionStatus = "loading" | "authenticated" | "unauthenticated";

export interface SessionContextValue {
  /** null while status is "loading" or "unauthenticated". */
  user: SessionUser | null;
  status: SessionStatus;
  isAuthenticated: boolean;
  /**
   * Re-reads the session from localStorage into React state. The provider
   * already does this automatically whenever lib/api/session.ts dispatches
   * 'auth:changed' (login, logout, a token refresh, or the legacy app
   * changing the shared session during coexistence) — this is an escape
   * hatch for the rare case something needs to force a re-sync.
   */
  refresh: () => void;
}

export const SessionContext = React.createContext<SessionContextValue | null>(null);

function readSession(): Pick<SessionContextValue, "user" | "status"> {
  const authenticated = session.isAuthenticated();
  return {
    user: authenticated ? session.getUser() : null,
    status: authenticated ? "authenticated" : "unauthenticated",
  };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = React.useState<Pick<SessionContextValue, "user" | "status">>({
    user: null,
    status: "loading",
  });

  const sync = React.useCallback(() => {
    setState(readSession());
  }, []);

  React.useEffect(() => {
    // One-time sync from external state (localStorage, via session.ts) on
    // mount, then kept live by the 'auth:changed' listener below — same
    // deliberate, external-source-on-mount pattern as
    // components/theme-toggle.tsx, not a render-triggered cascade.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    sync();

    window.addEventListener("auth:changed", sync);
    return () => window.removeEventListener("auth:changed", sync);
  }, [sync]);

  const value = React.useMemo<SessionContextValue>(
    () => ({
      user: state.user,
      status: state.status,
      isAuthenticated: state.status === "authenticated",
      refresh: sync,
    }),
    [state, sync]
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}
