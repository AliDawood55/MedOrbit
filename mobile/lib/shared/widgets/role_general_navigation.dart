import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/locale/locale_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../routes/route_paths.dart';

/// Shared, role-safe dashboard navigation.  It intentionally contains only
/// routes that every signed-in role may open.  Clinical and operational work
/// remains in the role-specific group below this component.
class RoleGeneralNavigation extends ConsumerWidget {
  const RoleGeneralNavigation({super.key, required this.role});

  final String role;

  bool get _canUseAiTools => role == 'patient' || role == 'doctor';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read the source of truth directly. This makes the group refresh on a
    // language switch even if the surrounding dashboard is kept alive.
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final actions = <_GeneralAction>[
      _GeneralAction(
        icon: Icons.dynamic_feed_outlined,
        arabic: 'المنشورات الصحية',
        english: 'Health feed',
        route: RoutePaths.feed,
      ),
      _GeneralAction(
        icon: Icons.chat_bubble_outline_rounded,
        arabic: 'المحادثة',
        english: 'Chat',
        route: RoutePaths.chatbot,
      ),
      _GeneralAction(
        icon: Icons.medical_services_outlined,
        arabic: 'الأطباء',
        english: 'Doctors',
        route: RoutePaths.doctors,
      ),
      _GeneralAction(
        icon: Icons.local_hospital_outlined,
        arabic: 'العيادات',
        english: 'Clinics',
        route: RoutePaths.clinics,
      ),
      _GeneralAction(
        icon: Icons.support_agent_outlined,
        arabic: 'تواصل معنا',
        english: 'Contact us',
        route: RoutePaths.contact,
      ),
      if (_canUseAiTools)
        _GeneralAction(
          icon: Icons.auto_awesome_outlined,
          arabic: 'أدوات الذكاء الاصطناعي',
          english: 'AI tools',
          onTap: () => _showAiTools(context, isArabic),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'استكشف MedOrbit' : 'Explore MedOrbit',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          isArabic
              ? 'خيارات عامة متاحة لحسابك.'
              : 'General options available to your account.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Wrap(
          spacing: AppTheme.spaceSm,
          runSpacing: AppTheme.spaceSm,
          children: actions
              .map((action) => _GeneralActionCard(
                    action: action,
                    isArabic: isArabic,
                  ))
              .toList(growable: false),
        ),
      ],
    );
  }

  void _showAiTools(BuildContext context, bool isArabic) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spaceLg,
            0,
            AppTheme.spaceLg,
            AppTheme.spaceLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isArabic ? 'أدوات الذكاء الاصطناعي' : 'AI tools',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              _AiToolTile(
                icon: Icons.health_and_safety_outlined,
                title: isArabic ? 'فاحص الأعراض' : 'Symptom checker',
                route: RoutePaths.symptomChecker,
              ),
              _AiToolTile(
                icon: Icons.medication_outlined,
                title: isArabic ? 'فاحص تداخل الأدوية' : 'Drug checker',
                route: RoutePaths.drugChecker,
              ),
              _AiToolTile(
                icon: Icons.summarize_outlined,
                title: isArabic ? 'تلخيص التقرير' : 'Report summarizer',
                route: RoutePaths.reportSummarizer,
              ),
              _AiToolTile(
                icon: Icons.record_voice_over_outlined,
                title: isArabic ? 'الطبيب الافتراضي' : 'Virtual doctor',
                route: RoutePaths.virtualDoctor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneralAction {
  const _GeneralAction({
    required this.icon,
    required this.arabic,
    required this.english,
    this.route,
    this.onTap,
  });

  final IconData icon;
  final String arabic;
  final String english;
  final String? route;
  final VoidCallback? onTap;
}

class _GeneralActionCard extends StatelessWidget {
  const _GeneralActionCard({required this.action, required this.isArabic});

  final _GeneralAction action;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final label = isArabic ? action.arabic : action.english;
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 56) / 2,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: action.onTap ?? () => context.push(action.route!),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, color: AppTheme.primary),
                const SizedBox(height: AppTheme.spaceSm),
                Text(label, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiToolTile extends StatelessWidget {
  const _AiToolTile({required this.icon, required this.title, required this.route});

  final IconData icon;
  final String title;
  final String route;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).pop();
          context.push(route);
        },
      );
}
