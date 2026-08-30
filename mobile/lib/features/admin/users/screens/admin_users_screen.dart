import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../common/providers/admin_access_provider.dart';
import '../../common/widgets/admin_confirm_dialog.dart';
import '../../common/widgets/admin_filter_chips.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_user.dart';
import '../providers/admin_users_provider.dart';
import '../widgets/admin_user_card.dart';

/// Mobile port of the web `admin-users.html` page.
///
/// Server-side `search`/`role`/`active` filtering exactly as the web page
/// sends it, plus the two activation mutations. Role changes are **not**
/// offered: `PUT /admin/users/:id/role` is hard-wired to answer `403
/// FORBIDDEN` (`backend/src/routes/admin.routes.js:137-147`), so a role
/// control here could only ever fail.
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminUsersTitle,
      child: const _AdminUsersView(),
    );
  }
}

class _AdminUsersView extends ConsumerStatefulWidget {
  const _AdminUsersView();

  @override
  ConsumerState<_AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends ConsumerState<_AdminUsersView> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(adminUsersControllerProvider).search,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _confirmAndMutate(
    AdminUser user,
    AdminUserAction action,
    AppStrings strings,
  ) async {
    final activate = action == AdminUserAction.reactivate;
    final confirmed = await showAdminConfirmDialog(
      context: context,
      strings: strings,
      title: activate
          ? strings.adminUsersConfirmReactivateTitle(user.displayName)
          : strings.adminUsersConfirmDeactivateTitle(user.displayName),
      body: activate
          ? strings.adminUsersConfirmReactivateBody
          : strings.adminUsersConfirmDeactivateBody,
      confirmLabel: activate
          ? strings.adminUsersReactivate
          : strings.adminUsersDeactivate,
      icon: activate ? Icons.check_rounded : Icons.block_rounded,
      tone: activate ? AppTheme.success : AppTheme.danger,
      confirmKey: const ValueKey('admin-user-action-confirm'),
    );
    if (!confirmed || !mounted) return;

    final succeeded = await ref
        .read(adminUsersControllerProvider.notifier)
        .setUserActive(user, activate: activate);
    if (!mounted || !succeeded) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            activate
                ? strings.adminUsersReactivateSuccess
                : strings.adminUsersDeactivateSuccess,
          ),
        ),
      );
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AdminUsersFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(adminUsersControllerProvider);
    final controller = ref.read(adminUsersControllerProvider.notifier);
    final access = ref.watch(adminAccessProvider);
    final actorId = ref.watch(authControllerProvider).user?.id;

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminUsersTitle),
        actions: [
          IconButton(
            key: const ValueKey('admin-users-refresh'),
            tooltip: strings.adminRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
          ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveContent(
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppTheme.spaceMd,
                bottom: AppTheme.spaceSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    key: const ValueKey('admin-users-search'),
                    label: strings.adminUsersSearchLabel,
                    hintText: strings.adminUsersSearchHint,
                    controller: _search,
                    maxLength: 120,
                    textInputAction: TextInputAction.search,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: state.search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clearSearch,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              controller.setSearch('');
                            },
                          ),
                    semanticLabel: strings.adminUsersSearchLabel,
                    onChanged: controller.setSearch,
                  ),
                  // A Wrap rather than a Row: at a large text scale the
                  // Filters button alone can be wider than a 320 px phone,
                  // and a Row would clip the count instead of moving it to
                  // its own line.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppTheme.spaceSm,
                    runSpacing: AppTheme.spaceXs,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('admin-users-filters'),
                        onPressed: _openFilters,
                        icon: const Icon(
                          Icons.tune_rounded,
                          size: AppTheme.iconMd,
                        ),
                        label: Text(strings.adminFiltersTitle),
                      ),
                      if (state.hasLoadedOnce)
                        Text(
                          strings.adminShowingCount(state.users.length),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  if (state.hasActiveFilters)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const ValueKey('admin-users-clear-filters'),
                        onPressed: () {
                          _search.clear();
                          controller.clearFilters();
                        },
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: AppTheme.iconMd,
                        ),
                        label: Text(strings.adminClearFilters),
                      ),
                    ),
                  if (state.actionErrorCode != null) ...[
                    const SizedBox(height: AppTheme.spaceSm),
                    InlineMessage(
                      message: strings.adminError(state.actionErrorCode),
                      tone: InlineMessageTone.error,
                    ),
                  ],
                  if (state.hasLoadedOnce && state.errorCode != null) ...[
                    const SizedBox(height: AppTheme.spaceSm),
                    InlineMessage(
                      message: strings.adminError(state.errorCode),
                      tone: InlineMessageTone.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _body(
                state: state,
                strings: strings,
                actorId: actorId,
                access: access,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body({
    required AdminUsersState state,
    required AppStrings strings,
    required String? actorId,
    required AdminAccess access,
  }) {
    final controller = ref.read(adminUsersControllerProvider.notifier);

    if (!state.hasLoadedOnce && state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasLoadedOnce && state.errorCode != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorRetryState(
            title: strings.adminLoadErrorTitle,
            message: strings.adminError(state.errorCode),
            retryLabel: strings.retry,
            onRetry: controller.load,
            retryKey: const ValueKey('admin-users-retry'),
          ),
        ],
      );
    }
    if (state.users.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            key: const ValueKey('admin-users-empty'),
            icon: Icons.person_search_outlined,
            title: strings.adminUsersEmptyTitle,
            hint: state.hasActiveFilters
                ? strings.adminNoResultsHint
                : strings.adminUsersEmptyHint,
            action: state.hasActiveFilters
                ? OutlinedButton(
                    onPressed: () {
                      _search.clear();
                      controller.clearFilters();
                    },
                    child: Text(strings.adminClearFilters),
                  )
                : null,
          ),
        ],
      );
    }

    return ResponsiveContent(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.pageHorizontalPadding(
            MediaQuery.sizeOf(context).width,
          ),
          vertical: AppTheme.spaceSm,
        ),
        itemCount: state.users.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          if (index == state.users.length) {
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceSm),
              child: Text(
                strings.adminUsersRoleChangeNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          final user = state.users[index];
          final action = adminUserAction(
            user: user,
            actorId: actorId,
            access: access,
          );
          return AdminUserCard(
            user: user,
            action: action,
            strings: strings,
            isPending: state.pendingUserIds.contains(user.id),
            onAction: () => _confirmAndMutate(user, action, strings),
          );
        },
      ),
    );
  }
}

class _AdminUsersFilterSheet extends ConsumerWidget {
  const _AdminUsersFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(adminUsersControllerProvider);
    final controller = ref.read(adminUsersControllerProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spaceLg,
          0,
          AppTheme.spaceLg,
          AppTheme.spaceXl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.adminFiltersTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            AdminFilterChips<AdminUserRole>(
              label: strings.adminUsersRoleFilterLabel,
              selected: state.role,
              onSelected: controller.setRole,
              options: [
                AdminFilterOption(
                  value: null,
                  label: strings.adminFilterAll,
                  key: const ValueKey('admin-users-role-all'),
                ),
                AdminFilterOption(
                  value: AdminUserRole.patient,
                  label: strings.rolePatient,
                  key: const ValueKey('admin-users-role-patient'),
                ),
                AdminFilterOption(
                  value: AdminUserRole.doctor,
                  label: strings.roleDoctor,
                  key: const ValueKey('admin-users-role-doctor'),
                ),
                AdminFilterOption(
                  value: AdminUserRole.admin,
                  label: strings.roleAdmin,
                  key: const ValueKey('admin-users-role-admin'),
                ),
                AdminFilterOption(
                  value: AdminUserRole.superAdmin,
                  label: strings.roleSuperAdmin,
                  key: const ValueKey('admin-users-role-super-admin'),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceLg),
            AdminFilterChips<bool>(
              label: strings.adminUsersStatusFilterLabel,
              selected: state.active,
              onSelected: controller.setActive,
              options: [
                AdminFilterOption(
                  value: null,
                  label: strings.adminFilterAll,
                  key: const ValueKey('admin-users-status-all'),
                ),
                AdminFilterOption(
                  value: true,
                  label: strings.adminUsersStatusActive,
                  key: const ValueKey('admin-users-status-active'),
                ),
                AdminFilterOption(
                  value: false,
                  label: strings.adminUsersStatusInactive,
                  key: const ValueKey('admin-users-status-inactive'),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceXl),
            FilledButton(
              key: const ValueKey('admin-users-filters-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.close),
            ),
          ],
        ),
      ),
    );
  }
}
