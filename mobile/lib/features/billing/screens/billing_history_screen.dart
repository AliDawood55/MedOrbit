import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../providers/billing_provider.dart';
import '../widgets/billing_formatters.dart';

class BillingHistoryScreen extends ConsumerWidget {
  const BillingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(billingControllerProvider);
    final notifier = ref.read(billingControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.billingHistoryTitle)),
      useSafeArea: true,
      body: state.isLoading && !state.hasData
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && !state.hasData
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageIntro(
                          title: strings.billingHistoryTitle,
                          subtitle: strings.billingHistorySubtitle,
                          icon: Icons.receipt_long_outlined,
                        ),
                        const SizedBox(height: AppTheme.spaceLg),
                        if (state.history.isEmpty)
                          EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: strings.billingHistoryEmpty,
                            variant: EmptyStateVariant.compact,
                          )
                        else
                          for (final event in state.history) ...[
                            FeatureCard(
                              title: strings.billingHistoryEvent(
                                event.eventType,
                              ),
                              subtitle: formatBillingDateTime(
                                event.occurredAt,
                                isArabic: strings.isArabic,
                              ),
                              icon: _eventIcon(event.eventType),
                              color: _eventColor(event.eventType),
                            ),
                            const SizedBox(height: AppTheme.spaceSm),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

IconData _eventIcon(String type) {
  if (type == 'payment.failed') return Icons.error_outline_rounded;
  if (type == 'payment.recovered') return Icons.check_circle_outline_rounded;
  if (type.contains('cancel')) return Icons.event_busy_outlined;
  if (type.contains('renew')) return Icons.autorenew_rounded;
  return Icons.receipt_long_outlined;
}

Color _eventColor(String type) {
  if (type == 'payment.failed') return AppTheme.danger;
  if (type == 'payment.recovered' || type.contains('activated')) {
    return AppTheme.success;
  }
  if (type.contains('cancel')) return AppTheme.warning;
  return AppTheme.info;
}
