/// Feature-local access rules for the social feed.
///
/// Deliberately *not* a global capability registry — this file answers only
/// the two questions the feed itself asks, so it can move into a wider
/// role/navigation architecture later without carrying assumptions.
///
/// Source of truth is `frontend/src/js/auth-gate.js`: `feed.html` appears in
/// `PROTECTED` (authentication required) but is absent from
/// `ROLE_RESTRICTED`, so every authenticated role may read the feed. The
/// backend agrees — `GET /api/feed/posts` is guarded by `authenticate` alone
/// (`backend/src/routes/social.routes.js:18`), with no role check.
library;

/// The roles this product actually issues (`users.role` in
/// `db/01_base_tables.sql`). Listed for documentation and tests; the check
/// below intentionally does not gate on membership, because the web gate
/// does not either.
const Set<String> kKnownRoles = {'patient', 'doctor', 'admin', 'super_admin'};

String? _normalize(String? role) {
  final value = role?.trim().toLowerCase();
  return (value == null || value.isEmpty) ? null : value;
}

/// True when an account with [role] may read the feed.
///
/// Feed *consumption* is a shared authenticated feature, not a patient-only
/// one: patient, doctor, admin and super_admin all qualify. A null or blank
/// role means there is no authenticated session to authorize.
bool socialFeedAvailableForRole(String? role) => _normalize(role) != null;

/// True when an account with [role] may publish from the feed's quick
/// composer.
///
/// Doctor only. `POST /api/doctors/me/posts` is wrapped in
/// `authorize('doctor')` (`backend/src/routes/doctor.routes.js:269`), and
/// the web composer additionally verifies the session role before it even
/// renders (`frontend/src/js/feed.js`'s `initComposer`). Admins and
/// super_admins moderate posts; they never author them.
bool socialComposerAvailableForRole(String? role) =>
    _normalize(role) == 'doctor';
