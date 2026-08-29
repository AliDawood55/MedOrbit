import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../models/chatbot_models.dart';

class ChatbotApi {
  ChatbotApi(this._dio);

  final Dio _dio;

  /// The only endpoint here that waits on an AI turn.
  ///
  /// The backend proxies this to its AI client, whose own budget is ~60s, so
  /// the shared 15s REST receive timeout aborted valid slow answers and told
  /// the patient the message had failed. Widened for this request only —
  /// every other method below keeps the 15s default deliberately.
  Future<ChatMessageResponse> sendMessage(ChatMessageRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/message',
      data: request.toJson(),
      options: Options(
        extra: {'network.requestName': 'chat.message'},
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: AppConfig.chatAiSendTimeout,
        receiveTimeout: AppConfig.chatAiReceiveTimeout,
      ),
    );
    return ChatMessageResponse.fromJson(_envelopeData(response.data));
  }

  Future<
    ({List<ConversationSummary> conversations, ChatPagination? pagination})
  >
  listConversations({int page = 1, int limit = 50, String? search}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations',
      queryParameters: _withoutNulls({
        'page': page,
        'limit': limit,
        'search': search,
      }),
    );
    final data = _envelopeData(response.data);
    return (
      conversations: _list(
        data['conversations'],
      ).map(ConversationSummary.fromJson).toList(),
      pagination: _map(data['pagination']) == null
          ? null
          : ChatPagination.fromJson(_map(data['pagination'])!),
    );
  }

  Future<ConversationSummary> createConversation({String? language}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations',
      data: _withoutNulls({'language': language}),
    );
    return ConversationSummary.fromJson(_envelopeData(response.data));
  }

  Future<List<ConversationSummary>> searchConversations(String query) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations/search',
      queryParameters: {'q': query},
    );
    final data = _envelopeData(response.data);
    return _list(
      data['conversations'],
    ).map(ConversationSummary.fromJson).toList();
  }

  Future<ConversationDetail> getConversation(
    String id, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations/$id',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return ConversationDetail.fromJson(_envelopeData(response.data));
  }

  Future<ConversationSummary> renameConversation(
    String id, {
    required String title,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/conversations/$id',
      data: {'title': title},
    );
    return ConversationSummary.fromJson(_envelopeData(response.data));
  }

  Future<void> deleteConversation(String id) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/conversations/$id',
    );
    _envelopeData(response.data, allowNullData: true);
  }

  Future<ConversationSummary> generateConversationTitle(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations/$id/title',
    );
    return ConversationSummary.fromJson(_envelopeData(response.data));
  }

  Future<List<ChatConversationPlace>> listConversationPlaces(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations/$id/places',
    );
    final data = _envelopeData(response.data);
    return _list(data['places']).map(ChatConversationPlace.fromJson).toList();
  }

  Future<ChatConversationPlace> saveConversationPlace(
    String id, {
    required String placeName,
    required String placeType,
    required double latitude,
    required double longitude,
    String? address,
    String? phone,
    double? distanceKm,
    double? rating,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations/$id/places',
      data: _withoutNulls({
        'placeName': placeName,
        'placeType': placeType,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'phone': phone,
        'distanceKm': distanceKm,
        'rating': rating,
      }),
    );
    return ChatConversationPlace.fromJson(_envelopeData(response.data));
  }
}

Map<String, dynamic> _envelopeData(
  Map<String, dynamic>? envelope, {
  bool allowNullData = false,
}) {
  if (envelope == null) {
    if (allowNullData) return const {};
    throw const ApiException(
      message: 'Empty response from server.',
      code: 'EMPTY_RESPONSE',
    );
  }

  if (envelope['success'] == false) {
    final rawError = envelope['error'];
    if (rawError is Map) {
      final error = Map<String, dynamic>.from(rawError);
      throw ApiException(
        message: error['message'] as String? ?? 'Request failed.',
        code: error['code'] as String? ?? 'BACKEND_FAILURE',
        details: error['details'],
      );
    }
    throw ApiException(
      message: envelope['message'] as String? ?? 'Request failed.',
      code: 'BACKEND_FAILURE',
    );
  }

  final data = envelope['data'];
  if (data == null && allowNullData) return const {};
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const ApiException(
    message: 'Unexpected response from server.',
    code: 'INVALID_RESPONSE',
  );
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> value) {
  return Map<String, dynamic>.fromEntries(
    value.entries.where((entry) => entry.value != null),
  );
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
