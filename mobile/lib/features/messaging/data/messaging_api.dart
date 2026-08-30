import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/utils/json_parsing.dart';
import '../models/messaging_models.dart';

class MessagingApi {
  MessagingApi(this._dio);

  final Dio _dio;

  Future<ConversationPage> listConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/messages/conversations',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _parse(() => ConversationPage.fromJson(_mapData(response.data)));
  }

  Future<CareConversation> createConversation(String counterpartId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/conversations',
      data: {'counterpartId': counterpartId},
    );
    return _parse(() => CareConversation.fromJson(_mapData(response.data)));
  }

  Future<MessagePage> listMessages(
    String conversationId, {
    int limit = 50,
    String? cursor,
    String? after,
  }) async {
    final id = Uri.encodeComponent(conversationId);
    final response = await _dio.get<Map<String, dynamic>>(
      '/messages/conversations/$id/messages',
      queryParameters: {'limit': limit, 'cursor': ?cursor, 'after': ?after},
    );
    return _parse(() => MessagePage.fromJson(_mapData(response.data)));
  }

  Future<CareMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) async {
    final id = Uri.encodeComponent(conversationId);
    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/conversations/$id/messages',
      data: {'body': body, 'client_message_id': clientMessageId},
    );
    return _parse(() => CareMessage.fromJson(_mapData(response.data)));
  }

  Future<MessagingReadState> markRead(
    String conversationId, {
    String? messageId,
  }) async {
    final id = Uri.encodeComponent(conversationId);
    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/conversations/$id/read',
      data: {'message_id': ?messageId},
    );
    return _parse(() => MessagingReadState.fromJson(_mapData(response.data)));
  }

  Future<CareConversation> acceptRequest(String conversationId) async {
    final id = Uri.encodeComponent(conversationId);
    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/conversations/$id/accept',
      data: const <String, dynamic>{},
    );
    return _parse(() => CareConversation.fromJson(_mapData(response.data)));
  }

  Future<RequestDecision> declineRequest(String conversationId) async {
    final id = Uri.encodeComponent(conversationId);
    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/conversations/$id/decline',
      data: const <String, dynamic>{},
    );
    return _parse(() => RequestDecision.fromJson(_mapData(response.data)));
  }

  Future<List<MessagingRecipient>> searchDoctors(
    String search, {
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/doctors',
      queryParameters: {'search': search, 'page': 1, 'limit': limit},
    );
    return _parse(() {
      final data = _mapData(response.data);
      final doctors = data['doctors'];
      if (doctors is! List) throw const FormatException('Invalid doctors');
      return doctors
          .map((item) => MessagingRecipient.doctor(_asMap(item)))
          .toList(growable: false);
    });
  }

  Future<List<MessagingRecipient>> searchPatients(
    String search, {
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/patients/discover',
      queryParameters: {'search': search, 'limit': limit},
    );
    return _parse(() {
      final data = _mapData(response.data);
      final patients = data['items'];
      if (patients is! List) throw const FormatException('Invalid patients');
      return patients
          .map((item) => MessagingRecipient.patient(_asMap(item)))
          .toList(growable: false);
    });
  }

  Future<String> getOwnDoctorId() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/doctors/me/profile',
    );
    return _parse(() => requireExactString(_mapData(response.data), 'id'));
  }

  Future<PatientMessagingPreference> getPatientMessagingPreference() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/patients/me/profile',
    );
    return _parse(
      () => PatientMessagingPreference.fromJson(_mapData(response.data)),
    );
  }

  Future<PatientMessagingPreference> updatePatientMessagingPreference(
    bool allowDoctorMessages,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/patients/me/profile',
      data: {'allowDoctorMessages': allowDoctorMessages},
    );
    return _parse(
      () => PatientMessagingPreference.fromJson(_mapData(response.data)),
    );
  }
}

class RequestDecision {
  const RequestDecision({
    required this.id,
    required this.status,
    required this.requestStatus,
  });

  final String id;
  final String status;
  final String requestStatus;

  factory RequestDecision.fromJson(Map<String, dynamic> json) {
    return RequestDecision(
      id: requireExactString(json, 'id'),
      status: requireExactString(json, 'status'),
      requestStatus: requireExactString(json, 'request_status'),
    );
  }
}

Map<String, dynamic> _mapData(Map<String, dynamic>? envelope) {
  if (envelope == null) {
    throw const ApiException(
      message: 'Empty response from server.',
      code: 'INVALID_RESPONSE',
    );
  }
  if (envelope['success'] == false) {
    final rawError = envelope['error'];
    final error = rawError is Map ? Map<String, dynamic>.from(rawError) : null;
    throw ApiException(
      message: error?['message'] is String
          ? error!['message'] as String
          : 'Request failed.',
      code: error?['code'] is String
          ? error!['code'] as String
          : ApiException.codeUnknown,
      details: error?['details'],
    );
  }
  if (envelope['success'] != true) {
    throw const ApiException(
      message: 'Unexpected response from server.',
      code: 'INVALID_RESPONSE',
    );
  }
  final data = envelope['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const ApiException(
    message: 'Unexpected response from server.',
    code: 'INVALID_RESPONSE',
  );
}

T _parse<T>(T Function() parser) {
  try {
    return parser();
  } on ApiException {
    rethrow;
  } on FormatException {
    throw const ApiException(
      message: 'Unexpected response from server.',
      code: 'INVALID_RESPONSE',
    );
  } on TypeError {
    throw const ApiException(
      message: 'Unexpected response from server.',
      code: 'INVALID_RESPONSE',
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException('Invalid object');
}
