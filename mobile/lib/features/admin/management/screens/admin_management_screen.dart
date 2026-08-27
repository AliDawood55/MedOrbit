import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../models/admin_management_models.dart';
import '../providers/admin_management_provider.dart';

class AdminManagementScreen extends ConsumerStatefulWidget {
  const AdminManagementScreen({super.key});
  @override
  ConsumerState<AdminManagementScreen> createState() =>
      _AdminManagementScreenState();
}

class _AdminManagementScreenState extends ConsumerState<AdminManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final role = ref.watch(authControllerProvider).user?.role.toLowerCase();
    final superAdmin = role == 'super_admin';
    if (role != 'admin' && !superAdmin) {
      return AppScaffold(
        appBar: AppBar(),
        body: Center(
          child: EmptyState(
            icon: Icons.lock_outline,
            title: strings.adminAccessDenied,
            hint: strings.adminAccessDeniedHint,
          ),
        ),
      );
    }
    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminManagementTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: strings.adminApplications),
            Tab(text: strings.adminUsers),
            Tab(text: strings.adminInvitations),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ApplicationsTab(),
          _UsersTab(),
          superAdmin ? _InvitationsTab() : _RestrictedTab(),
        ],
      ),
    );
  }
}

class _ApplicationsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(doctorApplicationsProvider(strings.isArabic));
    return _AsyncList<DoctorApplication>(
      state: state,
      retry: () => ref.invalidate(doctorApplicationsProvider(strings.isArabic)),
      empty: EmptyState(
        icon: Icons.verified_user_outlined,
        title: strings.adminNoApplications,
        hint: strings.adminNoApplicationsHint,
      ),
      item: (item) => _ApplicationTile(item: item),
    );
  }
}

class _ApplicationTile extends ConsumerWidget {
  const _ApplicationTile({required this.item});
  final DoctorApplication item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name.isEmpty ? item.email : item.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(item.email),
            if (item.specialty.isNotEmpty) Text(item.specialty),
            if (item.license != null)
              Text('${strings.adminLicense}: ${item.license}'),
            const SizedBox(height: AppTheme.spaceSm),
            Wrap(
              spacing: AppTheme.spaceSm,
              children: [
                FilledButton.icon(
                  onPressed: () => _run(
                    context,
                    ref,
                    () => ref
                        .read(adminManagementApiProvider)
                        .approveApplication(item.id),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(strings.adminApprove),
                ),
                OutlinedButton.icon(
                  onPressed: () => _reject(context, ref),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(strings.adminReject),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      ref.invalidate(
        doctorApplicationsProvider(ref.read(appStringsProvider).isArabic),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(appStringsProvider).adminActionComplete),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
      }
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ref.read(appStringsProvider).adminReject),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: ref.read(appStringsProvider).adminRejectionReason,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.read(appStringsProvider).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(ref.read(appStringsProvider).adminReject),
          ),
        ],
      ),
    );
    controller.dispose();
    final rejectionReason = reason;
    if (rejectionReason == null ||
        rejectionReason.isEmpty ||
        !context.mounted) {
      return;
    }
    await _run(
      context,
      ref,
      () => ref
          .read(adminManagementApiProvider)
          .rejectApplication(item.id, rejectionReason),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return _AsyncList<AdminUser>(
      state: ref.watch(adminUsersProvider),
      retry: () => ref.invalidate(adminUsersProvider),
      empty: EmptyState(
        icon: Icons.groups_outlined,
        title: strings.adminNoUsers,
        hint: strings.adminNoUsersHint,
      ),
      item: (item) => _UserTile(item: item),
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.item});
  final AdminUser item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(authControllerProvider).user;
    final protected =
        item.id == self?.id ||
        item.role == 'super_admin' ||
        (item.role == 'admin' && self?.role != 'super_admin');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            item.isActive ? Icons.person_outline : Icons.person_off_outlined,
          ),
        ),
        title: Text(item.displayName),
        subtitle: Text('${item.email}\n${item.role}'),
        isThreeLine: true,
        trailing: Switch(
          value: item.isActive,
          onChanged: protected
              ? null
              : (value) async {
                  try {
                    await ref
                        .read(adminManagementApiProvider)
                        .setUserActive(item.id, value);
                    ref.invalidate(adminUsersProvider);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ApiException.from(error).message),
                        ),
                      );
                    }
                  }
                },
        ),
      ),
    );
  }
}

class _InvitationsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_InvitationsTab> createState() => _InvitationsTabState();
}

class _InvitationsTabState extends ConsumerState<_InvitationsTab> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: strings.adminInvitationEmail,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              FilledButton(onPressed: _send, child: Text(strings.adminInvite)),
            ],
          ),
        ),
        Expanded(
          child: _AsyncList<AdminInvitation>(
            state: ref.watch(adminInvitationsProvider),
            retry: () => ref.invalidate(adminInvitationsProvider),
            empty: EmptyState(
              icon: Icons.mail_outline,
              title: strings.adminNoInvitations,
              hint: strings.adminNoInvitationsHint,
            ),
            item: (item) => Card(
              child: ListTile(
                title: Text(item.email),
                subtitle: Text(item.status),
                trailing: IconButton(
                  tooltip: strings.adminRevoke,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await ref
                          .read(adminManagementApiProvider)
                          .revokeInvitation(item.id);
                      ref.invalidate(adminInvitationsProvider);
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ApiException.from(error).message),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final email = controller.text.trim();
    if (!email.contains('@')) return;
    try {
      final manualUrl = await ref
          .read(adminManagementApiProvider)
          .createInvitation(email);
      if (!mounted) return;
      controller.clear();
      ref.invalidate(adminInvitationsProvider);
      if (manualUrl != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(ref.read(appStringsProvider).adminManualLinkTitle),
            content: SelectableText(manualUrl),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ref.read(appStringsProvider).close),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ApiException.from(error).message)));
    }
  }
}

class _RestrictedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AppTheme.spaceXl),
      child: EmptyState(
        icon: Icons.lock_outline,
        title: 'Super admin only',
        hint: 'Only a super admin can manage administrative invitations.',
      ),
    ),
  );
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.state,
    required this.retry,
    required this.empty,
    required this.item,
  });
  final AsyncValue<List<T>> state;
  final VoidCallback retry;
  final Widget empty;
  final Widget Function(T) item;
  @override
  Widget build(BuildContext context) => state.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) => ErrorRetryState(
      title: 'Could not load data',
      message: 'Please try again.',
      retryLabel: 'Retry',
      onRetry: retry,
    ),
    data: (items) => RefreshIndicator(
      onRefresh: () async => retry(),
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceXl),
                  child: empty,
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              children: [
                for (final value in items) ...[
                  item(value),
                  const SizedBox(height: AppTheme.spaceSm),
                ],
              ],
            ),
    ),
  );
}
