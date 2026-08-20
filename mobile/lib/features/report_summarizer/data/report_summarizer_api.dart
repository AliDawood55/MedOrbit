import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/report_summary_result.dart';

/// Client for the AI service's `POST /summarize` — supports both text and
/// PDF/image file summarization, matching the web app's contract exactly.
/// `file` and `text` are mutually exclusive on the wire (each method sends
/// only the field it's named for); the AI service accepts either.
class ReportSummarizerApi {
  ReportSummarizerApi(this._dio);

  final Dio _dio;

  Future<ReportSummaryResult> summarizeText({
    required String text,
    // Retained as an in-process compatibility argument; never sent on the wire.
    String? userId,
    String? recordId,
  }) async {
    final formData = FormData.fromMap({
      'text': text,
      'record_id': ?recordId,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/ai/summarize',
      data: formData,
      options: Options(
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: AppConfig.reportTimeout,
        receiveTimeout: AppConfig.reportTimeout,
      ),
    );
    return ReportSummaryResult.fromJson(response.data!);
  }

  Future<ReportSummaryResult> summarizeFile({
    required String filePath,
    required String fileName,
    // Retained as an in-process compatibility argument; never sent on the wire.
    String? userId,
    String? recordId,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'record_id': ?recordId,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/ai/summarize',
      data: formData,
      options: Options(
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: AppConfig.reportTimeout,
        receiveTimeout: AppConfig.reportTimeout,
      ),
    );
    return ReportSummaryResult.fromJson(response.data!);
  }
}
