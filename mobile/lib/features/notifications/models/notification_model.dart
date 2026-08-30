/// A single row from `medorbit.notifications`, trimmed to the fields the
/// backend actually returns from `GET /notifications` and the ones mutation
/// endpoints echo back. There is no `data`/`metadata` JSON column on this
/// table — only `reference_id`/`reference_type` exist server-side, and this
/// direct-care message notifications now use those references for a tightly
/// allow-listed internal conversation route.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.notificationType,
    required this.titleAr,
    required this.titleEn,
    required this.messageAr,
    required this.messageEn,
    required this.isRead,
    required this.createdAt,
    this.readAt,
    this.referenceId,
    this.referenceType,
  });

  final String id;

  /// Free-text on the backend (no DB enum) — observed values are
  /// `'appointment'`, `'reminder'`, `'system'`, but nothing constrains it to
  /// just those.
  final String notificationType;
  final String titleAr;
  final String titleEn;
  final String messageAr;
  final String messageEn;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? referenceId;
  final String? referenceType;

  bool get opensCareConversation =>
      referenceType == 'DIRECT_CONVERSATION' &&
      referenceId != null &&
      _directConversationId.hasMatch(referenceId!) &&
      const {'NEW_DIRECT_MESSAGE', 'NEW_MESSAGE_REQUEST', 'MESSAGE_REQUEST_ACCEPTED'}.contains(notificationType);

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      notificationType: json['notification_type'] as String? ?? '',
      titleAr: json['title_ar'] as String? ?? '',
      titleEn: json['title_en'] as String? ?? '',
      messageAr: json['message_ar'] as String? ?? '',
      messageEn: json['message_en'] as String? ?? '',
      isRead: json['is_read'] == true,
      createdAt: _parseDate(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      readAt: _parseDate(json['read_at']),
      referenceId: _optionalString(json['reference_id']),
      referenceType: _optionalString(json['reference_type']),
    );
  }

  NotificationModel copyWith({bool? isRead, DateTime? readAt}) {
    return NotificationModel(
      id: id,
      notificationType: notificationType,
      titleAr: titleAr,
      titleEn: titleEn,
      messageAr: messageAr,
      messageEn: messageEn,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      referenceId: referenceId,
      referenceType: referenceType,
    );
  }
}

DateTime? _parseDate(Object? value) => value is String ? DateTime.tryParse(value) : null;
final RegExp _directConversationId = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
