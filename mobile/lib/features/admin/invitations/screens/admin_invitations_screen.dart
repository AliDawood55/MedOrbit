import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_confirm_dialog.dart';
import '../../common/widgets/admin_detail_rows.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_invitation.dart';
import '../providers/admin_invitations_provider.dart';

/// Mobile port of the web `admin-invitations.html` page.
///
/// Super-administrator only, at three layers: the router refuses the route,
/// [AdminGate] refuses the screen, and `authorizeSuperAdmin` refuses the API.
class AdminInvitationsScreen extends ConsumerWidget {
  const AdminInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminInvitationsTitle,
      requireSuperAdmin: true,
      child: const _AdminInvitationsView(),
    );
  }
}

class _AdminInvitationsView extends ConsumerStatefulWidget {
  const _AdminInvitationsView();

  @override
  ConsumerState<_AdminInvitationsView> createState() =>
      _AdminInvitationsViewState();
}

class _AdminInvitationsViewState extends ConsumerState<_AdminInvitationsView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create(AppStrings strings) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final controller = ref.read(adminInvitationsControllerProvider.notifier);
    final succeeded = await controller.create(_email.text);
    if (!mounted || !succeeded) return;

    _email.clear();
    final creation = ref.read(adminInvitationsControllerProvider).lastCreation;
    _snack(
      creation?.delivered == true
          ? strings.adminInvitationCreatedSent
          : strings.adminInvitationCreatedManual,
    );
  }

  Future<void> _revoke(AdminInvitation invitation, AppStrings strings) async {
    final confirmed = await showAdminConfirmDialog(
      context: context,
      strings: strings,
      title: strings.adminInvitationRevokeTitle(invitation.email),
      body: strings.adminInvitationRevokeBody,
      confirmLabel: strings.adminInvitationRevoke,
      icon: Icons.link_off_rounded,
      tone: AppTheme.danger,
      confirmKey: const ValueKey('admin-invitation-revoke-confirm'),
    );
    if (!confirmed || !mounted) return;

    final succeeded = await ref
        .read(adminInvitationsControllerProvider.notifier)
        .revoke(invitation.id);
    if (!mounted || !succeeded) return;
    _snack(strings.adminInvitationRevokedSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(adminInvitationsControllerProvider);
    final controller = ref.read(adminInvitationsControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminInvitationsTitle),
        actions: [
          IconButton(
            key: const ValueKey('admin-invitations-refresh'),
            tooltip: strings.adminRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
          ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      keyboardAware: true,
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(
                    title: strings.adminInvitationsTitle,
                    subtitle: strings.adminInvitationsSubtitle,
                    icon: Icons.person_add_alt_1_outlined,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  _CreateForm(
                    formKey: _formKey,
                    controller: _email,
                    strings: strings,
                    isSubmitting: state.isCreating,
                    errorCode: state.createErrorCode,
                    onSubmit: () => _create(strings),
                  ),
                  if (state.lastCreation?.acceptanceUrl != null) ...[
                    const SizedBox(height: AppTheme.spaceLg),
                    _AcceptanceLinkCard(
                      strings: strings,
                      creation: state.lastCreation!,
                      onDismiss: controller.dismissCreationLink,
                    ),
                  ],
                  const SizedBox(height: AppTheme.spaceXl),
                  if (state.revokeErrorCode != null) ...[
                    InlineMessage(
                      message: strings.adminError(state.revokeErrorCode),
                      tone: InlineMessageTone.error,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                  ],
                  ..._listSections(state, strings, isArabic, controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _listSections(
    AdminInvitationsState state,
    AppStrings strings,
    bool isArabic,
    AdminInvitationsController controller,
  ) {
    if (!state.hasLoadedOnce && state.isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppTheme.space2xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (!state.hasLoadedOnce && state.errorCode != null) {
      return [
        Card(
          child: ErrorRetryState(
            title: strings.adminLoadErrorTitle,
            message: strings.adminError(state.errorCode),
            retryLabel: strings.retry,
            onRetry: controller.load,
            variant: ErrorRetryVariant.compact,
            retryKey: const ValueKey('admin-invitations-retry'),
          ),
        ),
      ];
    }
    if (state.invitations.isEmpty) {
      return [
        Card(
          child: EmptyState(
            key: const ValueKey('admin-invitations-empty'),
            icon: Icons.mail_outline_rounded,
            title: strings.adminInvitationsEmptyTitle,
            hint: strings.adminInvitationsEmptyHint,
            variant: EmptyStateVariant.compact,
          ),
        ),
      ];
    }

    final now = DateTime.now();
    final pending = state.pending;
    final history = state.history;

    return [
      if (state.hasLoadedOnce && state.errorCode != null) ...[
        InlineMessage(
          message: strings.adminError(state.errorCode),
          tone: InlineMessageTone.warning,
        ),
        const SizedBox(height: AppTheme.spaceLg),
      ],
      SectionHeader(title: strings.adminInvitationPendingSection),
      if (pending.isEmpty)
        Card(
          child: EmptyState(
            icon: Icons.inbox_outlined,
            title: strings.adminInvitationsEmptyTitle,
            hint: strings.adminInvitationsEmptyHint,
            variant: EmptyStateVariant.compact,
          ),
        )
      else
        for (final invitation in pending) ...[
          _InvitationCard(
            invitation: invitation,
            strings: strings,
            isArabic: isArabic,
            now: now,
            isRevoking: state.revokingIds.contains(invitation.id),
            onRevoke: () => _revoke(invitation, strings),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      if (history.isNotEmpty) ...[
        const SizedBox(height: AppTheme.spaceLg),
        SectionHeader(title: strings.adminInvitationHistorySection),
        for (final invitation in history) ...[
          _InvitationCard(
            invitation: invitation,
            strings: strings,
            isArabic: isArabic,
            now: now,
            isRevoking: false,
            onRevoke: null,
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ],
    ];
  }
}

class _CreateForm extends StatelessWidget {
  const _CreateForm({
    required this.formKey,
    required this.controller,
    required this.strings,
    required this.isSubmitting,
    required this.errorCode,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final AppStrings strings;
  final bool isSubmitting;
  final String? errorCode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      title: strings.adminInvitationSend,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              key: const ValueKey('admin-invitation-email'),
              label: strings.adminInvitationEmailLabel,
              hintText: strings.emailPlaceholder,
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 320,
              enabled: !isSubmitting,
              semanticLabel: strings.adminInvitationEmailLabel,
              onFieldSubmitted: (_) => onSubmit(),
              // Same shape the auth screens use: `Validators.email` decides,
              // `AppStrings` supplies the localized message.
              validator: (value) {
                if (Validators.email(value) == null) return null;
                return (value?.trim().isEmpty ?? true)
                    ? strings.emailRequired
                    : strings.invalidEmail;
              },
            ),
            if (errorCode != null) ...[
              InlineMessage(
                message: strings.adminError(errorCode),
                tone: InlineMessageTone.error,
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            PrimaryButton(
              key: const ValueKey('admin-invitation-submit'),
              label: strings.adminInvitationSend,
              icon: Icons.send_rounded,
              isLoading: isSubmitting,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The single-use acceptance link, shown once.
///
/// It is never written to storage and never logged — the network logger
/// redacts unknown path segments and never inspects bodies. Copy hands it to
/// the clipboard so the super admin can deliver it to the invited address.
class _AcceptanceLinkCard extends StatelessWidget {
  const _AcceptanceLinkCard({
    required this.strings,
    required this.creation,
    required this.onDismiss,
  });

  final AppStrings strings;
  final AdminInvitationCreation creation;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final url = creation.acceptanceUrl!;
    return AdminSectionCard(
      title: strings.adminInvitationLinkTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InlineMessage(
            message: creation.delivered
                ? strings.adminInvitationCreatedSent
                : strings.adminInvitationCreatedManual,
            tone: creation.delivered
                ? InlineMessageTone.success
                : InlineMessageTone.warning,
          ),
          const SizedBox(height: AppTheme.spaceMd),
          Text(
            strings.adminInvitationLinkHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.spaceMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            decoration: BoxDecoration(
              color: AppTheme.mutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: SelectableText(
              url,
              key: const ValueKey('admin-invitation-link'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          Wrap(
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceSm,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('admin-invitation-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text(strings.adminCopied)),
                    );
                },
                icon: const Icon(Icons.copy_rounded, size: AppTheme.iconMd),
                label: Text(strings.adminCopy),
              ),
              OutlinedButton.icon(
                key: const ValueKey('admin-invitation-hide-link'),
                onPressed: onDismiss,
                icon: const Icon(
                  Icons.visibility_off_outlined,
                  size: AppTheme.iconMd,
                ),
                label: Text(strings.adminInvitationLinkHide),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.strings,
    required this.isArabic,
    required this.now,
    required this.isRevoking,
    required this.onRevoke,
  });

  final AdminInvitation invitation;
  final AppStrings strings;
  final bool isArabic;
  final DateTime now;
  final bool isRevoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = _statusVisual();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              invitation.email,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppTheme.weightBold,
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusBadge(label: statusLabel, color: statusColor),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Text(
              '${strings.adminInvitationCreatedOn}: ${adminIsolate(adminFormatDate(invitation.createdAt, isArabic: isArabic))}',
              style: theme.textTheme.bodySmall,
            ),
            if (invitation.expiresAt != null)
              Text(
                '${strings.adminInvitationExpiresOn}: ${adminIsolate(adminFormatDate(invitation.expiresAt!, isArabic: isArabic))}',
                style: theme.textTheme.bodySmall,
              ),
            if (onRevoke != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: ValueKey('admin-invitation-revoke-${invitation.id}'),
                  onPressed: isRevoking ? null : onRevoke,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text(strings.adminInvitationRevoke),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, Color) _statusVisual() {
    if (invitation.isExpiredAt(now)) {
      return (strings.adminInvitationStatusExpired, AppTheme.warning);
    }
    return switch (invitation.status) {
      AdminInvitationStatus.pending => (
        strings.adminInvitationStatusPending,
        AppTheme.primary,
      ),
      AdminInvitationStatus.accepted => (
        strings.adminInvitationStatusAccepted,
        AppTheme.success,
      ),
      AdminInvitationStatus.revoked => (
        strings.adminInvitationStatusRevoked,
        AppTheme.danger,
      ),
      AdminInvitationStatus.expired => (
        strings.adminInvitationStatusExpired,
        AppTheme.warning,
      ),
      AdminInvitationStatus.unknown => (
        invitation.statusValue,
        AppTheme.info,
      ),
    };
  }
}
