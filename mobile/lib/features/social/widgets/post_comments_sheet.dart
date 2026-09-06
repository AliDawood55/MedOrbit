import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../data/social_api.dart';
import '../localization/social_strings.dart';
import '../models/social_models.dart';
import '../providers/social_providers.dart';
import 'social_avatar.dart';
import 'social_text.dart';

/// Opens the comments for [postId] as a modal bottom sheet.
///
/// A sheet rather than a pushed screen: comments are a short, disposable
/// side-trip from the post, the feed stays visible behind it, and this app
/// already uses modal sheets for exactly this kind of detail view.
///
/// This surface deliberately contains no moderation controls. Approving,
/// rejecting and hiding comments live in the admin feature against
/// `/api/admin/social/*`; the feed only ever shows content the server has
/// already approved.
Future<void> showPostCommentsSheet(
  BuildContext context, {
  required String postId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => PostCommentsSheet(postId: postId),
  );
}

class PostCommentsSheet extends ConsumerStatefulWidget {
  const PostCommentsSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends ConsumerState<PostCommentsSheet> {
  final TextEditingController _input = TextEditingController();
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onChanged);
    _input.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() => _validationMessage = null);
  }

  Future<void> _send() async {
    final strings = ref.read(socialStringsProvider);
    final value = _input.text.trim();
    if (value.isEmpty) {
      setState(() => _validationMessage = strings.commentEmptyValidation);
      return;
    }

    final result = await ref
        .read(postCommentsProvider(widget.postId).notifier)
        .send(value);
    if (!mounted) return;

    if (result.isSuccess) {
      _input.clear();
      // The feed card's counter is kept in step locally rather than by
      // refetching the page — the server count is authoritative again on
      // the next feed load.
      ref
          .read(socialFeedProvider.notifier)
          .incrementCommentCount(widget.postId);
    }
  }

  Future<void> _delete(String commentId) async {
    final strings = ref.read(socialStringsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(postCommentsProvider(widget.postId).notifier)
        .delete(commentId);
    if (!mounted) return;

    if (result.isSuccess) {
      ref
          .read(socialFeedProvider.notifier)
          .decrementCommentCount(widget.postId);
    } else {
      messenger?.showSnackBar(
        SnackBar(content: Text(strings.socialError(result.error?.code))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(socialStringsProvider);
    final state = ref.watch(postCommentsProvider(widget.postId));
    final isArabic = strings.isArabic;
    final origin = ref.watch(activeOriginProvider);

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.75;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;
    // With the keyboard open, 75% of the *full* screen height plus the
    // bottom padding below (which clears the keyboard) can exceed the space
    // actually left above the keyboard, overflowing the sheet. Shrink to
    // whatever's left instead once the keyboard is showing.
    final sheetHeight = keyboardInset > 0
        ? availableHeight.clamp(0.0, maxSheetHeight)
        : maxSheetHeight;

    return Padding(
      // Keeps the composer above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.commentsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: strings.close,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _CommentsBody(
                state: state,
                strings: strings,
                isArabic: isArabic,
                assetOrigin: origin,
                onRetry: () => ref
                    .read(postCommentsProvider(widget.postId).notifier)
                    .load(),
                onDelete: _delete,
              ),
            ),
            const Divider(height: 1),
            _CommentComposer(
              controller: _input,
              strings: strings,
              isSending: state.isSending,
              validationMessage: _validationMessage,
              sendError: state.sendError == null
                  ? null
                  : strings.socialError(state.sendError!.code),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsBody extends StatelessWidget {
  const _CommentsBody({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.assetOrigin,
    required this.onRetry,
    required this.onDelete,
  });

  final PostCommentsState state;
  final SocialStrings strings;
  final bool isArabic;
  final String assetOrigin;
  final VoidCallback onRetry;
  final Future<void> Function(String commentId) onDelete;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.comments.isEmpty) {
      return Semantics(
        liveRegion: true,
        label: strings.loading,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && state.comments.isEmpty) {
      return ErrorRetryState(
        title: strings.commentsError,
        message: strings.socialError(state.error!.code),
        retryLabel: strings.retry,
        onRetry: onRetry,
        retryKey: const Key('socialCommentsRetry'),
      );
    }
    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.mode_comment_outlined,
        title: strings.commentsEmpty,
        hint: strings.commentsEmptyHint,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      itemCount: state.comments.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
      itemBuilder: (context, index) {
        final comment = state.comments[index];
        return _CommentRow(
          comment: comment,
          strings: strings,
          isArabic: isArabic,
          assetOrigin: assetOrigin,
          // Ownership: the comments endpoint returns author *names* only —
          // no user id, no ownership flag — while
          // `DELETE /feed/comments/:id` authorizes strictly by the
          // authenticated user. Matching on names would be a guess, so the
          // only rows offered a Delete are the ones this session created,
          // whose ids came back from our own POST.
          onDelete: state.ownComments.contains(comment.id)
              ? () => onDelete(comment.id)
              : null,
        );
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.strings,
    required this.isArabic,
    required this.assetOrigin,
    required this.onDelete,
  });

  final PostComment comment;
  final SocialStrings strings;
  final bool isArabic;
  final String assetOrigin;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawAuthor = comment.authorName(isArabic: isArabic);
    final author = rawAuthor.isEmpty ? strings.commentUnknownAuthor : rawAuthor;
    final timestamp = _timestamp();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SocialAvatar(
          name: author,
          imageUrl: socialAssetUrl(assetOrigin, comment.profileImageUrl),
          radius: 16,
        ),
        const SizedBox(width: AppTheme.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoDirectionText(
                author,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: AppTheme.weightBold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (timestamp.isNotEmpty)
                Text(
                  timestamp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: AppTheme.spaceXs),
              AutoDirectionText(
                comment.body,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (onDelete != null)
          IconButton(
            tooltip: strings.delete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    );
  }

  String _timestamp() {
    final value = comment.createdAt;
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

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.strings,
    required this.isSending,
    required this.validationMessage,
    required this.sendError,
    required this.onSend,
  });

  final TextEditingController controller;
  final SocialStrings strings;
  final bool isSending;
  final String? validationMessage;
  final String? sendError;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = validationMessage ?? sendError;

    return Padding(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final used = value.text.characters.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('socialCommentInput'),
                    controller: controller,
                    enabled: !isSending,
                    minLines: 1,
                    maxLines: 4,
                    // The server rejects anything over 1000 characters
                    // (`social.routes.js:69`); the field enforces the same
                    // ceiling so the user is stopped before the request.
                    maxLength: SocialApi.maxCommentLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      hintText: strings.commentPlaceholder,
                      labelText: strings.commentPlaceholder,
                      errorText: error,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Semantics(
                    label: strings.commentLengthSemantics(
                      SocialApi.maxCommentLength,
                    ),
                    value: strings.commentLengthCounter(
                      used,
                      SocialApi.maxCommentLength,
                    ),
                    child: Text(
                      strings.commentLengthCounter(
                        used,
                        SocialApi.maxCommentLength,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Semantics(
              button: true,
              enabled: !isSending,
              label: strings.commentSend,
              child: FilledButton(
                key: const Key('socialCommentSend'),
                onPressed: isSending ? null : onSend,
                child: ExcludeSemantics(
                  child: isSending
                      ? const SizedBox.square(
                          dimension: AppTheme.iconSm,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.commentSend),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
