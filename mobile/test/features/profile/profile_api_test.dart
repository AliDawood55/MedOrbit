import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/profile/data/profile_api.dart';
import 'package:mobile/features/profile/models/profile_edit_model.dart';

Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

void main() {
  test('getMe() hits GET /users/me and parses every field', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': {
          'id': 'user-1',
          'email': 'sara@example.com',
          'role': 'patient',
          'first_name_ar': 'سارة',
          'last_name_ar': 'أحمد',
          'first_name_en': 'Sara',
          'last_name_en': 'Ahmad',
          'phone': '+970-59-1234567',
          'gender': 'female',
          'avatar_url': '/uploads/avatars/1.jpg',
          'address': 'Rafidia',
          'city': 'Nablus',
          'preferred_language': 'ar',
          'created_at': '2026-01-05T09:00:00.000Z',
        },
      }),
    ]);
    final api = ProfileApi(fake.dio);

    final profile = await api.getMe();

    expect(fake.requests.single.method, 'GET');
    expect(fake.requests.single.path, '/users/me');
    expect(profile.firstNameEn, 'Sara');
    expect(profile.phone, '+970-59-1234567');
    expect(profile.city, 'Nablus');
    expect(profile.preferredLanguage, 'ar');
  });

  test(
    'updateMe() PUTs /users/me with exact camelCase payload fields',
    () async {
      final fake = _FakeDio([
        _ok({'success': true, 'data': null}),
      ]);
      final api = ProfileApi(fake.dio);

      await api.updateMe(
        const ProfileEditModel(
          firstNameAr: 'سارة',
          lastNameAr: 'أحمد',
          firstNameEn: 'Sara',
          lastNameEn: 'Ahmad',
          phone: '0591234567',
          gender: 'female',
          address: 'Rafidia',
          city: 'Nablus',
        ),
      );

      expect(fake.requests.single.method, 'PUT');
      expect(fake.requests.single.path, '/users/me');
      expect(fake.requests.single.data, {
        'firstNameAr': 'سارة',
        'lastNameAr': 'أحمد',
        'firstNameEn': 'Sara',
        'lastNameEn': 'Ahmad',
        'phone': '0591234567',
        'gender': 'female',
        'address': 'Rafidia',
        'city': 'Nablus',
      });
    },
  );

  test(
    'updateLanguagePreference() PUTs /users/me/preferences with just { language }',
    () async {
      final fake = _FakeDio([
        _ok({'success': true, 'data': null}),
      ]);
      final api = ProfileApi(fake.dio);

      await api.updateLanguagePreference('en');

      expect(fake.requests.single.method, 'PUT');
      expect(fake.requests.single.path, '/users/me/preferences');
      expect(fake.requests.single.data, {'language': 'en'});
    },
  );

  test(
    'uploadAvatar() POSTs multipart field name "avatar" and returns the new relative path',
    () async {
      final fake = _FakeDio([
        _ok({
          'success': true,
          'data': {'avatar': '/uploads/avatars/1700000000000.png'},
        }),
      ]);
      final api = ProfileApi(fake.dio);
      final tempFile = await _writeTempImage();
      addTearDown(() => tempFile.delete());

      final avatarPath = await api.uploadAvatar(
        filePath: tempFile.path,
        fileName: 'photo.png',
      );

      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/users/me/avatar');
      final formData = fake.requests.single.data as FormData;
      expect(formData.files, hasLength(1));
      expect(formData.files.single.key, 'avatar');
      expect(formData.files.single.value.filename, 'photo.png');
      expect(avatarPath, '/uploads/avatars/1700000000000.png');
    },
  );

  test(
    'uploadAvatar() throws INVALID_RESPONSE when the avatar key is missing',
    () async {
      final fake = _FakeDio([
        _ok({'success': true, 'data': <String, dynamic>{}}),
      ]);
      final api = ProfileApi(fake.dio);
      final tempFile = await _writeTempImage();
      addTearDown(() => tempFile.delete());

      await expectLater(
        api.uploadAvatar(filePath: tempFile.path, fileName: 'photo.png'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    },
  );

  test(
    'changePassword() POSTs /auth/change-password with exact payload fields',
    () async {
      final fake = _FakeDio([
        _ok({'success': true, 'data': null}),
      ]);
      final api = ProfileApi(fake.dio);

      await api.changePassword(
        currentPassword: 'OldPass1!',
        newPassword: 'NewPass1!',
      );

      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/auth/change-password');
      expect(fake.requests.single.data, {
        'currentPassword': 'OldPass1!',
        'newPassword': 'NewPass1!',
      });
    },
  );

  test(
    'getMe() throws BACKEND_FAILURE on success:false without leaking the raw body',
    () async {
      final fake = _FakeDio([
        _ok({
          'success': false,
          'data': {'internal': 'details'},
        }),
      ]);
      final api = ProfileApi(fake.dio);

      await expectLater(
        api.getMe(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'BACKEND_FAILURE')
              .having((e) => e.message, 'message', isNot(contains('internal'))),
        ),
      );
    },
  );

  // These methods don't catch Dio errors themselves — in production,
  // `DioClient`'s `ErrorInterceptor` normalizes every `DioException` into one
  // carrying an `ApiException` in `.error` before it reaches here. These
  // confirm the raw exception passes through untouched and, once normalized,
  // carries a safe code with no raw body leaking into the message.
  test(
    'a wrong-current-password 400 from changePassword propagates untouched and normalizes safely',
    () async {
      final fake = _FakeDio([
        _httpError(
          statusCode: 400,
          body: {
            'success': false,
            'error': {
              'code': 'INVALID_CREDENTIALS',
              'message': 'Current password is incorrect',
            },
          },
        ),
      ]);
      final api = ProfileApi(fake.dio);

      final dioError = await _captureDioException(
        api.changePassword(currentPassword: 'wrong', newPassword: 'NewPass1!'),
      );
      final normalized = ApiException.fromDioException(dioError);

      expect(normalized.code, 'INVALID_CREDENTIALS');
      expect(normalized.message, 'Current password is incorrect');
      expect(normalized.message, isNot(contains('success')));
      expect(normalized.message, isNot(contains('{')));
    },
  );

  test(
    'a receive timeout on getMe() propagates untouched and normalizes to codeReceiveTimeout',
    () async {
      final fake = _FakeDio([_timeout()]);
      final api = ProfileApi(fake.dio);

      final dioError = await _captureDioException(api.getMe());

      expect(
        ApiException.fromDioException(dioError).code,
        ApiException.codeReceiveTimeout,
      );
    },
  );

  test(
    'an unreachable service on updateMe() propagates untouched and normalizes to codeServiceUnavailable',
    () async {
      final fake = _FakeDio([_connectionError()]);
      final api = ProfileApi(fake.dio);

      final dioError = await _captureDioException(
        api.updateMe(
          const ProfileEditModel(
            firstNameAr: 'س',
            lastNameAr: 'أ',
            firstNameEn: 'S',
            lastNameEn: 'A',
          ),
        ),
      );

      expect(
        ApiException.fromDioException(dioError).code,
        ApiException.codeServiceUnavailable,
      );
    },
  );

  test(
    'client does not print or manually log request or response bodies',
    () async {
      final fake = _FakeDio([
        _ok({
          'success': true,
          'data': {
            'id': 'user-1',
            'email': 'sara@example.com',
            'role': 'patient',
            'phone': '+970-59-1234567',
            'address': 'A private street address',
          },
        }),
      ]);
      final api = ProfileApi(fake.dio);
      final printed = <String>[];

      await runZoned(
        api.getMe,
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );

      expect(printed, isEmpty);
    },
  );
}

Future<File> _writeTempImage() async {
  final file = File(
    '${Directory.systemTemp.path}/medorbit_avatar_test_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(const [
    0x89,
    0x50,
    0x4E,
    0x47,
  ]); // PNG magic bytes — content doesn't matter for this test
  return file;
}

class _QueuedResponse {
  const _QueuedResponse.ok(this.body) : error = null;
  const _QueuedResponse.error(this.error) : body = null;

  final Map<String, dynamic>? body;
  final DioException Function(RequestOptions options)? error;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

_QueuedResponse _httpError({
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  return _QueuedResponse.error(
    (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: statusCode,
        data: body,
      ),
    ),
  );
}

_QueuedResponse _timeout() {
  return _QueuedResponse.error(
    (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
    ),
  );
}

_QueuedResponse _connectionError() {
  return _QueuedResponse.error(
    (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    ),
  );
}

class _FakeDio {
  _FakeDio(List<_QueuedResponse> responses)
    : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(
            _RecordedRequest(
              method: options.method,
              path: options.path,
              data: options.data,
            ),
          );
          final next = responses.removeAt(0);
          if (next.error != null) {
            handler.reject(next.error!(options));
          } else {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: next.body,
              ),
            );
          }
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_RecordedRequest>[];
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.data,
  });

  final String method;
  final String path;
  final dynamic data;
}
