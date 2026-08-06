import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/notifications/data/notifications_api.dart';

/// Awaits [future] and returns the [DioException] it throws.
Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

void main() {
  test('list() hits GET /notifications with no query params and parses each row', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': [
          {
            'id': 'notif-1',
            'notification_type': 'appointment',
            'title_ar': 'ع',
            'title_en': 'New appointment',
            'message_ar': 'م',
            'message_en': 'Confirmed',
            'is_read': false,
            'read_at': null,
            'created_at': '2026-08-05T09:00:00.000Z',
          },
        ],
      }),
    ]);
    final api = NotificationsApi(fake.dio);

    final result = await api.list();

    expect(fake.requests.single.method, 'GET');
    expect(fake.requests.single.path, '/notifications');
    expect(fake.requests.single.queryParameters, isEmpty);
    expect(result, hasLength(1));
    expect(result.single.id, 'notif-1');
    expect(result.single.titleEn, 'New appointment');
    expect(result.single.isRead, isFalse);
  });

  test('list() throws INVALID_RESPONSE when data is not a list', () async {
    final fake = _FakeDio([_ok({'success': true, 'data': {'not': 'a list'}})]);
    final api = NotificationsApi(fake.dio);

    await expectLater(api.list(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')));
  });

  test('list() throws BACKEND_FAILURE on success:false without leaking the raw body', () async {
    final fake = _FakeDio([_ok({'success': false, 'data': {'internal': 'details'}})]);
    final api = NotificationsApi(fake.dio);

    await expectLater(
      api.list(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'BACKEND_FAILURE')
            .having((e) => e.message, 'message', isNot(contains('internal'))),
      ),
    );
  });

  test('markRead() PUTs /notifications/:id/read and parses the full updated row', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': {
          'id': 'notif-1',
          'user_id': 'user-1',
          'notification_type': 'appointment',
          'title_ar': 'ع',
          'title_en': 'T',
          'message_ar': 'م',
          'message_en': 'M',
          'reference_id': 'appt-1',
          'reference_type': 'appointment',
          'channel': 'in_app',
          'is_read': true,
          'read_at': '2026-08-05T10:00:00.000Z',
          'email_sent_at': null,
          'created_at': '2026-08-05T09:00:00.000Z',
        },
      }),
    ]);
    final api = NotificationsApi(fake.dio);

    final updated = await api.markRead('notif-1');

    expect(fake.requests.single.method, 'PUT');
    expect(fake.requests.single.path, '/notifications/notif-1/read');
    expect(updated.isRead, isTrue);
    expect(updated.readAt, DateTime.parse('2026-08-05T10:00:00.000Z'));
  });

  test('markAllRead() PATCHes /notifications/read-all and returns the updated count', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': {'updated': 3},
      }),
    ]);
    final api = NotificationsApi(fake.dio);

    final updated = await api.markAllRead();

    expect(fake.requests.single.method, 'PATCH');
    expect(fake.requests.single.path, '/notifications/read-all');
    expect(updated, 3);
  });

  test('delete() DELETEs /notifications/:id and succeeds on a null data payload', () async {
    final fake = _FakeDio([
      _ok({'success': true, 'data': null}),
    ]);
    final api = NotificationsApi(fake.dio);

    await api.delete('notif-1');

    expect(fake.requests.single.method, 'DELETE');
    expect(fake.requests.single.path, '/notifications/notif-1');
  });

  // The API class doesn't catch Dio errors itself — in production,
  // `DioClient`'s `ErrorInterceptor` normalizes every `DioException` into one
  // carrying an `ApiException` in `.error` before it reaches these methods.
  // These confirm the raw exception passes through untouched and, once
  // normalized, carries the right code with no raw body leaking into the
  // message — matching the pattern in booking_api_test.dart.
  test('a 404 NOT_FOUND from markRead propagates untouched and normalizes safely', () async {
    final fake = _FakeDio([
      _httpError(
        statusCode: 404,
        body: {
          'success': false,
          'error': {'code': 'NOT_FOUND', 'message': 'Notification not found'},
        },
      ),
    ]);
    final api = NotificationsApi(fake.dio);

    final dioError = await _captureDioException(api.markRead('missing'));
    final normalized = ApiException.fromDioException(dioError);

    expect(normalized.code, 'NOT_FOUND');
    expect(normalized.message, 'Notification not found');
    expect(normalized.message, isNot(contains('success')));
    expect(normalized.message, isNot(contains('{')));
  });

  test('a receive timeout on list() propagates untouched and normalizes to codeReceiveTimeout', () async {
    final fake = _FakeDio([_timeout()]);
    final api = NotificationsApi(fake.dio);

    final dioError = await _captureDioException(api.list());

    expect(ApiException.fromDioException(dioError).code, ApiException.codeReceiveTimeout);
  });

  test('an unreachable service on delete() propagates untouched and normalizes to codeServiceUnavailable', () async {
    final fake = _FakeDio([_connectionError()]);
    final api = NotificationsApi(fake.dio);

    final dioError = await _captureDioException(api.delete('notif-1'));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeServiceUnavailable);
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': [
          {
            'id': 'notif-1',
            'notification_type': 'appointment',
            'title_ar': 'موعدك مع طبيب القلب غدًا',
            'title_en': 'Sensitive appointment title',
            'message_ar': 'م',
            'message_en': 'Sensitive medical message body',
            'is_read': false,
            'created_at': '2026-08-05T09:00:00.000Z',
          },
        ],
      }),
    ]);
    final api = NotificationsApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      api.list,
      zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
    );

    expect(printed, isEmpty);
  });
}

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
  return _QueuedResponse.error((options) => DioException(requestOptions: options, type: DioExceptionType.receiveTimeout));
}

_QueuedResponse _connectionError() {
  return _QueuedResponse.error((options) => DioException(requestOptions: options, type: DioExceptionType.connectionError));
}

class _FakeDio {
  _FakeDio(List<_QueuedResponse> responses) : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
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
    );
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
