import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/messaging_models.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.strings,
    required this.isArabic,
    required this.assetOrigin,
    required this.onTap,
  });

  final CareConversation conversation;
  final AppStrings strings;
  final bool isArabic;
  final String assetOrigin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount;
    final preview = conversation.isPending
        ? strings.messagesRequestPendingPreview
        : (conversation.lastMessagePreview ?? strings.messagesStartPreview);
    final role = conversation.otherRole == 'doctor'
        ? strings.messagesRoleDoctor
        : strings.messagesRolePatient;
    final timestamp =
        conversation.lastMessageCreatedAt ?? conversation.createdAt;
    final time = DateFormat.MMMd(
      isArabic ? 'ar' : 'en',
    ).add_jm().format(timestamp.toLocal());
    final semantics = unread > 0
        ? '${conversation.otherDisplayName}, $role, '
              '${strings.messagesUnreadCount(unread)}, $preview, $time'
        : '${conversation.otherDisplayName}, $role, $preview, $time';

    return Semantics(
      button: true,
      label: semantics,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              child: Row(
                children: [
                  _Avatar(
                    name: conversation.otherDisplayName,
                    imageUrl: _assetUrl(
                      assetOrigin,
                      conversation.otherAvatarUrl,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppTheme.spaceSm,
                          runSpacing: AppTheme.spaceXs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              conversation.otherDisplayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: unread > 0
                                        ? AppTheme.weightExtraBold
                                        : AppTheme.weightBold,
                                  ),
                            ),
                            StatusBadge(label: role, color: AppTheme.primary),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: unread > 0 ? FontWeight.w600 : null,
                              ),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: AppTheme.spaceSm),
                    ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: AppTheme.minTouchTarget / 2,
                          minHeight: AppTheme.minTouchTarget / 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spaceSm,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLg,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onError,
                                fontWeight: AppTheme.weightExtraBold,
                              ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppTheme.spaceXs),
                  const ExcludeSemantics(
                    child: Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return CircleAvatar(
      radius: 24,
      foregroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
      child: Text(fallback.toUpperCase()),
    );
  }
}

String? _assetUrl(String origin, String? value) {
  final source = value?.trim() ?? '';
  if (source.isEmpty) return null;
  final uri = Uri.tryParse(source);
  if (uri?.hasScheme == true) return source;
  if (origin.isEmpty) return null;
  return '$origin/${source.replaceFirst(RegExp(r'^/+'), '')}';
}
