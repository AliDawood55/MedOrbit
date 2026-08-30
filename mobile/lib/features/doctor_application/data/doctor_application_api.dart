import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../discovery/models/doctor_models.dart';
import '../models/doctor_application_model.dart';

class DoctorApplicationApi {
  DoctorApplicationApi(this._dio);

  final Dio _dio;

  Future<List<DoctorApplication>> loadMyApplications() async {
    final response = await _dio.get<Map<String, dynamic>>('/doctor-applications/me');
    final data = _data(response.data);
    if (data is! List) throw _invalidResponse;
    return data.map((item) {
      if (item is! Map) throw _invalidResponse;
      return DoctorApplication.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  Future<List<Specialty>> loadSpecialties() async {
    final response = await _dio.get<Map<String, dynamic>>('/specialties');
    final data = _data(response.data);
    if (data is! List) throw _invalidResponse;
    return data.map((item) {
      if (item is! Map) throw _invalidResponse;
      return Specialty.fromJson(Map<String, dynamic>.from(item));
    }).where((item) => item.id != null && item.nameEn.isNotEmpty).toList();
  }

  Future<DoctorApplication> submitApplication(DoctorApplicationRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>('/doctor-applications', data: request.toJson());
    return DoctorApplication.fromJson(_applicationData(response.data));
  }

  Future<DoctorApplication> withdrawApplication(String applicationId) async {
    final response = await _dio.post<Map<String, dynamic>>('/doctor-applications/$applicationId/withdraw', data: const <String, dynamic>{});
    return DoctorApplication.fromJson(_applicationData(response.data));
  }
}

const _invalidResponse = ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');

Object? _data(Map<String, dynamic>? envelope) {
  if (envelope == null) throw _invalidResponse;
  if (envelope['success'] == false) {
    final error = envelope['error'];
    if (error is Map) {
      final message = error['message'];
      final code = error['code'];
      throw ApiException(
        message: message is String ? message : 'Request failed.',
        code: code is String ? code : 'BACKEND_FAILURE',
        details: error['details'],
      );
    }
    throw const ApiException(message: 'Request failed.', code: 'BACKEND_FAILURE');
  }
  return envelope['data'];
}

Map<String, dynamic> _applicationData(Map<String, dynamic>? envelope) {
  final data = _data(envelope);
  if (data is Map) return Map<String, dynamic>.from(data);
  throw _invalidResponse;
}
