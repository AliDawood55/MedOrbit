import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';
import '../widgets/doctor_workspace_gate.dart';
import '../providers/doctor_workspace_providers.dart';

class DoctorWorkspaceScreen extends ConsumerWidget {
  const DoctorWorkspaceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final entries = [
      (
        s.professionalProfile,
        Icons.badge_outlined,
        RoutePaths.doctorProfessionalProfile,
      ),
      (s.schedule, Icons.calendar_month_outlined, RoutePaths.doctorSchedule),
      (
        s.doctorAppointments,
        Icons.event_available_outlined,
        RoutePaths.doctorAppointments,
      ),
      (s.myPatients, Icons.groups_outlined, RoutePaths.doctorPatients),
      (s.doctorPosts, Icons.article_outlined, RoutePaths.doctorPosts),
      (
        s.doctorRecords,
        Icons.medical_information_outlined,
        RoutePaths.doctorRecords,
      ),
    ];
    return AppScaffold(
      appBar: AppBar(title: Text(s.doctorWorkspace)),
      body: DoctorWorkspaceGate(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(doctorProfileProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: s.doctorWorkspace,
                      subtitle: s.doctorWorkspaceSubtitle,
                      icon: Icons.medical_services_outlined,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 600 ? 2 : 1;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: entries.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: 112,
                                crossAxisSpacing: AppTheme.spaceMd,
                                mainAxisSpacing: AppTheme.spaceMd,
                              ),
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            return Semantics(
                              button: true,
                              label: e.$1,
                              child: Card(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusLg,
                                  ),
                                  onTap: () => context.push(e.$3),
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppTheme.spaceLg,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(e.$2, size: AppTheme.iconXl),
                                        const SizedBox(width: AppTheme.spaceLg),
                                        Expanded(
                                          child: Text(
                                            e.$1,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right_rounded),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
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
