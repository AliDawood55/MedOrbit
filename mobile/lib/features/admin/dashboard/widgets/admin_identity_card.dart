import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../home/models/user_profile_model.dart';
import '../../../home/providers/user_provider.dart';
import '../../common/providers/admin_access_provider.dart';

/// Identity header for the administration hub.
///
/// Kept in the admin feature rather than reusing Home's private profile header:
/// this one shows the `admin` / `super_admin` distinction (Home collapses both
/// into one "Administrator" badge), which is exactly the difference that
/// decides which tools are on the screen below it.
class AdminIdentityCard extends ConsumerWidget {
  const AdminIdentityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final profileAsync = ref.watch(currentUserProfileProvider);
    final access = ref.watch(adminAccessProvider);

    return profileAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spaceXl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: ErrorRetryState(
          title: strings.profileLoadErrorTitle,
          message: strings.profileLoadErrorMessage,
          retryLabel: strings.retry,
          onRetry: () => ref.invalidate(currentUserProfileProvider),
          variant: ErrorRetryVariant.compact,
          retryKey: const ValueKey('admin-identity-retry'),
        ),
      ),
      data: (profile) => _Header(
        profile: profile,
        strings: strings,
        isArabic: isArabic,
        access: access,
        origin: ref.watch(activeOriginProvider),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.strings,
    required this.isArabic,
    required this.access,
    required this.origin,
  });

  final UserProfileModel profile;
  final AppStrings strings;
  final bool isArabic;
  final AdminAccess access;
  final String origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = profile.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final (roleLabel, roleColor) = access.canUseSuperAdminTools
        ? (strings.roleSuperAdmin, AppTheme.violet)
        : (strings.roleAdmin, AppTheme.accent);

    final avatar = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasAvatar ? null : AppTheme.primaryGradient,
        image: hasAvatar
            ? DecorationImage(
                image: NetworkImage('$origin$avatarUrl'),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasAvatar
          ? null
          : Text(
              profile.initial,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: AppTheme.weightExtraBold,
              ),
            ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${strings.welcomeBack}, ${profile.displayName(isArabic)}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppTheme.weightExtraBold,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          strings.adminDashboardSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Wrap(
          spacing: AppTheme.spaceSm,
          runSpacing: AppTheme.spaceXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(label: roleLabel, color: roleColor),
            Directionality(
              // An email is always LTR, whatever the surrounding language.
              textDirection: TextDirection.ltr,
              child: Text(
                profile.email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(RoutePaths.profile),
        child: Semantics(
          button: true,
          hint: strings.navProfile,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceXl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(AppTheme.fontMd) >
                    AppTheme.fontLg * 1.25;
                final stack =
                    constraints.maxWidth < AppTheme.compactBreakpoint ||
                    largeText;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(height: AppTheme.spaceLg),
                      details,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: AppTheme.spaceLg),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
