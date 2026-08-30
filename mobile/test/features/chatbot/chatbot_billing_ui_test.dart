import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/billing/data/billing_api.dart';
import 'package:mobile/features/billing/models/billing_models.dart';
import 'package:mobile/features/billing/providers/billing_provider.dart';
import 'package:mobile/features/chatbot/data/chatbot_api.dart';
import 'package:mobile/features/chatbot/providers/chatbot_provider.dart';
import 'package:mobile/features/chatbot/screens/chatbot_screen.dart';

const en = AppStrings(false);

void main() {
  testWidgets('free user sees remaining quota from the entitlement snapshot', (
    tester,
  ) async {
    final harness = _Harness(_entitlements());
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app());
    await tester.pump();
    await tester.pump();

    expect(find.text(en.billingChatRemaining(5, 7)), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .enabled,
      isTrue,
    );
  });

  testWidgets(
    'exhausted quota disables sends and upgrade CTA navigates to billing',
    (tester) async {
      final harness = _Harness(_entitlements(exhausted: true));
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.app());
      await tester.pump();
      await tester.pump();

      expect(find.text(en.chatQuotaExhaustedBody), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
            .onPressed,
        isNull,
      );

      await tester.ensureVisible(find.text(en.entitlementUpgradeAction));
      await tester.tap(find.text(en.entitlementUpgradeAction));
      await tester.pumpAndSettle();
      expect(find.text('billing-route-marker'), findsOneWidget);
    },
  );

  testWidgets('Pro user has no fake finite quota or paywall and can send', (
    tester,
  ) async {
    final harness = _Harness(_entitlements(pro: true));
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app());
    await tester.pump();
    await tester.pump();

    expect(find.text(en.billingChatRemaining(5, 7)), findsNothing);
    expect(find.text(en.entitlementUpgradeAction), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .enabled,
      isTrue,
    );
  });

  testWidgets(
    'quota paywall remains overflow-free at 320px, 2x text, and RTL',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = _Harness(_entitlements(exhausted: true), arabic: true);
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.app(textScale: 2));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}

BillingEntitlements _entitlements({bool pro = false, bool exhausted = false}) {
  return BillingEntitlements.fromJson({
    'plan': pro ? 'pro_monthly' : 'free',
    'subscription': {'status': pro ? 'active' : null},
    'features': {
      'chatbot': {
        'allowed': pro || !exhausted,
        'unlimited': pro,
        'used': pro ? null : (exhausted ? 7 : 2),
        'limit': pro ? null : 7,
        'remaining': pro ? null : (exhausted ? 0 : 5),
        'resets_at': pro ? null : '2026-08-30T10:00:00Z',
      },
      'voice_doctor': {
        'allowed': pro,
        'unlimited': pro,
        'active_session_id': null,
        'next_free_at': pro ? null : '2026-08-30T10:00:00Z',
      },
    },
    'server_time': '2026-08-29T10:00:00Z',
  });
}

class _Harness {
  _Harness(BillingEntitlements snapshot, {this.arabic = false})
    : chat = ChatbotController(_ChatApi()),
      billing = BillingController(BillingApi(Dio()), accountKey: null) {
    billing.state = BillingState(entitlements: snapshot);
    router = GoRouter(
      initialLocation: '/chatbot',
      routes: [
        GoRoute(
          path: '/chatbot',
          builder: (context, state) => const ChatbotScreen(),
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
  final ChatbotController chat;
  final BillingController billing;
  late final GoRouter router;

  Widget app({double textScale = 1}) {
    return ProviderScope(
      overrides: [
        chatbotControllerProvider.overrideWith((ref) => chat),
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

class _ChatApi extends ChatbotApi {
  _ChatApi() : super(Dio());
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
