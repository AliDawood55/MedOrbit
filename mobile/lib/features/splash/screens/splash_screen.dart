import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../auth/providers/auth_provider.dart';

/// Checks for a persisted session on startup, then routes to /home or /login.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveInitialRoute());
  }

  Future<void> _resolveInitialRoute() async {
    // Pick a reachable API host before anything issues a request, so the
    // first real call already points at the right backend.
    await ref.read(apiHostResolverProvider).resolve();
    if (!mounted) return;

    await ref.read(authControllerProvider.notifier).checkAuthStatus();
    if (!mounted) return;

    final status = ref.read(authControllerProvider).status;
    context.go(status == AuthStatus.authenticated ? RoutePaths.home : RoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AppScaffold(
      useSafeArea: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primary.withValues(alpha: dark ? 0.12 : 0.07),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: ResponsiveContent(
          maxWidth: 480,
          child: Center(
            child: Semantics(
              container: true,
              liveRegion: true,
              label: strings.appStarting,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(AppTheme.radius2xl),
                      boxShadow: dark
                          ? AppTheme.shadowMdDark
                          : AppTheme.shadowMdLight,
                    ),
                    child: const Icon(
                      Icons.monitor_heart_rounded,
                      size: AppTheme.icon2xl,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceXl),
                  Text(
                    strings.appName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: AppTheme.weightExtraBold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    strings.brandTagline,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spaceXl),
                  const SizedBox.square(
                    dimension: AppTheme.iconLg,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
