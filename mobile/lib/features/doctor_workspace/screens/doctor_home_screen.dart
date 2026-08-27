import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/locale/locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../auth/providers/auth_provider.dart';

class DoctorHomeScreen extends ConsumerWidget {
  const DoctorHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final user = ref.watch(authControllerProvider).user;
    final name = user?.name?.trim().isNotEmpty == true
        ? user!.name!.trim()
        : user?.email ?? 'Doctor';
    return AppScaffold(
      appBar: AppBar(
        title: const Text('MedOrbit'),
        actions: const [RoleHeaderActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    child: Icon(Icons.medical_services_outlined),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${ar ? 'مرحباً' : 'Welcome'}, $name',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          ar ? 'حساب طبيب معتمد' : 'Approved doctor account',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          Text(
            ar ? 'مساحة العمل' : 'Workspace',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTheme.spaceSm),
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
                label: ar ? 'المواعيد' : 'Appointments',
                onTap: () => context.push(RoutePaths.appointments),
              ),
              _Action(
                context: context,
                icon: Icons.description_outlined,
                label: ar ? 'التقارير' : 'Reports',
                onTap: () => context.push(RoutePaths.myReports),
              ),
              _Action(
                context: context,
                icon: Icons.notifications_outlined,
                label: ar ? 'الإشعارات' : 'Notifications',
                onTap: () => context.push(RoutePaths.notifications),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
