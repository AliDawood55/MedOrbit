import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../providers/admin_access_provider.dart';

/// Screen-level authorization for an administration surface.
///
/// The router already redirects an unauthorized session away before the screen
/// is built ([adminRedirect]); this is the second, in-widget guard so a screen
/// that is pushed directly, or one whose session changes while it is on top of
/// the stack, still cannot render administration data.
///
/// Three states, deliberately distinct:
///  * [AdminAccess.unknown] — the splash bootstrap has not resolved the
///    persisted session. Renders a neutral progress indicator: claiming "not
///    authorized" here would be wrong for an administrator on a cold start,
///    and rendering [child] would leak a frame of admin data.
///  * [AdminAccess.none] — a resolved non-administrator. Renders the
///    restricted state and never builds [child].
///  * authorized — builds [child].
class AdminGate extends ConsumerWidget {
  const AdminGate({
    super.key,
    required this.title,
    required this.child,
    this.requireSuperAdmin = false,
  });

  /// App-bar title used by the placeholder and restricted states, so those two
  /// still look like the screen the user navigated to.
  final String title;
  final Widget child;

  /// True for the surfaces the backend protects with `authorizeSuperAdmin`.
  final bool requireSuperAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminAccessProvider);
    final strings = ref.watch(appStringsProvider);

    if (access == AdminAccess.unknown) {
      return AppScaffold(
        appBar: AppBar(title: Text(title)),
        useSafeArea: true,
        body: Center(
          child: Semantics(
            label: strings.loading,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }

    final allowed = requireSuperAdmin
        ? access.canUseSuperAdminTools
        : access.canUseAdminTools;
    if (allowed) return child;

    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      useSafeArea: true,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Card(
              child: EmptyState(
                key: const ValueKey('admin-restricted'),
                icon: Icons.lock_outline_rounded,
                title: requireSuperAdmin && access.canUseAdminTools
                    ? strings.adminSuperAdminOnlyTitle
                    : strings.adminRestrictedTitle,
                hint: requireSuperAdmin && access.canUseAdminTools
                    ? strings.adminSuperAdminOnlyBody
                    : strings.adminRestrictedBody,
                variant: EmptyStateVariant.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
