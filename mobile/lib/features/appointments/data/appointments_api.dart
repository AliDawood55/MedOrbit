import 'package:dio/dio.dart';

import '../models/appointment_model.dart';

class AppointmentsApi {
  AppointmentsApi(this._dio);

  final Dio _dio;

  Future<List<AppointmentModel>> list() async {
    final response = await _dio.get('/appointments');
    final data = response.data['data'] as List;
    return data.map((e) => AppointmentModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppointmentModel> cancel(String id, {String? reason}) async {
    final response = await _dio.put(
      '/appointments/$id/cancel',
      data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    return AppointmentModel.fromJson(response.data['data'] as Map<String, dynamic>);
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
