import '../../common/models/admin_parsing.dart';

/// `medorbit.admin_invitations.status`.
enum AdminInvitationStatus { pending, accepted, revoked, expired, unknown }

AdminInvitationStatus adminInvitationStatusFromWire(String value) =>
    switch (value) {
      'pending' => AdminInvitationStatus.pending,
      'accepted' => AdminInvitationStatus.accepted,
      'revoked' => AdminInvitationStatus.revoked,
      'expired' => AdminInvitationStatus.expired,
      _ => AdminInvitationStatus.unknown,
    };

/// One row of `GET /api/admin/invitations` (`authorizeSuperAdmin`), shaped by
/// `invitationDto`.
///
/// The token is **never** part of this payload — it exists only as a SHA-256
/// hash in the database and is returned exactly once, in the creation
/// response.
class AdminInvitation {
  const AdminInvitation({
    required this.id,
    required this.email,
    required this.status,
    required this.statusValue,
    required this.createdAt,
    this.expiresAt,
    this.acceptedAt,
    this.revokedAt,
  });

  final String id;
  final String email;
  final AdminInvitationStatus status;
  final String statusValue;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  /// The service expires rows lazily — a `pending` row whose `expires_at` has
  /// passed keeps that status until something touches it, but
  /// `acceptInvitation` would answer `INVITATION_EXPIRED`. The UI reflects the
  /// state the invitee would actually meet rather than the stale column.
  bool isExpiredAt(DateTime now) =>
      status == AdminInvitationStatus.pending &&
      expiresAt != null &&
      !expiresAt!.isAfter(now);

  /// Whether a revoke action applies. `revokeInvitation` requires the stored
  /// status to still be `pending`, which a time-expired row also satisfies.
  bool get isRevocable => status == AdminInvitationStatus.pending;

  factory AdminInvitation.fromJson(Map<String, dynamic> json) {
    final statusValue = adminRequireString(json, 'status');
    return AdminInvitation(
      id: adminRequireString(json, 'id'),
      email: adminRequireString(json, 'email'),
      status: adminInvitationStatusFromWire(statusValue),
      statusValue: statusValue,
      createdAt: adminRequireDate(json, 'created_at'),
      expiresAt: adminOptionalDate(json['expires_at']),
      acceptedAt: adminOptionalDate(json['accepted_at']),
      revokedAt: adminOptionalDate(json['revoked_at']),
    );
  }
}

/// The one-time result of `POST /api/admin/invitations`.
///
/// [acceptanceUrl] embeds the invitation's single-use token. It is held in
/// memory for the length of the creating screen only: never persisted, never
/// logged, and not retrievable from the list endpoint afterwards.
class AdminInvitationCreation {
  const AdminInvitationCreation({
    required this.invitation,
    required this.delivered,
    required this.acceptanceUrl,
  });

  final AdminInvitation invitation;

  /// True when the backend's SMTP send succeeded (`delivery: 'sent'`); false
  /// when it fell back to `'manual'` and the link must be delivered by hand.
  final bool delivered;
  final String? acceptanceUrl;

  factory AdminInvitationCreation.fromJson(Map<String, dynamic> json) =>
      AdminInvitationCreation(
        invitation: AdminInvitation.fromJson(
          adminRequireMap(json['invitation'], 'invitation'),
        ),
        delivered: adminOptionalString(json, 'delivery') == 'sent',
        acceptanceUrl: adminOptionalString(json, 'acceptance_url'),
      );
}

/// Extracts the invitation token from whatever the invitee pastes.
///
/// The backend emails a link of the form
/// `<FRONTEND_URL>/admin-invitation-accept.html?token=<token>`, so both the
/// whole link and the bare token are accepted. Returns `null` when the input
/// carries no usable token, which the screen surfaces as a validation error
/// instead of sending an empty request.
String? adminInvitationTokenFromInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.hasQuery || uri.hasFragment)) {
    final fromQuery = uri.queryParameters['token']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

    // Some mail clients rewrite the link so the query ends up in the
    // fragment; the token is still the only parameter that matters.
    if (uri.fragment.isNotEmpty) {
      final fromFragment = Uri.splitQueryString(
        uri.fragment.contains('?')
            ? uri.fragment.split('?').last
            : uri.fragment,
      )['token']?.trim();
      if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
    }
    return null;
  }

  // A bare token: `crypto.randomBytes(32).toString('base64url')`, so URL-safe
  // base64 characters only. Anything else is a mistyped or truncated paste.
  if (RegExp(r'^[A-Za-z0-9_-]{16,}$').hasMatch(trimmed)) return trimmed;
  return null;
}
