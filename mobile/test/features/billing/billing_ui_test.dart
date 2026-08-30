import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/billing/data/billing_api.dart';
import 'package:mobile/features/billing/data/checkout_launcher.dart';
import 'package:mobile/features/billing/models/billing_models.dart';
import 'package:mobile/features/billing/providers/billing_provider.dart';
import 'package:mobile/features/billing/screens/billing_history_screen.dart';
import 'package:mobile/features/billing/screens/billing_screen.dart';
import 'package:mobile/features/billing/screens/sandbox_checkout_screen.dart';
import 'package:mobile/features/billing/screens/subscription_screen.dart';

import 'billing_test_fixtures.dart';

const en = AppStrings(false);
const ar = AppStrings(true);

void main() {
  testWidgets(
    'free overview renders server plans, price, quota, and cooldown',
    (tester) async {
      await _tall(tester);
      final harness = _Harness(state: _freeState());
      await tester.pumpWidget(_app(harness, const BillingScreen()));
      await _settleLocale(tester);

      expect(find.text(en.billingFreeBadge), findsOneWidget);
      expect(find.text('Orbit Pro Monthly'), findsOneWidget);
      expect(find.textContaining('23.45'), findsOneWidget);
      expect(find.text(en.billingChatRemaining(5, 7)), findsOneWidget);
      expect(find.text(en.billingVoiceCooldown), findsOneWidget);
      expect(find.text(en.billingUpgrade), findsNWidgets(2));
    },
  );

  testWidgets(
    'Pro overview shows unlimited benefits without a fake finite quota',
    (tester) async {
      await _tall(tester);
      final harness = _Harness(
        state: _freeState().copyWith(
          entitlements: entitlements(pro: true),
          subscription: activeSubscription(),
        ),
      );
      await tester.pumpWidget(_app(harness, const BillingScreen()));
      await _settleLocale(tester);

      expect(find.text(en.billingProBadge), findsOneWidget);
      expect(find.text(en.billingChatUnlimited), findsOneWidget);
      expect(find.text(en.billingVoiceUnlimited), findsOneWidget);
      expect(find.text(en.billingChatRemaining(5, 7)), findsNothing);
      expect(find.text(en.billingCurrentPlanAction), findsWidgets);
    },
  );

  testWidgets('checkout unavailable disables hosted checkout actions', (
    tester,
  ) async {
    await _tall(tester);
    final harness = _Harness(
      state: _freeState().copyWith(
        config: const BillingConfig(checkoutAvailable: false, sandbox: false),
      ),
    );
    await tester.pumpWidget(_app(harness, const BillingScreen()));
    await _settleLocale(tester);

    expect(find.text(en.billingCheckoutUnavailable), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text(en.billingUpgrade).first,
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(harness.api.checkoutPlans, isEmpty);
  });

  testWidgets('checkout launches only the server URL for the selected plan', (
    tester,
  ) async {
    await _tall(tester);
    final harness = _Harness(state: _freeState())
      ..api.checkoutResults.add(
        Future.value(Uri.parse('https://payments.example.test/session/abc')),
      );
    await tester.pumpWidget(_app(harness, const BillingScreen()));
    await _settleLocale(tester);

    await tester.tap(find.text(en.billingUpgrade).first);
    await tester.pump();
    await tester.pump();

    expect(harness.api.checkoutPlans, ['pro_monthly']);
    expect(
      harness.launched.single.toString(),
      'https://payments.example.test/session/abc',
    );
    expect(harness.controller.state.checkoutAwaitingReturn, isTrue);
  });

  testWidgets(
    'sandbox controls are absent in production and visible when server enables them',
    (tester) async {
      await _tall(tester);
      final production = _Harness(state: _freeState());
      await tester.pumpWidget(_app(production, const BillingScreen()));
      await _settleLocale(tester);
      expect(find.text(en.sandboxBillingBanner), findsNothing);

      final sandbox = _Harness(
        state: _freeState().copyWith(
          config: const BillingConfig(checkoutAvailable: true, sandbox: true),
        ),
      );
      await tester.pumpWidget(_app(sandbox, const BillingScreen()));
      await _settleLocale(tester);
      expect(find.text(en.sandboxBillingBanner), findsWidgets);
    },
  );

  testWidgets(
    'sandbox checkout route fails closed when config disables sandbox',
    (tester) async {
      final harness = _Harness(state: _freeState());
      harness.api.configResult = const BillingConfig(
        checkoutAvailable: true,
        sandbox: false,
      );
      await tester.pumpWidget(
        _app(harness, const SandboxCheckoutScreen(token: 'cs_mock_abc')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(en.sandboxDisabled), findsOneWidget);
      expect(find.text(en.sandboxSimulateSuccess), findsNothing);
      expect(harness.api.sandboxCheckoutCalls, 0);
    },
  );

  testWidgets(
    'verified sandbox route labels simulation and exposes exact outcomes',
    (tester) async {
      await _tall(tester);
      final harness = _Harness(state: _freeState());
      harness.api.configResult = const BillingConfig(
        checkoutAvailable: true,
        sandbox: true,
      );
      harness.api.sandboxCheckout = SandboxCheckout.fromJson({
        ...planJson(),
        'status': 'open',
        'is_open': true,
        'expires_at': '2026-08-29T11:00:00Z',
        'return_path': '/billing',
        'server_time': serverNow.toIso8601String(),
        'sandbox': true,
      });
      await tester.pumpWidget(
        _app(harness, const SandboxCheckoutScreen(token: 'cs_mock_abc')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(en.sandboxBillingBanner), findsWidgets);
      expect(find.text(en.sandboxNoCard), findsOneWidget);
      expect(find.text(en.sandboxSimulateSuccess), findsOneWidget);
      expect(find.text(en.sandboxSimulateFailure), findsOneWidget);
      expect(find.text(en.sandboxSimulateCancel), findsOneWidget);
      expect(harness.api.sandboxCheckoutCalls, 1);
    },
  );

  testWidgets('load failure renders safe localized copy and Retry', (
    tester,
  ) async {
    final harness = _Harness(
      state: const BillingState(
        error: ApiException(
          message: 'provider prose',
          code: 'ENTITLEMENT_UNAVAILABLE',
        ),
      ),
    );
    await tester.pumpWidget(_app(harness, const BillingScreen()));
    await _settleLocale(tester);

    expect(find.text(en.billingLoadErrorTitle), findsOneWidget);
    expect(find.text(en.billingLoadErrorMessage), findsOneWidget);
    expect(find.text(en.retry), findsOneWidget);
    expect(find.textContaining('provider'), findsNothing);
  });

  testWidgets('billing overview is overflow-free at 320px, 2x text, and RTL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = _Harness(state: _freeState());
    await tester.pumpWidget(
      _app(harness, const BillingScreen(), arabic: true, textScale: 2),
    );
    await _settleLocale(tester);

    expect(find.text(ar.billingTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active subscription requires confirmation before canceling', (
    tester,
  ) async {
    await _tall(tester);
    final harness =
        _Harness(
            state: _freeState().copyWith(
              entitlements: entitlements(pro: true),
              subscription: activeSubscription(),
            ),
          )
          ..api.cancelResults.add(
            Future.value(activeSubscription(cancelAtPeriodEnd: true)),
          );
    await tester.pumpWidget(_app(harness, const SubscriptionScreen()));
    await _settleLocale(tester);

    await tester.tap(find.text(en.subscriptionCancel));
    await tester.pumpAndSettle();
    expect(harness.api.cancelCalls, 0);
    expect(find.text(en.subscriptionCancelTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, en.subscriptionCancel));
    await tester.pump();
    await tester.pump();
    expect(harness.api.cancelCalls, 1);
    expect(harness.controller.state.subscription?.cancelAtPeriodEnd, isTrue);
  });

  testWidgets('cancel-at-period-end state offers confirmed resume', (
    tester,
  ) async {
    await _tall(tester);
    final harness = _Harness(
      state: _freeState().copyWith(
        entitlements: entitlements(pro: true),
        subscription: activeSubscription(cancelAtPeriodEnd: true),
      ),
    )..api.resumeResults.add(Future.value(activeSubscription()));
    await tester.pumpWidget(_app(harness, const SubscriptionScreen()));
    await _settleLocale(tester);

    expect(find.text(en.subscriptionResume), findsOneWidget);
    await tester.tap(find.text(en.subscriptionResume));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.subscriptionResume).last,
    );
    await tester.pump();
    await tester.pump();

    expect(harness.api.resumeCalls, 1);
    expect(harness.controller.state.subscription?.cancelAtPeriodEnd, isFalse);
  });

  testWidgets(
    'plan change is confirmed and records backend pending plan state',
    (tester) async {
      await _tall(tester);
      final pending = SubscriptionDetail.fromJson(
        subscriptionJson(
          planCode: 'pro_monthly',
          status: 'active',
          pendingPlan: {
            ...planJson(code: 'pro_annual', interval: 'year', cents: 19999),
            'effective_at': '2026-09-29T10:00:00Z',
          },
        ),
      );
      final harness = _Harness(
        state: _freeState().copyWith(
          entitlements: entitlements(pro: true),
          subscription: activeSubscription(),
        ),
      )..api.changeResults.add(Future.value(pending));
      await tester.pumpWidget(_app(harness, const SubscriptionScreen()));
      await _settleLocale(tester);

      await tester.tap(find.text('Orbit Pro Annual'));
      await tester.pumpAndSettle();
      expect(harness.api.changedPlans, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, en.confirm));
      await tester.pump();
      await tester.pump();

      expect(harness.api.changedPlans, ['pro_annual']);
      expect(
        harness.controller.state.subscription?.pendingPlan?.code,
        'pro_annual',
      );
    },
  );

  testWidgets('past-due subscription renders backend grace-period semantics', (
    tester,
  ) async {
    await _tall(tester);
    final pastDue = SubscriptionDetail.fromJson(
      subscriptionJson(planCode: 'pro_monthly', status: 'past_due'),
    );
    final harness = _Harness(
      state: _freeState().copyWith(
        subscription: pastDue,
        entitlements: entitlements(),
      ),
    );
    await tester.pumpWidget(_app(harness, const SubscriptionScreen()));
    await _settleLocale(tester);

    expect(find.text(en.subscriptionPastDue), findsOneWidget);
    expect(find.text(en.subscriptionPastDueHint), findsOneWidget);
    expect(find.text(en.subscriptionGraceEndsAt), findsOneWidget);
  });

  testWidgets('billing history renders server event chronology as cards', (
    tester,
  ) async {
    final harness = _Harness(state: _freeState());
    await tester.pumpWidget(_app(harness, const BillingHistoryScreen()));
    await _settleLocale(tester);

    expect(find.text(en.billingHistoryTitle), findsWidgets);
    expect(
      find.text(en.billingHistoryEvent('subscription_started')),
      findsOneWidget,
    );
  });
}

BillingState _freeState() => BillingState(
  entitlements: entitlements(),
  plans: [monthlyPlan(), annualPlan()],
  config: const BillingConfig(checkoutAvailable: true, sandbox: false),
  subscription: freeSubscription(),
  history: [historyEvent()],
);

class _Harness {
  _Harness({required BillingState state}) : api = _UiBillingApi() {
    controller = BillingController(api, accountKey: null)..state = state;
  }

  final _UiBillingApi api;
  late BillingController controller;
  final launched = <Uri>[];
}

Widget _app(
  _Harness harness,
  Widget home, {
  bool arabic = false,
  double textScale = 1,
}) {
  return ProviderScope(
    key: ObjectKey(harness),
    overrides: [
      billingControllerProvider.overrideWith((ref) => harness.controller),
      billingApiProvider.overrideWithValue(harness.api),
      checkoutUrlLauncherProvider.overrideWithValue((uri) async {
        harness.launched.add(uri);
        return true;
      }),
      secureStorageProvider.overrideWithValue(_Storage(arabic ? 'ar' : 'en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: arabic),
      locale: Locale(arabic ? 'ar' : 'en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: home,
        ),
      ),
    ),
  );
}

Future<void> _settleLocale(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

class _UiBillingApi extends BillingApi {
  _UiBillingApi() : super(Dio());

  final checkoutResults = <Future<Uri>>[];
  final cancelResults = <Future<SubscriptionDetail>>[];
  final resumeResults = <Future<SubscriptionDetail>>[];
  final changeResults = <Future<SubscriptionDetail>>[];
  final checkoutPlans = <String>[];
  final changedPlans = <String>[];
  int cancelCalls = 0;
  int resumeCalls = 0;
  BillingConfig configResult = const BillingConfig(
    checkoutAvailable: true,
    sandbox: false,
  );
  SandboxCheckout? sandboxCheckout;
  int sandboxCheckoutCalls = 0;

  @override
  Future<BillingConfig> getConfig() async => configResult;

  @override
  Future<SandboxCheckout> getSandboxCheckout(String token) async {
    sandboxCheckoutCalls += 1;
    return sandboxCheckout!;
  }

  @override
  Future<Uri> createCheckout(String planCode) {
    checkoutPlans.add(planCode);
    return checkoutResults.removeAt(0);
  }

  @override
  Future<SubscriptionDetail> cancelSubscription() {
    cancelCalls += 1;
    return cancelResults.removeAt(0);
  }

  @override
  Future<SubscriptionDetail> resumeSubscription() {
    resumeCalls += 1;
    return resumeResults.removeAt(0);
  }

  @override
  Future<SubscriptionDetail> changePlan(String planCode) {
    changedPlans.add(planCode);
    return changeResults.removeAt(0);
  }

  @override
  Future<BillingEntitlements> getEntitlements() async =>
      entitlements(pro: true);

  @override
  Future<List<BillingHistoryEvent>> getHistory({int limit = 50}) async => [
    historyEvent(),
  ];
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
