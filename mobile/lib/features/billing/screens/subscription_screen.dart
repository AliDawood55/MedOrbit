import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/billing_models.dart';
import '../providers/billing_provider.dart';
import '../widgets/billing_formatters.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(billingControllerProvider);
    final notifier = ref.read(billingControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.subscriptionTitle)),
      useSafeArea: true,
      body: state.isLoading && !state.hasData
          ? const Center(child: CircularProgressIndicator())
          : state.subscription == null
          ? Center(
              child: ErrorRetryState(
                title: strings.billingLoadErrorTitle,
                message: strings.billingLoadErrorMessage,
                retryLabel: strings.retry,
                onRetry: notifier.load,
              ),
            )
          : RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
                children: [
                  ResponsiveContent(
                    child: _SubscriptionContent(
                      strings: strings,
                      state: state,
                      notifier: notifier,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SubscriptionContent extends StatelessWidget {
  const _SubscriptionContent({
    required this.strings,
    required this.state,
    required this.notifier,
  });

  final AppStrings strings;
  final BillingState state;
  final BillingController notifier;

  @override
  Widget build(BuildContext context) {
    final subscription = state.subscription!;
    final busy = state.actionInFlight;
    final statusLabel = strings.subscriptionStatusLabel(
      subscription.status,
      subscription.cancelAtPeriodEnd,
    );
    final planName = subscription.localizedPlanName(
      strings.isArabic,
      strings.billingFreePlan,
    );
    final price =
        subscription.priceCents != null && subscription.currency != null
        ? formatServerPrice(
            priceCents: subscription.priceCents!,
            currency: subscription.currency!,
            isArabic: strings.isArabic,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageIntro(
          title: strings.subscriptionTitle,
          subtitle: strings.billingHostedCheckoutHint,
          icon: Icons.manage_accounts_outlined,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final header = SectionHeader(
                      title: planName,
                      subtitle: price == null
                          ? null
                          : '$price · ${strings.billingInterval(subscription.billingInterval ?? '', subscription.intervalCount ?? 1)}',
                    );
                    final badge = StatusBadge(
                      label: statusLabel,
                      color: _statusColor(subscription),
                    );
                    final stack =
                        constraints.maxWidth < 360 ||
                        MediaQuery.textScalerOf(
                              context,
                            ).scale(AppTheme.fontMd) >=
                            AppTheme.fontLg * 1.2;
                    if (stack) {
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
                if (subscription.currentPeriodStart != null)
                  _DetailRow(
                    label: strings.subscriptionPeriod,
                    value:
                        '${formatBillingDate(subscription.currentPeriodStart!, isArabic: strings.isArabic)} – ${subscription.currentPeriodEnd == null ? '—' : formatBillingDate(subscription.currentPeriodEnd!, isArabic: strings.isArabic)}',
                  ),
                if (subscription.currentPeriodEnd != null)
                  _DetailRow(
                    label: subscription.cancelAtPeriodEnd
                        ? strings.subscriptionEndsAt
                        : strings.subscriptionRenewsAt,
                    value: formatBillingDateTime(
                      subscription.currentPeriodEnd!,
                      isArabic: strings.isArabic,
                    ),
                  ),
                if (subscription.gracePeriodEndsAt != null) ...[
                  _DetailRow(
                    label: strings.subscriptionGraceEndsAt,
                    value: formatBillingDateTime(
                      subscription.gracePeriodEndsAt!,
                      isArabic: strings.isArabic,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  InlineMessage(
                    message: strings.subscriptionPastDueHint,
                    tone: InlineMessageTone.warning,
                  ),
                ],
                if (subscription.pendingPlan != null) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  InlineMessage(
                    message: strings.subscriptionPendingPlanHint(
                      subscription.pendingPlan!.localizedName(strings.isArabic),
                      formatBillingDate(
                        subscription.pendingPlan!.effectiveAt,
                        isArabic: strings.isArabic,
                      ),
                    ),
                    tone: InlineMessageTone.info,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (state.actionError != null) ...[
          const SizedBox(height: AppTheme.spaceMd),
          InlineMessage(
            message: strings.billingError(state.actionError!.code),
            tone: InlineMessageTone.error,
          ),
        ],
        if (subscription.hasLiveSubscription) ...[
          const SizedBox(height: AppTheme.spaceLg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: strings.subscriptionChangePlan),
                  for (final plan in state.plans.where(
                    (plan) =>
                        plan.grantsPro && plan.code != subscription.planCode,
                  )) ...[
                    _PlanChangeTile(
                      plan: plan,
                      strings: strings,
                      enabled: !busy && !subscription.cancelAtPeriodEnd,
                      onChanged: () =>
                          _confirmPlanChange(context, plan, notifier),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                  ],
                  const Divider(),
                  if (subscription.cancelAtPeriodEnd)
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => _confirmResume(context, notifier),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(strings.subscriptionResume),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _confirmCancel(context, notifier),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: Text(strings.subscriptionCancel),
                    ),
                  if (busy) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    BillingController notifier,
  ) async {
    final confirmed = await _confirm(
      context,
      strings.subscriptionCancelTitle,
      strings.subscriptionCancelBody,
      strings.subscriptionCancel,
    );
    if (confirmed != true) return;
    final ok = await notifier.cancelSubscription();
    if (ok && context.mounted) _success(context);
  }

  Future<void> _confirmResume(
    BuildContext context,
    BillingController notifier,
  ) async {
    final confirmed = await _confirm(
      context,
      strings.subscriptionResumeTitle,
      strings.subscriptionResumeBody,
      strings.subscriptionResume,
    );
    if (confirmed != true) return;
    final ok = await notifier.resumeSubscription();
    if (ok && context.mounted) _success(context);
  }

  Future<void> _confirmPlanChange(
    BuildContext context,
    BillingPlan plan,
    BillingController notifier,
  ) async {
    final name = plan.localizedName(strings.isArabic);
    final confirmed = await _confirm(
      context,
      strings.subscriptionChangeTitle(name),
      strings.subscriptionChangeBody(name),
      strings.confirm,
    );
    if (confirmed != true) return;
    final ok = await notifier.changePlan(plan.code);
    if (ok && context.mounted) _success(context);
  }

  Future<bool?> _confirm(
    BuildContext context,
    String title,
    String body,
    String action,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _success(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.subscriptionActionSuccess)));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: AppTheme.spaceMd,
        runSpacing: AppTheme.spaceXs,
        children: [
          Text(label),
          Text(value, textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

class _PlanChangeTile extends StatelessWidget {
  const _PlanChangeTile({
    required this.plan,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });

  final BillingPlan plan;
  final AppStrings strings;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final price = formatServerPrice(
      priceCents: plan.priceCents,
      currency: plan.currency,
      isArabic: strings.isArabic,
    );
    return FeatureCard(
      title: plan.localizedName(strings.isArabic),
      subtitle:
          '$price · ${strings.billingInterval(plan.billingInterval, plan.intervalCount)}',
      icon: Icons.calendar_month_outlined,
      trailing: Icon(
        AppTheme.directionalForwardIconOf(context),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: enabled ? onChanged : null,
    );
  }
}

Color _statusColor(SubscriptionDetail subscription) {
  if (subscription.status == 'active' && !subscription.cancelAtPeriodEnd) {
    return AppTheme.success;
  }
  if (subscription.status == 'past_due') return AppTheme.danger;
  if (subscription.cancelAtPeriodEnd || subscription.status == 'incomplete') {
    return AppTheme.warning;
  }
  return AppTheme.info;
}
