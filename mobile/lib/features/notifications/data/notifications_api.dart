import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/notification_model.dart';

class NotificationsApi {
  NotificationsApi(this._dio);

  final Dio _dio;

  /// `GET /notifications` — no query params: the backend returns everything
  /// (capped at 50 rows server-side, newest first), no pagination.
  Future<List<NotificationModel>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/notifications');
    final data = _envelopeList(response.data);
    return data.map(NotificationModel.fromJson).toList();
  }

  /// `PUT /notifications/:id/read` — returns the full updated row.
  Future<NotificationModel> markRead(String id) async {
    final response = await _dio.put<Map<String, dynamic>>('/notifications/$id/read');
    return NotificationModel.fromJson(_envelopeData(response.data));
  }

  /// `PATCH /notifications/read-all` — returns `{ updated: <count> }`.
  Future<int> markAllRead() async {
    final response = await _dio.patch<Map<String, dynamic>>('/notifications/read-all');
    final data = _envelopeData(response.data);
    final updated = data['updated'];
    return updated is num ? updated.toInt() : 0;
  }

  /// `DELETE /notifications/:id` — `data` is always `null` on success; only
  /// the envelope's `success` flag matters here.
  Future<void> delete(String id) async {
    final response = await _dio.delete<Map<String, dynamic>>('/notifications/$id');
    _envelopeSuccess(response.data);
  }
}

void _envelopeSuccess(Map<String, dynamic>? envelope) {
  if (envelope == null) {
    throw const ApiException(message: 'Empty response from server.', code: 'EMPTY_RESPONSE');
  }
  if (envelope['success'] == false) {
    throw const ApiException(message: 'Request failed.', code: 'BACKEND_FAILURE');
  }
}

Map<String, dynamic> _envelopeData(Map<String, dynamic>? envelope) {
  _envelopeSuccess(envelope);
  final data = envelope!['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');
}

List<Map<String, dynamic>> _envelopeList(Map<String, dynamic>? envelope) {
  _envelopeSuccess(envelope);
  final data = envelope!['data'];
  if (data is! List) {
    throw const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');
  }
  return data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}
