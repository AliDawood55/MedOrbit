import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/dashboard/data/admin_dashboard_api.dart';

import '../admin_test_support.dart';

void main() {
  test('loads the admin dashboard statistics envelope from the exact path', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          // Uncast COUNT(*) columns arrive as strings through node-postgres.
          'users': {'total': '32', 'patients': '28', 'doctors': '5'},
          'appointments': {
            'total': '11',
            'completed': '6',
            'scheduled': '3',
            'cancelled': '2',
          },
          'medical_records': {'total': '2'},
          'prescriptions': {'total': '4'},
          'ratings': {'average': '4.5'},
        },
      });

    final stats = await AdminDashboardApi(dio.dio).getStats();

    expect(dio.paths, ['/dashboard/stats']);
    expect(dio.methods, ['GET']);
    expect(stats.usersTotal, 32);
    expect(stats.patients, 28);
    expect(stats.doctors, 5);
    expect(stats.appointmentsTotal, 11);
    expect(stats.appointmentsCompleted, 6);
    expect(stats.appointmentsScheduled, 3);
    expect(stats.appointmentsCancelled, 2);
    expect(stats.recordsTotal, 2);
    expect(stats.prescriptionsTotal, 4);
    expect(stats.averageRating, 4.5);
  });

  test('a payload with no analytics still parses, with every section unavailable', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          'users': {'total': 1},
        },
      });

    final stats = await AdminDashboardApi(dio.dio).getStats();

    expect(stats.usersTotal, 1);
    expect(stats.averageRating, isNull);
    expect(stats.analytics.isEntirelyUnavailable, isTrue);
  });

  test('a malformed envelope surfaces INVALID_RESPONSE, not a raw error', () async {
    final dio = RecordingDio()..enqueue({'success': true, 'data': 'nope'});

    await expectLater(
      AdminDashboardApi(dio.dio).getStats(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
      ),
    );
  });

  test('a 403 keeps the server code and drops the server message', () async {
    final dio = RecordingDio()..enqueueFailure(403, 'FORBIDDEN');

    try {
      await AdminDashboardApi(dio.dio).getStats();
      fail('expected a failure');
    } catch (error) {
      final failure = ApiException.from(error);
      expect(failure.code, 'FORBIDDEN');
    }
  });
}
