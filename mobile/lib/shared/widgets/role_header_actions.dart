import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/locale/locale_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../routes/route_paths.dart';

/// Common signed-in dashboard controls. Compact mode is deliberately empty:
/// sub-pages keep only their normal back/home control, while full controls
/// remain on each role's main dashboard.
class RoleHeaderActions extends ConsumerWidget {
  const RoleHeaderActions({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final notification = IconButton(
      tooltip: strings.navNotifications,
      icon: const Icon(Icons.notifications_outlined),
      onPressed: () => context.push(RoutePaths.notifications),
    );
    final profile = IconButton(
      tooltip: strings.navProfile,
      icon: const Icon(Icons.account_circle_outlined),
      onPressed: () => context.push(RoutePaths.profile),
    );
    final language = IconButton(
      tooltip: strings.languageToggleTooltip,
      icon: const Icon(Icons.translate_rounded),
      onPressed: () => ref.read(localeControllerProvider.notifier).toggle(),
    );
    final logout = IconButton(
      tooltip: strings.logoutTooltip,
      icon: const Icon(Icons.logout_rounded),
      onPressed: () async {
        await ref.read(authControllerProvider.notifier).logout();
        if (context.mounted) context.go(RoutePaths.login);
      },
    );

    if (!compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [notification, profile, language, logout],
      );
    }
    return const SizedBox.shrink();
  }
}
