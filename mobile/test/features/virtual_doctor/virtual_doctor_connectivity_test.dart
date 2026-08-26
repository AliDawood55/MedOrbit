import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/ai_health_client.dart';
import 'package:mobile/features/virtual_doctor/data/tts_player.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';
import 'package:mobile/features/virtual_doctor/data/voice_recorder.dart';
import 'package:mobile/features/virtual_doctor/models/consultation_models.dart';
import 'package:mobile/features/virtual_doctor/providers/virtual_doctor_provider.dart';

void main() {
  group('AI health preflight', () {
    test(
      'an unreachable service blocks the consultation with a safe state',
      () async {
        final harness = _Harness(health: AiHealthStatus.unreachable);
        addTearDown(harness.dispose);

        await harness.controller.startConsultation('ar');

        expect(harness.controller.state.state, ConsultState.error);
        expect(harness.controller.state.errorMessage, 'ai_unavailable');
      },
    );

    test('a failed preflight never asks for the microphone', () async {
      // Asking for a permission the app then cannot use is a bad prompt to
      // spend: the patient grants mic access and the consultation still fails.
      final harness = _Harness(health: AiHealthStatus.unreachable);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');

      expect(harness.recorder.permissionChecks, 0);
      expect(harness.recorder.startCalls, 0);
    });

    test('a failed preflight never calls the AI service', () async {
      final harness = _Harness(health: AiHealthStatus.timedOut);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');

      expect(harness.api.startCalls, 0);
      expect(harness.tts.speakCalls, 0);
    });

    test('every unhealthy status is treated as unavailable', () async {
      for (final status in [
        AiHealthStatus.unreachable,
        AiHealthStatus.timedOut,
        AiHealthStatus.unhealthy,
      ]) {
        final harness = _Harness(health: status);
        await harness.controller.startConsultation('ar');

        expect(
          harness.controller.state.errorMessage,
          'ai_unavailable',
          reason: '$status',
        );
        harness.dispose();
      }
    });

    test('a healthy service lets the consultation start', () async {
      final harness = _Harness(health: AiHealthStatus.available);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');

      expect(harness.api.startCalls, 1);
      expect(harness.recorder.permissionChecks, 1);
      expect(harness.controller.state.state, ConsultState.listening);
      expect(harness.controller.state.errorMessage, isNull);
    });
  });

  group('start failure categories', () {
    test('a connect timeout maps to the AI timeout message', () async {
      final harness = _Harness(
        startFailure: DioExceptionType.connectionTimeout,
      );
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');

      expect(harness.controller.state.state, ConsultState.error);
      expect(harness.controller.state.errorMessage, 'ai_timeout');
    });

    test('a receive timeout maps to the AI timeout message', () async {
      final harness = _Harness(startFailure: DioExceptionType.receiveTimeout);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');

      expect(harness.controller.state.errorMessage, 'ai_timeout');
    });

    test('a connection error is reported as unreachable, not slow', () async {
      final harness = _Harness(startFailure: DioExceptionType.connectionError);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');

      expect(harness.controller.state.errorMessage, 'ai_unreachable');
    });

    test(
      'an unclassified failure falls back to a mapped code, never a raw one',
      () async {
        // `start_${api.code}` used to produce codes like `start_UNKNOWN_ERROR`,
        // which the string mapper did not recognise and rendered verbatim.
        final harness = _Harness(startFailure: DioExceptionType.unknown);
        addTearDown(harness.dispose);

        await harness.controller.startConsultation('ar');

        final code = harness.controller.state.errorMessage!;
        expect(code, 'ai_failed');
        expect(code, isNot(contains('UNKNOWN_ERROR')));
        expect(const AppStrings(false).vdError(code), isNot(code));
      },
    );

    test('a failed start invalidates the cached health pass', () async {
      final harness = _Harness(startFailure: DioExceptionType.connectionError);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');
      await harness.controller.startConsultation('ar');

      // Without invalidation the second attempt would reuse the stale pass and
      // never re-probe a service that has since gone away.
      expect(harness.health.checks, 2);
    });
  });

  group('duplicate start', () {
    test('two rapid taps issue exactly one /virtual-doctor/start', () async {
      final harness = _Harness(
        health: AiHealthStatus.available,
        holdStart: true,
      );
      addTearDown(harness.dispose);

      final first = harness.controller.startConsultation('ar');
      final second = harness.controller.startConsultation('ar');
      harness.api.releaseStart();
      await Future.wait([first, second]);

      expect(harness.api.startCalls, 1);
    });

    test('a retry after the first attempt settles is allowed', () async {
      final harness = _Harness(startFailure: DioExceptionType.connectionError);
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('ar');
      harness.api.startFailure = null;
      await harness.controller.startConsultation('ar');

      expect(harness.api.startCalls, 2);
      expect(harness.controller.state.state, ConsultState.listening);
    });
  });

  group('safe error text', () {
    test('every code the controller can emit maps to a real message', () {
      const codes = [
        'ai_unavailable',
        'ai_timeout',
        'ai_unreachable',
        'ai_failed',
        'session_expired',
        'session_unavailable',
        'mic_denied',
        'no_speech',
        'stt_timeout',
        'record_failed',
        'report_failed',
        'microphone unavailable',
      ];

      for (final locale in [true, false]) {
        final strings = AppStrings(locale);
        for (final code in codes) {
          final text = strings.vdError(code);
          expect(text, isNot(code), reason: '$code leaked verbatim');
          expect(text, isNotEmpty);
        }
      }
    });

    test('an unrecognised code degrades to the generic message', () {
      const strings = AppStrings(false);

      expect(strings.vdError('start_UNKNOWN_ERROR'), strings.vdErrGeneric);
      expect(
        strings.vdError(r'FileSystemException: C:\patients\record.pdf'),
        strings.vdErrGeneric,
      );
    });

    test('the unavailable message names no host, port or diagnostic', () {
      for (final strings in [const AppStrings(true), const AppStrings(false)]) {
        final text = strings.aiServiceUnavailable;
        expect(text, isNot(contains('8001')));
        expect(text, isNot(contains('192.168')));
        expect(text, isNot(contains('http')));
      }
    });
  });
}

class _Harness {
  _Harness({
    AiHealthStatus health = AiHealthStatus.available,
    DioExceptionType? startFailure,
    bool holdStart = false,
  }) : health = _FakeHealth(health),
       api = _FakeApi(startFailure: startFailure, hold: holdStart),
       recorder = _FakeRecorder(),
       tts = _FakeTts() {
    controller = VirtualDoctorController(api, recorder, tts, this.health);
  }

  final _FakeHealth health;
  final _FakeApi api;
  final _FakeRecorder recorder;
  final _FakeTts tts;
  late final VirtualDoctorController controller;

  void dispose() => controller.dispose();
}

/// Subclassed rather than mocked — `AiHealthClient` takes a `Dio`, and the
/// controller only ever calls `check`/`invalidate`.
class _FakeHealth extends AiHealthClient {
  _FakeHealth(this.status) : super(Dio());

  final AiHealthStatus status;
  int checks = 0;

  @override
  Future<AiHealthStatus> check({bool force = false}) async {
    checks++;
    return status;
  }

  @override
  void invalidate() {}
}

class _FakeApi extends VirtualDoctorApi {
  _FakeApi({this.startFailure, bool hold = false})
    : _gate = hold ? Completer<void>() : null,
      super(Dio());

  DioExceptionType? startFailure;
  int startCalls = 0;
  final Completer<void>? _gate;

  void releaseStart() {
    if (_gate != null && !_gate.isCompleted) _gate.complete();
  }

  @override
  Future<StartResult> start({required String language}) async {
    startCalls++;
    if (_gate != null) await _gate.future;
    final failure = startFailure;
    if (failure != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/virtual-doctor/start'),
        type: failure,
      );
    }
    return StartResult(
      sessionId: 'session-1',
      reply: 'Hello.',
      phase: 'intake',
      language: language,
    );
  }

  @override
  Future<void> warmup(String language) async {}
}

class _FakeRecorder extends VoiceRecorder {
  int permissionChecks = 0;
  int startCalls = 0;

  @override
  Future<MicPermissionResult> ensurePermission() async {
    permissionChecks++;
    return MicPermissionResult.granted;
  }

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeTts extends TtsPlayer {
  _FakeTts() : super(_FakeApi());

  int speakCalls = 0;

  @override
  Future<bool> speak(
    String text, {
    required String language,
    required String sessionId,
    void Function(String sentence)? onSentence,
  }) async {
    speakCalls++;
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
