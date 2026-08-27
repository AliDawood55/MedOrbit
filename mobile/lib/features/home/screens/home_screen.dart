import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../appointments/models/enriched_appointment.dart';
import '../../appointments/providers/appointments_provider.dart';
import '../../appointments/utils/appointment_filters.dart';
import '../../appointments/widgets/appointment_card.dart';
import '../../admin/dashboard/models/admin_dashboard_stats.dart';
import '../../admin/dashboard/providers/admin_dashboard_provider.dart';
import '../../doctor_workspace/screens/doctor_home_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../prescriptions/models/prescription_model.dart';
import '../../prescriptions/providers/prescriptions_provider.dart';
import '../../records/models/record_entry_model.dart';
import '../../records/providers/records_provider.dart';
import '../models/user_profile_model.dart';
import '../providers/user_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshDashboard() async {
    Future<void> ignoreFailure(Future<void> Function() refresh) async {
      try {
        await refresh();
      } catch (_) {
        // Each provider exposes its own retryable section error state.
      }
    }

    final role = ref.read(authControllerProvider).user?.role.toLowerCase();
    if (role == 'admin' || role == 'super_admin') {
      await Future.wait([
        ignoreFailure(() async {
          final _ = await ref.refresh(currentUserProfileProvider.future);
        }),
        ignoreFailure(() async {
          final _ = await ref.refresh(adminDashboardStatsProvider.future);
        }),
      ]);
      return;
    }

    await Future.wait([
      ignoreFailure(() async {
        final _ = await ref.refresh(currentUserProfileProvider.future);
      }),
      ignoreFailure(
        () => ref.read(appointmentsControllerProvider.notifier).load(),
      ),
      ignoreFailure(() async {
        final _ = await ref.refresh(prescriptionsListProvider.future);
      }),
      ignoreFailure(() async {
        final _ = await ref.refresh(recordsTimelineProvider.future);
      }),
    ]);
  }

  void _updateQuery(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  void _clearQuery() {
    _searchController.clear();
    _updateQuery('');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final role = ref.watch(authControllerProvider).user?.role.toLowerCase();
    final isAdmin = role == 'admin' || role == 'super_admin';
    final isDoctor = role == 'doctor';
    final profileAsync = ref.watch(currentUserProfileProvider);

    if (isAdmin) {
      final statsAsync = ref.watch(adminDashboardStatsProvider);
      return _AdminHomeScreen(
        profileAsync: profileAsync,
        statsAsync: statsAsync,
        isSuperAdmin: role == 'super_admin',
        isArabic: isArabic,
        strings: strings,
        origin: ref.watch(activeOriginProvider),
        onRefresh: _refreshDashboard,
        onRetry: () => ref.invalidate(currentUserProfileProvider),
        onRetryStats: () => ref.invalidate(adminDashboardStatsProvider),
      );
    }
    if (isDoctor) return const DoctorHomeScreen();

    final appointmentsAsync = ref.watch(appointmentsControllerProvider);
    final prescriptionsAsync = ref.watch(prescriptionsListProvider);
    final recordsAsync = ref.watch(recordsTimelineProvider);
    // `null` while loading/on error — the quick action falls back to a
    // generic description rather than showing a stale or wrong count.
    final notificationsState = ref.watch(notificationsControllerProvider);
    final notificationsUnreadCount = notificationsState.notifications.hasError
        ? null
        : notificationsState.unreadCount;

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.appName),
        actions: [
          IconButton(
            tooltip: strings.navNotifications,
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push(RoutePaths.notifications),
          ),
          IconButton(
            tooltip: strings.navProfile,
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(RoutePaths.profile),
          ),
          IconButton(
            tooltip: strings.languageToggleTooltip,
            icon: const Icon(Icons.translate_rounded),
            onPressed: () =>
                ref.read(localeControllerProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: strings.logoutTooltip,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(RoutePaths.login);
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: ListView(
            key: const PageStorageKey<String>('dashboard-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileSection(
                      profileAsync: profileAsync,
                      isArabic: isArabic,
                      strings: strings,
                      origin: ref.watch(activeOriginProvider),
                      onRetry: () => ref.invalidate(currentUserProfileProvider),
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.dashboardStatisticsTitle,
                      subtitle: strings.dashboardStatisticsSubtitle,
                    ),
                    _StatisticsGrid(
                      appointmentsAsync: appointmentsAsync,
                      prescriptionsAsync: prescriptionsAsync,
                      recordsAsync: recordsAsync,
                      strings: strings,
                      onRetryAppointments: () => ref
                          .read(appointmentsControllerProvider.notifier)
                          .load(),
                      onRetryPrescriptions: () =>
                          ref.invalidate(prescriptionsListProvider),
                      onRetryRecords: () =>
                          ref.invalidate(recordsTimelineProvider),
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.quickActionsTitle,
                      subtitle: strings.quickActionsSubtitle,
                    ),
                    AppTextField(
                      label: strings.dashboardSearchLabel,
                      hintText: strings.dashboardSearchPlaceholder,
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: strings.clearSearch,
                              onPressed: _clearQuery,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      semanticLabel: strings.dashboardSearchLabel,
                      onChanged: _updateQuery,
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    _QuickActions(
                      strings: strings,
                      query: _query,
                      notificationsUnreadCount: notificationsUnreadCount,
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.upcomingAppointmentsTitle,
                      trailing: _ViewAllButton(
                        label: strings.viewAll,
                        onPressed: () => context.go(RoutePaths.appointments),
                      ),
                    ),
                    _UpcomingAppointments(
                      appointmentsAsync: appointmentsAsync,
                      strings: strings,
                      isArabic: isArabic,
                      onRetry: () => ref
                          .read(appointmentsControllerProvider.notifier)
                          .load(),
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.recentPrescriptionsTitle,
                      trailing: _ViewAllButton(
                        label: strings.viewAll,
                        onPressed: () => context.go(RoutePaths.prescriptions),
                      ),
                    ),
                    _PrescriptionPreview(
                      prescriptionsAsync: prescriptionsAsync,
                      strings: strings,
                      isArabic: isArabic,
                      onRetry: () => ref.invalidate(prescriptionsListProvider),
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.recentMedicalRecordsTitle,
                      trailing: _ViewAllButton(
                        label: strings.viewAll,
                        onPressed: () => context.go(RoutePaths.records),
                      ),
                    ),
                    _MedicalRecordPreview(
                      recordsAsync: recordsAsync,
                      strings: strings,
                      isArabic: isArabic,
                      onRetry: () => ref.invalidate(recordsTimelineProvider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Operational accounts must not be shown patient records, prescriptions,
/// care data, AI tools, or contact submission actions. Admin management is
/// currently web-first; this deliberately provides a clear, safe mobile home
/// rather than pretending patient-only routes belong to an administrator.
class _AdminHomeScreen extends ConsumerWidget {
  const _AdminHomeScreen({
    required this.profileAsync,
    required this.statsAsync,
    required this.isSuperAdmin,
    required this.isArabic,
    required this.strings,
    required this.origin,
    required this.onRefresh,
    required this.onRetry,
    required this.onRetryStats,
  });

  final AsyncValue<UserProfileModel> profileAsync;
  final AsyncValue<AdminDashboardStats> statsAsync;
  final bool isSuperAdmin;
  final bool isArabic;
  final AppStrings strings;
  final String origin;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onRetryStats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.appName),
        actions: [
          IconButton(
            tooltip: strings.navNotifications,
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push(RoutePaths.notifications),
          ),
          IconButton(
            tooltip: strings.navProfile,
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(RoutePaths.profile),
          ),
          IconButton(
            tooltip: strings.languageToggleTooltip,
            icon: const Icon(Icons.translate_rounded),
            onPressed: () =>
                ref.read(localeControllerProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: strings.logoutTooltip,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(RoutePaths.login);
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileSection(
                      profileAsync: profileAsync,
                      isArabic: isArabic,
                      strings: strings,
                      origin: origin,
                      onRetry: onRetry,
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.adminMobileDashboardTitle,
                      subtitle: strings.adminDashboardSubtitle,
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    _AdminStatisticsGrid(
                      statsAsync: statsAsync,
                      strings: strings,
                      onRetry: onRetryStats,
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.spaceXl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: AppTheme.accent,
                              size: AppTheme.iconXl,
                            ),
                            const SizedBox(height: AppTheme.spaceMd),
                            Text(
                              strings.adminMobileDashboardHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppTheme.spaceLg),
                            Wrap(
                              spacing: AppTheme.spaceSm,
                              runSpacing: AppTheme.spaceSm,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push(RoutePaths.adminManagement),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  label: Text(strings.adminManagementTitle),
                                ),
                                if (isSuperAdmin)
                                  OutlinedButton.icon(
                                    onPressed: () => context.push(
                                      RoutePaths.adminManagementPath(
                                        tab: 'admins',
                                      ),
                                    ),
                                    icon: const Icon(Icons.groups_2_outlined),
                                    label: Text(strings.adminAdministrators),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push(RoutePaths.notifications),
                                  icon: const Icon(
                                    Icons.notifications_outlined,
                                  ),
                                  label: Text(strings.navNotifications),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push(RoutePaths.profile),
                                  icon: const Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                  label: Text(strings.navProfile),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminStatisticsGrid extends StatelessWidget {
  const _AdminStatisticsGrid({
    required this.statsAsync,
    required this.strings,
    required this.onRetry,
  });

  final AsyncValue<AdminDashboardStats> statsAsync;
  final AppStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return statsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spaceLg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stackTrace) => FeatureCard(
        title: strings.adminMobileDashboardTitle,
        subtitle: strings.statLoadError,
        icon: Icons.refresh_rounded,
        color: Theme.of(context).colorScheme.error,
        onTap: onRetry,
        semanticLabel: '${strings.retry}: ${strings.adminMobileDashboardTitle}',
      ),
      data: (stats) {
        final tiles = <_AdminStatData>[
          _AdminStatData(
            stats.usersTotal,
            strings.adminStatsUsers,
            Icons.groups_outlined,
            AppTheme.primary,
            RoutePaths.adminManagement,
          ),
          _AdminStatData(
            stats.patients,
            strings.adminStatsPatients,
            Icons.person_outline_rounded,
            AppTheme.secondary,
            RoutePaths.adminManagement,
          ),
          _AdminStatData(
            stats.doctors,
            strings.adminStatsDoctors,
            Icons.medical_services_outlined,
            AppTheme.accent,
            RoutePaths.adminManagement,
          ),
          _AdminStatData(
            stats.appointmentsTotal,
            strings.adminStatsAppointments,
            Icons.event_available_outlined,
            AppTheme.violet,
          ),
          _AdminStatData(
            stats.recordsTotal,
            strings.adminStatsRecords,
            Icons.description_outlined,
            AppTheme.primary,
          ),
          _AdminStatData(
            stats.prescriptionsTotal,
            strings.adminStatsPrescriptions,
            Icons.medication_outlined,
            AppTheme.secondary,
          ),
          if (stats.averageRating != null)
            _AdminStatData(
              stats.averageRating!.toStringAsFixed(1),
              strings.adminStatsRating,
              Icons.star_outline_rounded,
              AppTheme.accent,
            ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= AppTheme.compactBreakpoint
                ? 2
                : 1;
            final gap = AppTheme.spaceMd;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: width,
                    child: StatTile(
                      value: '\u2066${tile.value}\u2069',
                      label: tile.label,
                      icon: tile.icon,
                      color: tile.color,
                      onTap: tile.route == null
                          ? null
                          : () => context.push(tile.route!),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AdminStatData {
  const _AdminStatData(
    this.value,
    this.label,
    this.icon,
    this.color, [
    this.route,
  ]);

  final Object value;
  final String label;
  final IconData icon;
  final Color color;
  final String? route;
}

List<EnrichedAppointment> _upcomingAppointments(
  List<EnrichedAppointment> appointments,
) {
  final upcoming = appointments.where(isUpcomingAppointment).toList()
    ..sort((a, b) {
      final dateCompare = parseDateOnly(
        a.appointment.scheduledDate,
      ).compareTo(parseDateOnly(b.appointment.scheduledDate));
      return dateCompare != 0
          ? dateCompare
          : a.appointment.startTime.compareTo(b.appointment.startTime);
    });
  return upcoming;
}

List<PrescriptionModel> _recentPrescriptions(
  List<PrescriptionModel> prescriptions,
) {
  final sorted = [...prescriptions]
    ..sort((a, b) => b.prescriptionDate.compareTo(a.prescriptionDate));
  return sorted;
}

List<RecordEntryModel> _medicalRecords(List<RecordEntryModel> entries) {
  final records = entries.where((entry) => entry.entryType == 'record').toList()
    ..sort((a, b) => (b.entryDate ?? '').compareTo(a.entryDate ?? ''));
  return records;
}

String? _formattedDate(String? value, bool isArabic) {
  if (value == null || value.isEmpty) return null;
  try {
    return formatDate(parseDateOnly(value), localeCode: isArabic ? 'ar' : 'en');
  } catch (_) {
    return null;
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.profileAsync,
    required this.isArabic,
    required this.strings,
    required this.origin,
    required this.onRetry,
  });

  final AsyncValue<UserProfileModel> profileAsync;
  final bool isArabic;
  final AppStrings strings;
  final String origin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return profileAsync.when(
      data: (profile) => _ProfileHeader(
        profile: profile,
        isArabic: isArabic,
        strings: strings,
        origin: origin,
      ),
      loading: () => _LoadingCard(label: strings.loadingProfile),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.profileLoadErrorTitle,
          message: strings.profileLoadErrorMessage,
          retryLabel: strings.retry,
          onRetry: onRetry,
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isArabic,
    required this.strings,
    required this.origin,
  });

  final UserProfileModel profile;
  final bool isArabic;
  final AppStrings strings;
  final String origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = profile.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final (roleLabel, roleColor) = _roleVisual(profile.role, strings);

    final avatar = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasAvatar ? null : AppTheme.primaryGradient,
        image: hasAvatar
            ? DecorationImage(
                image: NetworkImage('$origin$avatarUrl'),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasAvatar
          ? null
          : Text(
              profile.initial,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: AppTheme.weightExtraBold,
              ),
            ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${strings.welcomeBack}, ${profile.displayName(isArabic)}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppTheme.weightExtraBold,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          _roleSubtitle(profile.role, strings),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Wrap(
          spacing: AppTheme.spaceSm,
          runSpacing: AppTheme.spaceXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(label: roleLabel, color: roleColor),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                profile.email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(RoutePaths.profile),
        child: Semantics(
          button: true,
          hint: strings.navProfile,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceXl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(AppTheme.fontMd) >
                    AppTheme.fontLg * 1.25;
                final stack =
                    constraints.maxWidth < AppTheme.compactBreakpoint ||
                    largeText;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(height: AppTheme.spaceLg),
                      details,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: AppTheme.spaceLg),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

(String, Color) _roleVisual(String role, AppStrings strings) {
  return switch (role.toLowerCase()) {
    'doctor' => (strings.roleDoctor, AppTheme.secondary),
    'admin' || 'super_admin' => (strings.roleAdmin, AppTheme.accent),
    _ => (strings.rolePatient, AppTheme.primary),
  };
}

String _roleSubtitle(String role, AppStrings strings) {
  return switch (role.toLowerCase()) {
    'doctor' => strings.doctorDashboardSubtitle,
    'admin' || 'super_admin' => strings.adminDashboardSubtitle,
    _ => strings.patientDashboardSubtitle,
  };
}

class _StatisticsGrid extends StatelessWidget {
  const _StatisticsGrid({
    required this.appointmentsAsync,
    required this.prescriptionsAsync,
    required this.recordsAsync,
    required this.strings,
    required this.onRetryAppointments,
    required this.onRetryPrescriptions,
    required this.onRetryRecords,
  });

  final AsyncValue<List<EnrichedAppointment>> appointmentsAsync;
  final AsyncValue<List<PrescriptionModel>> prescriptionsAsync;
  final AsyncValue<List<RecordEntryModel>> recordsAsync;
  final AppStrings strings;
  final VoidCallback onRetryAppointments;
  final VoidCallback onRetryPrescriptions;
  final VoidCallback onRetryRecords;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columns =
            constraints.maxWidth >= AppTheme.wideBreakpoint && textScale <= 1.5
            ? 3
            : constraints.maxWidth >= AppTheme.compactBreakpoint &&
                  textScale <= 1.25
            ? 2
            : 1;
        final gap = AppTheme.spaceMd;
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: itemWidth,
              child: _StatisticState<EnrichedAppointment>(
                value: appointmentsAsync,
                count: (items) => _upcomingAppointments(items).length,
                label: strings.upcomingAppointmentsStat,
                icon: Icons.event_available_outlined,
                color: AppTheme.primary,
                onTap: () => context.go(RoutePaths.appointments),
                onRetry: onRetryAppointments,
                strings: strings,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _StatisticState<PrescriptionModel>(
                value: prescriptionsAsync,
                count: (items) => items.length,
                label: strings.prescriptionsStat,
                icon: Icons.medication_outlined,
                color: AppTheme.accent,
                onTap: () => context.go(RoutePaths.prescriptions),
                onRetry: onRetryPrescriptions,
                strings: strings,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _StatisticState<RecordEntryModel>(
                value: recordsAsync,
                count: (items) => _medicalRecords(items).length,
                label: strings.medicalRecordsStat,
                icon: Icons.description_outlined,
                color: AppTheme.secondary,
                onTap: () => context.go(RoutePaths.records),
                onRetry: onRetryRecords,
                strings: strings,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatisticState<T> extends StatelessWidget {
  const _StatisticState({
    required this.value,
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onRetry,
    required this.strings,
  });

  final AsyncValue<List<T>> value;
  final int Function(List<T>) count;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (items) => StatTile(
        value: '\u2066${count(items)}\u2069',
        label: label,
        icon: icon,
        color: color,
        onTap: onTap,
      ),
      loading: () =>
          StatTile(value: '…', label: label, icon: icon, color: color),
      error: (error, stackTrace) => FeatureCard(
        title: label,
        subtitle: strings.statLoadError,
        icon: Icons.refresh_rounded,
        color: Theme.of(context).colorScheme.error,
        onTap: onRetry,
        semanticLabel: '${strings.retry}: $label',
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.strings,
    required this.query,
    required this.notificationsUnreadCount,
  });

  final AppStrings strings;
  final String query;

  /// Null while the notifications provider is loading or errored.
  final int? notificationsUnreadCount;

  @override
  Widget build(BuildContext context) {
    final groups = [
      _QuickActionGroupData(
        title: strings.quickGroupCare,
        icon: Icons.medical_services_outlined,
        actions: [
          _QuickAction(
            label: strings.quickClinicsNearbyLabel,
            description: strings.quickClinicsNearbyDescription,
            icon: Icons.local_hospital_outlined,
            color: AppTheme.secondary,
            path: RoutePaths.clinics,
            push: true,
          ),
          _QuickAction(
            label: strings.quickFindDoctorLabel,
            description: strings.quickFindDoctorDescription,
            icon: Icons.person_search_outlined,
            color: AppTheme.primary,
            path: RoutePaths.doctors,
            push: true,
          ),
          _QuickAction(
            label: strings.quickMedicalChatLabel,
            description: strings.quickMedicalChatDescription,
            icon: Icons.chat_bubble_outline_rounded,
            color: AppTheme.violet,
            path: RoutePaths.chatbot,
            push: true,
          ),
          _QuickAction(
            label: strings.navAppointments,
            description: strings.quickAppointmentsDescription,
            icon: Icons.event_available_outlined,
            color: AppTheme.info,
            path: RoutePaths.appointments,
          ),
          _QuickAction(
            label: strings.navNotifications,
            description:
                notificationsUnreadCount == null ||
                    notificationsUnreadCount == 0
                ? strings.quickNotificationsDescription
                : strings.notificationsUnreadCountDescription(
                    notificationsUnreadCount!,
                  ),
            icon: Icons.notifications_outlined,
            color: AppTheme.accent,
            path: RoutePaths.notifications,
            push: true,
          ),
          _QuickAction(
            label: strings.bookNewAppointment,
            description: strings.quickBookAppointmentDescription,
            icon: Icons.event_outlined,
            color: AppTheme.primary,
            path: RoutePaths.appointmentBooking,
            push: true,
          ),
          _QuickAction(
            label: strings.virtualDoctorTitle,
            description: strings.quickVirtualDoctorDescription,
            icon: Icons.graphic_eq_rounded,
            color: AppTheme.primary,
            path: RoutePaths.virtualDoctor,
            push: true,
          ),
          _QuickAction(
            label: strings.symptomCheckerTitle,
            description: strings.quickSymptomCheckerDescription,
            icon: Icons.health_and_safety_outlined,
            color: AppTheme.warning,
            path: RoutePaths.symptomChecker,
            push: true,
          ),
          _QuickAction(
            label: strings.drugCheckerTitle,
            description: strings.quickDrugCheckerDescription,
            icon: Icons.medication_liquid_outlined,
            color: AppTheme.secondary,
            path: RoutePaths.drugChecker,
            push: true,
          ),
          _QuickAction(
            label: strings.reportSummarizerTitle,
            description: strings.quickReportSummarizerDescription,
            icon: Icons.summarize_outlined,
            color: AppTheme.info,
            path: RoutePaths.reportSummarizer,
            push: true,
          ),
        ],
      ),
      _QuickActionGroupData(
        title: strings.quickGroupHealthData,
        icon: Icons.folder_shared_outlined,
        actions: [
          _QuickAction(
            label: strings.myDoctorsTitle,
            description: strings.quickMyDoctorsDescription,
            icon: Icons.health_and_safety_outlined,
            color: AppTheme.secondary,
            path: RoutePaths.myDoctors,
            push: true,
          ),
          _QuickAction(
            label: strings.savedPlacesTitle,
            description: strings.quickSavedPlacesDescription,
            icon: Icons.bookmark_outline_rounded,
            color: AppTheme.accent,
            path: RoutePaths.savedPlaces,
            push: true,
          ),
          _QuickAction(
            label: strings.navPrescriptions,
            description: strings.quickPrescriptionsDescription,
            icon: Icons.medication_outlined,
            color: AppTheme.accent,
            path: RoutePaths.prescriptions,
          ),
          _QuickAction(
            label: strings.navRecords,
            description: strings.quickRecordsDescription,
            icon: Icons.description_outlined,
            color: AppTheme.secondary,
            path: RoutePaths.records,
          ),
          _QuickAction(
            label: strings.myReportsTitle,
            description: strings.quickMyReportsDescription,
            icon: Icons.article_outlined,
            color: AppTheme.success,
            path: RoutePaths.myReports,
            push: true,
          ),
        ],
      ),
      _QuickActionGroupData(
        title: strings.quickGroupSupport,
        icon: Icons.support_agent_outlined,
        actions: [
          _QuickAction(
            label: strings.navFeedback,
            description: strings.quickFeedbackDescription,
            icon: Icons.comment_outlined,
            color: AppTheme.violet,
            path: RoutePaths.feedback,
          ),
          _QuickAction(
            label: strings.contactTitle,
            description: strings.quickContactDescription,
            icon: Icons.support_agent_outlined,
            color: AppTheme.violet,
            path: RoutePaths.contact,
            push: true,
          ),
          _QuickAction(
            label: strings.navProfile,
            description: strings.quickProfileDescription,
            icon: Icons.settings_outlined,
            color: AppTheme.primary,
            path: RoutePaths.profile,
            push: true,
          ),
        ],
      ),
    ];

    final filteredGroups = groups
        .map(
          (group) => group.copyWith(
            actions: group.actions.where((action) {
              if (query.isEmpty) return true;
              return '${action.label} ${action.description}'
                  .toLowerCase()
                  .contains(query);
            }).toList(),
          ),
        )
        .where((group) => group.actions.isNotEmpty)
        .toList();

    if (filteredGroups.isEmpty) {
      return Card(
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: strings.dashboardSearchNoResults,
          hint: strings.dashboardSearchNoResultsHint,
          variant: EmptyStateVariant.compact,
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < filteredGroups.length; index++) ...[
          _QuickActionGroup(group: filteredGroups[index]),
          if (index != filteredGroups.length - 1)
            const SizedBox(height: AppTheme.spaceMd),
        ],
      ],
    );
  }
}

class _QuickActionGroup extends StatelessWidget {
  const _QuickActionGroup({required this.group});

  final _QuickActionGroupData group;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: AppTheme.minTouchTarget,
                  height: AppTheme.minTouchTarget,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Icon(
                    group.icon,
                    color: AppTheme.primary,
                    size: AppTheme.iconMd,
                  ),
                ),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Text(
                    group.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: AppTheme.weightBold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText = AppTheme.usesLargeText(context);
                final columns =
                    constraints.maxWidth >= AppTheme.compactBreakpoint &&
                        !largeText
                    ? 2
                    : 1;
                final gap = AppTheme.spaceMd;
                final width =
                    (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: group.actions
                      .map(
                        (action) => SizedBox(
                          width: width,
                          child: FeatureCard(
                            title: action.label,
                            subtitle: action.description,
                            icon: action.icon,
                            color: action.color,
                            trailing: Icon(
                              AppTheme.directionalForwardIconOf(context),
                              size: AppTheme.iconSm,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onTap: () => action.push
                                ? context.push(action.path)
                                : context.go(action.path),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionGroupData {
  const _QuickActionGroupData({
    required this.title,
    required this.icon,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final List<_QuickAction> actions;

  _QuickActionGroupData copyWith({List<_QuickAction>? actions}) {
    return _QuickActionGroupData(
      title: title,
      icon: icon,
      actions: actions ?? this.actions,
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.path,
    this.push = false,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final String path;
  final bool push;
}

class _UpcomingAppointments extends StatelessWidget {
  const _UpcomingAppointments({
    required this.appointmentsAsync,
    required this.strings,
    required this.isArabic,
    required this.onRetry,
  });

  final AsyncValue<List<EnrichedAppointment>> appointmentsAsync;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return appointmentsAsync.when(
      data: (appointments) {
        final upcoming = _upcomingAppointments(appointments);
        if (upcoming.isEmpty) {
          return Card(
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: strings.noUpcomingAppointments,
              hint: strings.noUpcomingAppointmentsHint,
              variant: EmptyStateVariant.compact,
            ),
          );
        }

        return Column(
          children: upcoming
              .take(3)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                  child: _AppointmentPreviewCard(
                    entry: entry,
                    strings: strings,
                    isArabic: isArabic,
                  ),
                ),
              )
              .toList(),
        );
      },
      loading: () => _LoadingPreview(label: strings.loadingAppointments),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.appointmentsLoadErrorTitle,
          message: strings.appointmentsLoadErrorMessage,
          retryLabel: strings.retry,
          onRetry: onRetry,
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _AppointmentPreviewCard extends StatelessWidget {
  const _AppointmentPreviewCard({
    required this.entry,
    required this.strings,
    required this.isArabic,
  });

  final EnrichedAppointment entry;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final appointment = entry.appointment;
    final (statusLabel, statusColor) = appointmentStatusVisual(
      appointment.status,
      strings,
    );
    final date = _formattedDate(appointment.scheduledDate, isArabic);
    final time =
        '\u2066${formatTime(appointment.startTime)}–${formatTime(appointment.endTime)}\u2069';
    final clinic = entry.clinicName(isArabic);
    final metadata = [
      ?clinic,
      if (date != null) '$date · $time' else time,
    ].join(' · ');

    return FeatureCard(
      title:
          entry.doctorName(isArabic) ??
          '\u2066${appointment.appointmentNumber}\u2069',
      subtitle: metadata,
      icon: appointment.appointmentType == 'telemedicine'
          ? Icons.chat_bubble_outline
          : Icons.local_hospital_outlined,
      color: AppTheme.primary,
      trailing: StatusBadge(label: statusLabel, color: statusColor),
      onTap: () => context.go(RoutePaths.appointments),
    );
  }
}

class _PrescriptionPreview extends StatelessWidget {
  const _PrescriptionPreview({
    required this.prescriptionsAsync,
    required this.strings,
    required this.isArabic,
    required this.onRetry,
  });

  final AsyncValue<List<PrescriptionModel>> prescriptionsAsync;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return prescriptionsAsync.when(
      data: (prescriptions) {
        final recent = _recentPrescriptions(prescriptions);
        if (recent.isEmpty) {
          return Card(
            child: EmptyState(
              icon: Icons.medication_outlined,
              title: strings.prescriptionsEmptyTitle,
              hint: strings.prescriptionsEmptyHint,
              variant: EmptyStateVariant.compact,
            ),
          );
        }

        return Column(
          children: recent
              .take(2)
              .map(
                (prescription) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                  child: _PrescriptionPreviewCard(
                    prescription: prescription,
                    strings: strings,
                    isArabic: isArabic,
                  ),
                ),
              )
              .toList(),
        );
      },
      loading: () => _LoadingPreview(label: strings.loadingPrescriptions),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.prescriptionsLoadErrorTitle,
          message: strings.errorGeneric,
          retryLabel: strings.retry,
          onRetry: onRetry,
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _PrescriptionPreviewCard extends StatelessWidget {
  const _PrescriptionPreviewCard({
    required this.prescription,
    required this.strings,
    required this.isArabic,
  });

  final PrescriptionModel prescription;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final firstItem = prescription.items.isEmpty
        ? null
        : prescription.items.first;
    final medicationName = firstItem == null
        ? null
        : isArabic
        ? firstItem.medicationNameAr ?? firstItem.medicationNameEn
        : firstItem.medicationNameEn ?? firstItem.medicationNameAr;
    final title = medicationName?.trim().isNotEmpty == true
        ? medicationName!
        : prescription.diagnosis?.trim().isNotEmpty == true
        ? prescription.diagnosis!
        : prescription.prescriptionNumber;
    final date = _formattedDate(prescription.prescriptionDate, isArabic);
    final metadata = [
      '\u2066${prescription.prescriptionNumber}\u2069',
      ?date,
    ].join(' · ');
    final (statusLabel, statusColor) = _prescriptionStatus(
      prescription.status,
      strings,
    );

    return FeatureCard(
      title: title,
      subtitle: metadata,
      icon: Icons.medication_outlined,
      color: AppTheme.accent,
      trailing: StatusBadge(label: statusLabel, color: statusColor),
      onTap: () => context.go(RoutePaths.prescriptions),
    );
  }
}

(String, Color) _prescriptionStatus(String status, AppStrings strings) {
  return switch (status) {
    'active' => (strings.statusActive, AppTheme.success),
    'completed' => (strings.statusCompleted, AppTheme.success),
    'expired' => (strings.statusExpired, AppTheme.danger),
    'cancelled' => (strings.statusCancelled, AppTheme.danger),
    _ => (status, AppTheme.info),
  };
}

class _MedicalRecordPreview extends StatelessWidget {
  const _MedicalRecordPreview({
    required this.recordsAsync,
    required this.strings,
    required this.isArabic,
    required this.onRetry,
  });

  final AsyncValue<List<RecordEntryModel>> recordsAsync;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return recordsAsync.when(
      data: (entries) {
        final records = _medicalRecords(entries);
        if (records.isEmpty) {
          return Card(
            child: EmptyState(
              icon: Icons.folder_open_outlined,
              title: strings.recordsEmptyTitle,
              hint: strings.recordsEmptyHint,
              variant: EmptyStateVariant.compact,
            ),
          );
        }

        return Column(
          children: records
              .take(2)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                  child: _MedicalRecordPreviewCard(
                    entry: entry,
                    strings: strings,
                    isArabic: isArabic,
                  ),
                ),
              )
              .toList(),
        );
      },
      loading: () => _LoadingPreview(label: strings.loadingMedicalRecords),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.recordsLoadErrorTitle,
          message: strings.errorGeneric,
          retryLabel: strings.retry,
          onRetry: onRetry,
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _MedicalRecordPreviewCard extends StatelessWidget {
  const _MedicalRecordPreviewCard({
    required this.entry,
    required this.strings,
    required this.isArabic,
  });

  final RecordEntryModel entry;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final title = entry.diagnosis?.trim().isNotEmpty == true
        ? entry.diagnosis!
        : entry.chiefComplaint?.trim().isNotEmpty == true
        ? entry.chiefComplaint!
        : entry.recordType?.trim().isNotEmpty == true
        ? entry.recordType!
        : entry.recordNumber ?? strings.typeRecord;
    final doctor = entry.doctorFullName(isArabic);
    final date = _formattedDate(entry.entryDate, isArabic);
    final metadata = [?doctor, ?date].join(' · ');

    return FeatureCard(
      title: title,
      subtitle: metadata.isEmpty ? null : metadata,
      icon: Icons.description_outlined,
      color: AppTheme.secondary,
      trailing: StatusBadge(
        label: strings.typeRecord,
        color: AppTheme.secondary,
      ),
      onTap: () => context.go(RoutePaths.records),
    );
  }
}

class _LoadingPreview extends StatelessWidget {
  const _LoadingPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LoadingCard(label: label),
        const SizedBox(height: AppTheme.spaceSm),
        _LoadingCard(label: label),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: AppTheme.iconLg,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: Icon(
        AppTheme.directionalForwardIconOf(context),
        size: AppTheme.iconSm,
      ),
      label: Text(label),
    );
  }
}
