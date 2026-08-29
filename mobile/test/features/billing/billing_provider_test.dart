import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/billing/data/billing_api.dart';
import 'package:mobile/features/billing/models/billing_models.dart';
import 'package:mobile/features/billing/providers/billing_provider.dart';

import 'billing_test_fixtures.dart';

void main() {
  test('authenticated account performs one complete initial load', () async {
    final api = _FakeBillingApi();
    final controller = BillingController(api, accountKey: 'user-a');
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.hasData);

    expect(api.entitlementCalls, 1);
    expect(api.planCalls, 1);
    expect(api.configCalls, 1);
    expect(api.subscriptionCalls, 1);
    expect(api.historyCalls, 1);
    expect(controller.state.entitlements?.chatbot.remaining, 5);
    expect(controller.state.isLoading, isFalse);
  });

  test(
    'signed-out account does not fetch or retain another account snapshot',
    () async {
      final api = _FakeBillingApi();
      final signedOut = BillingController(api, accountKey: null);
      addTearDown(signedOut.dispose);
      await signedOut.load();

      expect(api.totalReadCalls, 0);
      expect(signedOut.state.hasData, isFalse);

      final signedIn = BillingController(api, accountKey: 'user-b');
      addTearDown(signedIn.dispose);
      await _waitFor(() => signedIn.state.hasData);
      expect(signedIn.state.entitlements, isNotNull);
      expect(signedOut.state.entitlements, isNull);
    },
  );

  test(
    'a slower older refresh cannot overwrite the newest account snapshot',
    () async {
      final api = _FakeBillingApi();
      final controller = BillingController(api, accountKey: 'user-a');
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.hasData);

      final stale = Completer<BillingEntitlements>();
      api.entitlementResults.add(stale.future);
      api.entitlementResults.add(Future.value(entitlements(pro: true)));

      final first = controller.refresh();
      final second = controller.refresh();
      await second;
      expect(controller.state.entitlements?.isPro, isTrue);

      stale.complete(entitlements());
      await first;
      expect(controller.state.entitlements?.isPro, isTrue);
    },
  );

  test(
    'a targeted quota update wins over an older aggregate refresh',
    () async {
      final api = _FakeBillingApi();
      final controller = BillingController(api, accountKey: 'user-a');
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.hasData);

      final stale = Completer<BillingEntitlements>();
      api.entitlementResults.add(stale.future);
      final refresh = controller.refresh();
      controller.applyChatQuota(
        const ChatEntitlement(
          allowed: false,
          unlimited: false,
          used: 7,
          limit: 7,
          remaining: 0,
        ),
      );
      stale.complete(entitlements());
      await refresh;

      expect(controller.state.entitlements?.chatbot.remaining, 0);
    },
  );

  test(
    'disposal ignores a delayed initial response without post-dispose writes',
    () async {
      final api = _FakeBillingApi();
      final delayed = Completer<BillingEntitlements>();
      api.entitlementResults.add(delayed.future);
      final controller = BillingController(api, accountKey: 'user-a');

      controller.dispose();
      delayed.complete(entitlements(pro: true));
      await Future<void>.delayed(Duration.zero);

      expect(api.entitlementCalls, 1);
    },
  );

  test(
    'duplicate checkout is suppressed until launch or return is resolved',
    () async {
      final api = _FakeBillingApi();
      final pending = Completer<Uri>();
      api.checkoutResults.add(pending.future);
      final controller = BillingController(api, accountKey: null);
      addTearDown(controller.dispose);

      final first = controller.beginCheckout('pro_monthly');
      final duplicate = await controller.beginCheckout('pro_monthly');
      expect(duplicate, isNull);
      expect(api.checkoutCalls, ['pro_monthly']);

      pending.complete(Uri.parse('https://payments.example.test/session/a'));
      expect(await first, isNotNull);
      expect(controller.state.checkoutAwaitingReturn, isTrue);
      expect(await controller.beginCheckout('pro_monthly'), isNull);

      controller.checkoutLaunchFailed();
      expect(controller.state.checkoutAwaitingReturn, isFalse);
    },
  );

  test(
    'sandbox completion clears checkout lock and keeps returned entitlement fresh',
    () async {
      final api = _FakeBillingApi();
      final checkout = Completer<Uri>();
      api.checkoutResults.add(checkout.future);
      final controller = BillingController(api, accountKey: null);
      addTearDown(controller.dispose);

      final pending = controller.beginCheckout('pro_monthly');
      checkout.complete(Uri.parse('/billing-sandbox.html?session=cs_mock_abc'));
      await pending;
      expect(controller.state.checkoutAwaitingReturn, isTrue);

      await controller.refreshAfterSandboxCheckout(entitlements(pro: true));

      expect(controller.state.checkoutAwaitingReturn, isFalse);
      expect(controller.state.entitlements?.isPro, isTrue);
    },
  );

  test('cancel blocks simultaneous resume and plan-change mutations', () async {
    final api = _FakeBillingApi();
    final pending = Completer<SubscriptionDetail>();
    api.cancelResults.add(pending.future);
    final controller = BillingController(api, accountKey: null);
    addTearDown(controller.dispose);

    final cancel = controller.cancelSubscription();
    expect(await controller.resumeSubscription(), isFalse);
    expect(await controller.changePlan('pro_annual'), isFalse);
    expect(api.cancelCalls, 1);
    expect(api.resumeCalls, 0);
    expect(api.changedPlans, isEmpty);

    pending.complete(activeSubscription(cancelAtPeriodEnd: true));
    expect(await cancel, isTrue);
    expect(controller.state.subscription?.cancelAtPeriodEnd, isTrue);
  });

  test(
    'resume and plan change apply only returned server subscription state',
    () async {
      final api = _FakeBillingApi()
        ..resumeResults.add(Future.value(activeSubscription()))
        ..changeResults.add(
          Future.value(
            SubscriptionDetail.fromJson(
              subscriptionJson(
                planCode: 'pro_monthly',
                status: 'active',
                pendingPlan: {
                  ...planJson(
                    code: 'pro_annual',
                    interval: 'year',
                    cents: 19999,
                  ),
                  'effective_at': '2026-09-29T10:00:00Z',
                },
              ),
            ),
          ),
        );
      final controller = BillingController(api, accountKey: null);
      addTearDown(controller.dispose);

      expect(await controller.resumeSubscription(), isTrue);
      expect(await controller.changePlan('pro_annual'), isTrue);
      expect(controller.state.subscription?.pendingPlan?.code, 'pro_annual');
      expect(api.changedPlans, ['pro_annual']);
    },
  );

  test(
    'sandbox lifecycle is unreachable unless backend config says sandbox',
    () async {
      final api = _FakeBillingApi();
      final controller = BillingController(api, accountKey: null);
      addTearDown(controller.dispose);
      controller.state = BillingState(
        config: const BillingConfig(checkoutAvailable: true, sandbox: false),
      );

      expect(await controller.simulateLifecycle('renewal'), isFalse);
      expect(api.simulationKinds, isEmpty);

      controller.state = const BillingState(
        config: BillingConfig(checkoutAvailable: true, sandbox: true),
      );
      api.simulationResults.add(Future.value(activeSubscription()));
      expect(await controller.simulateLifecycle('renewal'), isTrue);
      expect(api.simulationKinds, ['renewal']);
    },
  );

  test(
    'mutation error preserves its stable code and releases the action lock',
    () async {
      final api = _FakeBillingApi()
        ..cancelResults.add(
          Future.error(
            const ApiException(
              message: 'raw text',
              code: 'SUBSCRIPTION_NOT_FOUND',
            ),
          ),
        );
      final controller = BillingController(api, accountKey: null);
      addTearDown(controller.dispose);

      expect(await controller.cancelSubscription(), isFalse);
      expect(controller.state.actionError?.code, 'SUBSCRIPTION_NOT_FOUND');
      expect(controller.state.actionInFlight, isFalse);
    },
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var i = 0; i < 30 && !predicate(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}

class _FakeBillingApi extends BillingApi {
  _FakeBillingApi() : super(Dio());

  final entitlementResults = <Future<BillingEntitlements>>[];
  final checkoutResults = <Future<Uri>>[];
  final cancelResults = <Future<SubscriptionDetail>>[];
  final resumeResults = <Future<SubscriptionDetail>>[];
  final changeResults = <Future<SubscriptionDetail>>[];
  final simulationResults = <Future<SubscriptionDetail>>[];

  int entitlementCalls = 0;
  int planCalls = 0;
  int configCalls = 0;
  int subscriptionCalls = 0;
  int historyCalls = 0;
  int cancelCalls = 0;
  int resumeCalls = 0;
  final checkoutCalls = <String>[];
  final changedPlans = <String>[];
  final simulationKinds = <String>[];

  int get totalReadCalls =>
      entitlementCalls +
      planCalls +
      configCalls +
      subscriptionCalls +
      historyCalls;

  @override
  Future<BillingEntitlements> getEntitlements() {
    entitlementCalls += 1;
    return entitlementResults.isEmpty
        ? Future.value(entitlements())
        : entitlementResults.removeAt(0);
  }

  @override
  Future<List<BillingPlan>> getPlans() {
    planCalls += 1;
    return Future.value([monthlyPlan(), annualPlan()]);
  }

  @override
  Future<BillingConfig> getConfig() {
    configCalls += 1;
    return Future.value(
      const BillingConfig(checkoutAvailable: true, sandbox: false),
    );
  }

  @override
  Future<SubscriptionDetail> getSubscription() {
    subscriptionCalls += 1;
    return Future.value(freeSubscription());
  }

  @override
  Future<List<BillingHistoryEvent>> getHistory({int limit = 50}) {
    historyCalls += 1;
    return Future.value([historyEvent()]);
  }

  @override
  Future<Uri> createCheckout(String planCode) {
    checkoutCalls.add(planCode);
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
  Future<SubscriptionDetail> simulateSandboxLifecycle(String kind) {
    simulationKinds.add(kind);
    return simulationResults.removeAt(0);
  }
}
