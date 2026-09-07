import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../auth/providers/app_role_capabilities_provider.dart';

/// Route inventory for the role-aware service hub. Kept free of localized UI
/// data so the role/navigation matrix is directly unit-testable.
List<String> serviceRoutesFor(AppRoleCapabilities capabilities) {
  return [
    RoutePaths.notifications,
    RoutePaths.billing,
    if (capabilities.canUseConsumerAi) RoutePaths.chatbot,
    if (capabilities.canUseCareMessages) RoutePaths.messages,
    if (capabilities.canUseConsumerAi) ...[
      RoutePaths.virtualDoctor,
      RoutePaths.symptomChecker,
      RoutePaths.drugChecker,
      RoutePaths.reportSummarizer,
      RoutePaths.myReports,
    ],
    if (capabilities.canUsePatientCare) ...[
      RoutePaths.appointments,
      RoutePaths.records,
      RoutePaths.prescriptions,
      RoutePaths.myDoctors,
      RoutePaths.myDoctor,
      RoutePaths.savedPlaces,
      RoutePaths.doctorApplication,
    ],
    if (capabilities.canUseDoctorWorkspace) ...[
      RoutePaths.doctorWorkspace,
      RoutePaths.doctorProfessionalProfile,
      RoutePaths.doctorSchedule,
      RoutePaths.doctorAppointments,
      RoutePaths.doctorPatients,
      RoutePaths.doctorPosts,
      RoutePaths.doctorRecords,
    ],
    if (capabilities.canUseAdminTools) ...[
      RoutePaths.adminDashboard,
      RoutePaths.adminAnalytics,
      RoutePaths.adminUsers,
      RoutePaths.adminDoctorApplications,
      RoutePaths.adminContactMessages,
      RoutePaths.adminModeration,
      RoutePaths.adminAuditLogs,
    ],
    if (capabilities.canUseSuperAdminTools) RoutePaths.adminInvitations,
    if (capabilities.canUseContactAndFeedback) ...[
      RoutePaths.contact,
      RoutePaths.feedback,
    ],
  ];
}

class ServicesHubScreen extends ConsumerWidget {
  const ServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final capabilities = ref.watch(appRoleCapabilitiesProvider);
    final groups = _groups(strings, capabilities);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.servicesTitle)),
      body: ListView(
        key: ValueKey('services-${capabilities.role.name}'),
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageIntro(
                  title: strings.servicesTitle,
                  subtitle: strings.servicesSubtitle,
                  icon: Icons.apps_rounded,
                ),
                for (final group in groups) ...[
                  const SizedBox(height: AppTheme.spaceXl),
                  SectionHeader(title: group.title),
                  const SizedBox(height: AppTheme.spaceSm),
                  for (final entry in group.entries) ...[
                    FeatureCard(
                      key: ValueKey('service-${entry.path}'),
                      title: entry.title,
                      subtitle: entry.subtitle,
                      icon: entry.icon,
                      color: entry.color,
                      trailing: Icon(
                        AppTheme.directionalForwardIconOf(context),
                        size: AppTheme.iconMd,
                      ),
                      onTap: () => context.push(entry.path),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<_ServiceGroup> _groups(AppStrings s, AppRoleCapabilities capabilities) {
  final groups = <_ServiceGroup>[
    _ServiceGroup(s.servicesSharedGroup, [
      _ServiceEntry(
        s.navNotifications,
        s.quickNotificationsDescription,
        Icons.notifications_outlined,
        AppTheme.accent,
        RoutePaths.notifications,
      ),
      _ServiceEntry(
        s.billingTitle,
        s.billingProfileDescription,
        Icons.workspace_premium_outlined,
        AppTheme.violet,
        RoutePaths.billing,
      ),
    ]),
  ];

  if (capabilities.canUseConsumerAi || capabilities.canUseCareMessages) {
    groups.add(
      _ServiceGroup(s.servicesCommunicationGroup, [
        if (capabilities.canUseCareMessages)
          _ServiceEntry(
            s.messagesTitle,
            s.messagesSubtitle,
            Icons.forum_outlined,
            AppTheme.info,
            RoutePaths.messages,
          ),
        if (capabilities.canUseConsumerAi)
          _ServiceEntry(
            s.quickMedicalChatLabel,
            s.quickMedicalChatDescription,
            Icons.chat_bubble_outline_rounded,
            AppTheme.violet,
            RoutePaths.chatbot,
          ),
        if (capabilities.canUseConsumerAi) ...[
          _ServiceEntry(
            s.virtualDoctorTitle,
            s.quickVirtualDoctorDescription,
            Icons.graphic_eq_rounded,
            AppTheme.primary,
            RoutePaths.virtualDoctor,
          ),
          _ServiceEntry(
            s.symptomCheckerTitle,
            s.quickSymptomCheckerDescription,
            Icons.health_and_safety_outlined,
            AppTheme.warning,
            RoutePaths.symptomChecker,
          ),
          _ServiceEntry(
            s.drugCheckerTitle,
            s.quickDrugCheckerDescription,
            Icons.medication_liquid_outlined,
            AppTheme.secondary,
            RoutePaths.drugChecker,
          ),
          _ServiceEntry(
            s.reportSummarizerTitle,
            s.quickReportSummarizerDescription,
            Icons.summarize_outlined,
            AppTheme.info,
            RoutePaths.reportSummarizer,
          ),
          _ServiceEntry(
            s.myReportsTitle,
            s.quickMyReportsDescription,
            Icons.article_outlined,
            AppTheme.success,
            RoutePaths.myReports,
          ),
        ],
      ]),
    );
  }

  if (capabilities.canUsePatientCare) {
    groups.add(
      _ServiceGroup(s.servicesPatientGroup, [
        _ServiceEntry(
          s.navAppointments,
          s.quickAppointmentsDescription,
          Icons.event_available_outlined,
          AppTheme.info,
          RoutePaths.appointments,
        ),
        _ServiceEntry(
          s.navRecords,
          s.quickRecordsDescription,
          Icons.description_outlined,
          AppTheme.secondary,
          RoutePaths.records,
        ),
        _ServiceEntry(
          s.navPrescriptions,
          s.quickPrescriptionsDescription,
          Icons.medication_outlined,
          AppTheme.accent,
          RoutePaths.prescriptions,
        ),
        _ServiceEntry(
          s.myDoctorsTitle,
          s.quickMyDoctorsDescription,
          Icons.health_and_safety_outlined,
          AppTheme.primary,
          RoutePaths.myDoctors,
        ),
        _ServiceEntry(
          s.myDoctorTitle,
          s.quickMyDoctorDescription,
          Icons.favorite_outline_rounded,
          AppTheme.danger,
          RoutePaths.myDoctor,
        ),
        _ServiceEntry(
          s.savedPlacesTitle,
          s.quickSavedPlacesDescription,
          Icons.bookmark_outline_rounded,
          AppTheme.accent,
          RoutePaths.savedPlaces,
        ),
        _ServiceEntry(
          s.doctorApplicationQuickActionLabel,
          s.doctorApplicationQuickActionDescription,
          Icons.medical_information_outlined,
          AppTheme.primary,
          RoutePaths.doctorApplication,
        ),
      ]),
    );
  }

  if (capabilities.canUseDoctorWorkspace) {
    groups.add(
      _ServiceGroup(s.servicesDoctorGroup, [
        _ServiceEntry(
          s.doctorWorkspace,
          s.doctorWorkspaceSubtitle,
          Icons.medical_services_outlined,
          AppTheme.primary,
          RoutePaths.doctorWorkspace,
        ),
        _ServiceEntry(
          s.professionalProfile,
          s.doctorProfessionalProfileSubtitle,
          Icons.badge_outlined,
          AppTheme.secondary,
          RoutePaths.doctorProfessionalProfile,
        ),
        _ServiceEntry(
          s.schedule,
          s.doctorScheduleSubtitle,
          Icons.calendar_month_outlined,
          AppTheme.info,
          RoutePaths.doctorSchedule,
        ),
        _ServiceEntry(
          s.doctorAppointments,
          s.doctorAppointmentsSubtitle,
          Icons.event_available_outlined,
          AppTheme.accent,
          RoutePaths.doctorAppointments,
        ),
        _ServiceEntry(
          s.myPatients,
          s.doctorPatientsSubtitle,
          Icons.groups_outlined,
          AppTheme.violet,
          RoutePaths.doctorPatients,
        ),
        _ServiceEntry(
          s.doctorPosts,
          s.doctorPostsSubtitle,
          Icons.article_outlined,
          AppTheme.success,
          RoutePaths.doctorPosts,
        ),
        _ServiceEntry(
          s.doctorRecords,
          s.doctorRecordsSubtitle,
          Icons.medical_information_outlined,
          AppTheme.warning,
          RoutePaths.doctorRecords,
        ),
      ]),
    );
  }

  if (capabilities.canUseAdminTools) {
    groups.add(
      _ServiceGroup(s.servicesAdminGroup, [
        _ServiceEntry(
          s.adminMobileDashboardTitle,
          s.adminMobileDashboardHint,
          Icons.admin_panel_settings_outlined,
          AppTheme.accent,
          RoutePaths.adminDashboard,
        ),
        _ServiceEntry(
          s.adminToolAnalytics,
          s.adminToolAnalyticsDescription,
          Icons.insights_outlined,
          AppTheme.primary,
          RoutePaths.adminAnalytics,
        ),
        _ServiceEntry(
          s.adminToolUsers,
          s.adminToolUsersDescription,
          Icons.manage_accounts_outlined,
          AppTheme.primary,
          RoutePaths.adminUsers,
        ),
        _ServiceEntry(
          s.adminToolApplications,
          s.adminToolApplicationsDescription,
          Icons.assignment_turned_in_outlined,
          AppTheme.secondary,
          RoutePaths.adminDoctorApplications,
        ),
        _ServiceEntry(
          s.adminToolContact,
          s.adminToolContactDescription,
          Icons.mark_email_unread_outlined,
          AppTheme.info,
          RoutePaths.adminContactMessages,
        ),
        _ServiceEntry(
          s.adminToolModeration,
          s.adminToolModerationDescription,
          Icons.shield_outlined,
          AppTheme.violet,
          RoutePaths.adminModeration,
        ),
        _ServiceEntry(
          s.adminToolAuditLogs,
          s.adminToolAuditLogsDescription,
          Icons.history_outlined,
          AppTheme.warning,
          RoutePaths.adminAuditLogs,
        ),
        if (capabilities.canUseSuperAdminTools)
          _ServiceEntry(
            s.adminToolInvitations,
            s.adminToolInvitationsDescription,
            Icons.person_add_alt_1_outlined,
            AppTheme.accent,
            RoutePaths.adminInvitations,
          ),
      ]),
    );
  }

  if (capabilities.canUseContactAndFeedback) {
    groups.add(
      _ServiceGroup(s.quickGroupSupport, [
        _ServiceEntry(
          s.contactTitle,
          s.quickContactDescription,
          Icons.support_agent_outlined,
          AppTheme.violet,
          RoutePaths.contact,
        ),
        _ServiceEntry(
          s.navFeedback,
          s.quickFeedbackDescription,
          Icons.comment_outlined,
          AppTheme.violet,
          RoutePaths.feedback,
        ),
      ]),
    );
  }
  return groups;
}

class _ServiceGroup {
  const _ServiceGroup(this.title, this.entries);
  final String title;
  final List<_ServiceEntry> entries;
}

class _ServiceEntry {
  const _ServiceEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.path,
  );
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String path;
}
