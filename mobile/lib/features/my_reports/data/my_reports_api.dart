import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/my_report_item.dart';

/// Client for the backend's report-listing routes
/// (`backend/src/routes/report.routes.js`) — the Node `/api` origin,
/// `{success, data}` envelope, unlike the AI-service-direct feature APIs
/// (Symptom/Drug Checker, Report Summarizer).
class MyReportsApi {
  MyReportsApi(this._dio);

  final Dio _dio;

  /// `GET /reports/summaries` — patient-scoped (any authenticated role),
  /// filtered server-side to the current user, newest first.
  Future<List<MyReportItem>> listReportSummaries() async {
    final response = await _dio.get<Map<String, dynamic>>('/reports/summaries');
    final data = _envelopeList(response.data);
    return data.map(MyReportItem.fromReportSummaryJson).toList();
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

List<Map<String, dynamic>> _envelopeList(Map<String, dynamic>? envelope) {
  _envelopeSuccess(envelope);
  final data = envelope!['data'];
  if (data is! List) {
    throw const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');
  }
  return data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}
