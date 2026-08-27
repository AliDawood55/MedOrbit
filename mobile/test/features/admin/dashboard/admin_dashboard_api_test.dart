import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/dashboard/data/admin_dashboard_api.dart';

void main() {
  test('loads the existing admin dashboard statistics envelope', () async {
    final fake = _FakeDio({
      'success': true,
      'data': {
        'users': {'total': '32', 'patients': '28', 'doctors': '5'},
        'appointments': {'total': '11'},
        'medical_records': {'total': '2'},
        'prescriptions': {'total': '4'},
        'ratings': {'average': '4.5'},
      },
    });

    final stats = await AdminDashboardApi(fake.dio).getStats();

    expect(fake.path, '/dashboard/stats');
    expect(stats.usersTotal, 32);
    expect(stats.patients, 28);
    expect(stats.doctors, 5);
    expect(stats.appointmentsTotal, 11);
    expect(stats.recordsTotal, 2);
    expect(stats.prescriptionsTotal, 4);
    expect(stats.averageRating, 4.5);
  });
}

class _FakeDio {
  _FakeDio(this.body) : dio = Dio() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
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
}
