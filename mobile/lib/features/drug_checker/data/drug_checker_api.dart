import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/drug_check_request.dart';
import '../models/drug_check_result.dart';

/// Client for the authenticated backend Drug Checker gateway.
///
/// The mobile app never calls the AI service directly. The backend validates
/// the medication list, applies rate limits and forwards the request with an
/// internal-only identity credential.
class DrugCheckerApi {
  DrugCheckerApi(this._dio);

  final Dio _dio;

  /// This check is short-running, so it does not need the Virtual Doctor's
  /// long message timeout.
  static const Duration _checkTimeout = Duration(seconds: 20);

  Future<DrugCheckResult> checkInteractions(List<String> medicationNames) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/ai/drug-interactions',
      data: DrugCheckRequest(medicationNames: medicationNames).toJson(),
      options: Options(
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: _checkTimeout,
        receiveTimeout: _checkTimeout,
      ),
    );
    final body = response.data;
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Drug Checker response is missing data.');
    }
    return DrugCheckResult.fromJson(data);
  }
}
