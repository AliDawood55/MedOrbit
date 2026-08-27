import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/management/data/admin_management_api.dart';

void main() {
  test(
    'loads pending doctor applications through the admin endpoint',
    () async {
      final fake = _FakeDio({
        'success': true,
        'data': [
          {
            'id': 'application-1',
            'status': 'pending',
            'medical_license_number': 'P-123',
            'applicant': {
              'email': 'doctor@example.test',
              'first_name_en': 'Amina',
              'last_name_en': 'Khalil',
            },
            'specialty': {'name_en': 'Family medicine'},
          },
        ],
      });

      final applications = await AdminManagementApi(
        fake.dio,
      ).applications(isArabic: false);

      expect(fake.path, '/admin/doctor-applications?status=pending');
      expect(applications.single.name, 'Amina Khalil');
      expect(applications.single.specialty, 'Family medicine');
      expect(applications.single.license, 'P-123');
    },
  );

  test('uses the protected activation endpoint for an admin action', () async {
    final fake = _FakeDio({'success': true, 'data': {}});

    await AdminManagementApi(fake.dio).setUserActive('user-1', false);

    expect(fake.path, '/admin/users/user-1/deactivate');
    expect(fake.method, 'PUT');
  });
}

class _FakeDio {
  _FakeDio(this.body) : dio = Dio() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
          method = options.method;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: body,
            ),
          );
        },
      ),
    );
  }
  final Map<String, dynamic> body;
  final Dio dio;
  String? path;
  String? method;
}
