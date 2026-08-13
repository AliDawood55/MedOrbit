"use client";

import * as React from "react";
import { Moon, Sun } from "lucide-react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";

const STORAGE_KEY = "medorbit-theme";

type Theme = "light" | "dark";

function applyTheme(theme: Theme) {
  document.documentElement.classList.toggle("dark", theme === "dark");
}

/**
 * Minimal class-based light/dark toggle — no next-themes dependency
 * installed in frontend-next yet, so this hand-rolls the same
 * localStorage + prefers-color-scheme pattern legacy's theme.js used.
 */
export function ThemeToggle() {
  const t = useTranslations();
  const [theme, setTheme] = React.useState<Theme | null>(null);

  React.useEffect(() => {
    // One-time sync from external state (localStorage / OS preference) on
    // mount — intentionally not derived via a lazy useState initializer,
    // since that would run during SSR (no window) and cause a hydration
    // mismatch between server and client output.
    const stored = window.localStorage.getItem(STORAGE_KEY) as Theme | null;
    const initial =
      stored ?? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time mount sync from an external source (localStorage/matchMedia), not a render-triggered cascade
    setTheme(initial);
    applyTheme(initial);
  }, []);

  function toggle() {
    const next: Theme = theme === "dark" ? "light" : "dark";
    setTheme(next);
    applyTheme(next);
    window.localStorage.setItem(STORAGE_KEY, next);
  }

  return (
    <Button variant="outline" size="icon" onClick={toggle} aria-label={t("theme")}>
      {theme === "dark" ? <Sun /> : <Moon />}
    </Button>
  );
}
