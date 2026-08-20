import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../providers/notifications_provider.dart';
import '../widgets/notification_filter_bar.dart';
import '../widgets/notification_tile.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(notificationsControllerProvider);
    final notifier = ref.read(notificationsControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.notificationsTitle),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: state.isMarkingAllRead ? null : () => _markAllRead(context, notifier, strings),
              child: state.isMarkingAllRead
                  ? const SizedBox.square(dimension: AppTheme.iconMd, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(strings.notificationsMarkAllRead),
            ),
        ],
      ),
      useSafeArea: true,
      body: state.notifications.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [const CircularProgressIndicator(), const SizedBox(height: AppTheme.spaceMd), Text(strings.loading)],
          ),
        ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Card(
              child: ErrorRetryState(
                title: strings.notificationsErrorLoad,
                message: strings.errorGeneric,
                retryLabel: strings.retry,
                onRetry: notifier.retry,
                variant: ErrorRetryVariant.compact,
              ),
            ),
          ),
        ),
        data: (_) => RefreshIndicator(
          onRefresh: notifier.retry,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: strings.notificationsTitle,
                      subtitle: strings.notificationsSubtitle,
                      icon: Icons.notifications_outlined,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: NotificationFilterBar(
                        unreadOnly: state.unreadOnly,
                        onChanged: notifier.setUnreadOnly,
                        strings: strings,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    if (state.visible.isEmpty)
                      Card(
                        child: EmptyState(
                          icon: Icons.notifications_off_outlined,
                          title: state.unreadOnly ? strings.notificationsEmptyUnreadTitle : strings.notificationsEmptyTitle,
                          hint: state.unreadOnly ? strings.notificationsEmptyUnreadHint : strings.notificationsEmptyHint,
                          variant: EmptyStateVariant.compact,
                        ),
                      )
                    else
                      for (final notification in state.visible) ...[
                        NotificationTile(
                          notification: notification,
                          isArabic: isArabic,
                          strings: strings,
                          isBusy: state.pendingIds.contains(notification.id),
                          onMarkRead: notification.isRead
                              ? null
                              : () => _markRead(context, notifier, notification.id, strings),
                          onDelete: () => _confirmDelete(context, notifier, notification.id, strings),
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _markRead(
  BuildContext context,
  NotificationsController notifier,
  String id,
  AppStrings strings,
) async {
  final ok = await notifier.markRead(id);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.notificationsMarkReadError)));
  }
}

Future<void> _markAllRead(
  BuildContext context,
  NotificationsController notifier,
  AppStrings strings,
) async {
  final ok = await notifier.markAllRead();
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.notificationsMarkAllError)));
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  NotificationsController notifier,
  String id,
  AppStrings strings,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.notificationsDeleteDialogTitle),
      content: Text(strings.notificationsDeleteDialogBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(strings.cancel)),
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(strings.notificationsDeleteOne)),
      ],
    ),
  );
  if (confirmed != true) return;

  final ok = await notifier.delete(id);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.notificationsDeleteError)));
  }
}
