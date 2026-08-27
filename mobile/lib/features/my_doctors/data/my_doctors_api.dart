import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/patient_doctor_models.dart';

class MyDoctorsApi {
  MyDoctorsApi(this._dio);
  final Dio _dio;

  Future<List<PatientDoctor>> listDoctors() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/patients/me/doctors',
    );
    return _listData(response.data)
        .map(
          (item) =>
              PatientDoctor.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<SharedDoctorNote>> listSharedNotes(String doctorId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/patients/me/doctors/$doctorId/notes',
    );
    return _listData(response.data)
        .map(
          (item) =>
              SharedDoctorNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
}

List<dynamic> _listData(Map<String, dynamic>? envelope) {
  if (envelope == null) {
    throw const ApiException(
      message: 'Empty response from server.',
      code: 'EMPTY_RESPONSE',
    );
  }
  if (envelope['success'] == false) {
    throw const ApiException(
      message: 'Request failed.',
      code: 'BACKEND_FAILURE',
    );
  }
  final data = envelope['data'];
  if (data is List) return data;
  throw const ApiException(
    message: 'Unexpected response from server.',
    code: 'INVALID_RESPONSE',
  );
}
