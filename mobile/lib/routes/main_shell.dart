import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/locale/locale_controller.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/providers/auth_provider.dart';
import '../shared/widgets/app_scaffold.dart';
import 'route_paths.dart';

enum _ShellAction { language, logout }

/// Persistent bottom navigation for the five existing patient branches.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final scaledLabel = MediaQuery.textScalerOf(context).scale(AppTheme.fontXs);
    final compactNavigation =
        width < AppTheme.compactBreakpoint || scaledLabel > 15;
    final navigationHeight = (58 + (scaledLabel * 1.5))
        .clamp(72.0, 104.0)
        .toDouble();

    Future<void> handleAction(_ShellAction action) async {
      switch (action) {
        case _ShellAction.language:
          await ref.read(localeControllerProvider.notifier).toggle();
          return;
        case _ShellAction.logout:
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.go(RoutePaths.login);
          return;
      }
    }

    return AppScaffold(
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          if (navigationShell.currentIndex != 0)
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + AppTheme.spaceXs,
              end: AppTheme.spaceXs,
              child: _ShellActionsButton(
                strings: strings,
                onSelected: handleAction,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          height: navigationHeight,
          selectedIndex: navigationShell.currentIndex,
          labelBehavior: compactNavigation
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: [
            _destination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: strings.navHome,
            ),
            _destination(
              icon: Icons.description_outlined,
              selectedIcon: Icons.description_rounded,
              label: strings.navRecords,
            ),
            _destination(
              icon: Icons.medication_outlined,
              selectedIcon: Icons.medication_rounded,
              label: strings.navPrescriptions,
            ),
            _destination(
              icon: Icons.event_available_outlined,
              selectedIcon: Icons.event_available_rounded,
              label: strings.navAppointments,
            ),
            _destination(
              icon: Icons.comment_outlined,
              selectedIcon: Icons.comment_rounded,
              label: strings.navFeedback,
            ),
          ],
        ),
      ),
    );
  }

  NavigationDestination _destination({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    Widget accessibleIcon(IconData data) {
      return Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Icon(data),
      );
    }

    return NavigationDestination(
      icon: accessibleIcon(icon),
      selectedIcon: accessibleIcon(selectedIcon),
      label: label,
    );
  }
}

class _ShellActionsButton extends StatelessWidget {
  const _ShellActionsButton({required this.strings, required this.onSelected});

  final AppStrings strings;
  final ValueChanged<_ShellAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: AppTheme.elevation1,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<_ShellAction>(
        tooltip: strings.moreActionsTooltip,
        onSelected: onSelected,
        icon: const Icon(Icons.more_vert_rounded),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _ShellAction.language,
            child: Row(
              children: [
                const Icon(Icons.translate_rounded, size: AppTheme.iconMd),
                const SizedBox(width: AppTheme.spaceMd),
                Flexible(child: Text(strings.languageToggleTooltip)),
              ],
            ),
          ),
          PopupMenuItem(
            value: _ShellAction.logout,
            child: Row(
              children: [
                const Icon(Icons.logout_rounded, size: AppTheme.iconMd),
                const SizedBox(width: AppTheme.spaceMd),
                Flexible(child: Text(strings.logoutTooltip)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
