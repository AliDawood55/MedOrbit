"use client";

import { useLocale, useTranslations } from "next-intl";
import { usePathname, useRouter } from "@/i18n/navigation";
import { Button } from "@/components/ui/button";

/**
 * A single toggle button, matching legacy's i18n.js `toggle()` pattern
 * (two supported locales, one button shows the *other* language's name).
 */
export function LocaleSwitcher() {
  const locale = useLocale();
  const t = useTranslations();
  const pathname = usePathname();
  const router = useRouter();

  function toggle() {
    const next = locale === "ar" ? "en" : "ar";
    router.replace(pathname, { locale: next });
  }

  return (
    <Button variant="outline" onClick={toggle}>
      {t("language")}
    </Button>
  );
}
