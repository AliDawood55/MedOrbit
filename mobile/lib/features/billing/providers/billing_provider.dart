import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/billing_api.dart';
import '../models/billing_models.dart';

final billingApiProvider = Provider<BillingApi>(
  (ref) => BillingApi(ref.watch(dioProvider)),
);

enum BillingAction {
  checkout,
  cancel,
  resume,
  changePlan,
  sandboxCheckout,
  sandboxSimulation,
}

class BillingState {
  const BillingState({
    this.entitlements,
    this.plans = const [],
    this.config,
    this.subscription,
    this.history = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.checkoutAwaitingReturn = false,
    this.activeAction,
    this.error,
    this.actionError,
  });

  final BillingEntitlements? entitlements;
  final List<BillingPlan> plans;
  final BillingConfig? config;
  final SubscriptionDetail? subscription;
  final List<BillingHistoryEvent> history;
  final bool isLoading;
  final bool isRefreshing;
  final bool checkoutAwaitingReturn;
  final BillingAction? activeAction;
  final ApiException? error;
  final ApiException? actionError;

  bool get hasData =>
      entitlements != null && config != null && subscription != null;
  bool get actionInFlight => activeAction != null;

  BillingState copyWith({
    BillingEntitlements? entitlements,
    List<BillingPlan>? plans,
    BillingConfig? config,
    SubscriptionDetail? subscription,
    List<BillingHistoryEvent>? history,
    bool? isLoading,
    bool? isRefreshing,
    bool? checkoutAwaitingReturn,
    BillingAction? activeAction,
    bool clearActiveAction = false,
    ApiException? error,
    bool clearError = false,
    ApiException? actionError,
    bool clearActionError = false,
  }) {
    return BillingState(
      entitlements: entitlements ?? this.entitlements,
      plans: plans ?? this.plans,
      config: config ?? this.config,
      subscription: subscription ?? this.subscription,
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      checkoutAwaitingReturn:
          checkoutAwaitingReturn ?? this.checkoutAwaitingReturn,
      activeAction: clearActiveAction
          ? null
          : (activeAction ?? this.activeAction),
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

class BillingController extends StateNotifier<BillingState> {
  BillingController(this._api, {required String? accountKey})
    : _accountKey = accountKey,
      super(const BillingState()) {
    if (accountKey != null) unawaited(load());
  }

  final BillingApi _api;
  final String? _accountKey;

  int _loadGeneration = 0;
  int _entitlementRevision = 0;
  bool _disposed = false;

  Future<void> load({bool refresh = false}) async {
    if (_accountKey == null) return;
    final generation = ++_loadGeneration;
    final entitlementRevision = _entitlementRevision;
    _set(
      state.copyWith(
        isLoading: !state.hasData,
        isRefreshing: refresh && state.hasData,
        clearError: true,
      ),
    );

    try {
      final results = await Future.wait<Object>([
        _api.getEntitlements(),
        _api.getPlans(),
        _api.getConfig(),
        _api.getSubscription(),
        _api.getHistory(),
      ]);
      if (!_isCurrent(generation)) return;
      _set(
        state.copyWith(
          entitlements: entitlementRevision == _entitlementRevision
              ? results[0] as BillingEntitlements
              : state.entitlements,
          plans: results[1] as List<BillingPlan>,
          config: results[2] as BillingConfig,
          subscription: results[3] as SubscriptionDetail,
          history: results[4] as List<BillingHistoryEvent>,
          isLoading: false,
          isRefreshing: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _set(
        state.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: ApiException.from(error),
        ),
      );
    }
  }

  Future<void> refresh() => load(refresh: true);

  Future<void> refreshEntitlements() async {
    if (_accountKey == null) return;
    final revision = ++_entitlementRevision;
    try {
      final entitlements = await _api.getEntitlements();
      if (_disposed || revision != _entitlementRevision) return;
      _set(state.copyWith(entitlements: entitlements));
    } catch (_) {
      // Feature screens keep their last known snapshot and the backend still
      // enforces every action. The full billing screen exposes refresh errors.
    }
  }

  void applyChatQuota(ChatEntitlement quota) {
    _entitlementRevision += 1;
    final current = state.entitlements;
    if (current != null) {
      _set(state.copyWith(entitlements: current.copyWith(chatbot: quota)));
    }
  }

  void applyEntitlements(BillingEntitlements entitlements) {
    _entitlementRevision += 1;
    _set(state.copyWith(entitlements: entitlements));
  }

  Future<Uri?> beginCheckout(String planCode) async {
    if (state.actionInFlight || state.checkoutAwaitingReturn) return null;
    _beginAction(BillingAction.checkout);
    try {
      final uri = await _api.createCheckout(planCode);
      if (_disposed) return null;
      _set(
        state.copyWith(checkoutAwaitingReturn: true, clearActiveAction: true),
      );
      return uri;
    } catch (error) {
      _failAction(error);
      return null;
    }
  }

  void checkoutLaunchFailed() {
    _set(state.copyWith(checkoutAwaitingReturn: false));
  }

  Future<void> refreshAfterCheckoutReturn() async {
    if (!state.checkoutAwaitingReturn) return;
    _set(state.copyWith(checkoutAwaitingReturn: false));
    await load(refresh: true);
  }

  Future<void> refreshAfterSandboxCheckout(
    BillingEntitlements entitlements,
  ) async {
    applyEntitlements(entitlements);
    _set(state.copyWith(checkoutAwaitingReturn: false));
    await load(refresh: true);
  }

  Future<bool> cancelSubscription() async {
    if (!_beginAction(BillingAction.cancel)) return false;
    try {
      final subscription = await _api.cancelSubscription();
      return _finishSubscriptionAction(subscription);
    } catch (error) {
      _failAction(error);
      return false;
    }
  }

  Future<bool> resumeSubscription() async {
    if (!_beginAction(BillingAction.resume)) return false;
    try {
      final subscription = await _api.resumeSubscription();
      return _finishSubscriptionAction(subscription);
    } catch (error) {
      _failAction(error);
      return false;
    }
  }

  Future<bool> changePlan(String planCode) async {
    if (!_beginAction(BillingAction.changePlan)) return false;
    try {
      final subscription = await _api.changePlan(planCode);
      return _finishSubscriptionAction(subscription);
    } catch (error) {
      _failAction(error);
      return false;
    }
  }

  Future<bool> simulateLifecycle(String kind) async {
    if (state.config?.sandbox != true ||
        !_beginAction(BillingAction.sandboxSimulation)) {
      return false;
    }
    try {
      final subscription = await _api.simulateSandboxLifecycle(kind);
      return _finishSubscriptionAction(subscription);
    } catch (error) {
      _failAction(error);
      return false;
    }
  }

  bool _finishSubscriptionAction(SubscriptionDetail subscription) {
    if (_disposed) return false;
    _set(
      state.copyWith(
        subscription: subscription,
        clearActiveAction: true,
        clearActionError: true,
      ),
    );
    unawaited(refreshEntitlements());
    unawaited(_refreshHistory());
    return true;
  }

  Future<void> _refreshHistory() async {
    try {
      final history = await _api.getHistory();
      if (!_disposed) _set(state.copyWith(history: history));
    } catch (_) {
      // A lifecycle action already succeeded. A history refresh failure must
      // not replace that authoritative subscription response with an error.
    }
  }

  bool _beginAction(BillingAction action) {
    if (_disposed || state.actionInFlight) return false;
    _set(state.copyWith(activeAction: action, clearActionError: true));
    return true;
  }

  void _failAction(Object error) {
    if (_disposed) return;
    _set(
      state.copyWith(
        clearActiveAction: true,
        actionError: ApiException.from(error),
      ),
    );
  }

  void clearActionError() => _set(state.copyWith(clearActionError: true));

  bool _isCurrent(int generation) =>
      !_disposed && generation == _loadGeneration;

  void _set(BillingState next) {
    if (!_disposed) state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration += 1;
    _entitlementRevision += 1;
    super.dispose();
  }
}

final billingControllerProvider =
    StateNotifierProvider.autoDispose<BillingController, BillingState>((ref) {
      final accountKey = ref.watch(
        authControllerProvider.select(
          (state) =>
              state.status == AuthStatus.authenticated ? state.user?.id : null,
        ),
      );
      return BillingController(
        ref.watch(billingApiProvider),
        accountKey: accountKey,
      );
    });
