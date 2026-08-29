import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/storage_keys.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';

void main() {
  group('AuthController.checkAuthStatus', () {
    test('resolves to unauthenticated when no token is persisted', () async {
      final controller = _controller({});

      await controller.checkAuthStatus();

      expect(controller.state.status, AuthStatus.unauthenticated);
    });

    test('resolves to authenticated with the persisted user for a valid session', () async {
      final controller = _controller({
        StorageKeys.accessToken: 'access-1',
        StorageKeys.user: '{"id":"u-1","email":"a@b.com","role":"patient"}',
      });

      await controller.checkAuthStatus();

      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user?.id, 'u-1');
    });

    test(
      'a token with corrupted persisted user data resolves to unauthenticated instead of hanging or throwing',
      () async {
        final storage = _InMemorySecureStorage({
          StorageKeys.accessToken: 'access-1',
          StorageKeys.user: 'not-json{{{',
        });
        final controller = _controllerFor(storage);

        await controller.checkAuthStatus();

        expect(controller.state.status, AuthStatus.unauthenticated);
      },
    );

    test('a token with a persisted user missing required fields resolves to unauthenticated', () async {
      final storage = _InMemorySecureStorage({
        StorageKeys.accessToken: 'access-1',
        StorageKeys.user: '{"email":"a@b.com"}',
      });
      final controller = _controllerFor(storage);

      await controller.checkAuthStatus();

      expect(controller.state.status, AuthStatus.unauthenticated);
    });
  });
}

AuthController _controller(Map<String, String> seed) => _controllerFor(_InMemorySecureStorage(seed));

AuthController _controllerFor(FlutterSecureStorage backing) {
  final storage = SecureStorageService(storage: backing);
  final repository = AuthRepository(AuthApi(Dio()), storage);
  return AuthController(repository, GoogleAuthService(), storage);
}

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
