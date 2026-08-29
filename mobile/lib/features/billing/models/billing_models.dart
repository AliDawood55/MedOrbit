class BillingEntitlements {
  const BillingEntitlements({
    required this.plan,
    required this.subscription,
    required this.chatbot,
    required this.voiceDoctor,
    required this.serverTime,
  });

  final String plan;
  final EntitlementSubscription subscription;
  final ChatEntitlement chatbot;
  final VoiceEntitlement voiceDoctor;
  final DateTime serverTime;

  bool get isPro => chatbot.unlimited && voiceDoctor.unlimited;

  factory BillingEntitlements.fromJson(Map<String, dynamic> json) {
    final features = _requiredMap(json, 'features');
    return BillingEntitlements(
      plan: _requiredString(json, 'plan'),
      subscription: EntitlementSubscription.fromJson(
        _requiredMap(json, 'subscription'),
      ),
      chatbot: ChatEntitlement.fromJson(_requiredMap(features, 'chatbot')),
      voiceDoctor: VoiceEntitlement.fromJson(
        _requiredMap(features, 'voice_doctor'),
      ),
      serverTime: _requiredDate(json, 'server_time'),
    );
  }

  BillingEntitlements copyWith({ChatEntitlement? chatbot}) {
    return BillingEntitlements(
      plan: plan,
      subscription: subscription,
      chatbot: chatbot ?? this.chatbot,
      voiceDoctor: voiceDoctor,
      serverTime: serverTime,
    );
  }
}

class EntitlementSubscription {
  const EntitlementSubscription({
    this.status,
    this.cancelAtPeriodEnd = false,
    this.currentPeriodEnd,
    this.billingInterval,
  });

  final String? status;
  final bool cancelAtPeriodEnd;
  final DateTime? currentPeriodEnd;
  final String? billingInterval;

  factory EntitlementSubscription.fromJson(Map<String, dynamic> json) {
    return EntitlementSubscription(
      status: _string(json['status']),
      cancelAtPeriodEnd: _bool(json['cancel_at_period_end']) ?? false,
      currentPeriodEnd: _date(json['current_period_end']),
      billingInterval: _string(json['billing_interval']),
    );
  }
}

class ChatEntitlement {
  const ChatEntitlement({
    required this.allowed,
    required this.unlimited,
    this.used,
    this.limit,
    this.remaining,
    this.resetsAt,
  });

  final bool allowed;
  final bool unlimited;
  final int? used;
  final int? limit;
  final int? remaining;
  final DateTime? resetsAt;

  factory ChatEntitlement.fromJson(Map<String, dynamic> json) {
    return ChatEntitlement(
      allowed: _requiredBool(json, 'allowed'),
      unlimited: _requiredBool(json, 'unlimited'),
      used: _int(json['used']),
      limit: _int(json['limit']),
      remaining: _int(json['remaining']),
      resetsAt: _date(json['resets_at']),
    );
  }

  factory ChatEntitlement.fromQuotaJson(Map<String, dynamic> json) {
    final limit = _int(json['limit']);
    final remaining = _int(json['remaining']);
    final unlimited = _bool(json['unlimited']) ?? limit == null;
    return ChatEntitlement(
      allowed: unlimited || (remaining != null && remaining > 0),
      unlimited: unlimited,
      used: _int(json['used']),
      limit: limit,
      remaining: remaining,
      resetsAt: _date(json['resets_at']),
    );
  }
}

class VoiceEntitlement {
  const VoiceEntitlement({
    required this.allowed,
    required this.unlimited,
    this.activeSessionId,
    this.nextFreeAt,
  });

  final bool allowed;
  final bool unlimited;
  final String? activeSessionId;
  final DateTime? nextFreeAt;

  bool get canResume => activeSessionId?.isNotEmpty == true;

  factory VoiceEntitlement.fromJson(Map<String, dynamic> json) {
    return VoiceEntitlement(
      allowed: _requiredBool(json, 'allowed'),
      unlimited: _requiredBool(json, 'unlimited'),
      activeSessionId: _string(json['active_session_id']),
      nextFreeAt: _date(json['next_free_at']),
    );
  }
}

class BillingPlan {
  const BillingPlan({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.priceCents,
    required this.currency,
    required this.billingInterval,
    required this.intervalCount,
    required this.grantsPro,
  });

  final String code;
  final String nameEn;
  final String nameAr;
  final int priceCents;
  final String currency;
  final String billingInterval;
  final int intervalCount;
  final bool grantsPro;

  String localizedName(bool isArabic) => isArabic ? nameAr : nameEn;

  factory BillingPlan.fromJson(Map<String, dynamic> json) {
    return BillingPlan(
      code: _requiredString(json, 'plan_code'),
      nameEn: _requiredString(json, 'name_en'),
      nameAr: _requiredString(json, 'name_ar'),
      priceCents: _requiredInt(json, 'price_cents'),
      currency: _requiredString(json, 'currency'),
      billingInterval: _requiredString(json, 'billing_interval'),
      intervalCount: _requiredInt(json, 'interval_count'),
      grantsPro: _requiredBool(json, 'grants_pro'),
    );
  }
}

class BillingConfig {
  const BillingConfig({required this.checkoutAvailable, required this.sandbox});

  final bool checkoutAvailable;
  final bool sandbox;

  factory BillingConfig.fromJson(Map<String, dynamic> json) {
    return BillingConfig(
      checkoutAvailable: _requiredBool(json, 'checkout_available'),
      sandbox: _requiredBool(json, 'sandbox'),
    );
  }
}

class SubscriptionDetail {
  const SubscriptionDetail({
    required this.planCode,
    required this.serverTime,
    this.planNameEn,
    this.planNameAr,
    this.priceCents,
    this.currency,
    this.billingInterval,
    this.intervalCount,
    this.status,
    this.cancelAtPeriodEnd = false,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.gracePeriodEndsAt,
    this.endedAt,
    this.pendingPlan,
  });

  final String planCode;
  final String? planNameEn;
  final String? planNameAr;
  final int? priceCents;
  final String? currency;
  final String? billingInterval;
  final int? intervalCount;
  final String? status;
  final bool cancelAtPeriodEnd;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? gracePeriodEndsAt;
  final DateTime? endedAt;
  final PendingBillingPlan? pendingPlan;
  final DateTime serverTime;

  bool get hasLiveSubscription =>
      status == 'incomplete' || status == 'active' || status == 'past_due';

  String localizedPlanName(bool isArabic, String freeName) {
    final value = isArabic ? planNameAr : planNameEn;
    return value?.trim().isNotEmpty == true ? value! : freeName;
  }

  factory SubscriptionDetail.fromJson(Map<String, dynamic> json) {
    final pending = _map(json['pending_plan']);
    return SubscriptionDetail(
      planCode: _requiredString(json, 'plan_code'),
      planNameEn: _string(json['plan_name_en']),
      planNameAr: _string(json['plan_name_ar']),
      priceCents: _int(json['price_cents']),
      currency: _string(json['currency']),
      billingInterval: _string(json['billing_interval']),
      intervalCount: _int(json['interval_count']),
      status: _string(json['status']),
      cancelAtPeriodEnd: _bool(json['cancel_at_period_end']) ?? false,
      currentPeriodStart: _date(json['current_period_start']),
      currentPeriodEnd: _date(json['current_period_end']),
      gracePeriodEndsAt: _date(json['grace_period_ends_at']),
      endedAt: _date(json['ended_at']),
      pendingPlan: pending == null
          ? null
          : PendingBillingPlan.fromJson(pending),
      serverTime: _requiredDate(json, 'server_time'),
    );
  }
}

class PendingBillingPlan {
  const PendingBillingPlan({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.priceCents,
    required this.billingInterval,
    required this.effectiveAt,
  });

  final String code;
  final String nameEn;
  final String nameAr;
  final int priceCents;
  final String billingInterval;
  final DateTime effectiveAt;

  String localizedName(bool isArabic) => isArabic ? nameAr : nameEn;

  factory PendingBillingPlan.fromJson(Map<String, dynamic> json) {
    return PendingBillingPlan(
      code: _requiredString(json, 'plan_code'),
      nameEn: _requiredString(json, 'name_en'),
      nameAr: _requiredString(json, 'name_ar'),
      priceCents: _requiredInt(json, 'price_cents'),
      billingInterval: _requiredString(json, 'billing_interval'),
      effectiveAt: _requiredDate(json, 'effective_at'),
    );
  }
}

class BillingHistoryEvent {
  const BillingHistoryEvent({
    required this.eventType,
    required this.occurredAt,
  });

  final String eventType;
  final DateTime occurredAt;

  factory BillingHistoryEvent.fromJson(Map<String, dynamic> json) {
    return BillingHistoryEvent(
      eventType: _requiredString(json, 'event_type'),
      occurredAt: _requiredDate(json, 'occurred_at'),
    );
  }
}

class SandboxCheckout {
  const SandboxCheckout({
    required this.planCode,
    required this.nameEn,
    required this.nameAr,
    required this.priceCents,
    required this.currency,
    required this.billingInterval,
    required this.intervalCount,
    required this.status,
    required this.isOpen,
    required this.expiresAt,
    required this.serverTime,
    required this.sandbox,
    this.returnPath,
  });

  final String planCode;
  final String nameEn;
  final String nameAr;
  final int priceCents;
  final String currency;
  final String billingInterval;
  final int intervalCount;
  final String status;
  final bool isOpen;
  final DateTime expiresAt;
  final String? returnPath;
  final DateTime serverTime;
  final bool sandbox;

  String localizedName(bool isArabic) => isArabic ? nameAr : nameEn;

  factory SandboxCheckout.fromJson(Map<String, dynamic> json) {
    return SandboxCheckout(
      planCode: _requiredString(json, 'plan_code'),
      nameEn: _requiredString(json, 'name_en'),
      nameAr: _requiredString(json, 'name_ar'),
      priceCents: _requiredInt(json, 'price_cents'),
      currency: _requiredString(json, 'currency'),
      billingInterval: _requiredString(json, 'billing_interval'),
      intervalCount: _requiredInt(json, 'interval_count'),
      status: _requiredString(json, 'status'),
      isOpen: _requiredBool(json, 'is_open'),
      expiresAt: _requiredDate(json, 'expires_at'),
      returnPath: _string(json['return_path']),
      serverTime: _requiredDate(json, 'server_time'),
      sandbox: _requiredBool(json, 'sandbox'),
    );
  }
}

class SandboxCheckoutResult {
  const SandboxCheckoutResult({
    required this.outcome,
    required this.entitlements,
    this.returnPath,
  });

  final String outcome;
  final String? returnPath;
  final BillingEntitlements entitlements;

  factory SandboxCheckoutResult.fromJson(Map<String, dynamic> json) {
    return SandboxCheckoutResult(
      outcome: _requiredString(json, 'outcome'),
      returnPath: _string(json['return_path']),
      entitlements: BillingEntitlements.fromJson(
        _requiredMap(json, 'entitlements'),
      ),
    );
  }
}

class BillingModelException implements Exception {
  const BillingModelException(this.field);

  final String field;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = _map(json[key]);
  if (value == null) throw BillingModelException(key);
  return value;
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json[key]);
  if (value == null || value.isEmpty) throw BillingModelException(key);
  return value;
}

bool? _bool(Object? value) => value is bool ? value : null;

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = _bool(json[key]);
  if (value == null) throw BillingModelException(key);
  return value;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = _int(json[key]);
  if (value == null) throw BillingModelException(key);
  return value;
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _date(json[key]);
  if (value == null) throw BillingModelException(key);
  return value;
}
