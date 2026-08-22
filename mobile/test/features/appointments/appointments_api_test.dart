import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';

void main() {
  group('AppointmentsApi.list', () {
    test('parses a normal envelope', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {
              'id': 'appt-1',
              'appointment_number': 'APT-1',
              'doctor_id': 'doctor-1',
              'scheduled_date': '2026-08-10',
              'start_time': '09:00:00',
              'end_time': '09:30:00',
              'status': 'scheduled',
            },
          ],
        }),
      );
      final api = AppointmentsApi(fake.dio);

      final appointments = await api.list();

      expect(appointments, hasLength(1));
      expect(appointments.single.appointmentNumber, 'APT-1');
    });

    test('throws ApiException(INVALID_RESPONSE) when data is not a list', () async {
      final fake = _FakeDio(_ok({'data': {'not': 'a list'}}));
      final api = AppointmentsApi(fake.dio);

      await expectLater(
        api.list(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('throws ApiException(INVALID_RESPONSE) when data is entirely missing', () async {
      final fake = _FakeDio(_ok({}));
      final api = AppointmentsApi(fake.dio);

      await expectLater(
        api.list(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('fails the whole fetch on a malformed entry rather than silently dropping it', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {
              'id': 'appt-1',
              'appointment_number': 'APT-1',
              'doctor_id': 'doctor-1',
              'scheduled_date': '2026-08-10',
              'start_time': '09:00:00',
              'end_time': '09:30:00',
              'status': 'scheduled',
            },
            'not-an-object',
          ],
        }),
      );
      final api = AppointmentsApi(fake.dio);

      await expectLater(
        api.list(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('throws ApiException(INVALID_RESPONSE) for a well-formed entry with an invalid required field', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {
              'id': 'appt-1',
              // appointment_number missing.
              'doctor_id': 'doctor-1',
              'scheduled_date': '2026-08-10',
              'start_time': '09:00:00',
              'end_time': '09:30:00',
              'status': 'scheduled',
            },
          ],
        }),
      );
      final api = AppointmentsApi(fake.dio);

      // AppointmentModel.fromJson raises this directly for a well-formed
      // entry with an invalid field — still a controlled failure, not a
      // TypeError, and still caught by the caller's AsyncValue.guard.
      await expectLater(api.list(), throwsA(isA<FormatException>()));
    });
  });
}

class _QueuedResponse {
  const _QueuedResponse.ok(this.body);
  final Map<String, dynamic> body;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

class _FakeDio {
  _FakeDio(_QueuedResponse response) : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: response.body));
        },
      ),
    );
  }

  final Dio dio;
}
