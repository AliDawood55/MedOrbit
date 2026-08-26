// Headless smoke test for the Virtual Doctor wiring.
//
// Runs the app's REAL authenticated `VirtualDoctorApi` against the backend
// gateway. The AI service is internal-only and is never called from here.
//
//   cd mobile && dart run tool/vd_smoke.dart [host]
//
// Everything it touches is pure Dart, so no Flutter engine is required.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';

Future<void> main(List<String> args) async {
  final apiBase = args.isNotEmpty ? args.first : AppConfig.baseUrl;
  final accessToken = Platform.environment['MEDORBIT_ACCESS_TOKEN']?.trim();
  if (accessToken == null || accessToken.isEmpty) {
    stderr.writeln('Set MEDORBIT_ACCESS_TOKEN to a signed-in patient access token.');
    exitCode = 64;
    return;
  }

  stdout.writeln('API base   : $apiBase');
  stdout.writeln('Virtual Doctor uses the authenticated backend gateway.');
  stdout.writeln('');

  // Matches the app API client: backend `/api` base plus a Bearer token.
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBase,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.aiMessageTimeout,
      sendTimeout: AppConfig.aiMessageTimeout,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $accessToken'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        stdout.writeln('→ ${options.method} ${options.uri}');
        final safeHeaders = Map<String, dynamic>.from(options.headers)..remove('Authorization');
        stdout.writeln('  headers: $safeHeaders');
        if (options.data != null) stdout.writeln('  body: ${options.data}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        stdout.writeln('← ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (err, handler) {
        stdout.writeln('✖ ${err.type.name} ${err.requestOptions.uri}');
        handler.next(err);
      },
    ),
  );

  final api = VirtualDoctorApi(dio);
  var failures = 0;

  Future<void> step(String label, Future<void> Function() body) async {
    stdout.writeln('--- $label ---');
    try {
      await body();
      stdout.writeln('PASS: $label\n');
    } on DioException catch (e, stack) {
      failures++;
      stdout.writeln('FAIL: $label');
      stdout.writeln('  DioExceptionType : ${e.type}');
      stdout.writeln('  message          : ${e.message}');
      stdout.writeln('  underlying error : ${e.error}  (${e.error.runtimeType})');
      stdout.writeln('  status           : ${e.response?.statusCode}');
      stdout.writeln('  response body    : ${e.response?.data}');
      stdout.writeln('  stack            :\n$stack\n');
    } catch (e, stack) {
      failures++;
      stdout.writeln('FAIL: $label');
      stdout.writeln('  ${e.runtimeType}: $e');
      stdout.writeln('  stack:\n$stack\n');
    }
  }

  String? sessionId;

  await step('POST /virtual-doctor/start', () async {
    final result = await api.start(language: 'en');
    sessionId = result.sessionId;
    stdout.writeln('  session_id : ${result.sessionId}');
    stdout.writeln('  language   : ${result.language}');
    stdout.writeln('  phase      : ${result.phase}');
    stdout.writeln('  reply      : ${result.reply}');
  });

  if (sessionId != null) {
    await step('POST /virtual-doctor/message', () async {
      final result = await api.sendMessage(sessionId: sessionId!, message: 'Ali');
      stdout.writeln('  phase : ${result.phase}');
      stdout.writeln('  reply : ${result.reply}');
    });
  }

  if (sessionId != null) {
    await step('POST /virtual-doctor/speak (TTS bytes)', () async {
      final bytes = await api.speak(text: 'Hello, this is a test.', language: 'en', sessionId: sessionId!);
      stdout.writeln('  wav bytes : ${bytes.length}');
      final isRiff = bytes.length > 4 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46;
      stdout.writeln('  RIFF/WAV header : $isRiff');
      if (!isRiff) throw StateError('response is not a WAV file');
    });
  }

  stdout.writeln(failures == 0 ? 'ALL STEPS PASSED' : '$failures STEP(S) FAILED');
  exit(failures == 0 ? 0 : 1);
}
