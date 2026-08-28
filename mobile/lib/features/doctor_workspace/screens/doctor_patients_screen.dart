import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/doctor_patients_provider.dart';

class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});
  @override
  ConsumerState<DoctorPatientsScreen> createState() =>
      _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends ConsumerState<DoctorPatientsScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final isDoctor = ref.watch(authControllerProvider).user?.role == 'doctor';
    if (!isDoctor) {
      return AppScaffold(
        appBar: AppBar(),
        body: const Center(
          child: EmptyState(
            icon: Icons.lock_outline,
            title: 'Doctor access required',
            hint:
                'This workspace is available to approved doctor accounts only.',
          ),
        ),
      );
    }
    final state = ref.watch(doctorPatientsProvider);
    return AppScaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'مرضاي' : 'My patients'),
        leading: IconButton(
          tooltip: isArabic ? 'الرئيسية' : 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.go(RoutePaths.home),
        ),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetryState(
          title: isArabic ? 'تعذر تحميل المرضى' : 'Could not load patients',
          message: isArabic ? 'حاول مرة أخرى.' : 'Please try again.',
          retryLabel: isArabic ? 'إعادة المحاولة' : 'Retry',
          onRetry: () => ref.invalidate(doctorPatientsProvider),
        ),
        data: (patients) {
          final list = patients
              .where(
                (p) => '${p.name(isArabic)} ${p.email}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(doctorPatientsProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              children: [
                PageIntro(
                  title: isArabic ? 'مرضاي' : 'My patients',
                  subtitle: isArabic
                      ? 'مرضى مرتبطون برعايتك.'
                      : 'Patients linked to your care.',
                  icon: Icons.groups_outlined,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                TextField(
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    labelText: isArabic ? 'ابحث عن مريض' : 'Search patients',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceLg),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.people_outline,
                    title: isArabic ? 'لا يوجد مرضى بعد' : 'No patients yet',
                    hint: isArabic
                        ? 'سيظهر المرضى بعد وجود موعد أو علاقة رعاية.'
                        : 'Patients appear after an appointment or care relationship.',
                  )
                else
                  for (final patient in list)
                    Card(
                      child: ListTile(
                        onTap: () => context.push(RoutePaths.doctorPatientDetailPath(patient.id)),
                        leading: CircleAvatar(
                          child: Text(
                            (patient.name(isArabic).isEmpty
                                    ? patient.email
                                    : patient.name(isArabic))
                                .substring(0, 1)
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(
                          patient.name(isArabic).isEmpty
                              ? patient.email
                              : patient.name(isArabic),
                        ),
                        subtitle: Text(
                          patient.hasUpcoming
                              ? (isArabic
                                    ? 'لديه موعد قادم'
                                    : 'Has an upcoming appointment')
                              : patient.email,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
