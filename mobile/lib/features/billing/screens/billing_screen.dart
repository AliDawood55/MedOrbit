import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/checkout_launcher.dart';
import '../models/billing_models.dart';
import '../providers/billing_provider.dart';
import '../widgets/billing_formatters.dart';
import '../widgets/server_countdown.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen>
    with WidgetsBindingObserver {
  final _plansKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(billingControllerProvider.notifier)
            .refreshAfterCheckoutReturn(),
      );
    }
  }

  Future<void> _checkout(BillingPlan plan) async {
    final notifier = ref.read(billingControllerProvider.notifier);
    final uri = await notifier.beginCheckout(plan.code);
    if (uri == null || !mounted) return;

    final config = ref.read(billingControllerProvider).config;
    if (config?.sandbox == true) {
      final token = uri.queryParameters['session'];
      if (token == null || token.isEmpty) {
        notifier.checkoutLaunchFailed();
        _showError('INVALID_RESPONSE');
        return;
      }
      await context.push(RoutePaths.billingSandboxPath(token));
      if (mounted) await notifier.refreshAfterCheckoutReturn();
      return;
    }

    var launched = false;
    try {
      launched = await ref.read(checkoutUrlLauncherProvider)(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      notifier.checkoutLaunchFailed();
      _showError('CHECKOUT_LAUNCH_FAILED');
    }
  }

  void _showError(String code) {
    final strings = ref.read(appStringsProvider);
    final message = code == 'CHECKOUT_LAUNCH_FAILED'
        ? strings.billingCheckoutLaunchFailed
        : strings.billingError(code);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(billingControllerProvider);
    final notifier = ref.read(billingControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.billingTitle),
        actions: [
          IconButton(
            tooltip: strings.billingRefresh,
            onPressed: state.isRefreshing ? null : notifier.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      useSafeArea: true,
      body: _body(context, strings, state, notifier),
    );
  }

  Widget _body(
    BuildContext context,
    AppStrings strings,
    BillingState state,
    BillingController notifier,
  ) {
    if (state.isLoading && !state.hasData) {
      return Center(
        child: Semantics(
          liveRegion: true,
          label: strings.loading,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (!state.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: ErrorRetryState(
            title: strings.billingLoadErrorTitle,
            message: strings.billingLoadErrorMessage,
            retryLabel: strings.retry,
            onRetry: notifier.load,
          ),
        ),
      );
    }

    final entitlements = state.entitlements!;
    final config = state.config!;
    final subscription = state.subscription!;
    final isArabic = strings.isArabic;

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageIntro(
                  title: strings.billingTitle,
                  subtitle: strings.billingSubtitle,
                  icon: Icons.workspace_premium_outlined,
                  color: AppTheme.violet,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                _CurrentPlanCard(
                  strings: strings,
                  entitlements: entitlements,
                  subscription: subscription,
                  onManage: subscription.hasLiveSubscription
                      ? () => context.push(RoutePaths.subscription)
                      : null,
                  onHistory: () => context.push(RoutePaths.billingHistory),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                _UsageCard(
                  strings: strings,
                  entitlements: entitlements,
                  onRefresh: notifier.refreshEntitlements,
                  onUpgrade: () => _scrollToPlans(context),
                ),
                if (config.sandbox) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  InlineMessage(
                    message: strings.sandboxBillingBanner,
                    tone: InlineMessageTone.warning,
                  ),
                  if (subscription.hasLiveSubscription) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    _SandboxLifecycleCard(
                      strings: strings,
                      state: state,
                      onSimulate: notifier.simulateLifecycle,
                    ),
                  ],
                ],
                const SizedBox(height: AppTheme.spaceXl),
                SectionHeader(
                  key: _plansKey,
                  title: strings.billingPlansTitle,
                  subtitle: strings.billingPlansSubtitle,
                ),
                if (!config.checkoutAvailable) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  InlineMessage(
                    message: strings.billingCheckoutUnavailable,
                    tone: InlineMessageTone.info,
                  ),
                ],
                if (state.checkoutAwaitingReturn && !config.sandbox) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  InlineMessage(
                    message: strings.billingCheckoutReturnHint,
                    tone: InlineMessageTone.info,
                  ),
                ],
                if (state.actionError != null) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  InlineMessage(
                    message: strings.billingError(state.actionError!.code),
                    tone: InlineMessageTone.error,
                  ),
                ],
                const SizedBox(height: AppTheme.spaceMd),
                for (final plan in state.plans) ...[
                  _PlanCard(
                    plan: plan,
                    strings: strings,
                    isArabic: isArabic,
                    isCurrent: entitlements.plan == plan.code,
                    checkoutAvailable: config.checkoutAvailable,
                    isLoading: state.activeAction == BillingAction.checkout,
                    onCheckout: () => _checkout(plan),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToPlans(BuildContext context) {
    final plansContext = _plansKey.currentContext;
    if (plansContext != null) Scrollable.ensureVisible(plansContext);
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.strings,
    required this.entitlements,
    required this.subscription,
    required this.onHistory,
    this.onManage,
  });

  final AppStrings strings;
  final BillingEntitlements entitlements;
  final SubscriptionDetail subscription;
  final VoidCallback? onManage;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final isPro = entitlements.isPro;
    final planName = subscription.localizedPlanName(
      strings.isArabic,
      strings.billingFreePlan,
    );
    final status = strings.subscriptionStatusLabel(
      subscription.status,
      subscription.cancelAtPeriodEnd,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final badge = StatusBadge(
                  label: isPro
                      ? strings.billingProBadge
                      : strings.billingFreeBadge,
                  color: isPro ? AppTheme.success : AppTheme.info,
                );
                final header = SectionHeader(
                  title: strings.billingCurrentPlan,
                  subtitle: planName,
                );
                if (_stackBillingHeader(context, constraints.maxWidth)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: badge,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    badge,
                  ],
                );
              },
            ),
            if (subscription.status != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              Text(status),
            ],
            const SizedBox(height: AppTheme.spaceMd),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                if (onManage != null)
                  OutlinedButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(strings.subscriptionTitle),
                  ),
                TextButton.icon(
                  onPressed: onHistory,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(strings.billingHistoryTitle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.strings,
    required this.entitlements,
    required this.onRefresh,
    required this.onUpgrade,
  });

  final AppStrings strings;
  final BillingEntitlements entitlements;
  final VoidCallback onRefresh;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final chat = entitlements.chatbot;
    final voice = entitlements.voiceDoctor;
    final chatText = chat.unlimited
        ? strings.billingChatUnlimited
        : chat.remaining != null && chat.limit != null
        ? strings.billingChatRemaining(chat.remaining!, chat.limit!)
        : strings.billingChatUnavailable;
    final voiceText = voice.canResume
        ? strings.billingVoiceActive
        : voice.unlimited
        ? strings.billingVoiceUnlimited
        : voice.allowed
        ? strings.billingVoiceAvailable
        : strings.billingVoiceCooldown;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.billingUsageTitle),
            const SizedBox(height: AppTheme.spaceMd),
            FeatureCard(
              title: chatText,
              icon: Icons.chat_bubble_outline_rounded,
              color: AppTheme.primary,
              trailing: !chat.unlimited && chat.resetsAt != null
                  ? ServerCountdown(
                      target: chat.resetsAt!,
                      serverTime: entitlements.serverTime,
                      isArabic: strings.isArabic,
                      onElapsed: onRefresh,
                    )
                  : null,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            FeatureCard(
              title: voiceText,
              icon: Icons.record_voice_over_outlined,
              color: AppTheme.violet,
              trailing: !voice.unlimited && voice.nextFreeAt != null
                  ? ServerCountdown(
                      target: voice.nextFreeAt!,
                      serverTime: entitlements.serverTime,
                      isArabic: strings.isArabic,
                      onElapsed: onRefresh,
                    )
                  : null,
            ),
            if (!entitlements.isPro) ...[
              const SizedBox(height: AppTheme.spaceMd),
              OutlinedButton.icon(
                onPressed: onUpgrade,
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(strings.entitlementUpgradeAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.strings,
    required this.isArabic,
    required this.isCurrent,
    required this.checkoutAvailable,
    required this.isLoading,
    required this.onCheckout,
  });

  final BillingPlan plan;
  final AppStrings strings;
  final bool isArabic;
  final bool isCurrent;
  final bool checkoutAvailable;
  final bool isLoading;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final price = formatServerPrice(
      priceCents: plan.priceCents,
      currency: plan.currency,
      isArabic: isArabic,
    );
    final interval = strings.billingInterval(
      plan.billingInterval,
      plan.intervalCount,
    );
    final canCheckout =
        plan.grantsPro && !isCurrent && checkoutAvailable && !isLoading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  plan.localizedName(isArabic),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: AppTheme.weightExtraBold,
                  ),
                );
                if (!isCurrent) return title;
                final badge = StatusBadge(
                  label: strings.billingCurrentPlanAction,
                  color: AppTheme.success,
                );
                if (_stackBillingHeader(context, constraints.maxWidth)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: AppTheme.spaceSm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: badge,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    badge,
                  ],
                );
              },
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              '$price · $interval',
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (plan.grantsPro && !isCurrent) ...[
              const SizedBox(height: AppTheme.spaceMd),
              PrimaryButton(
                label: strings.billingUpgrade,
                icon: Icons.lock_open_rounded,
                isLoading: isLoading,
                onPressed: canCheckout ? onCheckout : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _stackBillingHeader(BuildContext context, double width) {
  return width < 360 ||
      MediaQuery.textScalerOf(context).scale(AppTheme.fontMd) >=
          AppTheme.fontLg * 1.2;
}

class _SandboxLifecycleCard extends StatelessWidget {
  const _SandboxLifecycleCard({
    required this.strings,
    required this.state,
    required this.onSimulate,
  });

  final AppStrings strings;
  final BillingState state;
  final Future<bool> Function(String kind) onSimulate;

  @override
  Widget build(BuildContext context) {
    final busy = state.activeAction == BillingAction.sandboxSimulation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.sandboxLifecycleTitle,
              subtitle: strings.sandboxBillingBanner,
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                _simulationButton(
                  context,
                  'renewal',
                  strings.sandboxRenewal,
                  busy,
                ),
                _simulationButton(
                  context,
                  'renewal_failure',
                  strings.sandboxRenewalFailure,
                  busy,
                ),
                _simulationButton(
                  context,
                  'payment_recovered',
                  strings.sandboxPaymentRecovered,
                  busy,
                ),
                _simulationButton(
                  context,
                  'ended',
                  strings.sandboxSubscriptionEnded,
                  busy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _simulationButton(
    BuildContext context,
    String kind,
    String label,
    bool busy,
  ) {
    return OutlinedButton(
      onPressed: busy
          ? null
          : () async {
              if (kind == 'ended') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(label),
                    content: Text(strings.sandboxBillingBanner),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(strings.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(strings.confirm),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              await onSimulate(kind);
            },
      child: Text(label),
    );
  }
}
