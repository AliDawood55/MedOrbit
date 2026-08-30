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

const primaryNavigationRoutes = <String>[
  RoutePaths.home,
  RoutePaths.discover,
  RoutePaths.services,
  RoutePaths.profile,
];

/// Persistent global navigation for the shared MedOrbit product.
///
/// Role tools live in Home and Services as additive overlays; no role replaces
/// these shared destinations or loses the shell.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    ref.listen<String>(
      authControllerProvider.select(
        (state) => '${state.user?.id ?? ''}:${state.user?.role ?? ''}',
      ),
      (previous, next) {
        if (previous == null || previous == next) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            navigationShell.goBranch(0, initialLocation: true);
          }
        });
      },
    );
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
              icon: Icons.travel_explore_outlined,
              selectedIcon: Icons.travel_explore_rounded,
              label: strings.navDiscover,
            ),
            _destination(
              icon: Icons.apps_outlined,
              selectedIcon: Icons.apps_rounded,
              label: strings.navServices,
            ),
            _destination(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: strings.navProfile,
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
