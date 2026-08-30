import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/status_badge.dart';
import '../localization/social_strings.dart';
import '../models/social_models.dart';
import 'social_avatar.dart';
import 'social_text.dart';

/// One post in the feed.
///
/// Renders only fields the server actually sent — the display name, the
/// specialty, the published timestamp, the counts, and the like/follow flags
/// are all authoritative server state, never re-derived locally.
class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.strings,
    required this.isArabic,
    required this.assetOrigin,
    required this.onToggleLike,
    required this.onOpenComments,
    required this.onToggleFollow,
    this.isLikePending = false,
    this.isFollowPending = false,
  });

  final FeedPost post;
  final SocialStrings strings;
  final bool isArabic;
  final String assetOrigin;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenComments;
  final VoidCallback onToggleFollow;
  final bool isLikePending;
  final bool isFollowPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final doctorName = post.doctor.displayName(isArabic: isArabic);
    final specialty = post.doctor.specialty(isArabic: isArabic);
    final title = post.localizedTitle(isArabic: isArabic);
    final reason = strings.reasonLabel(post.reason);
    final category = strings.categoryLabel(post.category);
    final published = _publishedLabel();

    final meta = [
      if (specialty.isNotEmpty) specialty,
      if (published.isNotEmpty) published,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spaceMd),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              header: true,
              label: strings.postAuthorSemantics(
                doctor: doctorName.isEmpty ? '' : doctorName,
                specialty: specialty,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SocialAvatar(
                    name: doctorName,
                    imageUrl: socialAssetUrl(
                      assetOrigin,
                      post.doctor.profileImageUrl,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AutoDirectionText(
                          doctorName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: AppTheme.weightBold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.space2xs),
                          Text(
                            meta,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // A doctor never sees a Follow control on their own post:
            // `is_own_doctor` is server-computed, and the follow endpoint
            // would answer SELF_FOLLOW_NOT_ALLOWED anyway.
            if (!post.isOwnDoctor) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _FollowButton(
                  isFollowing: post.followingDoctor,
                  isPending: isFollowPending,
                  strings: strings,
                  doctorName: doctorName,
                  onPressed: onToggleFollow,
                ),
              ),
            ],

            if (reason.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceMd),
              _ReasonBanner(label: reason),
            ],

            if (category.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusBadge(label: category, color: AppTheme.primary),
              ),
            ],

            if (title.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceMd),
              AutoDirectionText(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppTheme.weightBold,
                ),
              ),
            ],

            const SizedBox(height: AppTheme.spaceSm),
            AutoDirectionText(post.body, style: theme.textTheme.bodyMedium),

            const SizedBox(height: AppTheme.spaceMd),
            const Divider(height: 1),
            const SizedBox(height: AppTheme.spaceSm),

            // Wrap, not Row: at 2x text scale on a 320pt screen the two
            // labelled actions do not fit side by side.
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceXs,
              children: [
                _ActionButton(
                  icon: post.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${post.likeCount}',
                  text: post.likedByMe ? strings.liked : strings.like,
                  semanticsLabel: strings.likeSemantics(
                    isLiked: post.likedByMe,
                    count: post.likeCount,
                  ),
                  isSelected: post.likedByMe,
                  isPending: isLikePending,
                  onPressed: onToggleLike,
                ),
                _ActionButton(
                  icon: Icons.mode_comment_outlined,
                  label: '${post.commentCount}',
                  text: strings.comment,
                  semanticsLabel: strings.commentSemantics(post.commentCount),
                  isSelected: false,
                  isPending: false,
                  onPressed: onOpenComments,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The server's `published_at` is the only timestamp shown — the client
  /// never substitutes its own clock. An unparseable value degrades to the
  /// raw string rather than disappearing.
  String _publishedLabel() {
    final value = post.publishedAt;
    if (value == null || value.isEmpty) return '';
    try {
      return formatDate(
        DateTime.parse(value).toLocal(),
        localeCode: isArabic ? 'ar' : 'en',
      );
    } catch (_) {
      return value;
    }
  }
}

class _ReasonBanner extends StatelessWidget {
  const _ReasonBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceMd,
        vertical: AppTheme.spaceSm,
      ),
      decoration: BoxDecoration(
        color: AppTheme.mutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: AppTheme.iconSm,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.isFollowing,
    required this.isPending,
    required this.strings,
    required this.doctorName,
    required this.onPressed,
  });

  final bool isFollowing;
  final bool isPending;
  final SocialStrings strings;
  final String doctorName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = isFollowing ? strings.following : strings.follow;
    final content = isPending
        ? const SizedBox.square(
            dimension: AppTheme.iconSm,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The check/plus icon carries the same distinction as the
              // label, so follow state is never signalled by color alone.
              Icon(
                isFollowing ? Icons.check_rounded : Icons.add_rounded,
                size: AppTheme.iconSm,
              ),
              const SizedBox(width: AppTheme.spaceXs),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    return Semantics(
      button: true,
      toggled: isFollowing,
      enabled: !isPending,
      label: strings.followSemantics(
        isFollowing: isFollowing,
        doctor: doctorName,
      ),
      // Only the visual content is excluded — the button itself keeps its
      // tap action, so a screen reader can still activate it.
      child: OutlinedButton(
        onPressed: isPending ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppTheme.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
        ),
        child: ExcludeSemantics(child: content),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.text,
    required this.semanticsLabel,
    required this.isSelected,
    required this.isPending,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String text;
  final String semanticsLabel;
  final bool isSelected;
  final bool isPending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: isSelected,
      enabled: !isPending,
      label: semanticsLabel,
      child: TextButton(
        onPressed: isPending ? null : onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppTheme.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
          foregroundColor: isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The filled/outlined icon distinguishes liked from not-liked
              // independently of the foreground color.
              Icon(icon, size: AppTheme.iconMd),
              const SizedBox(width: AppTheme.spaceXs),
              Flexible(
                child: Text('$text · $label', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
