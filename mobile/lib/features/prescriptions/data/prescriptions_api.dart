import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/prescription_model.dart';

const _invalidResponse = ApiException(
  message: 'Unexpected response from server. Please try again.',
  code: 'INVALID_RESPONSE',
);

class PrescriptionsApi {
  PrescriptionsApi(this._dio);

  final Dio _dio;

  /// A malformed entry fails the whole fetch rather than being silently
  /// dropped: a prescription quietly missing from the list would read to
  /// the patient as "you have no such prescription", which is worse than an
  /// error state they can retry.
  Future<List<PrescriptionModel>> list() async {
    final response = await _dio.get('/patients/me/prescriptions');
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) throw _invalidResponse;
    return data.map((e) {
      if (e is! Map<String, dynamic>) throw _invalidResponse;
      return PrescriptionModel.fromJson(e);
    }).toList();
  }
}
