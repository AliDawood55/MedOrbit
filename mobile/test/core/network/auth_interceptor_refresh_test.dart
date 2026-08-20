import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/storage_keys.dart';
import 'package:mobile/core/network/auth_interceptor.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';

void main() {
  late _InMemorySecureStorage backing;
  late SecureStorageService storage;

  setUp(() {
    backing = _InMemorySecureStorage({
      StorageKeys.accessToken: 'expired-access',
      StorageKeys.refreshToken: 'valid-refresh',
      StorageKeys.user: '{"id":"u1"}',
      StorageKeys.languageCode: 'ar',
    });
    storage = SecureStorageService(storage: backing);
  });

  group('bearer injection', () {
    test('attaches the persisted access token to a protected request', () async {
      final server = _FakeServer()..enqueue(_Reply.ok());
      final dio = _client(storage, server);

      await dio.get<dynamic>('/patients/me/records');

      expect(server.requests.single.headers['Authorization'], 'Bearer expired-access');
    });

    test('never attaches a bearer token to an auth endpoint', () async {
      final server = _FakeServer()
        ..enqueue(_Reply.ok())
        ..enqueue(_Reply.ok())
        ..enqueue(_Reply.ok());
      final dio = _client(storage, server);

      await dio.post<dynamic>('/auth/login');
      await dio.post<dynamic>('/auth/refresh');
      await dio.post<dynamic>('/auth/logout');

      for (final request in server.requests) {
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
    });
  });

  group('401 refresh', () {
    test('refreshes once, retries once, and replays with the new token', () async {
      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.refreshed('fresh-access', 'fresh-refresh'))
        ..enqueue(_Reply.ok());
      final dio = _client(storage, server);

      final response = await dio.get<dynamic>('/patients/me/records');

      expect(response.statusCode, 200);
      expect(server.paths, ['/patients/me/records', '/auth/refresh', '/patients/me/records']);
      expect(server.requests.last.headers['Authorization'], 'Bearer fresh-access');
      expect(await storage.getAccessToken(), 'fresh-access');
      expect(await storage.getRefreshToken(), 'fresh-refresh');
    });

    test('two concurrent 401s trigger exactly one refresh', () async {
      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.refreshed('fresh-access', 'fresh-refresh'))
        ..enqueue(_Reply.ok())
        ..enqueue(_Reply.ok());
      final dio = _client(storage, server);

      await Future.wait([
        dio.get<dynamic>('/patients/me/records'),
        dio.get<dynamic>('/patients/me/prescriptions'),
      ]);

      expect(server.paths.where((p) => p == '/auth/refresh'), hasLength(1));
    });

    test('a retried request that 401s again is not refreshed a second time', () async {
      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.refreshed('fresh-access', 'fresh-refresh'))
        ..enqueue(_Reply.unauthorized());
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      expect(server.paths.where((p) => p == '/auth/refresh'), hasLength(1));
    });

    test('a non-401 failure never triggers a refresh', () async {
      final server = _FakeServer()..enqueue(_Reply.status(500));
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      expect(server.paths, ['/patients/me/records']);
    });
  });

  group('refresh failure clears the session', () {
    test('a rejected refresh clears tokens and the cached user', () async {
      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.status(401));
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getUserJson(), isNull);
    });

    test('a malformed refresh payload is treated as a failure', () async {
      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.body({'data': {'accessToken': 'only-half'}}));
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('clearing the session notifies listeners so auth state can react', () async {
      final cleared = Completer<void>();
      final subscription = storage.onSessionCleared.listen((_) {
        if (!cleared.isCompleted) cleared.complete();
      });
      addTearDown(subscription.cancel);

      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.status(401));
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      await expectLater(cleared.future.timeout(const Duration(seconds: 2)), completes);
    });

    test('the persisted language survives a session clear', () async {
      // Deliberate: an expired session should not silently flip an Arabic-first
      // patient back to the default locale on the login screen.
      final server = _FakeServer()
        ..enqueue(_Reply.unauthorized())
        ..enqueue(_Reply.status(401));
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      expect(await storage.getLanguageCode(), 'ar');
    });

    test('a missing refresh token clears the session without calling the server', () async {
      await backing.delete(key: StorageKeys.refreshToken);
      final server = _FakeServer()..enqueue(_Reply.unauthorized());
      final dio = _client(storage, server);

      await expectLater(
        dio.get<dynamic>('/patients/me/records'),
        throwsA(isA<DioException>()),
      );

      expect(server.paths, ['/patients/me/records']);
      expect(await storage.getAccessToken(), isNull);
    });
  });
}

/// Builds the main client the way `DioClient` does — an `AuthInterceptor`
/// holding a separate, interceptor-free refresh client. Both are pointed at the
/// same fake transport so refresh and replay traffic is observable.
Dio _client(SecureStorageService storage, _FakeServer server) {
  final refreshClient = Dio(BaseOptions(baseUrl: 'https://api.example.test/api'))
    ..httpClientAdapter = server;

  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api'))
    ..httpClientAdapter = server;
  dio.interceptors.add(AuthInterceptor(storage, refreshClient));
  return dio;
}

/// A scripted transport shared by both clients, so ordering across the original
/// request, the refresh and the replay is asserted in one place.
///
/// Implemented as an [HttpClientAdapter] rather than an interceptor on purpose:
/// a request interceptor that rejects short-circuits the chain, so
/// `AuthInterceptor.onError` would never run and the 401 path under test would
/// be skipped entirely. Substituting the transport keeps the full interceptor
/// chain live, exactly as a real server would.
class _FakeServer implements HttpClientAdapter {
  final List<_Reply> _replies = [];
  final List<RequestOptions> requests = [];

  List<String> get paths => requests.map((r) => r.path).toList();

  void enqueue(_Reply reply) => _replies.add(reply);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = _replies.isEmpty ? _Reply.status(500) : _replies.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  const _Reply(this.statusCode, this.body);

  factory _Reply.ok() => const _Reply(200, {'success': true, 'data': {}});
  factory _Reply.status(int code) => _Reply(code, const {'success': false});
  factory _Reply.body(Map<String, dynamic> body) => _Reply(200, body);
  factory _Reply.unauthorized() => const _Reply(401, {'success': false});

  factory _Reply.refreshed(String accessToken, String refreshToken) => _Reply(200, {
        'success': true,
        'data': {'accessToken': accessToken, 'refreshToken': refreshToken},
      });

  final int statusCode;
  final Map<String, dynamic> body;
}

/// Stands in for the platform keystore. `SecureStorageService` already accepts
/// an injected `FlutterSecureStorage`, so no mocking package is needed.
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
  }) async =>
      _values[key];

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
