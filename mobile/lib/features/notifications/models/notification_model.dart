/// A single row from `medorbit.notifications`, trimmed to the fields the
/// backend actually returns from `GET /notifications` and the ones mutation
/// endpoints echo back. There is no `data`/`metadata` JSON column on this
/// table — only `reference_id`/`reference_type` exist server-side, and this
/// app has no use for them (no click-through/deep-link on a notification),
/// so they're deliberately not parsed here.
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
    );
  }
}

DateTime? _parseDate(Object? value) => value is String ? DateTime.tryParse(value) : null;
