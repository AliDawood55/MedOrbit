import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/storage_keys.dart';
import 'package:mobile/core/network/api_exception.dart';
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

  group('AuthController.resetPassword', () {
    test(
      'rejects a duplicate in-flight reset and preserves exact inputs',
      () async {
        final pending = Completer<void>();
        final storage = SecureStorageService(
          storage: _InMemorySecureStorage({}),
        );
        final repository = _ResetRepository(storage, pending: pending);
        final controller = AuthController(
          repository,
          GoogleAuthService(),
          storage,
        );
        addTearDown(controller.dispose);

        final first = controller.resetPassword(
          token: 'token+/_=-value',
          newPassword: 'Strong1!',
        );
        final duplicate = await controller.resetPassword(
          token: 'different-token',
          newPassword: 'Different2@',
        );

        expect(duplicate, isFalse);
        expect(repository.calls, 1);
        expect(repository.tokens, ['token+/_=-value']);
        expect(repository.passwords, ['Strong1!']);
        expect(controller.state.isSubmitting, isTrue);

        pending.complete();
        expect(await first, isTrue);
        expect(controller.state.isSubmitting, isFalse);
      },
    );

    test('preserves ApiException code and internal message', () async {
      const failure = ApiException(
        message: 'Invalid or expired token from provider',
        code: 'INVALID_TOKEN',
        statusCode: 400,
      );
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final controller = AuthController(
        _ResetRepository(storage, error: failure),
        GoogleAuthService(),
        storage,
      );
      addTearDown(controller.dispose);

      final result = await controller.resetPassword(
        token: 'reset-token',
        newPassword: 'Strong1!',
      );

      expect(result, isFalse);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorCode, 'INVALID_TOKEN');
      expect(
        controller.state.errorMessage,
        'Invalid or expired token from provider',
      );
    });

    test('recovers from an unexpected repository exception', () async {
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final controller = AuthController(
        _ResetRepository(storage, error: StateError('repository failure')),
        GoogleAuthService(),
        storage,
      );
      addTearDown(controller.dispose);

      final result = await controller.resetPassword(
        token: 'reset-token',
        newPassword: 'Strong1!',
      );

      expect(result, isFalse);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorCode, ApiException.codeUnknown);
    });
  });

  group('AuthController.verifyEmail', () {
    test('rejects a duplicate in-flight verify and preserves exact inputs', () async {
      final pending = Completer<void>();
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final repository = _VerifyRepository(storage, pending: pending);
      final controller = AuthController(repository, GoogleAuthService(), storage);
      addTearDown(controller.dispose);

      final first = controller.verifyEmail(token: '123456', email: 'user@example.com');
      final duplicate = await controller.verifyEmail(token: 'other', email: 'x@y.z');

      expect(duplicate, isFalse);
      expect(repository.verifyCalls, [(token: '123456', email: 'user@example.com')]);
      expect(controller.state.isSubmitting, isTrue);

      pending.complete();
      expect(await first, isTrue);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorMessage, isNull);
    });

    test('preserves the ApiException code and internal message', () async {
      const failure = ApiException(
        message: 'Verification token has expired',
        code: 'VERIFICATION_TOKEN_EXPIRED',
        statusCode: 410,
      );
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final controller = AuthController(
        _VerifyRepository(storage, error: failure),
        GoogleAuthService(),
        storage,
      );
      addTearDown(controller.dispose);

      final result = await controller.verifyEmail(token: '123456', email: 'user@example.com');

      expect(result, isFalse);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorCode, 'VERIFICATION_TOKEN_EXPIRED');
      expect(controller.state.errorMessage, 'Verification token has expired');
    });

    test('recovers from an unexpected repository exception without leaking it', () async {
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final controller = AuthController(
        _VerifyRepository(storage, error: StateError('boom')),
        GoogleAuthService(),
        storage,
      );
      addTearDown(controller.dispose);

      final result = await controller.verifyEmail(token: '123456', email: 'user@example.com');

      expect(result, isFalse);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorCode, ApiException.codeUnknown);
      expect(controller.state.errorMessage, isNot(contains('boom')));
    });
  });

  group('AuthController.resendVerification', () {
    test('rejects a duplicate in-flight resend and preserves the exact email', () async {
      final pending = Completer<void>();
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final repository = _VerifyRepository(storage, pending: pending);
      final controller = AuthController(repository, GoogleAuthService(), storage);
      addTearDown(controller.dispose);

      final first = controller.resendVerification('user@example.com');
      final duplicate = await controller.resendVerification('other@example.com');

      expect(duplicate, isFalse);
      expect(repository.resendCalls, ['user@example.com']);

      pending.complete();
      expect(await first, isTrue);
      expect(controller.state.isSubmitting, isFalse);
    });

    test('recovers from an unexpected repository exception without leaking it', () async {
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final controller = AuthController(
        _VerifyRepository(storage, error: StateError('boom')),
        GoogleAuthService(),
        storage,
      );
      addTearDown(controller.dispose);

      final result = await controller.resendVerification('user@example.com');

      expect(result, isFalse);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorCode, ApiException.codeUnknown);
      expect(controller.state.errorMessage, isNot(contains('boom')));
    });

    test('preserves the ApiException code and message on a RATE_LIMITED failure', () async {
      const failure = ApiException(
        message: 'Too many resend attempts',
        code: 'RATE_LIMITED',
        statusCode: 429,
      );
      final storage = SecureStorageService(storage: _InMemorySecureStorage({}));
      final controller = AuthController(
        _VerifyRepository(storage, error: failure),
        GoogleAuthService(),
        storage,
      );
      addTearDown(controller.dispose);

      final result = await controller.resendVerification('user@example.com');

      expect(result, isFalse);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorCode, 'RATE_LIMITED');
      expect(controller.state.errorMessage, 'Too many resend attempts');
    });
  });
}

AuthController _controller(Map<String, String> seed) => _controllerFor(_InMemorySecureStorage(seed));

AuthController _controllerFor(FlutterSecureStorage backing) {
  final storage = SecureStorageService(storage: backing);
  final repository = AuthRepository(AuthApi(Dio()), storage);
  return AuthController(repository, GoogleAuthService(), storage);
}

class _ResetRepository extends AuthRepository {
  _ResetRepository(SecureStorageService storage, {this.pending, this.error})
    : super(AuthApi(Dio()), storage);

  final Completer<void>? pending;
  final Object? error;
  final List<String> tokens = [];
  final List<String> passwords = [];
  int calls = 0;

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    calls++;
    tokens.add(token);
    passwords.add(newPassword);
    await pending?.future;
    if (error != null) throw error!;
  }
}

class _VerifyRepository extends AuthRepository {
  _VerifyRepository(SecureStorageService storage, {this.pending, this.error})
    : super(AuthApi(Dio()), storage);

  final Completer<void>? pending;
  final Object? error;
  final List<({String token, String? email})> verifyCalls = [];
  final List<String> resendCalls = [];

  @override
  Future<void> verifyEmail({required String token, String? email}) async {
    verifyCalls.add((token: token, email: email));
    await pending?.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> resendVerification(String email) async {
    resendCalls.add(email);
    await pending?.future;
    if (error != null) throw error!;
  }
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
