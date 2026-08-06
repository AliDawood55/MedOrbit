import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/drug_check_request.dart';
import '../models/drug_check_result.dart';

/// Client for the AI service's `POST /drug-interactions` — the exact same
/// contract the web app uses (`frontend/src/js/drug-checker.js`,
/// `ai-service/chatbot/main.py`). No `/api` prefix, no auth, and the response
/// is a flat JSON object rather than the backend's `{success, data}` envelope.
class DrugCheckerApi {
  DrugCheckerApi(this._dio);

  final Dio _dio;

  /// `/drug-interactions` runs a database/keyword match, not an LLM turn, so
  /// it doesn't need the shared 120s AI message budget.
  static const Duration _checkTimeout = Duration(seconds: 20);

  Future<DrugCheckResult> checkInteractions(List<String> medicationNames) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/drug-interactions',
      data: DrugCheckRequest(medicationNames: medicationNames).toJson(),
      options: Options(
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: _checkTimeout,
        receiveTimeout: _checkTimeout,
      ),
    );
    return DrugCheckResult.fromJson(response.data!);
  }
}
