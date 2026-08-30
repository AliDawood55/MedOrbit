import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_confirm_dialog.dart';
import '../../common/widgets/admin_detail_rows.dart';
import '../models/admin_contact_message.dart';
import '../providers/admin_contact_provider.dart';

(String, Color) adminContactStatusVisual(
  AdminContactMessage message,
  AppStrings strings,
) => switch (message.status) {
  AdminContactStatus.isNew => (strings.adminContactStatusNew, AppTheme.primary),
  AdminContactStatus.read => (strings.adminContactStatusRead, AppTheme.info),
  AdminContactStatus.resolved => (
    strings.adminContactStatusResolved,
    AppTheme.success,
  ),
  AdminContactStatus.unknown => (message.statusValue, AppTheme.warning),
};

/// Opens one contact message.
///
/// A sheet rather than a route: the message body is short, the only action is
/// "mark resolved", and returning to the queue is the common next step — so a
/// dismissible overlay beats a full navigation stack entry here.
Future<void> showAdminContactMessage({
  required BuildContext context,
  required String messageId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AdminContactDetailSheet(messageId: messageId),
  );
}

class _AdminContactDetailSheet extends ConsumerWidget {
  const _AdminContactDetailSheet({required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(adminContactDetailControllerProvider(messageId));
    final controller = ref.read(
      adminContactDetailControllerProvider(messageId).notifier,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spaceLg,
            0,
            AppTheme.spaceLg,
            AppTheme.spaceXl,
          ),
          child: _content(context, ref, state, controller, strings, isArabic),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    AdminContactDetailState state,
    AdminContactDetailController controller,
    AppStrings strings,
    bool isArabic,
  ) {
    final message = state.message;
    if (message == null && state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.space2xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (message == null) {
      return ErrorRetryState(
        title: strings.adminLoadErrorTitle,
        message: strings.adminError(state.errorCode),
        retryLabel: strings.retry,
        onRetry: controller.load,
        variant: ErrorRetryVariant.compact,
        retryKey: const ValueKey('admin-contact-detail-retry'),
      );
    }

    final (statusLabel, statusColor) = adminContactStatusVisual(
      message,
      strings,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.subject,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightBold),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Wrap(
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceSm,
            children: [
              StatusBadge(label: statusLabel, color: statusColor),
              if (message.authenticated)
                StatusBadge(
                  label: strings.adminContactSenderVerified,
                  color: AppTheme.info,
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceLg),
          AdminDetailRow(
            label: strings.adminContactSender,
            value: message.senderName.isEmpty
                ? message.senderEmail
                : '${message.senderName} · ${message.senderEmail}',
            selectable: true,
          ),
          AdminDetailRow(
            label: strings.adminContactReceived,
            value: adminFormatDateTime(message.createdAt, isArabic: isArabic),
          ),
          AdminDetailRow(
            label: strings.adminContactMessageLabel,
            value: message.body ?? '',
            selectable: true,
          ),
          if (state.actionErrorCode != null) ...[
            InlineMessage(
              message: strings.adminError(state.actionErrorCode),
              tone: InlineMessageTone.error,
            ),
            const SizedBox(height: AppTheme.spaceLg),
          ],
          if (!message.isResolved)
            FilledButton.icon(
              key: const ValueKey('admin-contact-resolve'),
              onPressed: state.isResolving
                  ? null
                  : () => _resolve(context, controller, strings),
              icon: state.isResolving
                  ? const SizedBox.square(
                      dimension: AppTheme.iconMd,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.task_alt_rounded),
              label: Text(strings.adminContactResolve),
            )
          else
            InlineMessage(
              message: strings.adminContactStatusResolved,
              tone: InlineMessageTone.success,
            ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            strings.adminContactAutoReadNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    AdminContactDetailController controller,
    AppStrings strings,
  ) async {
    final confirmed = await showAdminConfirmDialog(
      context: context,
      strings: strings,
      title: strings.adminContactResolveTitle,
      body: strings.adminContactResolveBody,
      confirmLabel: strings.adminContactResolve,
      icon: Icons.task_alt_rounded,
      tone: AppTheme.success,
      confirmKey: const ValueKey('admin-contact-resolve-confirm'),
    );
    if (!confirmed || !context.mounted) return;

    final succeeded = await controller.resolve();
    if (!succeeded || !context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(strings.adminContactResolvedSuccess)),
      );
  }
}
