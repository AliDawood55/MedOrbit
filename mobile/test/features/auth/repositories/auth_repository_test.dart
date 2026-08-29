import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/storage_keys.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';

void main() {
  group('AuthRepository.login', () {
    test('persists tokens and user on a valid response', () async {
      final storage = _storage();
      final fake = _FakeDio(
        _ok({
          'data': {
            'user': {'id': 'u-1', 'email': 'a@b.com', 'role': 'patient', 'name': 'Alex'},
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
          },
        }),
      );
      final repository = AuthRepository(AuthApi(fake.dio), storage);

      final result = await repository.login(email: 'a@b.com', password: 'pw');

      expect(result.user.id, 'u-1');
      expect(await storage.getAccessToken(), 'access-1');
      expect(await storage.getRefreshToken(), 'refresh-1');
      expect(await storage.getUserJson(), isNotNull);
    });

    test('throws ApiException(INVALID_RESPONSE), not a raw FormatException, on a malformed body', () async {
      final storage = _storage();
      final fake = _FakeDio(
        _ok({
          'data': {'user': {'id': 'u-1', 'email': 'a@b.com', 'role': 'patient'}},
          // accessToken/refreshToken missing.
        }),
      );
      final repository = AuthRepository(AuthApi(fake.dio), storage);

      await expectLater(
        repository.login(email: 'a@b.com', password: 'pw'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('does not persist a session when the response is malformed', () async {
      final storage = _storage();
      final fake = _FakeDio(
        _ok({
          'data': {'user': {'id': 'u-1', 'email': 'a@b.com', 'role': 'patient'}},
        }),
      );
      final repository = AuthRepository(AuthApi(fake.dio), storage);

      await expectLater(repository.login(email: 'a@b.com', password: 'pw'), throwsA(isA<ApiException>()));
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getUserJson(), isNull);
    });
  });

  group('AuthRepository.register', () {
    test('throws ApiException(INVALID_RESPONSE) on a malformed user payload', () async {
      final storage = _storage();
      final fake = _FakeDio(_ok({'data': {'email': 'a@b.com', 'role': 'patient'}}));
      final repository = AuthRepository(AuthApi(fake.dio), storage);

      await expectLater(
        repository.register(
          email: 'a@b.com',
          password: 'pw',
          firstNameAr: 'أ',
          lastNameAr: 'ب',
          firstNameEn: 'A',
          lastNameEn: 'B',
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });
  });

  group('AuthRepository.getPersistedUser', () {
    test('returns the cached user for valid persisted JSON', () async {
      final storage = _storage({StorageKeys.user:'{"id":"u-1","email":"a@b.com","role":"patient"}'});
      final repository = AuthRepository(AuthApi(Dio()), storage);

      final user = await repository.getPersistedUser();

      expect(user?.id, 'u-1');
    });

    test('returns null instead of throwing for corrupted persisted JSON', () async {
      final storage = _storage({StorageKeys.user:'not-json{{{'});
      final repository = AuthRepository(AuthApi(Dio()), storage);

      expect(await repository.getPersistedUser(), isNull);
    });

    test('returns null instead of throwing when persisted user is missing required fields', () async {
      final storage = _storage({StorageKeys.user:'{"email":"a@b.com"}'});
      final repository = AuthRepository(AuthApi(Dio()), storage);

      expect(await repository.getPersistedUser(), isNull);
    });

    test('returns null instead of throwing when persisted JSON is a scalar, not an object', () async {
      final storage = _storage({StorageKeys.user:'"just-a-string"'});
      final repository = AuthRepository(AuthApi(Dio()), storage);

      expect(await repository.getPersistedUser(), isNull);
    });
  });
}

SecureStorageService _storage([Map<String, String>? seed]) =>
    SecureStorageService(storage: _InMemorySecureStorage(seed ?? {}));

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

class _QueuedResponse {
  const _QueuedResponse.ok(this.body);
  final Map<String, dynamic> body;
}

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

/// Stands in for the platform keystore, matching the fake already used in
/// `test/core/network/auth_interceptor_refresh_test.dart`.
class _InMemorySecureStorage implements FlutterSecureStorage {
  _InMemorySecureStorage(this._values);

  final Map<String, String> _values;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
