import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_filter_chips.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_doctor_application.dart';
import '../providers/admin_doctor_applications_provider.dart';
import '../widgets/admin_application_status.dart';

/// Mobile port of the web `admin-doctor-applications.html` review queue.
///
/// The web page is a two-pane master/detail; on a phone that becomes a
/// filtered queue that pushes a full review screen, so the applicant's
/// credentials get the whole viewport when a decision is being made.
class AdminDoctorApplicationsScreen extends ConsumerWidget {
  const AdminDoctorApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminApplicationsTitle,
      child: const _AdminApplicationsView(),
    );
  }
}

class _AdminApplicationsView extends ConsumerWidget {
  const _AdminApplicationsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(adminDoctorApplicationsControllerProvider);
    final controller = ref.read(
      adminDoctorApplicationsControllerProvider.notifier,
    );

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminApplicationsTitle),
        actions: [
          IconButton(
            key: const ValueKey('admin-applications-refresh'),
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
                  AdminFilterChips<AdminApplicationStatus>(
                    label: strings.adminFiltersTitle,
                    selected: state.status,
                    onSelected: controller.setStatus,
                    options: [
                      AdminFilterOption(
                        value: AdminApplicationStatus.pending,
                        label: strings.adminApplicationsStatusPending,
                        key: const ValueKey('admin-applications-pending'),
                      ),
                      AdminFilterOption(
                        value: AdminApplicationStatus.approved,
                        label: strings.adminApplicationsStatusApproved,
                        key: const ValueKey('admin-applications-approved'),
                      ),
                      AdminFilterOption(
                        value: AdminApplicationStatus.rejected,
                        label: strings.adminApplicationsStatusRejected,
                        key: const ValueKey('admin-applications-rejected'),
                      ),
                      AdminFilterOption(
                        value: null,
                        label: strings.adminFilterAll,
                        key: const ValueKey('admin-applications-all'),
                      ),
                    ],
                  ),
                  if (state.hasLoadedOnce && state.errorCode != null) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    InlineMessage(
                      message: strings.adminError(state.errorCode),
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
                ref: ref,
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
    required WidgetRef ref,
    required AdminApplicationsState state,
    required AppStrings strings,
    required bool isArabic,
  }) {
    final controller = ref.read(
      adminDoctorApplicationsControllerProvider.notifier,
    );

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
            retryKey: const ValueKey('admin-applications-retry'),
          ),
        ],
      );
    }
    if (state.applications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            key: const ValueKey('admin-applications-empty'),
            icon: Icons.assignment_outlined,
            title: strings.adminApplicationsEmptyTitle,
            hint: strings.adminApplicationsEmptyHint,
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
        itemCount: state.applications.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          if (index == state.applications.length) {
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceSm),
              child: Text(
                strings.adminApplicationsLimitNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          final application = state.applications[index];
          final (statusLabel, statusColor) = adminApplicationStatusVisual(
            application,
            strings,
          );
          return _ApplicationCard(
            application: application,
            statusLabel: statusLabel,
            statusColor: statusColor,
            isArabic: isArabic,
            strings: strings,
            onOpen: () async {
              await context.push(
                RoutePaths.adminDoctorApplicationDetailPath(application.id),
              );
              // A decision taken on the detail screen changes which rows
              // belong to the current filter.
              await controller.refresh();
            },
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.statusLabel,
    required this.statusColor,
    required this.isArabic,
    required this.strings,
    required this.onOpen,
  });

  final AdminDoctorApplication application;
  final String statusLabel;
  final Color statusColor;
  final bool isArabic;
  final AppStrings strings;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = application.applicant.displayName(isArabic: isArabic);
    final specialty = application.specialtyName(isArabic: isArabic);
    final submitted = adminFormatDate(
      application.submittedAt,
      isArabic: isArabic,
    );

    return Semantics(
      button: true,
      label: '$name. $specialty. $statusLabel.',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('admin-application-${application.id}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: AppTheme.weightBold,
                    ),
                  ),
                  if (specialty.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space2xs),
                    Text(specialty, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: AppTheme.space2xs),
                  Text(
                    '${strings.adminApplicationSubmittedAt}: '
                    '${adminIsolate(submitted)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StatusBadge(label: statusLabel, color: statusColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
