import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/doctor_workspace/data/doctor_schedule_api.dart';

void main() {
  test('loads the doctor-owned schedule and preserves patient names', () async {
    final fake = _FakeDio({
      'success': true,
      'data': {
        'doctor': {'is_accepting_patients': true},
        'weekly': [],
        'overrides': [],
        'appointments': [
          {
            'id': 'appointment-1',
            'appointment_number': 'APT-001',
            'scheduled_date': '2026-08-28',
            'start_time': '09:00:00',
            'end_time': '09:30:00',
            'appointment_type': 'telemedicine',
            'status': 'scheduled',
            'first_name_en': 'Sami',
            'last_name_en': 'Ahmad',
          },
        ],
      },
    });

    final schedule = await DoctorScheduleApi(fake.dio).load();

    expect(fake.path, '/doctors/me/schedule');
    expect(schedule.isAcceptingPatients, isTrue);
    expect(schedule.appointments.single.patientName(false), 'Sami Ahmad');
  });

  test('uses doctor-only appointment transition endpoints', () async {
    final fake = _FakeDio({
      'success': true,
      'data': {
        'id': 'appointment-1',
        'appointment_number': 'APT-001',
        'scheduled_date': '2026-08-28',
        'start_time': '09:00:00',
        'end_time': '09:30:00',
        'status': 'confirmed',
      },
    });

    await DoctorScheduleApi(fake.dio).confirm('appointment-1');

    expect(fake.method, 'PUT');
    expect(fake.path, '/appointments/appointment-1/confirm');
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
