import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../../../shared/widgets/role_general_navigation.dart';
import '../../../../shared/widgets/role_dashboard_profile.dart';
import '../models/doctor_schedule_models.dart';
import '../providers/doctor_patients_provider.dart';
import '../providers/doctor_schedule_provider.dart';
import '../../home/providers/user_provider.dart';

class DoctorHomeScreen extends ConsumerWidget {
  const DoctorHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final strings = ref.watch(appStringsProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final patients = ref.watch(doctorPatientsProvider);
    final schedule = ref.watch(doctorScheduleProvider);
    return AppScaffold(
      appBar: AppBar(
        title: const Text('MedOrbit'),
        actions: const [RoleHeaderActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RoleDashboardProfileSection(
            profileAsync: profileAsync,
            isArabic: ar,
            strings: strings,
            origin: ref.watch(activeOriginProvider),
            onRetry: () => ref.invalidate(currentUserProfileProvider),
          ),
          const SizedBox(height: AppTheme.spaceXl),
          const RoleGeneralNavigation(role: 'doctor'),
          const SizedBox(height: AppTheme.spaceXl),
          SectionHeader(
            title: ar ? 'ملخص العيادة' : 'Practice overview',
            subtitle: ar ? 'نظرة سريعة على مرضاك ومواعيد اليوم.' : 'A quick view of your patients and today’s schedule.',
          ),
          _DoctorOverview(
            ar: ar,
            patientCount: patients.valueOrNull?.length,
            schedule: schedule.valueOrNull,
          ),
          const SizedBox(height: AppTheme.spaceXl),
          SectionHeader(
            title: ar ? 'مساحة عمل الطبيب' : 'Doctor workspace',
            subtitle: ar ? 'أدواتك المهنية والسريرية.' : 'Your professional and clinical tools.',
          ),
          Wrap(
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceSm,
            children: [
              _Action(
                context: context,
                icon: Icons.groups_outlined,
                label: ar ? 'مرضاي' : 'My patients',
                onTap: () => context.push(RoutePaths.doctorPatients),
              ),
              _Action(
                context: context,
                icon: Icons.event_available_outlined,
                label: ar ? 'جدولي والمواعيد' : 'Schedule & appointments',
                onTap: () => context.push(RoutePaths.doctorSchedule),
              ),
              _Action(
                context: context,
                icon: Icons.description_outlined,
                label: ar ? 'التقارير' : 'Reports',
                onTap: () => context.push(RoutePaths.myReports),
              ),
              _Action(
                context: context,
                icon: Icons.badge_outlined,
                label: ar ? 'ملفي المهني' : 'Professional profile',
                onTap: () => context.push(RoutePaths.doctorProfessional),
              ),
              _Action(
                context: context,
                icon: Icons.article_outlined,
                label: ar ? 'منشوراتي' : 'My posts',
                onTap: () => context.push(RoutePaths.doctorPosts),
              ),
              _Action(
                context: context,
                icon: Icons.chat_bubble_outline,
                label: ar ? 'الرسائل' : 'Messages',
                onTap: () => context.push(RoutePaths.doctorMessages),
              ),
              _Action(
                context: context,
                icon: Icons.workspace_premium_outlined,
                label: ar ? 'الاشتراك والفوترة' : 'Subscription & billing',
                onTap: () => context.push(RoutePaths.doctorBilling),
              ),
            ],
          ),
          ])),
        ],
      ),
    );
  }
}

class _DoctorOverview extends StatelessWidget {
  const _DoctorOverview({required this.ar, required this.patientCount, required this.schedule});
  final bool ar;
  final int? patientCount;
  final DoctorSchedule? schedule;

  @override
  Widget build(BuildContext context) {
    final appointments = schedule?.appointments;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todayCount = appointments?.where((item) => item.scheduledDate == today && !{'cancelled', 'completed', 'no_show'}.contains(item.status)).length;
    return Row(children: [
      _Metric(label: ar ? 'المرضى' : 'Patients', value: patientCount?.toString() ?? '—', icon: Icons.groups_outlined),
      const SizedBox(width: AppTheme.spaceSm),
      _Metric(label: ar ? 'مواعيد اليوم' : 'Today', value: todayCount?.toString() ?? '—', icon: Icons.today_outlined),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceMd), child: Row(children: [Icon(icon, color: AppTheme.primary), const SizedBox(width: AppTheme.spaceSm), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.titleLarge), Text(label, style: Theme.of(context).textTheme.bodySmall)])]))));
}

class _Action extends StatelessWidget {
  const _Action({
    required this.context,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final BuildContext context;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext _) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 56) / 2,
    child: Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(height: AppTheme.spaceSm),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
