import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/ai_health_client.dart';
import 'package:mobile/features/virtual_doctor/data/tts_player.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';
import 'package:mobile/features/virtual_doctor/data/voice_recorder.dart';
import 'package:mobile/features/virtual_doctor/models/consultation_models.dart';
import 'package:mobile/features/virtual_doctor/providers/virtual_doctor_provider.dart';

void main() {
  test(
    'eligible consultation starts once and refreshes entitlement snapshot',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('en');

      expect(harness.api.startCalls, 1);
      expect(harness.controller.state.state, ConsultState.listening);
      expect(harness.controller.state.recoveredSession, isFalse);
      expect(harness.controller.state.transcript.single.text, 'Welcome.');
      expect(harness.entitlementRefreshes, 1);
    },
  );

  test(
    'server resume restores the existing transcript without a duplicate greeting',
    () async {
      final harness = _Harness(
        startResult: const StartResult(
          sessionId: 'existing-session',
          reply: '',
          phase: 'assessment',
          language: 'ar',
          resumed: true,
          entitlementSource: 'free_active_session',
          messages: [
            TranscriptEntry(text: 'Previous question', isDoctor: true),
            TranscriptEntry(text: 'Previous answer', isDoctor: false),
          ],
        ),
      );
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('en');

      expect(harness.controller.state.recoveredSession, isTrue);
      expect(harness.controller.state.language, 'ar');
      expect(harness.controller.state.transcript, hasLength(2));
      expect(harness.tts.speakCalls, 0);
      expect(harness.api.startCalls, 1);
    },
  );

  test(
    'completed interview refreshes entitlement and manual close does not finalize twice',
    () async {
      final harness = _Harness(
        messageResult: const MessageResult(
          sessionId: 'session-1',
          reply: 'Your consultation is complete.',
          phase: 'complete',
        ),
      );
      addTearDown(harness.dispose);
      await harness.controller.startConsultation('en');

      await harness.controller.startRecording();
      await harness.controller.stopRecordingAndSubmit();

      expect(harness.controller.state.state, ConsultState.complete);
      expect(harness.entitlementRefreshes, 2);
      expect(await harness.controller.endConsultation(), isTrue);
      expect(harness.api.endCalls, 0);
      expect(harness.controller.state.state, ConsultState.idle);
    },
  );

  test('two manual End taps send one backend finalization request', () async {
    final endGate = Completer<void>();
    final harness = _Harness(endGate: endGate);
    addTearDown(harness.dispose);
    await harness.controller.startConsultation('en');

    final first = harness.controller.endConsultation();
    final duplicate = await harness.controller.endConsultation();
    await Future<void>.delayed(Duration.zero);
    expect(duplicate, isFalse);
    expect(harness.api.endCalls, 1);
    expect(harness.controller.state.isEnding, isTrue);

    endGate.complete();
    expect(await first, isTrue);
    expect(harness.api.endCalls, 1);
    expect(harness.controller.state.state, ConsultState.idle);
  });

  test(
    'failed manual end retains session state and exposes only safe retry code',
    () async {
      final harness = _Harness(endError: StateError('provider secret'));
      addTearDown(harness.dispose);
      await harness.controller.startConsultation('en');

      expect(await harness.controller.endConsultation(), isFalse);

      expect(harness.api.endCalls, 1);
      expect(harness.controller.state.state, isNot(ConsultState.idle));
      expect(harness.controller.state.isEnding, isFalse);
      expect(harness.controller.state.errorMessage, 'end_failed');
      expect(
        harness.controller.state.errorMessage,
        isNot(contains('provider')),
      );
    },
  );

  test(
    'disposing during a delayed start causes no post-dispose side effect',
    () async {
      final startGate = Completer<StartResult>();
      final harness = _Harness(startGate: startGate);

      final pending = harness.controller.startConsultation('en');
      await Future<void>.delayed(Duration.zero);
      harness.dispose();
      startGate.complete(
        const StartResult(
          sessionId: 'late-session',
          reply: 'Late',
          phase: 'intake',
          language: 'en',
        ),
      );

      await pending;
      expect(harness.tts.speakCalls, 0);
    },
  );
}

class _Harness {
  _Harness({
    StartResult? startResult,
    Completer<StartResult>? startGate,
    MessageResult? messageResult,
    Completer<void>? endGate,
    Object? endError,
  }) : api = _Api(
         startResult: startResult,
         startGate: startGate,
         messageResult: messageResult,
         endGate: endGate,
         endError: endError,
       ),
       recorder = _Recorder(),
       tts = _Tts(),
       health = _Health() {
    controller = VirtualDoctorController(
      api,
      recorder,
      tts,
      health,
      onEntitlementChanged: () async {
        entitlementRefreshes += 1;
      },
    );
  }

  final _Api api;
  final _Recorder recorder;
  final _Tts tts;
  final _Health health;
  late final VirtualDoctorController controller;
  int entitlementRefreshes = 0;

  void dispose() => controller.dispose();
}

class _Api extends VirtualDoctorApi {
  _Api({
    StartResult? startResult,
    this.startGate,
    MessageResult? messageResult,
    this.endGate,
    this.endError,
  }) : startResult =
           startResult ??
           const StartResult(
             sessionId: 'session-1',
             reply: 'Welcome.',
             phase: 'intake',
             language: 'en',
             entitlementSource: 'free',
           ),
       messageResult =
           messageResult ??
           const MessageResult(
             sessionId: 'session-1',
             reply: 'Continue.',
             phase: 'assessment',
           ),
       super(Dio());

  final StartResult startResult;
  final Completer<StartResult>? startGate;
  final MessageResult messageResult;
  final Completer<void>? endGate;
  final Object? endError;
  int startCalls = 0;
  int endCalls = 0;

  @override
  Future<StartResult> start({required String language}) {
    startCalls += 1;
    return startGate?.future ?? Future.value(startResult);
  }

  @override
  Future<void> warmup(String language) async {}

  @override
  Future<TranscriptionResult> transcribe({
    required String filePath,
    required String language,
    required String sessionId,
  }) async {
    return const TranscriptionResult(
      text: 'I have a headache.',
      timedOut: false,
    );
  }

  @override
  Future<MessageResult> sendMessage({
    required String sessionId,
    required String message,
  }) async {
    return messageResult;
  }

  @override
  Future<void> endSession(String sessionId) async {
    endCalls += 1;
    if (endError != null) throw endError!;
    if (endGate != null) await endGate!.future;
  }
}

class _Health extends AiHealthClient {
  _Health() : super(Dio());

  @override
  Future<AiHealthStatus> check({bool force = false}) async =>
      AiHealthStatus.available;

  @override
  void invalidate() {}
}

class _Recorder extends VoiceRecorder {
  @override
  Future<MicPermissionResult> ensurePermission() async =>
      MicPermissionResult.granted;

  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => 'not-a-real-recording.wav';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _Tts extends TtsPlayer {
  _Tts() : super(VirtualDoctorApi(Dio()));

  int speakCalls = 0;

  @override
  Future<bool> speak(
    String text, {
    required String language,
    required String sessionId,
    void Function(String sentence)? onSentence,
  }) async {
    speakCalls += 1;
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
