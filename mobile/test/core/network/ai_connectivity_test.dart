import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/ai_health_client.dart';

void main() {
  group('AI health probe', () {
    test('a 200 means the service is available', () async {
      final fake = _FakeAiDio.responding(200);

      expect(await AiHealthClient(fake.dio).check(), AiHealthStatus.available);
    });

    test('hits /health on the AI base with no /api prefix', () async {
      final fake = _FakeAiDio.responding(200);

      await AiHealthClient(fake.dio).check();

      expect(fake.requests.single.path, '/health');
      expect(fake.requests.single.uri.path, '/health');
      expect(fake.requests.single.uri.toString(), isNot(contains('/api')));
      expect(fake.requests.single.uri.port, AppConfig.aiServicePort);
    });

    test('applies a short bounded budget, not the 120s AI message timeout', () async {
      // The AI Dio carries a 120s receive budget for the inline reasoning turn.
      // A reachability probe inheriting that would leave a patient waiting two
      // minutes just to learn the host is unreachable.
      final fake = _FakeAiDio.responding(200);

      await AiHealthClient(fake.dio).check();

      final request = fake.requests.single;
      expect(request.connectTimeout, AppConfig.aiHealthTimeout);
      expect(request.receiveTimeout, AppConfig.aiHealthTimeout);
      expect(request.sendTimeout, AppConfig.aiHealthTimeout);
      expect(request.receiveTimeout, lessThan(AppConfig.aiMessageTimeout));
    });

    test('a receive timeout is reported as timedOut, not unreachable', () async {
      final fake = _FakeAiDio.failing(DioExceptionType.receiveTimeout);

      expect(await AiHealthClient(fake.dio).check(), AiHealthStatus.timedOut);
    });

    test('a connect timeout is reported as timedOut', () async {
      final fake = _FakeAiDio.failing(DioExceptionType.connectionTimeout);

      expect(await AiHealthClient(fake.dio).check(), AiHealthStatus.timedOut);
    });

    test('an unreachable service is distinguished from a slow one', () async {
      // This is the firewall/wrong-host case, and it must not be described to
      // the patient as "taking longer than expected".
      final fake = _FakeAiDio.failing(DioExceptionType.connectionError);

      expect(await AiHealthClient(fake.dio).check(), AiHealthStatus.unreachable);
    });

    test('a non-200 answer is unhealthy rather than available', () async {
      final fake = _FakeAiDio.responding(503);

      expect(await AiHealthClient(fake.dio).check(), AiHealthStatus.unhealthy);
    });

    test('an unexpected transport failure degrades to unhealthy', () async {
      final fake = _FakeAiDio.failing(DioExceptionType.badCertificate);

      expect(await AiHealthClient(fake.dio).check(), AiHealthStatus.unhealthy);
    });
  });

  group('result caching', () {
    test('a repeated check inside the TTL does not re-probe', () async {
      final fake = _FakeAiDio.responding(200);
      final client = AiHealthClient(fake.dio);

      await client.check();
      await client.check();
      await client.check();

      expect(fake.requests, hasLength(1));
    });

    test('force bypasses the cache', () async {
      final fake = _FakeAiDio.responding(200);
      final client = AiHealthClient(fake.dio);

      await client.check();
      await client.check(force: true);

      expect(fake.requests, hasLength(2));
    });

    test('invalidate makes the next check re-probe', () async {
      final fake = _FakeAiDio.responding(200);
      final client = AiHealthClient(fake.dio);

      await client.check();
      client.invalidate();
      await client.check();

      expect(fake.requests, hasLength(2));
    });
  });

  group('privacy', () {
    test('never logs, and never reads the health response body', () async {
      final printed = <String>[];
      final fake = _FakeAiDio.responding(
        200,
        body: {
          'model': 'qwen2:7b',
          'device': 'cuda',
          'host': '192.0.2.1',
          'sessions': ['private-session-id'],
        },
      );

      await runZoned(
        () async => AiHealthClient(fake.dio).check(),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );

      expect(printed, isEmpty);
    });

    test('carries no medical or identifying payload in the request', () async {
      final fake = _FakeAiDio.responding(200);

      await AiHealthClient(fake.dio).check();

      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(request.data, isNull);
      expect(request.queryParameters, isEmpty);
    });
  });
}

/// Interceptor-backed fake, matching the `_FakeDio` pattern in
/// `test/features/chatbot/chatbot_api_test.dart`. Records the fully-resolved
/// `RequestOptions` so per-request timeout overrides can be asserted.
class _FakeAiDio {
  _FakeAiDio._(void Function(RequestOptions, RequestInterceptorHandler) onRequest)
      : dio = Dio(BaseOptions(
          baseUrl: 'http://192.0.2.1:8001',
          // Mirrors aiDioProvider: a long budget the probe must override.
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.aiMessageTimeout,
          sendTimeout: AppConfig.aiMessageTimeout,
        )) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          onRequest(options, handler);
        },
      ),
    );
  }

  factory _FakeAiDio.responding(int statusCode, {Object? body}) {
    return _FakeAiDio._((options, handler) {
      handler.resolve(
        Response<dynamic>(requestOptions: options, statusCode: statusCode, data: body),
      );
    });
  }

  factory _FakeAiDio.failing(DioExceptionType type) {
    return _FakeAiDio._((options, handler) {
      handler.reject(DioException(requestOptions: options, type: type));
    });
  }

  final Dio dio;
  final List<RequestOptions> requests = [];
}
