import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Unread/all segmented filter — client-side only, matches the web app's
/// single fetched list being filtered in place rather than re-queried.
class NotificationFilterBar extends StatelessWidget {
  const NotificationFilterBar({super.key, required this.unreadOnly, required this.onChanged, required this.strings});

  final bool unreadOnly;
  final ValueChanged<bool> onChanged;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTouchTarget),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(value: false, label: Text(strings.notificationsFilterAll)),
          ButtonSegment<bool>(value: true, label: Text(strings.notificationsFilterUnread)),
        ],
        selected: {unreadOnly},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}
