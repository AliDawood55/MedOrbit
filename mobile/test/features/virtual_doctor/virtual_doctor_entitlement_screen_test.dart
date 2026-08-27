import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/ai_health_client.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/virtual_doctor/data/tts_player.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';
import 'package:mobile/features/virtual_doctor/data/voice_recorder.dart';
import 'package:mobile/features/virtual_doctor/providers/virtual_doctor_provider.dart';
import 'package:mobile/features/virtual_doctor/screens/virtual_doctor_screen.dart';

const _strings = AppStrings(false); // English, matching secureStorageProvider's override below

void main() {
  testWidgets('a voice-cooldown fatal state shows a quiet notice with no Retry action', (tester) async {
    final controller = _controller()
      ..state = const VirtualDoctorState(state: ConsultState.error, errorMessage: 'voice_cooldown');
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.textContaining(_strings.vdCooldownTitle), findsOneWidget);
    expect(find.textContaining(_strings.vdErrVoiceCooldown), findsOneWidget);
    // The backend enforces the same cooldown on an immediate retry, so no
    // "Try again" action is offered for this denial.
    expect(find.text(_strings.vdRetryConsultation), findsNothing);
  });

  testWidgets('a voice-cooldown notice includes the server-supplied retry time when present', (tester) async {
    final retryAt = DateTime.utc(2026, 8, 23, 10);
    final controller = _controller()
      ..state = VirtualDoctorState(
        state: ConsultState.error,
        errorMessage: 'voice_cooldown',
        entitlementRetryAt: retryAt,
      );
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.textContaining(_strings.vdCooldownUntilPrefix), findsOneWidget);
  });

  testWidgets('a free-quota-exhausted fatal state shows its own title and no Retry action', (tester) async {
    final controller = _controller()
      ..state = const VirtualDoctorState(state: ConsultState.error, errorMessage: 'free_quota_exhausted');
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.textContaining(_strings.vdQuotaTitle), findsOneWidget);
    expect(find.text(_strings.vdRetryConsultation), findsNothing);
  });

  testWidgets('an entitlement-unavailable fatal state still offers Retry', (tester) async {
    final controller = _controller()
      ..state = const VirtualDoctorState(state: ConsultState.error, errorMessage: 'entitlement_unavailable');
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text(_strings.vdRetryConsultation), findsOneWidget);
  });

  testWidgets('a mid-conversation cooldown denial renders as a warning notice, not a generic error', (tester) async {
    final controller = _controller()
      ..state = const VirtualDoctorState(state: ConsultState.listening, errorMessage: 'voice_session_active');
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.textContaining(_strings.vdErrVoiceSessionActive), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing,
        reason: 'an entitlement denial is a product rule, not a broken request');
  });
}

VirtualDoctorController _controller() {
  return VirtualDoctorController(_FakeApi(), _FakeRecorder(), _FakeTts(), _FakeHealth());
}

Widget _app(VirtualDoctorController controller) {
  return ProviderScope(
    overrides: [
      virtualDoctorControllerProvider.overrideWith((ref) => controller),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const VirtualDoctorScreen(),
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}

  @override
  Future<String?> getThemeMode() async => null;

  @override
  Future<void> saveThemeMode(String mode) async {}
}

class _FakeHealth extends AiHealthClient {
  _FakeHealth() : super(Dio());

  @override
  Future<AiHealthStatus> check({bool force = false}) async => AiHealthStatus.available;

  @override
  void invalidate() {}
}

class _FakeApi extends VirtualDoctorApi {
  _FakeApi() : super(Dio());
}

class _FakeRecorder extends VoiceRecorder {
  @override
  Future<MicPermissionResult> ensurePermission() async => MicPermissionResult.granted;

  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => null;

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
