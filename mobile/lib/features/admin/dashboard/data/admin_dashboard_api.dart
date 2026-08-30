import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../models/admin_dashboard_stats.dart';

/// Authenticated client for the administrator dashboard/analytics endpoint.
///
/// One request serves both surfaces: `GET /dashboard/stats` returns the
/// headline totals **and** the six analytics sections in a single envelope
/// (`backend/src/services/report.service.js:161-286`), which is exactly what
/// the web `analytics.js` page consumes.
class AdminDashboardApi {
  AdminDashboardApi(this._dio);

  final Dio _dio;

  Future<AdminDashboardStats> getStats() async {
    final response = await _dio.get<Map<String, dynamic>>('/dashboard/stats');
    return AdminDashboardStats.fromJson(adminEnvelopeObject(response.data));
  }
}
