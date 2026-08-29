import '../../common/models/admin_parsing.dart';

/// One row of `GET /api/admin/audit-logs` (`authorizeAdmin`, read-only —
/// the router exposes no write, update, or delete operation).
///
/// `old_values` / `new_values` are deliberately **not** modelled. They are
/// free-form JSON snapshots that can contain a medical licence number, an
/// applicant's professional bio, or an account's full record, and dumping
/// them on a phone would be a data export rather than an audit view. The
/// metadata below — who, what, which record, when, from where — is what an
/// audit trail is read for.
class AdminAuditLog {
  const AdminAuditLog({
    required this.id,
    required this.action,
    required this.createdAt,
    this.userId,
    this.userRole,
    this.entityType,
    this.entityId,
    this.ipAddress,
    this.userAgent,
  });

  final String id;

  /// The raw action constant (`DOCTOR_APPLICATION_APPROVED`, …). Rendered
  /// verbatim: it is an operational identifier, not UI copy, and translating
  /// it would break the correspondence with the server-side log.
  final String action;
  final DateTime createdAt;

  /// `null` for an action recorded without an actor (an anonymous contact
  /// submission, a system job).
  final String? userId;
  final String? userRole;
  final String? entityType;
  final String? entityId;
  final String? ipAddress;
  final String? userAgent;

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) => AdminAuditLog(
    id: adminRequireString(json, 'id'),
    action: adminRequireString(json, 'action'),
    createdAt: adminRequireDate(json, 'created_at'),
    userId: adminOptionalString(json, 'user_id'),
    userRole: adminOptionalString(json, 'user_role'),
    entityType: adminOptionalString(json, 'entity_type'),
    entityId: adminOptionalString(json, 'entity_id'),
    ipAddress: adminOptionalString(json, 'ip_address'),
    userAgent: adminOptionalString(json, 'user_agent'),
  );
}

/// Trailing windows offered for the `from` bound.
///
/// The endpoint applies **no `LIMIT`** — an unfiltered call downloads the
/// whole audit table. Every request therefore carries a `from`, which is a
/// filter the backend genuinely supports, rather than an unbounded read the
/// app then has to truncate client-side.
enum AdminAuditRange { day, week, month }

Duration adminAuditRangeDuration(AdminAuditRange range) => switch (range) {
  AdminAuditRange.day => const Duration(days: 1),
  AdminAuditRange.week => const Duration(days: 7),
  AdminAuditRange.month => const Duration(days: 30),
};

/// Entity types an administrator's own actions produce, offered as filters.
/// "All" (a `null` filter) still covers every other value the table holds.
const List<String> adminAuditEntityTypes = [
  'USER',
  'DOCTOR_APPLICATION',
  'ADMIN_INVITATION',
  'CONTACT_MESSAGE',
  'DOCTOR_POST',
  'DOCTOR',
  'SYSTEM_SETTING',
];
