import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';

class DoctorPortalApi {
  DoctorPortalApi(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> professionalProfile() => _mapGet('/doctors/me/profile');
  Future<Map<String, dynamic>> updateProfessionalProfile(Map<String, dynamic> body) => _mapPut('/doctors/me/profile', body);
  Future<Map<String, dynamic>> patientDetail(String patientId) => _mapGet('/doctors/me/patients/$patientId');
  Future<Map<String, dynamic>> billing() => _mapGet('/billing/subscription');

  Future<List<Map<String, dynamic>>> posts() => _listGet('/doctors/me/posts');
  Future<Map<String, dynamic>> createPost(Map<String, dynamic> body) => _mapPost('/doctors/me/posts', body);
  Future<Map<String, dynamic>> updatePost(String id, Map<String, dynamic> body) => _mapPut('/doctors/me/posts/$id', body);
  Future<void> deletePost(String id) async {
    final response = await _dio.delete<Map<String, dynamic>>('/doctors/me/posts/$id');
    _success(response.data);
  }

  Future<List<Map<String, dynamic>>> conversations() async {
    final data = await _mapGet('/messages/conversations');
    return _maps(data['items']);
  }

  Future<List<Map<String, dynamic>>> messages(String conversationId) async {
    final data = await _mapGet('/messages/conversations/$conversationId/messages');
    return _maps(data['items']);
  }

  Future<Map<String, dynamic>> sendMessage(String conversationId, String body, String clientMessageId) =>
      _mapPost('/messages/conversations/$conversationId/messages', {'body': body, 'client_message_id': clientMessageId});
  Future<Map<String, dynamic>> startConversation(String counterpartId) =>
      _mapPost('/messages/conversations', {'counterpartId': counterpartId});

  Future<Map<String, dynamic>> _mapGet(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(path);
    return _mapData(response.data);
  }

  Future<List<Map<String, dynamic>>> _listGet(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(path);
    _success(response.data);
    return _maps(response.data?['data']);
  }

  Future<Map<String, dynamic>> _mapPost(String path, Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>(path, data: body);
    return _mapData(response.data);
  }

  Future<Map<String, dynamic>> _mapPut(String path, Map<String, dynamic> body) async {
    final response = await _dio.put<Map<String, dynamic>>(path, data: body);
    return _mapData(response.data);
  }

  static void _success(Map<String, dynamic>? body) {
    if (body == null || body['success'] != true) {
      throw const ApiException(message: 'The server returned an incomplete response.', code: 'INVALID_RESPONSE');
    }
  }

  static Map<String, dynamic> _mapData(Map<String, dynamic>? body) {
    _success(body);
    final data = body?['data'];
    if (data is! Map) {
      throw const ApiException(message: 'The server returned an incomplete response.', code: 'INVALID_RESPONSE');
    }
    return Map<String, dynamic>.from(data);
  }

  static List<Map<String, dynamic>> _maps(dynamic data) => data is List
      ? data.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList()
      : const [];
}
