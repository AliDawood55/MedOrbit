import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../models/admin_user.dart';

/// One account row.
///
/// Everything stacks vertically: a side-by-side name/actions row overflows on
/// a 320 px screen once an Arabic role label and an activation button share
/// the line, so the badges and the action live on their own wrapped rows.
class AdminUserCard extends StatelessWidget {
  const AdminUserCard({
    super.key,
    required this.user,
    required this.action,
    required this.strings,
    required this.isPending,
    required this.onAction,
  });

  final AdminUser user;
  final AdminUserAction action;
  final AppStrings strings;
  final bool isPending;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppTheme.weightBold,
              ),
            ),
            const SizedBox(height: AppTheme.space2xs),
            Text(
              user.email,
              style: theme.textTheme.bodySmall,
            ),
            if (user.city != null || user.phone != null) ...[
              const SizedBox(height: AppTheme.space2xs),
              Text(
                [user.city, user.phone].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppTheme.spaceMd),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                StatusBadge(
                  label: strings.adminRoleLabel(user.roleValue),
                  color: _roleColor(user.role),
                ),
                StatusBadge(
                  label: user.isActive
                      ? strings.adminUsersStatusActive
                      : strings.adminUsersStatusInactive,
                  color: user.isActive ? AppTheme.success : AppTheme.danger,
                ),
                StatusBadge(
                  label: user.emailVerified
                      ? strings.adminUsersVerified
                      : strings.adminUsersUnverified,
                  color: user.emailVerified ? AppTheme.info : AppTheme.warning,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _action(context),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context) {
    switch (action) {
      case AdminUserAction.blockedSelfAccount:
        return _protectedNote(
          context,
          badge: strings.adminUsersCurrentAccount,
          hint: strings.adminUsersSelfHint,
        );
      case AdminUserAction.blockedProtectedAccount:
        return _protectedNote(
          context,
          badge: strings.adminUsersProtectedAccount,
          hint: strings.adminUsersProtectedHint,
        );
      case AdminUserAction.deactivate:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: ValueKey('admin-user-deactivate-${user.id}'),
            onPressed: isPending ? null : onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger),
            ),
            icon: const Icon(Icons.block_rounded, size: AppTheme.iconMd),
            label: Text(strings.adminUsersDeactivate),
          ),
        );
      case AdminUserAction.reactivate:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: ValueKey('admin-user-reactivate-${user.id}'),
            onPressed: isPending ? null : onAction,
            icon: const Icon(Icons.check_rounded, size: AppTheme.iconMd),
            label: Text(strings.adminUsersReactivate),
          ),
        );
    }
  }

  Widget _protectedNote(
    BuildContext context, {
    required String badge,
    required String hint,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge(label: badge, color: AppTheme.info),
        const SizedBox(height: AppTheme.spaceXs),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

Color _roleColor(AdminUserRole role) => switch (role) {
  AdminUserRole.doctor => AppTheme.secondary,
  AdminUserRole.admin => AppTheme.accent,
  AdminUserRole.superAdmin => AppTheme.violet,
  _ => AppTheme.primary,
};
