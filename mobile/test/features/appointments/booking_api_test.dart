import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/appointments/data/booking_api.dart';

/// Awaits [future] and returns the [DioException] it throws — a normal
/// `throwsA` matcher can't inspect the exception further and then use it, so
/// tests that both check propagation and feed it into
/// [ApiException.fromDioException] need the object itself.
Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

void main() {
  test('availableSlots uses exact endpoint and snake_case query fields', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': [
          {'start_time': '09:00:00', 'end_time': '17:00:00', 'slot_duration': 30, 'is_telemedicine': false},
        ],
      }),
    ]);
    final api = BookingApi(fake.dio);

    final windows = await api.availableSlots(doctorId: 'doctor-1', clinicId: 'clinic-1', date: '2026-08-10');

    expect(fake.requests.single.method, 'GET');
    expect(fake.requests.single.path, '/appointments/available-slots');
    expect(fake.requests.single.queryParameters, {'doctor_id': 'doctor-1', 'clinic_id': 'clinic-1', 'date': '2026-08-10'});
    expect(windows, hasLength(1));
    expect(windows.single.startTime, '09:00:00');
    expect(windows.single.slotDurationMinutes, 30);
    expect(windows.single.isTelemedicine, false);
  });

  test('availableSlots throws INVALID_RESPONSE when data is not a list', () async {
    final fake = _FakeDio([
      _ok({'success': true, 'data': {'not': 'a list'}}),
    ]);
    final api = BookingApi(fake.dio);

    await expectLater(
      api.availableSlots(doctorId: 'd', clinicId: 'c', date: '2026-08-10'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
    );
  });

  test('availableSlots throws BACKEND_FAILURE on success:false without leaking the raw body', () async {
    final fake = _FakeDio([
      _ok({'success': false, 'data': {'internal': 'details'}}),
    ]);
    final api = BookingApi(fake.dio);

    await expectLater(
      api.availableSlots(doctorId: 'd', clinicId: 'c', date: '2026-08-10'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'BACKEND_FAILURE')
            .having((e) => e.message, 'message', isNot(contains('internal'))),
      ),
    );
  });

  test('create sends exact snake_case payload fields and parses the returned appointment', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': {
          'id': 'appt-1',
          'appointment_number': 'APT-482913',
          'doctor_id': 'doctor-1',
          'clinic_id': 'clinic-1',
          'scheduled_date': '2026-08-10',
          'start_time': '09:00:00',
          'end_time': '09:30:00',
          'appointment_type': 'in_person',
          'status': 'scheduled',
          'reason_for_visit': null,
        },
      }),
    ]);
    final api = BookingApi(fake.dio);

    final appointment = await api.create(
      doctorId: 'doctor-1',
      clinicId: 'clinic-1',
      scheduledDate: '2026-08-10',
      startTime: '09:00:00',
      endTime: '09:30:00',
      durationMinutes: 30,
      appointmentType: 'in_person',
      reasonForVisit: null,
      notes: null,
    );

    expect(fake.requests.single.method, 'POST');
    expect(fake.requests.single.path, '/appointments');
    expect(fake.requests.single.data, {
      'doctor_id': 'doctor-1',
      'clinic_id': 'clinic-1',
      'scheduled_date': '2026-08-10',
      'start_time': '09:00:00',
      'end_time': '09:30:00',
      'duration_minutes': 30,
      'appointment_type': 'in_person',
      'reason_for_visit': null,
      'notes': null,
    });
    expect(appointment.appointmentNumber, 'APT-482913');
    expect(appointment.status, 'scheduled');
  });

  // `create`/`availableSlots` don't catch Dio errors themselves — in
  // production, `DioClient`'s `ErrorInterceptor` normalizes every
  // `DioException` into one carrying an `ApiException` in `.error` before it
  // ever reaches these methods (see error_interceptor.dart, and
  // network_log_interceptor_test.dart for that interceptor's own coverage).
  // These tests confirm the two things that are actually this file's
  // responsibility: the raw exception passes through unmodified (nothing
  // here re-wraps or discards it), and once normalized, `ApiException`
  // carries the right code with no raw body leaking into the message.
  test('SLOT_BUSY conflict propagates untouched and normalizes to code SLOT_BUSY, not a raw response body', () async {
    final fake = _FakeDio([
      _httpError(
        statusCode: 400,
        body: {
          'success': false,
          'error': {'code': 'SLOT_BUSY', 'message': 'Appointment slot already booked'},
        },
      ),
    ]);
    final api = BookingApi(fake.dio);

    final dioError = await _captureDioException(
      api.create(
        doctorId: 'd',
        clinicId: 'c',
        scheduledDate: '2026-08-10',
        startTime: '09:00:00',
        endTime: '09:30:00',
        durationMinutes: 30,
        appointmentType: 'in_person',
      ),
    );

    final normalized = ApiException.fromDioException(dioError);
    expect(normalized.code, 'SLOT_BUSY');
    expect(normalized.message, 'Appointment slot already booked');
    expect(normalized.message, isNot(contains('success')));
    expect(normalized.message, isNot(contains('{')));
  });

  test('a receive timeout propagates untouched and normalizes to ApiException.codeReceiveTimeout', () async {
    final fake = _FakeDio([_timeout()]);
    final api = BookingApi(fake.dio);

    final dioError = await _captureDioException(api.availableSlots(doctorId: 'd', clinicId: 'c', date: '2026-08-10'));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeReceiveTimeout);
  });

  test('an unreachable service propagates untouched and normalizes to ApiException.codeServiceUnavailable', () async {
    final fake = _FakeDio([_connectionError()]);
    final api = BookingApi(fake.dio);

    final dioError = await _captureDioException(
      api.create(
        doctorId: 'd',
        clinicId: 'c',
        scheduledDate: '2026-08-10',
        startTime: '09:00:00',
        endTime: '09:30:00',
        durationMinutes: 30,
        appointmentType: 'in_person',
      ),
    );

    expect(ApiException.fromDioException(dioError).code, ApiException.codeServiceUnavailable);
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': {
          'id': 'appt-1',
          'appointment_number': 'APT-1',
          'doctor_id': 'd',
          'scheduled_date': '2026-08-10',
          'start_time': '09:00:00',
          'end_time': '09:30:00',
          'status': 'scheduled',
        },
      }),
    ]);
    final api = BookingApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      () => api.create(
        doctorId: 'd',
        clinicId: 'c',
        scheduledDate: '2026-08-10',
        startTime: '09:00:00',
        endTime: '09:30:00',
        durationMinutes: 30,
        appointmentType: 'in_person',
        reasonForVisit: 'Persistent private medical detail',
        notes: 'Private note',
      ),
      zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
    );

    expect(printed, isEmpty);
  });
}

/// A queued fake response: either resolve with [body], or reject with
/// [error] — used to simulate both success envelopes and the DioExceptions a
/// real HTTP failure produces once [ErrorInterceptor] normalizes them.
class _QueuedResponse {
  const _QueuedResponse.ok(this.body) : error = null;
  const _QueuedResponse.error(this.error) : body = null;

  final Map<String, dynamic>? body;
  final DioException Function(RequestOptions options)? error;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

_QueuedResponse _httpError({required int statusCode, required Map<String, dynamic> body}) {
  return _QueuedResponse.error(
    (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, dynamic>>(requestOptions: options, statusCode: statusCode, data: body),
    ),
  );
}

_QueuedResponse _timeout() {
  return _QueuedResponse.error(
    (options) => DioException(requestOptions: options, type: DioExceptionType.receiveTimeout),
  );
}

_QueuedResponse _connectionError() {
  return _QueuedResponse.error(
    (options) => DioException(requestOptions: options, type: DioExceptionType.connectionError),
  );
}

class _FakeDio {
  _FakeDio(List<_QueuedResponse> responses) : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(
            _RecordedRequest(
              method: options.method,
              path: options.path,
              data: options.data,
              queryParameters: Map<String, dynamic>.from(options.queryParameters),
            ),
          );
          final next = responses.removeAt(0);
          if (next.error != null) {
            handler.reject(next.error!(options));
          } else {
            handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: next.body));
          }
        },
      ),
    ]);
  }

  final Dio dio;
  final requests = <_RecordedRequest>[];
}

class _RecordedRequest {
  const _RecordedRequest({required this.method, required this.path, required this.data, required this.queryParameters});

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic> queryParameters;
}
