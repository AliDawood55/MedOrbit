import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../home/providers/user_provider.dart';
import '../../common/providers/admin_access_provider.dart';
import '../../common/widgets/admin_gate.dart';
import '../../common/widgets/admin_stat_grid.dart';
import '../models/admin_dashboard_stats.dart';
import '../providers/admin_dashboard_provider.dart';
import '../widgets/admin_identity_card.dart';

/// The administration hub — the landing surface for an `admin` or
/// `super_admin` account, and the mobile counterpart of the web dashboard's
/// admin tile group.
///
/// Operational accounts are never shown patient records, prescriptions, care
/// data, or the AI tools: none of those belong to an administrator, and the
/// backend would refuse them anyway.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminMobileDashboardTitle,
      child: const _AdminDashboardView(),
    );
  }
}

class _AdminDashboardView extends ConsumerWidget {
  const _AdminDashboardView();

  Future<void> _refresh(WidgetRef ref) async {
    Future<void> ignoreFailure(Future<void> Function() work) async {
      try {
        await work();
      } catch (_) {
        // Each section renders its own retryable error state.
      }
    }

    await Future.wait([
      ignoreFailure(() async {
        final _ = await ref.refresh(currentUserProfileProvider.future);
      }),
      ignoreFailure(() async {
        final _ = await ref.refresh(adminDashboardStatsProvider.future);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final access = ref.watch(adminAccessProvider);
    final statsAsync = ref.watch(adminDashboardStatsProvider);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.appName),
        actions: [
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
          onRefresh: () => _refresh(ref),
          child: ListView(
            key: const PageStorageKey<String>('admin-dashboard-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminIdentityCard(),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.adminMobileDashboardTitle,
                      subtitle: strings.adminDashboardSubtitle,
                      trailing: TextButton.icon(
                        key: const ValueKey('admin-dashboard-analytics-link'),
                        onPressed: () => context.push(RoutePaths.adminAnalytics),
                        icon: const Icon(
                          Icons.insights_outlined,
                          size: AppTheme.iconMd,
                        ),
                        label: Text(strings.adminToolAnalytics),
                      ),
                    ),
                    _OverviewSection(statsAsync: statsAsync, strings: strings),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(
                      title: strings.adminToolsTitle,
                      subtitle: strings.adminToolsSubtitle,
                    ),
                    _AdminToolList(strings: strings, access: access),
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

class _OverviewSection extends ConsumerWidget {
  const _OverviewSection({required this.statsAsync, required this.strings});

  final AsyncValue<AdminDashboardStats> statsAsync;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spaceLg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => FeatureCard(
        key: const ValueKey('admin-dashboard-stats-error'),
        title: strings.adminMobileDashboardTitle,
        subtitle: strings.adminError(ApiException.from(error).code),
        icon: Icons.refresh_rounded,
        color: Theme.of(context).colorScheme.error,
        onTap: () => ref.invalidate(adminDashboardStatsProvider),
        semanticLabel: '${strings.retry}: ${strings.adminMobileDashboardTitle}',
      ),
      data: (stats) => AdminStatGrid(
        stats: [
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
          if (stats.averageRating != null)
            AdminStat(
              value: stats.averageRating!.toStringAsFixed(1),
              label: strings.adminStatsRating,
              icon: Icons.star_outline_rounded,
              color: AppTheme.accent,
            ),
        ],
      ),
    );
  }
}

/// The administration tools an account may open.
///
/// The invitation registry appears only for `super_admin`, matching
/// `authorizeSuperAdmin` on `/api/admin/invitations` and the web layout's
/// `isSuperAdmin` branch. Hiding it is a navigation-visibility decision only —
/// the route and the API each refuse it independently.
class _AdminToolList extends StatelessWidget {
  const _AdminToolList({required this.strings, required this.access});

  final AppStrings strings;
  final AdminAccess access;

  @override
  Widget build(BuildContext context) {
    final tools = <_AdminTool>[
      _AdminTool(
        key: 'users',
        title: strings.adminToolUsers,
        description: strings.adminToolUsersDescription,
        icon: Icons.manage_accounts_outlined,
        color: AppTheme.primary,
        path: RoutePaths.adminUsers,
      ),
      _AdminTool(
        key: 'applications',
        title: strings.adminToolApplications,
        description: strings.adminToolApplicationsDescription,
        icon: Icons.assignment_turned_in_outlined,
        color: AppTheme.secondary,
        path: RoutePaths.adminDoctorApplications,
      ),
      _AdminTool(
        key: 'contact',
        title: strings.adminToolContact,
        description: strings.adminToolContactDescription,
        icon: Icons.mark_email_unread_outlined,
        color: AppTheme.info,
        path: RoutePaths.adminContactMessages,
      ),
      _AdminTool(
        key: 'moderation',
        title: strings.adminToolModeration,
        description: strings.adminToolModerationDescription,
        icon: Icons.shield_outlined,
        color: AppTheme.violet,
        path: RoutePaths.adminModeration,
      ),
      if (access.canUseSuperAdminTools)
        _AdminTool(
          key: 'invitations',
          title: strings.adminToolInvitations,
          description: strings.adminToolInvitationsDescription,
          icon: Icons.person_add_alt_1_outlined,
          color: AppTheme.accent,
          path: RoutePaths.adminInvitations,
        ),
      _AdminTool(
        key: 'analytics',
        title: strings.adminToolAnalytics,
        description: strings.adminToolAnalyticsDescription,
        icon: Icons.insights_outlined,
        color: AppTheme.primary,
        path: RoutePaths.adminAnalytics,
      ),
      _AdminTool(
        key: 'audit',
        title: strings.adminToolAuditLogs,
        description: strings.adminToolAuditLogsDescription,
        icon: Icons.history_outlined,
        color: AppTheme.warning,
        path: RoutePaths.adminAuditLogs,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tool in tools) ...[
          FeatureCard(
            key: ValueKey('admin-tool-${tool.key}'),
            title: tool.title,
            subtitle: tool.description,
            icon: tool.icon,
            color: tool.color,
            semanticLabel: '${tool.title}. ${tool.description}',
            trailing: Icon(
              AppTheme.directionalForwardIconOf(context),
              size: AppTheme.iconMd,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onTap: () => context.push(tool.path),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ],
    );
  }
}

class _AdminTool {
  const _AdminTool({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.path,
  });

  final String key;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String path;
}
