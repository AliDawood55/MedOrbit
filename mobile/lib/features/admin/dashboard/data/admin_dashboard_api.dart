import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../models/admin_dashboard_stats.dart';

/// Authenticated client for the existing administrator dashboard endpoint.
class AdminDashboardApi {
  AdminDashboardApi(this._dio);

  final Dio _dio;

  Future<AdminDashboardStats> getStats() async {
    final response = await _dio.get<Map<String, dynamic>>('/dashboard/stats');
    final envelope = response.data;
    if (envelope == null || envelope['success'] != true) {
      throw const ApiException(
        message: 'The dashboard statistics could not be loaded.',
        code: 'INVALID_RESPONSE',
      );
    }

    final data = envelope['data'];
    if (data is! Map) {
      throw const ApiException(
        message: 'The dashboard statistics response was incomplete.',
        code: 'INVALID_RESPONSE',
      );
    }
    return AdminDashboardStats.fromJson(Map<String, dynamic>.from(data));
  }
}
