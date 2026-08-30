import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/localized_field.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_detail_rows.dart';
import '../../common/widgets/admin_gate.dart';
import '../../common/widgets/admin_stat_grid.dart';
import '../../dashboard/models/admin_dashboard_stats.dart';
import '../../dashboard/providers/admin_dashboard_provider.dart';
import '../widgets/admin_breakdown_list.dart';
import '../widgets/admin_trend_bars.dart';

/// Mobile port of the web `analytics.html` page.
///
/// Same single source — `GET /dashboard/stats` — and the same six sections,
/// re-expressed for a phone: KPI tiles, two flexible bar trends, and four
/// proportional breakdowns. Every number rendered here comes from a field the
/// backend actually returns; nothing is derived, projected, or invented.
class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminAnalyticsTitle,
      child: const _AdminAnalyticsView(),
    );
  }
}

class _AdminAnalyticsView extends ConsumerWidget {
  const _AdminAnalyticsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final statsAsync = ref.watch(adminDashboardStatsProvider);

    Future<void> refresh() async {
      try {
        final _ = await ref.refresh(adminDashboardStatsProvider.future);
      } catch (_) {
        // The section below renders its own retryable error state.
      }
    }

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminAnalyticsTitle),
        actions: [
          IconButton(
            key: const ValueKey('admin-analytics-refresh'),
            tooltip: strings.adminRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: refresh,
          ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(
                    title: strings.adminAnalyticsTitle,
                    subtitle: strings.adminAnalyticsSubtitle,
                    icon: Icons.insights_outlined,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  statsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppTheme.space2xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => Card(
                      child: ErrorRetryState(
                        title: strings.adminLoadErrorTitle,
                        message: strings.adminError(
                          ApiException.from(error).code,
                        ),
                        retryLabel: strings.retry,
                        onRetry: () =>
                            ref.invalidate(adminDashboardStatsProvider),
                        variant: ErrorRetryVariant.compact,
                        retryKey: const ValueKey('admin-analytics-retry'),
                      ),
                    ),
                    data: (stats) => _AnalyticsBody(
                      stats: stats,
                      strings: strings,
                      isArabic: isArabic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({
    required this.stats,
    required this.strings,
    required this.isArabic,
  });

  final AdminDashboardStats stats;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final analytics = stats.analytics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminStatGrid(stats: _summaryTiles()),
        const SizedBox(height: AppTheme.spaceXl),
        if (analytics.isEntirelyUnavailable)
          AdminSectionCard(
            title: strings.adminAnalyticsAllUnavailableTitle,
            child: Text(
              strings.adminAnalyticsAllUnavailableHint,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else ...[
          _TrendSection(
            title: strings.adminAnalyticsAppointmentsOverTime,
            section: analytics.appointmentsOverTime,
            strings: strings,
            isArabic: isArabic,
            color: AppTheme.primary,
          ),
          const SizedBox(height: AppTheme.spaceLg),
          _TrendSection(
            title: strings.adminAnalyticsConversationsPerWeek,
            section: analytics.conversationsPerWeek,
            strings: strings,
            isArabic: isArabic,
            color: AppTheme.secondary,
          ),
          const SizedBox(height: AppTheme.spaceLg),
          _BreakdownSection(
            title: strings.adminAnalyticsUsersByRole,
            section: analytics.usersByRole,
            strings: strings,
            labelBuilder: strings.adminRoleLabel,
            palette: const [
              AppTheme.primary,
              AppTheme.secondary,
              AppTheme.accent,
              AppTheme.violet,
              AppTheme.info,
            ],
          ),
          const SizedBox(height: AppTheme.spaceLg),
          _SpecialtiesSection(
            section: analytics.topSpecialties,
            strings: strings,
            isArabic: isArabic,
          ),
          const SizedBox(height: AppTheme.spaceLg),
          _BreakdownSection(
            title: strings.adminAnalyticsTriageLevels,
            section: analytics.triageLevels,
            strings: strings,
            labelBuilder: strings.adminTriageLabel,
            colorForKey: _triageColor,
          ),
          const SizedBox(height: AppTheme.spaceLg),
          _BreakdownSection(
            title: strings.adminAnalyticsClinicTypes,
            section: analytics.clinicTypes,
            strings: strings,
            labelBuilder: strings.adminClinicTypeLabel,
            palette: const [
              AppTheme.primary,
              AppTheme.secondary,
              AppTheme.accent,
              AppTheme.violet,
              AppTheme.info,
              AppTheme.danger,
            ],
          ),
        ],
      ],
    );
  }

  List<AdminStat> _summaryTiles() => [
    AdminStat(
      value: '${stats.usersTotal}',
      label: strings.adminStatsUsers,
      icon: Icons.groups_outlined,
      color: AppTheme.primary,
    ),
    AdminStat(
      value: '${stats.patients}',
      label: strings.adminStatsPatients,
      icon: Icons.person_outline_rounded,
      color: AppTheme.secondary,
    ),
    AdminStat(
      value: '${stats.doctors}',
      label: strings.adminStatsDoctors,
      icon: Icons.medical_services_outlined,
      color: AppTheme.accent,
    ),
    AdminStat(
      value: '${stats.appointmentsTotal}',
      label: strings.adminStatsAppointments,
      icon: Icons.event_available_outlined,
      color: AppTheme.violet,
    ),
    AdminStat(
      value: '${stats.appointmentsCompleted}',
      label: strings.adminStatsAppointmentsCompleted,
      icon: Icons.task_alt_rounded,
      color: AppTheme.success,
    ),
    AdminStat(
      value: '${stats.appointmentsScheduled}',
      label: strings.adminStatsAppointmentsScheduled,
      icon: Icons.schedule_rounded,
      color: AppTheme.warning,
    ),
    AdminStat(
      value: '${stats.appointmentsCancelled}',
      label: strings.adminStatsAppointmentsCancelled,
      icon: Icons.event_busy_outlined,
      color: AppTheme.danger,
    ),
    AdminStat(
      value: '${stats.recordsTotal}',
      label: strings.adminStatsRecords,
      icon: Icons.description_outlined,
      color: AppTheme.primary,
    ),
    AdminStat(
      value: '${stats.prescriptionsTotal}',
      label: strings.adminStatsPrescriptions,
      icon: Icons.medication_outlined,
      color: AppTheme.secondary,
    ),
    AdminStat(
      value: stats.averageRating == null
          ? '—'
          : stats.averageRating!.toStringAsFixed(2),
      label: strings.adminStatsRating,
      icon: Icons.star_outline_rounded,
      color: AppTheme.accent,
    ),
  ];
}

Color _triageColor(String key) => switch (key) {
  'emergency' => AppTheme.danger,
  'urgent' => AppTheme.accent,
  'routine' => AppTheme.success,
  _ => AppTheme.primary,
};

/// Shared "this one section could not be computed / has no rows yet" copy.
class _SectionNotice extends StatelessWidget {
  const _SectionNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({
    required this.title,
    required this.section,
    required this.strings,
    required this.isArabic,
    required this.color,
  });

  final String title;
  final AdminAnalyticsSection<AdminAnalyticsSeries> section;
  final AppStrings strings;
  final bool isArabic;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!section.isAvailable) {
      return AdminSectionCard(
        title: title,
        child: _SectionNotice(
          message: strings.adminAnalyticsSectionUnavailable,
        ),
      );
    }

    final series = section.value!;
    if (!series.hasData) {
      return AdminSectionCard(
        title: title,
        child: _SectionNotice(message: strings.adminAnalyticsAwaitingData),
      );
    }

    final theme = Theme.of(context);
    final first = series.labels.isEmpty
        ? ''
        : adminFormatShortDay(series.labels.first, isArabic: isArabic);
    final last = series.labels.isEmpty
        ? ''
        : adminFormatShortDay(series.labels.last, isArabic: isArabic);

    return AdminSectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminTrendBars(
            values: series.counts,
            color: color,
            bucketSemanticLabel: (index, value) {
              final label = index < series.labels.length
                  ? adminFormatShortDay(
                      series.labels[index],
                      isArabic: isArabic,
                    )
                  : '';
              return '${strings.adminAnalyticsWeekOf(label)}: $value';
            },
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Row(
            children: [
              Expanded(
                child: Text(
                  adminIsolate(first),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              // Flexible, not fixed: a long localized date at a large text
              // scale must wrap rather than push the row past the card edge.
              Flexible(
                child: Text(
                  adminIsolate(last),
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            strings.adminAnalyticsWeeklyTrendHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            strings.adminAnalyticsTotalLabel(series.total),
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({
    required this.title,
    required this.section,
    required this.strings,
    required this.labelBuilder,
    this.palette,
    this.colorForKey,
  });

  final String title;
  final AdminAnalyticsSection<AdminAnalyticsSeries> section;
  final AppStrings strings;
  final String Function(String key) labelBuilder;
  final List<Color>? palette;
  final Color Function(String key)? colorForKey;

  @override
  Widget build(BuildContext context) {
    if (!section.isAvailable) {
      return AdminSectionCard(
        title: title,
        child: _SectionNotice(
          message: strings.adminAnalyticsSectionUnavailable,
        ),
      );
    }

    final series = section.value!;
    if (!series.hasData) {
      return AdminSectionCard(
        title: title,
        child: _SectionNotice(message: strings.adminAnalyticsAwaitingData),
      );
    }

    final entries = <AdminBreakdownEntry>[
      for (var index = 0; index < series.labels.length; index++)
        AdminBreakdownEntry(
          label: labelBuilder(series.labels[index]),
          count: series.counts[index],
          color: colorForKey != null
              ? colorForKey!(series.labels[index])
              : palette == null
              ? null
              : palette![index % palette!.length],
        ),
    ]..sort((a, b) => b.count.compareTo(a.count));

    return AdminSectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminBreakdownList(
            entries: entries,
            shareLabel: strings.adminAnalyticsShare,
          ),
          Text(
            strings.adminAnalyticsTotalLabel(series.total),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _SpecialtiesSection extends StatelessWidget {
  const _SpecialtiesSection({
    required this.section,
    required this.strings,
    required this.isArabic,
  });

  final AdminAnalyticsSection<List<AdminRankedItem>> section;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final title = strings.adminAnalyticsTopSpecialties;
    if (!section.isAvailable) {
      return AdminSectionCard(
        title: title,
        child: _SectionNotice(
          message: strings.adminAnalyticsSectionUnavailable,
        ),
      );
    }

    final items = section.value!;
    final total = items.fold<int>(0, (sum, item) => sum + item.count);
    if (items.isEmpty || total == 0) {
      return AdminSectionCard(
        title: title,
        child: _SectionNotice(message: strings.adminAnalyticsAwaitingData),
      );
    }

    return AdminSectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminBreakdownList(
            shareLabel: strings.adminAnalyticsShare,
            entries: [
              for (final item in items)
                AdminBreakdownEntry(
                  label: localizedField(
                    isArabic: isArabic,
                    ar: item.nameAr,
                    en: item.nameEn,
                  ),
                  count: item.count,
                  color: AppTheme.primary,
                ),
            ],
          ),
          Text(
            strings.adminAnalyticsTotalLabel(total),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
