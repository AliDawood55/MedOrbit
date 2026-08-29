import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/ai_health_client.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/billing/data/billing_api.dart';
import 'package:mobile/features/billing/models/billing_models.dart';
import 'package:mobile/features/billing/providers/billing_provider.dart';
import 'package:mobile/features/virtual_doctor/data/tts_player.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';
import 'package:mobile/features/virtual_doctor/data/voice_recorder.dart';
import 'package:mobile/features/virtual_doctor/providers/virtual_doctor_provider.dart';
import 'package:mobile/features/virtual_doctor/screens/virtual_doctor_screen.dart';

const en = AppStrings(false);

void main() {
  testWidgets('eligible free user can start and sees an upgrade option', (
    tester,
  ) async {
    await _tall(tester);
    final harness = _Harness(_snapshot());
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app());
    await _settle(tester);

    expect(find.text(en.voiceEntitlementEligible), findsOneWidget);
    expect(find.text(en.entitlementUpgradeAction), findsOneWidget);
    final start = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text(en.startConsultation),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(start.onPressed, isNotNull);
  });

  testWidgets(
    'active free session is presented as resume, not a second start',
    (tester) async {
      await _tall(tester);
      final harness = _Harness(_snapshot(activeSessionId: 'existing-session'));
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.app());
      await _settle(tester);

      expect(find.text(en.voiceEntitlementResume), findsWidgets);
      expect(find.text(en.startConsultation), findsNothing);
    },
  );

  testWidgets('cooldown disables Start and upgrade CTA navigates to billing', (
    tester,
  ) async {
    await _tall(tester);
    final harness = _Harness(_snapshot(cooldown: true));
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app());
    await _settle(tester);

    expect(find.text(en.voiceEntitlementCooldown), findsOneWidget);
    expect(find.text(en.voiceNextFree), findsOneWidget);
    final start = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text(en.startConsultation),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(start.onPressed, isNull);

    await tester.tap(find.text(en.entitlementUpgradeAction));
    await tester.pumpAndSettle();
    expect(find.text('billing-route-marker'), findsOneWidget);
  });

  testWidgets('Pro user sees unlimited access without a paywall action', (
    tester,
  ) async {
    await _tall(tester);
    final harness = _Harness(_snapshot(pro: true));
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app());
    await _settle(tester);

    expect(find.text(en.voiceEntitlementPro), findsOneWidget);
    expect(find.text(en.entitlementUpgradeAction), findsNothing);
    expect(find.text(en.startConsultation), findsOneWidget);
  });

  testWidgets('cooldown layout is overflow-free at 320px, 2x text, and RTL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = _Harness(_snapshot(cooldown: true), arabic: true);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app(textScale: 2));
    await _settle(tester);

    expect(tester.takeException(), isNull);
  });
}

BillingEntitlements _snapshot({
  bool pro = false,
  bool cooldown = false,
  String? activeSessionId,
}) {
  return BillingEntitlements.fromJson({
    'plan': pro ? 'pro_monthly' : 'free',
    'subscription': {'status': pro ? 'active' : null},
    'features': {
      'chatbot': {
        'allowed': true,
        'unlimited': pro,
        'used': pro ? null : 0,
        'limit': pro ? null : 7,
        'remaining': pro ? null : 7,
        'resets_at': null,
      },
      'voice_doctor': {
        'allowed': pro || !cooldown,
        'unlimited': pro,
        'active_session_id': activeSessionId,
        'next_free_at': cooldown ? '2026-08-30T10:00:00Z' : null,
      },
    },
    'server_time': '2026-08-29T10:00:00Z',
  });
}

class _Harness {
  _Harness(BillingEntitlements snapshot, {this.arabic = false})
    : voice = VirtualDoctorController(_Api(), _Recorder(), _Tts(), _Health()),
      billing = BillingController(BillingApi(Dio()), accountKey: null) {
    billing.state = BillingState(entitlements: snapshot);
    router = GoRouter(
      initialLocation: '/virtual-doctor',
      routes: [
        GoRoute(
          path: '/virtual-doctor',
          builder: (context, state) => const VirtualDoctorScreen(),
        ),
        GoRoute(
          path: '/billing',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('billing-route-marker'))),
        ),
      ],
    );
  }

  final bool arabic;
  final VirtualDoctorController voice;
  final BillingController billing;
  late final GoRouter router;

  Widget app({double textScale = 1}) {
    return ProviderScope(
      overrides: [
        virtualDoctorControllerProvider.overrideWith((ref) => voice),
        billingControllerProvider.overrideWith((ref) => billing),
        secureStorageProvider.overrideWithValue(_Storage(arabic ? 'ar' : 'en')),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(arabic ? 'ar' : 'en'),
        theme: AppTheme.light(isArabic: arabic),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

class _Api extends VirtualDoctorApi {
  _Api() : super(Dio());
}

class _Health extends AiHealthClient {
  _Health() : super(Dio());

  @override
  Future<AiHealthStatus> check({bool force = false}) async =>
      AiHealthStatus.available;
}

class _Recorder extends VoiceRecorder {
  @override
  Future<MicPermissionResult> ensurePermission() async =>
      MicPermissionResult.granted;

  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _Tts extends TtsPlayer {
  _Tts() : super(VirtualDoctorApi(Dio()));

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

class _Storage extends SecureStorageService {
  _Storage(this.language);
  final String language;

  @override
  Future<String?> getLanguageCode() async => language;

  @override
  Future<void> saveLanguageCode(String code) async {}

  @override
  Future<String?> getThemeMode() async => null;

  @override
  Future<void> saveThemeMode(String mode) async {}
}
