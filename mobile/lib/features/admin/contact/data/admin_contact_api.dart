import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../../common/models/admin_parsing.dart';
import '../models/admin_contact_message.dart';

/// Client for `/api/admin/contact-messages` (`authorizeAdmin`).
///
/// The endpoint supports `status`, `limit` (1–100, default 30) and `offset` —
/// and nothing else. There is no search parameter, so the app does not offer
/// one: a client-side filter over one loaded page would silently miss every
/// message the page has not reached.
class AdminContactApi {
  AdminContactApi(this._dio);

  final Dio _dio;

  Future<AdminContactPage> list({
    AdminContactStatus? status,
    required int limit,
    required int offset,
  }) async {
    final wireStatus = adminContactStatusWireValue(status);
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/contact-messages',
      queryParameters: {
        'status': ?wireStatus,
        'limit': limit,
        'offset': offset,
      },
    );

    final data = adminEnvelopeObject(response.data);
    return AdminContactPage(
      items: adminObjectList(
        data['items'],
      ).map(AdminContactMessage.fromJson).toList(growable: false),
      limit: adminOptionalInt(data['limit']) ?? limit,
      offset: adminOptionalInt(data['offset']) ?? offset,
    );
  }

  Future<AdminContactMessage> get(String messageId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/contact-messages/${Uri.encodeComponent(messageId)}',
    );
    return AdminContactMessage.fromJson(adminEnvelopeObject(response.data));
  }

  Future<AdminContactStatusUpdate> markRead(String messageId) =>
      _transition(messageId, 'read');

  Future<AdminContactStatusUpdate> resolve(String messageId) =>
      _transition(messageId, 'resolve');

  Future<AdminContactStatusUpdate> _transition(
    String messageId,
    String action,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/contact-messages/${Uri.encodeComponent(messageId)}/$action',
      data: const <String, dynamic>{},
    );
    return AdminContactStatusUpdate.fromJson(
      adminEnvelopeObject(response.data),
    );
  }
}
