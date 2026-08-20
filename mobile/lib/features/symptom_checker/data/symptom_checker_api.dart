import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/symptom_check_request.dart';
import '../models/symptom_check_result.dart';

/// Client for the AI service's `POST /triage` — the exact same contract the
/// web app uses (`frontend/src/js/symptom-checker.js`, `ai-service/chatbot/main.py`).
/// No `/api` prefix, no auth, and the response is a flat JSON object rather
/// than the backend's `{success, data}` envelope.
class SymptomCheckerApi {
  SymptomCheckerApi(this._dio);

  final Dio _dio;

  /// `/triage` runs a keyword-scoring engine, not an LLM turn, so it doesn't
  /// need the shared 120s AI message budget — a short, explicit timeout here
  /// keeps a genuinely unreachable service from stalling the form for two
  /// minutes.
  static const Duration _triageTimeout = Duration(seconds: 20);

  Future<SymptomCheckResult> checkSymptoms(List<String> symptoms) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/ai/triage',
      data: SymptomCheckRequest(symptoms: symptoms).toJson(),
      options: Options(
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: _triageTimeout,
        receiveTimeout: _triageTimeout,
      ),
    );
    return SymptomCheckResult.fromJson(response.data!);
  }
}
