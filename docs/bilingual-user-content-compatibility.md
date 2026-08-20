# User-authored bilingual field compatibility

MedOrbit accepts any Arabic, English, or mixed Unicode text in one canonical
field for newly authored content. No language detection, translation, or text
rewriting is performed. Outer whitespace is trimmed at the API boundary.

| Domain | Canonical API field | Legacy fields retained | UI decision |
| --- | --- | --- | --- |
| Doctor post title | `title` | `titleAr` / `titleEn`, `title_ar` / `title_en` | One title input |
| Doctor application bio | `bio` | `bio_ar` / `bio_en`, `bioAr` / `bioEn` | One professional-bio input |
| Doctor profile bio | `professionalBio` | `professionalBioAr` / `professionalBioEn` and snake-case aliases | No active dual-entry web/mobile form; API is forward-compatible |
| Doctor review text | `review_text` | `review_text_ar` / `review_text_en`, `reviewTextAr` / `reviewTextEn` | No active dual-entry web/mobile form; API is forward-compatible |

Canonical writes use the existing schema by storing the exact same value in
both legacy language columns. Legacy writes retain distinct historical values.
Read APIs continue returning both legacy fields and also expose the canonical
field. Renderers choose the current locale first and fall back to the other
stored value.

## Compatibility exceptions

- First and last names remain separate Arabic/English identity fields. They are
  required by registration, profile editing, authorization-era account
  contracts, doctor discovery/search, and current Flutter models. Collapsing
  them safely needs a separately planned identity migration and coordinated
  mobile/API rollout.
- Specialty/clinic names and descriptions remain bilingual because they are
  canonical reference or administrator-maintained catalog data.
- Notification titles/messages and other interface copy remain bilingual
  because they are product translations, not duplicated user input.
- Historical rows are not migrated or rewritten. When a historical post is
  edited without changing the title, the single-field web form omits the title
  from the update so both original translations survive.
