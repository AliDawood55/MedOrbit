import 'package:dio/dio.dart';
import '../../../../core/network/api_exception.dart';
import '../models/doctor_patient_models.dart';

class DoctorPatientsApi {
  DoctorPatientsApi(this._dio);
  final Dio _dio;
  Future<List<DoctorPatient>> list() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/doctors/me/patients',
    );
    final data = response.data?['data'];
    if (response.data?['success'] != true || data is! List) {
      throw const ApiException(
        message: 'The patient list response was incomplete.',
        code: 'INVALID_RESPONSE',
      );
    }
    return data
        .whereType<Map>()
        .map(
          (value) => DoctorPatient.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }
}
