import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/appointment_model.dart';

const _invalidResponse = ApiException(
  message: 'Unexpected response from server. Please try again.',
  code: 'INVALID_RESPONSE',
);

class AppointmentsApi {
  AppointmentsApi(this._dio);

  final Dio _dio;

  /// A malformed entry fails the whole fetch rather than being silently
  /// dropped: an appointment quietly missing from the list would read to
  /// the patient as "you have no appointment", which is worse than an error
  /// state they can retry.
  Future<List<AppointmentModel>> list() async {
    final response = await _dio.get('/appointments');
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) throw _invalidResponse;
    return data.map((e) {
      if (e is! Map<String, dynamic>) throw _invalidResponse;
      return AppointmentModel.fromJson(e);
    }).toList();
  }

  Future<AppointmentModel> cancel(String id, {String? reason}) async {
    final response = await _dio.put(
      '/appointments/$id/cancel',
      data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! Map<String, dynamic>) throw _invalidResponse;
    return AppointmentModel.fromJson(data);
  }

  /// Public endpoint — no auth middleware on `GET /doctors/:id`.
  Future<(String? ar, String? en)> getDoctorName(String doctorId) async {
    final response = await _dio.get('/doctors/$doctorId');
    final doctor = (response.data['data'] as Map<String, dynamic>)['doctor'] as Map<String, dynamic>?;
    if (doctor == null) return (null, null);
    final ar = [doctor['first_name_ar'], doctor['last_name_ar']].whereType<String>().join(' ').trim();
    final en = [doctor['first_name_en'], doctor['last_name_en']].whereType<String>().join(' ').trim();
    return (ar.isEmpty ? null : ar, en.isEmpty ? null : en);
  }

  /// Public endpoint — no auth middleware on `GET /clinics/:id`.
  Future<(String? ar, String? en)> getClinicName(String clinicId) async {
    final response = await _dio.get('/clinics/$clinicId');
    final clinic = (response.data['data'] as Map<String, dynamic>)['clinic'] as Map<String, dynamic>?;
    if (clinic == null) return (null, null);
    return (clinic['name_ar'] as String?, clinic['name_en'] as String?);
  }
}
