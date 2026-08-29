import '../../common/models/admin_parsing.dart';

/// `medorbit.contact_messages.status` lifecycle: `new → read → resolved`.
enum AdminContactStatus { isNew, read, resolved, unknown }

AdminContactStatus adminContactStatusFromWire(String value) => switch (value) {
  'new' => AdminContactStatus.isNew,
  'read' => AdminContactStatus.read,
  'resolved' => AdminContactStatus.resolved,
  _ => AdminContactStatus.unknown,
};

/// The `status` query value for each filter, or `null` for "all statuses".
/// The backend rejects anything outside this set with `VALIDATION_ERROR`.
String? adminContactStatusWireValue(AdminContactStatus? status) =>
    switch (status) {
      AdminContactStatus.isNew => 'new',
      AdminContactStatus.read => 'read',
      AdminContactStatus.resolved => 'resolved',
      _ => null,
    };

/// One contact message.
///
/// The list projection (`listContacts`) omits `message`; the detail projection
/// (`getContact`) includes it. One model covers both, with [body] `null` until
/// the detail has been read — the list must never claim a message is empty.
class AdminContactMessage {
  const AdminContactMessage({
    required this.id,
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.status,
    required this.statusValue,
    required this.createdAt,
    required this.authenticated,
    this.body,
    this.readAt,
    this.resolvedAt,
  });

  final String id;
  final String senderName;
  final String senderEmail;
  final String subject;
  final AdminContactStatus status;
  final String statusValue;
  final DateTime createdAt;

  /// `c.user_id IS NOT NULL` — whether the sender was signed in. The sender's
  /// user id itself is never returned by the endpoint.
  final bool authenticated;
  final String? body;
  final DateTime? readAt;
  final DateTime? resolvedAt;

  bool get isResolved => status == AdminContactStatus.resolved;
  bool get isUnread => status == AdminContactStatus.isNew;

  factory AdminContactMessage.fromJson(Map<String, dynamic> json) {
    final statusValue = adminRequireString(json, 'status');
    return AdminContactMessage(
      id: adminRequireString(json, 'id'),
      senderName: adminOptionalString(json, 'sender_name') ?? '',
      senderEmail: adminOptionalString(json, 'sender_email') ?? '',
      subject: adminOptionalString(json, 'subject') ?? '',
      status: adminContactStatusFromWire(statusValue),
      statusValue: statusValue,
      createdAt: adminRequireDate(json, 'created_at'),
      authenticated: adminBool(json['authenticated']),
      body: adminOptionalString(json, 'message'),
      readAt: adminOptionalDate(json['read_at']),
      resolvedAt: adminOptionalDate(json['resolved_at']),
    );
  }

  AdminContactMessage copyWithStatus(AdminContactStatusUpdate update) =>
      AdminContactMessage(
        id: id,
        senderName: senderName,
        senderEmail: senderEmail,
        subject: subject,
        status: update.status,
        statusValue: update.statusValue,
        createdAt: createdAt,
        authenticated: authenticated,
        body: body,
        readAt: update.readAt ?? readAt,
        resolvedAt: update.resolvedAt ?? resolvedAt,
      );
}

/// What `POST /:id/read` and `POST /:id/resolve` return: the workflow columns
/// only, so it is merged into the cached row rather than replacing it.
class AdminContactStatusUpdate {
  const AdminContactStatusUpdate({
    required this.id,
    required this.status,
    required this.statusValue,
    this.readAt,
    this.resolvedAt,
  });

  final String id;
  final AdminContactStatus status;
  final String statusValue;
  final DateTime? readAt;
  final DateTime? resolvedAt;

  factory AdminContactStatusUpdate.fromJson(Map<String, dynamic> json) {
    final statusValue = adminRequireString(json, 'status');
    return AdminContactStatusUpdate(
      id: adminRequireString(json, 'id'),
      status: adminContactStatusFromWire(statusValue),
      statusValue: statusValue,
      readAt: adminOptionalDate(json['read_at']),
      resolvedAt: adminOptionalDate(json['resolved_at']),
    );
  }
}

/// One page of `GET /admin/contact-messages`.
class AdminContactPage {
  const AdminContactPage({
    required this.items,
    required this.limit,
    required this.offset,
  });

  final List<AdminContactMessage> items;
  final int limit;
  final int offset;
}
