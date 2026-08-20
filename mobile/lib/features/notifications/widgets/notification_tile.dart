import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/localized_field.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/notification_model.dart';
import '../utils/relative_time.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.isArabic,
    required this.strings,
    required this.isBusy,
    required this.onMarkRead,
    required this.onDelete,
  });

  final NotificationModel notification;
  final bool isArabic;
  final AppStrings strings;
  final bool isBusy;

  /// Null when the notification is already read — hides the mark-read action.
  final VoidCallback? onMarkRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = localizedField(isArabic: isArabic, ar: notification.titleAr, en: notification.titleEn);
    final message = localizedField(isArabic: isArabic, ar: notification.messageAr, en: notification.messageEn);
    final unread = !notification.isRead;
    final scheme = Theme.of(context).colorScheme;
    final (typeLabel, typeColor) = _typeVisual(notification.notificationType, strings);

    return Card(
      key: ValueKey('notification-${notification.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 8,
                height: 8,
                child: unread
                    ? DecoratedBox(decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle))
                    : null,
              ),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: unread ? AppTheme.weightExtraBold : FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spaceSm),
                      StatusBadge(label: typeLabel, color: typeColor),
                    ],
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(message, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    formatNotificationRelativeTime(notification.createdAt, strings: strings),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMarkRead != null)
                  IconButton(
                    tooltip: strings.notificationsMarkRead,
                    icon: isBusy
                        ? const SizedBox.square(dimension: AppTheme.iconSm, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.done_rounded),
                    onPressed: isBusy ? null : onMarkRead,
                  ),
                IconButton(
                  tooltip: strings.notificationsDeleteOne,
                  icon: isBusy
                      ? const SizedBox.square(dimension: AppTheme.iconSm, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline_rounded),
                  onPressed: isBusy ? null : onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

(String, Color) _typeVisual(String notificationType, AppStrings strings) {
  return switch (notificationType) {
    'appointment' => (strings.notificationTypeAppointment, AppTheme.info),
    'reminder' => (strings.notificationTypeReminder, AppTheme.warning),
    'system' => (strings.notificationTypeSystem, AppTheme.violet),
    _ => (strings.notificationTypeGeneric, AppTheme.secondary),
  };
}
