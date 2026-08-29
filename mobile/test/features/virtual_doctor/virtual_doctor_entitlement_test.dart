import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/ai_health_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/virtual_doctor/data/tts_player.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';
import 'package:mobile/features/virtual_doctor/data/voice_recorder.dart';
import 'package:mobile/features/virtual_doctor/models/consultation_models.dart';
import 'package:mobile/features/virtual_doctor/providers/virtual_doctor_provider.dart';

/// Billing/entitlement codes from `backend/src/config/billing.js`'s
/// `ERROR_CODES`, as they arrive on `/virtual-doctor/*` responses. Before
/// P6C, `VirtualDoctorController._failureCode` collapsed every one of these
/// into the generic `'ai_failed'` code, which told the patient "something
/// went wrong, try again" for a denial the backend would repeat on the very
/// next attempt.
void main() {
  group('entitlement denials map to a stable semantic code, not ai_failed', () {
    final cases = {
      ApiException.codeVoiceCooldown: 'voice_cooldown',
      ApiException.codeVoiceSessionActive: 'voice_session_active',
      ApiException.codeFreeQuotaExhausted: 'free_quota_exhausted',
      ApiException.codeSubscriptionRequired: 'subscription_required',
      ApiException.codeSubscriptionInactive: 'subscription_inactive',
      ApiException.codeEntitlementUnavailable: 'entitlement_unavailable',
    };

    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () async {
        final harness = _Harness(startError: ApiException(message: 'denied', code: entry.key, statusCode: 429));
        addTearDown(harness.dispose);

        await harness.controller.startConsultation('en');

        expect(harness.controller.state.state, ConsultState.error);
        expect(harness.controller.state.errorMessage, entry.value);
        expect(harness.controller.state.errorMessage, isNot('ai_failed'));
      });
    }

    test('every entitlement code resolves to real, distinct AR/EN copy', () {
      for (final locale in [true, false]) {
        final strings = AppStrings(locale);
        final seen = <String>{};
        for (final code in cases.values) {
          final text = strings.vdError(code);
          expect(text, isNot(code), reason: '$code leaked verbatim ($locale)');
          expect(text, isNotEmpty);
          seen.add(text);
        }
        // Distinct messages, not all six collapsing onto one generic string.
        expect(seen.length, cases.length, reason: 'locale=$locale');
      }
    });
  });

  group('cooldown detail', () {
    test('a VOICE_COOLDOWN denial with next_free_at is captured without inventing a time', () async {
      final retryAt = DateTime.utc(2026, 8, 23, 10);
      final harness = _Harness(
        startError: ApiException(
          message: 'denied',
          code: ApiException.codeVoiceCooldown,
          statusCode: 429,
          details: {'next_free_at': retryAt.toIso8601String(), 'upgrade_available': true},
        ),
      );
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('en');

      expect(harness.controller.state.errorMessage, 'voice_cooldown');
      expect(harness.controller.state.entitlementRetryAt, retryAt);
    });

    test('a VOICE_COOLDOWN denial with no details leaves the retry time null', () async {
      final harness = _Harness(
        startError: const ApiException(message: 'denied', code: ApiException.codeVoiceCooldown, statusCode: 429),
      );
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('en');

      expect(harness.controller.state.errorMessage, 'voice_cooldown');
      expect(harness.controller.state.entitlementRetryAt, isNull);
    });

    test('a non-cooldown entitlement denial never carries a retry time', () async {
      final harness = _Harness(
        startError: ApiException(
          message: 'denied',
          code: ApiException.codeFreeQuotaExhausted,
          statusCode: 429,
          details: {'next_free_at': DateTime.now().toIso8601String()},
        ),
      );
      addTearDown(harness.dispose);

      await harness.controller.startConsultation('en');

      expect(harness.controller.state.errorMessage, 'free_quota_exhausted');
      expect(harness.controller.state.entitlementRetryAt, isNull);
    });

    test('clearError also clears a stale cooldown retry time', () async {
      final harness = _Harness(
        startError: ApiException(
          message: 'denied',
          code: ApiException.codeVoiceCooldown,
          statusCode: 429,
          details: {'next_free_at': DateTime.now().toIso8601String()},
        ),
      );
      addTearDown(harness.dispose);
      await harness.controller.startConsultation('en');
      expect(harness.controller.state.entitlementRetryAt, isNotNull);

      harness.controller.clearError();

      expect(harness.controller.state.entitlementRetryAt, isNull);
    });
  });

  test('an entitlement denial mid-conversation (sendMessage) classifies the same way as at start', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.controller.startConsultation('en');
    expect(harness.controller.state.state, ConsultState.listening);

    harness.api.transcribeText = 'I have a headache.';
    harness.api.sendMessageError = const ApiException(
      message: 'denied',
      code: ApiException.codeVoiceSessionActive,
      statusCode: 403,
    );
    // `_submit` is private, reached only via a successful transcription — this
    // stays a behavioral test of the public API rather than reaching into
    // controller internals.
    await harness.controller.startRecording();
    await harness.controller.stopRecordingAndSubmit();

    expect(harness.controller.state.errorMessage, 'voice_session_active');
    expect(harness.controller.state.state, ConsultState.listening,
        reason: 'a denial mid-conversation keeps the consultation alive, unlike a fatal start failure');
  });
}

class _Harness {
  _Harness({Object? startError})
      : health = _FakeHealth(),
        api = _FakeApi(startError: startError),
        recorder = _FakeRecorder(),
        tts = _FakeTts() {
    controller = VirtualDoctorController(api, recorder, tts, health);
  }

  final _FakeHealth health;
  final _FakeApi api;
  final _FakeRecorder recorder;
  final _FakeTts tts;
  late final VirtualDoctorController controller;

  void dispose() => controller.dispose();
}

class _FakeHealth extends AiHealthClient {
  _FakeHealth() : super(Dio());

  @override
  Future<AiHealthStatus> check({bool force = false}) async => AiHealthStatus.available;

  @override
  void invalidate() {}
}

class _FakeApi extends VirtualDoctorApi {
  _FakeApi({this.startError}) : super(Dio());

  Object? startError;
  Object? sendMessageError;
  String transcribeText = '';

  @override
  Future<StartResult> start({required String language}) async {
    final failure = startError;
    if (failure != null) return Future.error(failure);
    return StartResult(sessionId: 'session-1', reply: 'Hello.', phase: 'intake', language: language);
  }

  @override
  Future<void> warmup(String language) async {}

  @override
  Future<MessageResult> sendMessage({required String sessionId, required String message}) async {
    final failure = sendMessageError;
    if (failure != null) return Future.error(failure);
    return const MessageResult(sessionId: 'session-1', reply: 'Understood.', phase: 'intake');
  }

  @override
  Future<TranscriptionResult> transcribe({
    required String filePath,
    required String language,
    required String sessionId,
  }) async {
    return TranscriptionResult(text: transcribeText, timedOut: false);
  }
}

class _FakeRecorder extends VoiceRecorder {
  @override
  Future<MicPermissionResult> ensurePermission() async => MicPermissionResult.granted;

  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => 'recording.wav';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeTts extends TtsPlayer {
  _FakeTts() : super(_FakeApi());

  @override
  Future<bool> speak(
    String text, {
    required String language,
    required String sessionId,
    void Function(String sentence)? onSentence,
  }) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
