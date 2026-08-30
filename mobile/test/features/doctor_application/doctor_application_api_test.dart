import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/doctor_application/data/doctor_application_api.dart';
import 'package:mobile/features/doctor_application/models/doctor_application_model.dart';

void main() {
  test('uses exact doctor application routes and normalized JSON payload', () async {
    final dio = _RecordingDio(); final api = DoctorApplicationApi(dio.dio);
    await api.loadMyApplications(); await api.loadSpecialties();
    await api.submitApplication(DoctorApplicationRequest.fromMultiline(specialtyId: ' specialty ', medicalLicenseNumber: ' LIC ', subSpecialty: ' ', bio: ' ', education: ' A \n\n B ', certifications: ' C \n D ', yearsOfExperience: 0));
    await api.withdrawApplication('application-9');
    expect(dio.paths, ['/doctor-applications/me', '/specialties', '/doctor-applications', '/doctor-applications/application-9/withdraw']);
    expect(dio.methods, ['GET', 'GET', 'POST', 'POST']);
    final payload = dio.bodies[2] as Map<String, dynamic>;
    expect(payload, {'specialty_id': 'specialty', 'medical_license_number': 'LIC', 'sub_specialty': null, 'years_of_experience': 0, 'education': ['A', 'B'], 'certifications': ['C', 'D'], 'bio': null});
    for (final forbidden in ['user_id', 'userId', 'email', 'name', 'consultation_fee', 'consultation_duration', 'documents']) { expect(payload.containsKey(forbidden), isFalse); }
    expect(dio.bodies[3], <String, dynamic>{});
    expect(dio.contentTypes.whereType<String>().every((type) => !type.contains('multipart')), isTrue);
  });
}

class _RecordingDio {
  _RecordingDio() : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      paths.add(options.path); methods.add(options.method); bodies.add(options.data); contentTypes.add(options.contentType);
      final body = options.path == '/specialties' ? {'success': true, 'data': [{'id': 'specialty-1', 'name_en': 'Cardiology', 'name_ar': 'Cardiology'}]} : options.path == '/doctor-applications/me' ? {'success': true, 'data': <Map<String, dynamic>>[]} : {'success': true, 'data': _application()};
      handler.resolve(Response(requestOptions: options, data: body, statusCode: 200));
    }));
  }
  final Dio dio; final paths = <String>[]; final methods = <String>[]; final bodies = <Object?>[]; final contentTypes = <String?>[];
}

Map<String, dynamic> _application() => {'id': 'application-1', 'user_id': 'user-1', 'specialty_id': 'specialty-1', 'medical_license_number': 'LIC', 'status': 'pending', 'submitted_at': '2026-01-02T00:00:00Z', 'education': <String>[], 'certifications': <String>[]};
