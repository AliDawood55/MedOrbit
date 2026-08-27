import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/locale/locale_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../routes/route_paths.dart';

/// Common signed-in header controls. Compact mode keeps narrow workspace
/// headers usable while preserving language and logout inside the overflow.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        notification,
        profile,
        PopupMenuButton<_HeaderAction>(
          tooltip: strings.moreActionsTooltip,
          onSelected: (action) async {
            if (action == _HeaderAction.language) {
              await ref.read(localeControllerProvider.notifier).toggle();
            } else {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(RoutePaths.login);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _HeaderAction.language,
              child: Row(
                children: [
                  const Icon(Icons.translate_rounded),
                  const SizedBox(width: 12),
                  Text(strings.languageToggleTooltip),
                ],
              ),
            ),
            PopupMenuItem(
              value: _HeaderAction.logout,
              child: Row(
                children: [
                  const Icon(Icons.logout_rounded),
                  const SizedBox(width: 12),
                  Text(strings.logoutTooltip),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _HeaderAction { language, logout }
