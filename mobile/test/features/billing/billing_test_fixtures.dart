import 'package:mobile/features/billing/models/billing_models.dart';

final serverNow = DateTime.parse('2026-08-29T10:00:00Z');

Map<String, dynamic> entitlementJson({
  bool pro = false,
  bool exhausted = false,
}) {
  return {
    'plan': pro ? 'pro_monthly' : 'free',
    'subscription': {
      'status': pro ? 'active' : null,
      'cancel_at_period_end': false,
      'current_period_end': pro ? '2026-09-29T10:00:00Z' : null,
      'billing_interval': pro ? 'month' : null,
    },
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
    'server_time': serverNow.toIso8601String(),
  };
}

Map<String, dynamic> planJson({
  String code = 'pro_monthly',
  String interval = 'month',
  int cents = 2345,
}) {
  return {
    'plan_code': code,
    'name_en': interval == 'month' ? 'Orbit Pro Monthly' : 'Orbit Pro Annual',
    'name_ar': interval == 'month' ? 'أوربت برو الشهري' : 'أوربت برو السنوي',
    'price_cents': cents,
    'currency': 'USD',
    'billing_interval': interval,
    'interval_count': 1,
    'grants_pro': true,
  };
}

Map<String, dynamic> subscriptionJson({
  String planCode = 'free',
  String? status,
  bool cancelAtPeriodEnd = false,
  Map<String, dynamic>? pendingPlan,
}) {
  final live = status != null;
  return {
    'plan_code': planCode,
    'plan_name_en': live ? 'Orbit Pro Monthly' : 'Free',
    'plan_name_ar': live ? 'أوربت برو الشهري' : 'مجانية',
    'price_cents': live ? 2345 : 0,
    'currency': 'USD',
    'billing_interval': live ? 'month' : null,
    'interval_count': live ? 1 : null,
    'status': status,
    'cancel_at_period_end': cancelAtPeriodEnd,
    'current_period_start': live ? '2026-08-29T10:00:00Z' : null,
    'current_period_end': live ? '2026-09-29T10:00:00Z' : null,
    'grace_period_ends_at': status == 'past_due'
        ? '2026-09-02T10:00:00Z'
        : null,
    'ended_at': null,
    'pending_plan': pendingPlan,
    'server_time': serverNow.toIso8601String(),
  };
}

BillingEntitlements entitlements({bool pro = false, bool exhausted = false}) =>
    BillingEntitlements.fromJson(
      entitlementJson(pro: pro, exhausted: exhausted),
    );

BillingPlan monthlyPlan() => BillingPlan.fromJson(planJson());

BillingPlan annualPlan() => BillingPlan.fromJson(
  planJson(code: 'pro_annual', interval: 'year', cents: 19999),
);

SubscriptionDetail freeSubscription() =>
    SubscriptionDetail.fromJson(subscriptionJson());

SubscriptionDetail activeSubscription({bool cancelAtPeriodEnd = false}) =>
    SubscriptionDetail.fromJson(
      subscriptionJson(
        planCode: 'pro_monthly',
        status: 'active',
        cancelAtPeriodEnd: cancelAtPeriodEnd,
      ),
    );

BillingHistoryEvent historyEvent() => BillingHistoryEvent.fromJson({
  'event_type': 'subscription_started',
  'occurred_at': '2026-08-29T10:00:00Z',
});
