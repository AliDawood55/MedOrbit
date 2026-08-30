import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../models/admin_audit_log.dart';

/// Read-only client for `/api/admin/audit-logs` (`authorizeAdmin`).
///
/// The route supports `user_id`, `entity_type`, `from`, and `to` — and nothing
/// else. There is no mutation endpoint, and none is simulated here.
class AdminAuditApi {
  AdminAuditApi(this._dio);

  final Dio _dio;

  Future<List<AdminAuditLog>> list({
    required DateTime from,
    DateTime? to,
    String? entityType,
    String? userId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/audit-logs',
      queryParameters: {
        // Compared against a `timestamptz` column, so an absolute UTC instant
        // is sent rather than a local wall-clock string.
        'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (entityType != null && entityType.isNotEmpty)
          'entity_type': entityType,
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
      },
    );
    return adminEnvelopeList(
      response.data,
    ).map(AdminAuditLog.fromJson).toList(growable: false);
  }
}
