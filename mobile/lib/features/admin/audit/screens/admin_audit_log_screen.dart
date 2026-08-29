import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_detail_rows.dart';
import '../../common/widgets/admin_filter_chips.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_audit_log.dart';
import '../providers/admin_audit_provider.dart';

/// Read-only audit trail.
///
/// The backend exposes `GET /api/admin/audit-logs` under `authorizeAdmin` but
/// the web application has no page for it; this surfaces the record on mobile
/// without adding any capability the API does not already grant. There is no
/// write path here — the route has none.
class AdminAuditLogScreen extends ConsumerWidget {
  const AdminAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminAuditTitle,
      child: const _AdminAuditLogView(),
    );
  }
}

class _AdminAuditLogView extends ConsumerWidget {
  const _AdminAuditLogView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(adminAuditControllerProvider);
    final controller = ref.read(adminAuditControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminAuditTitle),
        actions: [
          IconButton(
            key: const ValueKey('admin-audit-refresh'),
            tooltip: strings.adminRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
          ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveContent(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminFilterChips<AdminAuditRange>(
                    label: strings.adminAuditRangeLabel,
                    selected: state.range,
                    onSelected: (range) =>
                        controller.setRange(range ?? AdminAuditRange.week),
                    options: [
                      AdminFilterOption(
                        value: AdminAuditRange.day,
                        label: strings.adminAuditRangeDay,
                        key: const ValueKey('admin-audit-range-day'),
                      ),
                      AdminFilterOption(
                        value: AdminAuditRange.week,
                        label: strings.adminAuditRangeWeek,
                        key: const ValueKey('admin-audit-range-week'),
                      ),
                      AdminFilterOption(
                        value: AdminAuditRange.month,
                        label: strings.adminAuditRangeMonth,
                        key: const ValueKey('admin-audit-range-month'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  AdminFilterChips<String>(
                    label: strings.adminAuditEntityLabel,
                    selected: state.entityType,
                    onSelected: controller.setEntityType,
                    options: [
                      AdminFilterOption(
                        value: null,
                        label: strings.adminFilterAll,
                        key: const ValueKey('admin-audit-entity-all'),
                      ),
                      for (final type in adminAuditEntityTypes)
                        AdminFilterOption(
                          value: type,
                          label: type,
                          key: ValueKey('admin-audit-entity-$type'),
                        ),
                    ],
                  ),
                  // Above the list rather than after it: learning that the
                  // window was capped is only useful before the entries are
                  // read, not two hundred rows later.
                  if (state.truncated) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    InlineMessage(
                      message: strings.adminAuditTruncatedNote(
                        adminAuditRenderLimit,
                      ),
                      tone: InlineMessageTone.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _body(
                context: context,
                controller: controller,
                state: state,
                strings: strings,
                isArabic: isArabic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body({
    required BuildContext context,
    required AdminAuditController controller,
    required AdminAuditState state,
    required AppStrings strings,
    required bool isArabic,
  }) {
    if (!state.hasLoadedOnce && state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasLoadedOnce && state.errorCode != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorRetryState(
            title: strings.adminLoadErrorTitle,
            message: strings.adminError(state.errorCode),
            retryLabel: strings.retry,
            onRetry: controller.load,
            retryKey: const ValueKey('admin-audit-retry'),
          ),
        ],
      );
    }
    if (state.entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            key: const ValueKey('admin-audit-empty'),
            icon: Icons.history_toggle_off_outlined,
            title: strings.adminAuditEmptyTitle,
            hint: strings.adminAuditEmptyHint,
          ),
        ],
      );
    }

    return ResponsiveContent(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.pageHorizontalPadding(
            MediaQuery.sizeOf(context).width,
          ),
          vertical: AppTheme.spaceSm,
        ),
        itemCount: state.entries.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          if (index == state.entries.length) {
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceSm),
              child: Text(
                strings.adminAuditPayloadNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          return _AuditCard(
            entry: state.entries[index],
            strings: strings,
            isArabic: isArabic,
          );
        },
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({
    required this.entry,
    required this.strings,
    required this.isArabic,
  });

  final AdminAuditLog entry;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = entry.userRole == null
        ? strings.adminAuditSystemActor
        : strings.adminRoleLabel(entry.userRole!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.action,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: AppTheme.weightBold,
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                StatusBadge(label: actor, color: AppTheme.primary),
                if (entry.entityType != null)
                  StatusBadge(label: entry.entityType!, color: AppTheme.info),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),
            AdminDetailRow(
              label: strings.adminAuditWhen,
              value: adminFormatDateTime(entry.createdAt, isArabic: isArabic),
            ),
            if (entry.entityId != null)
              AdminDetailRow(
                label: strings.adminAuditEntity,
                value: entry.entityId!,
                selectable: true,
              ),
            if (entry.ipAddress != null)
              AdminDetailRow(
                label: strings.adminAuditIpAddress,
                value: entry.ipAddress!,
              ),
          ],
        ),
      ),
    );
  }
}
