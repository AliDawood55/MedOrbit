"use client";

import * as React from "react";
import { SessionContext } from "@/components/providers/auth-provider";

/**
 * Reads the current browser auth/session state. Must be used within
 * <AuthProvider> (wired into app/[locale]/layout.tsx).
 *
 * This hook does not perform login/logout/API calls — call
 * lib/api/auth.ts's login()/logout()/register() etc. directly for that;
 * this hook will reflect the result automatically (they dispatch
 * 'auth:changed' via lib/api/session.ts).
 */
export function useSession() {
  const context = React.useContext(SessionContext);
  if (!context) {
    throw new Error("useSession() must be used within <AuthProvider>");
  }
  return context;
}
