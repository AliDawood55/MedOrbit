import '../../../shared/utils/json_parsing.dart';

enum MessageDeliveryState { sending, sent, failed }

class CareConversation {
  const CareConversation({
    required this.id,
    required this.status,
    required this.conversationType,
    required this.requestStatus,
    required this.initiatedByUserId,
    required this.createdAt,
    required this.otherRole,
    required this.otherDisplayName,
    required this.canRespondToRequest,
    required this.unreadCount,
    this.requestUpdatedAt,
    this.lastMessageAt,
    this.otherAvatarUrl,
    this.lastMessageId,
    this.lastMessagePreview,
    this.lastSenderUserId,
    this.lastMessageCreatedAt,
  });

  final String id;
  final String status;
  final String conversationType;
  final String requestStatus;
  final String initiatedByUserId;
  final DateTime createdAt;
  final DateTime? requestUpdatedAt;
  final DateTime? lastMessageAt;
  final String otherRole;
  final String? otherAvatarUrl;
  final String otherDisplayName;
  final String? lastMessageId;
  final String? lastMessagePreview;
  final String? lastSenderUserId;
  final DateTime? lastMessageCreatedAt;
  final bool canRespondToRequest;
  final int unreadCount;

  bool get isPending => requestStatus == 'pending';
  bool get isAccepted => requestStatus == 'accepted' && status == 'active';

  factory CareConversation.fromJson(Map<String, dynamic> json) {
    return CareConversation(
      id: requireExactString(json, 'id'),
      status: requireExactString(json, 'status'),
      conversationType: requireExactString(json, 'conversation_type'),
      requestStatus: requireExactString(json, 'request_status'),
      initiatedByUserId: requireExactString(json, 'initiated_by_user_id'),
      createdAt: _requiredDate(json, 'created_at'),
      requestUpdatedAt: _optionalDate(json['request_updated_at']),
      lastMessageAt: _optionalDate(json['last_message_at']),
      otherRole: requireExactString(json, 'other_role'),
      otherAvatarUrl: optionalExactString(json, 'other_avatar_url'),
      otherDisplayName: requireExactString(json, 'other_display_name'),
      lastMessageId: optionalExactString(json, 'last_message_id'),
      lastMessagePreview: optionalExactString(json, 'last_message_preview'),
      lastSenderUserId: optionalExactString(json, 'last_sender_user_id'),
      lastMessageCreatedAt: _optionalDate(json['last_message_created_at']),
      canRespondToRequest: json['can_respond_to_request'] == true,
      unreadCount: _nonNegativeInt(json['unread_count'], 'unread_count'),
    );
  }

  CareConversation copyWith({
    String? status,
    String? requestStatus,
    int? unreadCount,
    String? lastMessageId,
    String? lastMessagePreview,
    String? lastSenderUserId,
    DateTime? lastMessageCreatedAt,
  }) {
    return CareConversation(
      id: id,
      status: status ?? this.status,
      conversationType: conversationType,
      requestStatus: requestStatus ?? this.requestStatus,
      initiatedByUserId: initiatedByUserId,
      createdAt: createdAt,
      requestUpdatedAt: requestUpdatedAt,
      lastMessageAt: lastMessageCreatedAt ?? lastMessageAt,
      otherRole: otherRole,
      otherAvatarUrl: otherAvatarUrl,
      otherDisplayName: otherDisplayName,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastSenderUserId: lastSenderUserId ?? this.lastSenderUserId,
      lastMessageCreatedAt: lastMessageCreatedAt ?? this.lastMessageCreatedAt,
      canRespondToRequest: canRespondToRequest,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ConversationPage {
  const ConversationPage({
    required this.items,
    required this.limit,
    required this.offset,
  });

  final List<CareConversation> items;
  final int limit;
  final int offset;

  factory ConversationPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException('Invalid items');
    return ConversationPage(
      items: rawItems
          .map((item) => CareConversation.fromJson(_map(item)))
          .toList(growable: false),
      limit: _nonNegativeInt(json['limit'], 'limit'),
      offset: _nonNegativeInt(json['offset'], 'offset'),
    );
  }
}

class CareMessage {
  const CareMessage({
    required this.conversationId,
    required this.senderUserId,
    required this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.id,
    this.messageType = 'text',
    this.deliveryState = MessageDeliveryState.sent,
    this.errorCode,
  });

  final String? id;
  final String conversationId;
  final String senderUserId;
  final String clientMessageId;
  final String body;
  final String messageType;
  final DateTime createdAt;
  final MessageDeliveryState deliveryState;
  final String? errorCode;

  String get stableKey => id ?? clientMessageId;
  bool get isAuthoritative => id != null;

  factory CareMessage.fromJson(Map<String, dynamic> json) {
    return CareMessage(
      id: requireExactString(json, 'id'),
      conversationId: requireExactString(json, 'conversation_id'),
      senderUserId: requireExactString(json, 'sender_user_id'),
      clientMessageId: requireExactString(json, 'client_message_id'),
      body: requireExactString(json, 'body'),
      messageType: requireExactString(json, 'message_type'),
      createdAt: _requiredDate(json, 'created_at'),
    );
  }

  factory CareMessage.optimistic({
    required String conversationId,
    required String senderUserId,
    required String clientMessageId,
    required String body,
    required DateTime createdAt,
  }) {
    return CareMessage(
      conversationId: conversationId,
      senderUserId: senderUserId,
      clientMessageId: clientMessageId,
      body: body,
      createdAt: createdAt,
      deliveryState: MessageDeliveryState.sending,
    );
  }

  CareMessage copyWith({
    MessageDeliveryState? deliveryState,
    String? errorCode,
    bool clearError = false,
  }) {
    return CareMessage(
      id: id,
      conversationId: conversationId,
      senderUserId: senderUserId,
      clientMessageId: clientMessageId,
      body: body,
      messageType: messageType,
      createdAt: createdAt,
      deliveryState: deliveryState ?? this.deliveryState,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

class MessagePage {
  const MessagePage({required this.items, this.nextCursor, this.latestCursor});

  final List<CareMessage> items;
  final String? nextCursor;
  final String? latestCursor;

  factory MessagePage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException('Invalid items');
    return MessagePage(
      items: rawItems
          .map((item) => CareMessage.fromJson(_map(item)))
          .toList(growable: false),
      nextCursor: optionalExactString(json, 'next_cursor'),
      latestCursor: optionalExactString(json, 'latest_cursor'),
    );
  }
}

class MessagingReadState {
  const MessagingReadState({
    required this.conversationId,
    this.lastReadMessageId,
    this.lastReadAt,
  });

  final String conversationId;
  final String? lastReadMessageId;
  final DateTime? lastReadAt;

  factory MessagingReadState.fromJson(Map<String, dynamic> json) {
    return MessagingReadState(
      conversationId: requireExactString(json, 'conversation_id'),
      lastReadMessageId: optionalExactString(json, 'last_read_message_id'),
      lastReadAt: _optionalDate(json['last_read_at']),
    );
  }
}

enum RecipientKind { doctor, patient }

class MessagingRecipient {
  const MessagingRecipient({
    required this.id,
    required this.kind,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.avatarUrl,
    this.specialtyAr,
    this.specialtyEn,
    this.city,
  });

  final String id;
  final RecipientKind kind;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? avatarUrl;
  final String? specialtyAr;
  final String? specialtyEn;
  final String? city;

  factory MessagingRecipient.doctor(Map<String, dynamic> json) {
    return MessagingRecipient(
      id: requireExactString(json, 'id'),
      kind: RecipientKind.doctor,
      firstNameAr: optionalExactString(json, 'first_name_ar'),
      lastNameAr: optionalExactString(json, 'last_name_ar'),
      firstNameEn: optionalExactString(json, 'first_name_en'),
      lastNameEn: optionalExactString(json, 'last_name_en'),
      avatarUrl: optionalExactString(json, 'profile_image_url'),
      specialtyAr:
          optionalExactString(json, 'specialty_ar') ??
          optionalExactString(json, 'specialty_name_ar'),
      specialtyEn:
          optionalExactString(json, 'specialty_en') ??
          optionalExactString(json, 'specialty_name_en'),
      city: optionalExactString(json, 'city'),
    );
  }

  factory MessagingRecipient.patient(Map<String, dynamic> json) {
    return MessagingRecipient(
      id: requireExactString(json, 'id'),
      kind: RecipientKind.patient,
      firstNameAr: optionalExactString(json, 'first_name_ar'),
      lastNameAr: optionalExactString(json, 'last_name_ar'),
      firstNameEn: optionalExactString(json, 'first_name_en'),
      lastNameEn: optionalExactString(json, 'last_name_en'),
      avatarUrl: optionalExactString(json, 'avatar_url'),
      city: optionalExactString(json, 'city'),
    );
  }

  String displayName(bool isArabic) {
    final preferred = isArabic
        ? <String?>[firstNameAr, lastNameAr]
        : <String?>[firstNameEn, lastNameEn];
    final fallback = isArabic
        ? <String?>[firstNameEn, lastNameEn]
        : <String?>[firstNameAr, lastNameAr];
    final primary = preferred.whereType<String>().join(' ').trim();
    if (primary.isNotEmpty) return primary;
    return fallback.whereType<String>().join(' ').trim();
  }

  String? specialty(bool isArabic) =>
      isArabic ? (specialtyAr ?? specialtyEn) : (specialtyEn ?? specialtyAr);
}

class RecipientSearchResult {
  const RecipientSearchResult({required this.items});
  final List<MessagingRecipient> items;
}

class PatientMessagingPreference {
  const PatientMessagingPreference({required this.allowDoctorMessages});

  final bool allowDoctorMessages;

  factory PatientMessagingPreference.fromJson(Map<String, dynamic> json) {
    final value = json['allow_doctor_messages'];
    if (value is! bool) {
      throw const FormatException('Invalid allow_doctor_messages');
    }
    return PatientMessagingPreference(allowDoctorMessages: value);
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException('Invalid object');
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final raw = requireExactString(json, key);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('Invalid $key');
  return parsed;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid optional date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid optional date');
  return parsed;
}

int _nonNegativeInt(Object? value, String key) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0) throw FormatException('Invalid $key');
  return parsed;
}
