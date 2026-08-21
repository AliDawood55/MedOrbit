# Frontend CSS Architecture

Guardrails for the current styling architecture. Reflects what the codebase
actually does today (post Phase 1 cleanup), not an aspirational design.

## A. Load-order contract

Typical page `<head>` order:

```
main.css        → tokens, reset, base elements, global toast styles
components.css  → canonical reusable components
layout.css      → site shell / navigation (only on pages with the header)
listing.css / forms.css / animation.css   → optional, as needed
records.css / <page>.css                  → page-specific, last
```

Later stylesheets may intentionally refine earlier shared components (e.g. a
page tightening a `.card` variant). Before moving a rule from one file to
another, check the full load set of every consumer page — source order and
specificity both matter, and moving a rule can silently change which
declaration wins on a page that loads stylesheets in a different subset/order.

## B. Ownership rules

- **main.css** — reset/base, design tokens (spacing, color, radius, shadow,
  motion custom properties), global element defaults, global `.toast`/
  `.toast-container` styles.
- **components.css** — canonical reusable components: `.card`, `.btn` system,
  `.alert`, `.skeleton` base (+ reduced-motion override), `.empty-state`,
  `.error-state` where actually shared, `.page-header`, `.pagination`.
- **layout.css** — site shell only: header, nav, `.site-page` body contract,
  dropdown/user menus.
- **listing.css** — listing/search/filter composition (filter toolbar, list
  layouts). Not a dumping ground for generic components.
- **forms.css** — shared form-field patterns (inputs, selects, radio groups).
- **page-specific CSS** (`records.css`, `schedule.css`, `appointments.css`,
  etc.) — feature/page-only variants and composition. A page-specific file
  extending a shared class (e.g. `.records-empty-state` alongside
  `.empty-state-icon`) is expected and fine.

## C. Promotion rule

**Same class name does not imply the same shared component.** Before
promoting a class into `components.css`:

1. Enumerate every consumer page/file.
2. Enumerate each consumer's actual stylesheet load set.
3. Diff the declarations — are they really the same rule, or coincidentally
   named the same?
4. Check specificity and source order across all consumers.
5. Identify any page that would newly receive styling it didn't have before.
6. Separate the generic base from page-specific variants; promote only the
   base.

Phase 1 found real duplication in tabs (`.profile-tab`/`.appt-tab`/
`.schedule-tabs`) and dropdowns (`.nav-dropdown-menu`/`.user-menu`) that was
**deliberately not promoted** — consolidating them requires editing the
consumer stylesheets themselves, which is a separate, larger change from
adding a net-new primitive. See `KNOWN DEFERRED ITEMS` in the Phase 1 record.

## D. Breakpoints

For new or actively modernized code, prefer: `480`, `640`, `768`, `1024`.

Do not sweep existing breakpoints to normalize them just for consistency —
preserve current behavior unless the page itself is being intentionally
modernized.

## E. RTL

For new or touched rules, prefer logical properties (`inset-inline-start`,
`margin-inline`, etc.) over `left`/`right`. Preserve existing direction
behavior on untouched rules — do not perform a broad RTL cleanup pass as a
side effect of an unrelated change.

## F. Dark mode

Current contract: `data-theme` is applied on `document.body` (not
`documentElement`). Do not move this without a deliberate, scoped change —
every existing dark-mode selector in this codebase assumes `body[data-theme]`.

## G. JavaScript architecture

- Global IIFEs (`const Foo = (() => { ... })();`) attached to `window`
  implicitly via top-level `const`.
- No ES modules yet — no `<script type="module">`, no `import`/`export`.
- No framework migration.
- Script tags are order-dependent: a global must load before any page script
  that references it.
- Avoid adding shared helpers speculatively. A helper earns a place in a
  shared file only when it has real, evidenced duplicate call sites — not
  because a plan named it. (`frontend/src/js/ui.js` was built and then
  removed in Phase 1 for exactly this reason — see the Phase 1 record.)

## H. Dependencies

- No new frontend dependency or build step in Phase 1.
- CDN vendoring/localization (self-hosting Font Awesome, Leaflet, Google
  Fonts) is deferred to later performance work.
