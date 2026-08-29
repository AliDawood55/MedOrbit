import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/symptom_check_request.dart';
import '../models/symptom_check_result.dart';

/// Client for the authenticated MedOrbit backend's `POST /api/ai/triage`
/// (`backend/src/routes/ai.routes.js`), which forwards internally to the AI
/// service's `/triage` — the same contract the web app uses
/// (`frontend/src/js/symptom-checker.js`). Goes through `dioProvider`, so it
/// carries the `/api` base and the auth interceptor's bearer token; the
/// response is still the AI service's flat JSON object, not the backend's
/// usual `{success, data}` envelope, because the route passes it through
/// unchanged.
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
