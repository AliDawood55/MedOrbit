import { useTranslations } from "next-intl";
import { Card, CardContent } from "@/components/ui/card";
import { ThemeToggle } from "@/components/theme-toggle";
import { LocaleSwitcher } from "@/components/locale-switcher";

/**
 * Phase 1A foundation check — NOT the migrated Home page (that's Phase 2).
 * Exists only to prove the locale routing, RTL/LTR, brand tokens, fonts,
 * and theme toggle all work together on a real route.
 */
export default function FoundationCheckPage() {
  const t = useTranslations();

  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-6 p-6">
      <Card className="w-full max-w-md">
        <CardContent className="flex flex-col items-center gap-4 py-10 text-center">
          <div className="flex size-12 items-center justify-center rounded-xl bg-primary text-lg font-extrabold text-primary-foreground shadow-sm">
            M
          </div>
          <div>
            <h1 className="font-heading text-xl font-extrabold text-foreground">MedOrbit</h1>
            <p className="mt-1 text-sm text-muted-foreground">{t("brand.tagline")}</p>
          </div>
          <p className="rounded-md bg-muted px-3 py-1.5 text-xs text-muted-foreground">
            Phase 1 foundation preview — not the final home page.
          </p>
          <div className="flex items-center gap-2">
            <LocaleSwitcher />
            <ThemeToggle />
          </div>
        </CardContent>
      </Card>
    </main>
  );
}
