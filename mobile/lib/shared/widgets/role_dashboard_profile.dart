import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../features/home/models/user_profile_model.dart';
import '../../routes/route_paths.dart';
import 'error_retry_state.dart';
import 'status_badge.dart';

/// The shared patient-style dashboard identity card used by every role.
class RoleDashboardProfileSection extends StatelessWidget {
  const RoleDashboardProfileSection({
    super.key,
    required this.profileAsync,
    required this.isArabic,
    required this.strings,
    required this.origin,
    required this.onRetry,
  });
  final AsyncValue<UserProfileModel> profileAsync;
  final bool isArabic;
  final AppStrings strings;
  final String origin;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => profileAsync.when(
    data: (profile) => _ProfileCard(
      profile: profile,
      isArabic: isArabic,
      strings: strings,
      origin: origin,
    ),
    loading: () => const Card(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.spaceXl),
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
    error: (_, _) => Card(
      child: ErrorRetryState(
        title: strings.profileLoadErrorTitle,
        message: strings.profileLoadErrorMessage,
        retryLabel: strings.retry,
        onRetry: onRetry,
        variant: ErrorRetryVariant.compact,
      ),
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.isArabic,
    required this.strings,
    required this.origin,
  });
  final UserProfileModel profile;
  final bool isArabic;
  final AppStrings strings;
  final String origin;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAvatar = profile.avatarUrl?.isNotEmpty == true;
    final role = profile.role.toLowerCase();
    final (label, color) = switch (role) {
      'doctor' => (strings.roleDoctor, AppTheme.secondary),
      'admin' || 'super_admin' => (strings.roleAdmin, AppTheme.accent),
      _ => (strings.rolePatient, AppTheme.primary),
    };
    final subtitle = switch (role) {
      'doctor' => strings.doctorDashboardSubtitle,
      'admin' || 'super_admin' => strings.adminDashboardSubtitle,
      _ => strings.patientDashboardSubtitle,
    };
    final avatar = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasAvatar ? null : AppTheme.primaryGradient,
        image: hasAvatar
            ? DecorationImage(
                image: NetworkImage('$origin${profile.avatarUrl}'),
                fit: BoxFit.cover,
              )
            : null,
      ),
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
      children: [
        Text(
          '${strings.welcomeBack}, ${profile.displayName(isArabic)}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppTheme.weightExtraBold,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Wrap(
          spacing: AppTheme.spaceSm,
          runSpacing: AppTheme.spaceXs,
          children: [
            StatusBadge(label: label, color: color),
            Directionality(
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
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceXl),
          child: LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth < AppTheme.compactBreakpoint
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(height: AppTheme.spaceLg),
                      details,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: AppTheme.spaceLg),
                      Expanded(child: details),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
