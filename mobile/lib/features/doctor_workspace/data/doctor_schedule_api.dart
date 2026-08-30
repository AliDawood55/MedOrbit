import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../models/doctor_schedule_models.dart';

class DoctorScheduleApi {
  DoctorScheduleApi(this._dio);
  final Dio _dio;

  Future<DoctorSchedule> load() async {
    final response = await _dio.get<Map<String, dynamic>>('/doctors/me/schedule');
    final data = response.data?['data'];
    if (response.data?['success'] != true || data is! Map) {
      throw const ApiException(message: 'The doctor schedule response was incomplete.', code: 'INVALID_RESPONSE');
    }
    return DoctorSchedule.fromJson(Map<String, dynamic>.from(data));
  }

  Future<DoctorScheduleAppointment> confirm(String id) => _updateAppointment(id, 'confirm');
  Future<DoctorScheduleAppointment> complete(String id) => _updateAppointment(id, 'complete');

  Future<DoctorScheduleAppointment> _updateAppointment(String id, String action) async {
    final response = await _dio.put<Map<String, dynamic>>('/appointments/$id/$action');
    final data = response.data?['data'];
    if (response.data?['success'] != true || data is! Map) {
      throw const ApiException(message: 'The appointment update response was incomplete.', code: 'INVALID_RESPONSE');
    }
    return DoctorScheduleAppointment.fromJson(Map<String, dynamic>.from(data));
  }
}
