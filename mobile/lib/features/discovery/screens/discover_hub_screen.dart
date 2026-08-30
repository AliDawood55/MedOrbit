import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';

class DiscoverHubScreen extends ConsumerWidget {
  const DiscoverHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(strings.discoverTitle)),
      body: ListView(
        key: const PageStorageKey<String>('discover-hub-scroll'),
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageIntro(
                  title: strings.discoverTitle,
                  subtitle: strings.discoverSubtitle,
                  icon: Icons.travel_explore_rounded,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                FeatureCard(
                  key: const ValueKey('discover-doctors'),
                  title: strings.quickFindDoctorLabel,
                  subtitle: strings.quickFindDoctorDescription,
                  icon: Icons.person_search_outlined,
                  color: AppTheme.primary,
                  trailing: Icon(AppTheme.directionalForwardIconOf(context)),
                  onTap: () => context.push(RoutePaths.doctors),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                FeatureCard(
                  key: const ValueKey('discover-clinics'),
                  title: strings.quickClinicsNearbyLabel,
                  subtitle: strings.quickClinicsNearbyDescription,
                  icon: Icons.local_hospital_outlined,
                  color: AppTheme.secondary,
                  trailing: Icon(AppTheme.directionalForwardIconOf(context)),
                  onTap: () => context.push(RoutePaths.clinics),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
