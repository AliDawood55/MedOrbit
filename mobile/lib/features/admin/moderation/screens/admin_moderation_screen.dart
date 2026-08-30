import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_confirm_dialog.dart';
import '../../common/widgets/admin_filter_chips.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_moderation_models.dart';
import '../providers/admin_moderation_provider.dart';

/// Mobile port of the web `admin-social.html` moderation queue.
///
/// The web page stacks two independently filtered lists down one column; on a
/// phone they become two tabs so each queue gets the full width, keeps its own
/// filter, and loads independently — a failure in one never blanks the other.
class AdminModerationScreen extends ConsumerWidget {
  const AdminModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminModerationTitle,
      child: const _AdminModerationView(),
    );
  }
}

class _AdminModerationView extends ConsumerStatefulWidget {
  const _AdminModerationView();

  @override
  ConsumerState<_AdminModerationView> createState() =>
      _AdminModerationViewState();
}

class _AdminModerationViewState extends ConsumerState<_AdminModerationView> {
  Future<bool> _confirm(
    AdminModerationAction action,
    AppStrings strings,
  ) async {
    final (title, body, icon, tone) = switch (action) {
      AdminModerationAction.approve => (
        strings.adminModerationApproveTitle,
        strings.adminModerationApproveBody,
        Icons.check_rounded,
        AppTheme.success,
      ),
      AdminModerationAction.reject => (
        strings.adminModerationRejectTitle,
        strings.adminModerationRejectBody,
        Icons.close_rounded,
        AppTheme.danger,
      ),
      AdminModerationAction.hide => (
        strings.adminModerationHideTitle,
        strings.adminModerationHideBody,
        Icons.visibility_off_outlined,
        AppTheme.warning,
      ),
    };
    return showAdminConfirmDialog(
      context: context,
      strings: strings,
      title: title,
      body: body,
      confirmLabel: _actionLabel(action, strings),
      icon: icon,
      tone: tone,
      confirmKey: const ValueKey('admin-moderation-confirm'),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _moderatePost(
    String id,
    AdminModerationAction action,
    AppStrings strings,
  ) async {
    if (!await _confirm(action, strings) || !mounted) return;
    final succeeded = await ref
        .read(adminModerationControllerProvider.notifier)
        .moderatePost(id, action);
    if (!mounted || !succeeded) return;
    _snack(strings.adminModerationSuccess);
  }

  Future<void> _moderateComment(
    String id,
    AdminModerationAction action,
    AppStrings strings,
  ) async {
    if (!await _confirm(action, strings) || !mounted) return;
    final succeeded = await ref
        .read(adminModerationControllerProvider.notifier)
        .moderateComment(id, action);
    if (!mounted || !succeeded) return;
    _snack(strings.adminModerationSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(adminModerationControllerProvider);
    final controller = ref.read(adminModerationControllerProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        appBar: AppBar(
          title: Text(strings.adminModerationTitle),
          actions: [
            IconButton(
              key: const ValueKey('admin-moderation-refresh'),
              tooltip: strings.adminRefreshTooltip,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: controller.refresh,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: strings.adminModerationPostsTab),
              Tab(text: strings.adminModerationCommentsTab),
            ],
          ),
        ),
        useSafeArea: true,
        safeAreaTop: false,
        body: Column(
          children: [
            if (state.actionErrorCode != null)
              ResponsiveContent(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spaceMd),
                  child: InlineMessage(
                    message: strings.adminError(state.actionErrorCode),
                    tone: InlineMessageTone.error,
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _PostsTab(
                    state: state,
                    strings: strings,
                    isArabic: isArabic,
                    onModerate: (id, action) =>
                        _moderatePost(id, action, strings),
                  ),
                  _CommentsTab(
                    state: state,
                    strings: strings,
                    isArabic: isArabic,
                    onModerate: (id, action) =>
                        _moderateComment(id, action, strings),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _actionLabel(AdminModerationAction action, AppStrings strings) =>
    switch (action) {
      AdminModerationAction.approve => strings.adminModerationApprove,
      AdminModerationAction.reject => strings.adminModerationReject,
      AdminModerationAction.hide => strings.adminModerationHide,
    };

(String, Color) adminModerationStatusVisual(
  AdminModerationStatus status,
  String rawValue,
  AppStrings strings,
) => switch (status) {
  AdminModerationStatus.pending => (
    strings.adminModerationStatusPending,
    AppTheme.warning,
  ),
  AdminModerationStatus.approved => (
    strings.adminModerationStatusApproved,
    AppTheme.success,
  ),
  AdminModerationStatus.rejected => (
    strings.adminModerationStatusRejected,
    AppTheme.danger,
  ),
  AdminModerationStatus.hidden => (
    strings.adminModerationStatusHidden,
    AppTheme.info,
  ),
  AdminModerationStatus.unknown => (rawValue, AppTheme.primary),
};

class _PostsTab extends ConsumerWidget {
  const _PostsTab({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.onModerate,
  });

  final AdminModerationState state;
  final AppStrings strings;
  final bool isArabic;
  final void Function(String id, AdminModerationAction action) onModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(adminModerationControllerProvider.notifier);

    return Column(
      children: [
        ResponsiveContent(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
            child: AdminFilterChips<AdminModerationStatus>(
              label: strings.adminFiltersTitle,
              selected: state.postsFilter,
              onSelected: controller.setPostsFilter,
              options: [
                AdminFilterOption(
                  value: null,
                  label: strings.adminFilterAll,
                  key: const ValueKey('admin-moderation-posts-all'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.pending,
                  label: strings.adminModerationStatusPending,
                  key: const ValueKey('admin-moderation-posts-pending'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.approved,
                  label: strings.adminModerationStatusApproved,
                  key: const ValueKey('admin-moderation-posts-approved'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.hidden,
                  label: strings.adminModerationStatusHidden,
                  key: const ValueKey('admin-moderation-posts-hidden'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.rejected,
                  label: strings.adminModerationStatusRejected,
                  key: const ValueKey('admin-moderation-posts-rejected'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.loadPosts,
            child: _list(context, controller),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, AdminModerationController controller) {
    if (!state.hasLoadedPosts && state.isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasLoadedPosts && state.postsErrorCode != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorRetryState(
            title: strings.adminLoadErrorTitle,
            message: strings.adminError(state.postsErrorCode),
            retryLabel: strings.retry,
            onRetry: controller.loadPosts,
            retryKey: const ValueKey('admin-moderation-posts-retry'),
          ),
        ],
      );
    }
    if (state.posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            key: const ValueKey('admin-moderation-posts-empty'),
            icon: Icons.article_outlined,
            title: strings.adminModerationPostsEmptyTitle,
            hint: strings.adminModerationEmptyHint,
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
        itemCount: state.posts.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          if (index == state.posts.length) {
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceSm),
              child: Text(
                strings.adminModerationLimitNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          final post = state.posts[index];
          final title = post.title(isArabic: isArabic);
          final author = post.author(isArabic: isArabic);
          final (statusLabel, statusColor) = adminModerationStatusVisual(
            post.moderationStatus,
            post.moderationStatusValue,
            strings,
          );
          return _ModerationCard(
            id: post.id,
            title: title.isEmpty ? strings.adminModerationUntitled : title,
            body: post.body,
            author: author,
            createdAt: post.createdAt,
            statusLabel: statusLabel,
            statusColor: statusColor,
            extraLine: post.publishStatus == null
                ? null
                : '${strings.adminModerationPublishState}: '
                      '${post.publishStatus}',
            isPending: state.isPendingPost(post.id),
            strings: strings,
            isArabic: isArabic,
            keyPrefix: 'admin-moderation-post',
            onModerate: onModerate,
          );
        },
      ),
    );
  }
}

class _CommentsTab extends ConsumerWidget {
  const _CommentsTab({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.onModerate,
  });

  final AdminModerationState state;
  final AppStrings strings;
  final bool isArabic;
  final void Function(String id, AdminModerationAction action) onModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(adminModerationControllerProvider.notifier);

    return Column(
      children: [
        ResponsiveContent(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
            // The web comment filter deliberately omits "pending": comments
            // are created already approved, so that option would always be an
            // empty queue.
            child: AdminFilterChips<AdminModerationStatus>(
              label: strings.adminFiltersTitle,
              selected: state.commentsFilter,
              onSelected: controller.setCommentsFilter,
              options: [
                AdminFilterOption(
                  value: null,
                  label: strings.adminFilterAll,
                  key: const ValueKey('admin-moderation-comments-all'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.approved,
                  label: strings.adminModerationStatusApproved,
                  key: const ValueKey('admin-moderation-comments-approved'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.hidden,
                  label: strings.adminModerationStatusHidden,
                  key: const ValueKey('admin-moderation-comments-hidden'),
                ),
                AdminFilterOption(
                  value: AdminModerationStatus.rejected,
                  label: strings.adminModerationStatusRejected,
                  key: const ValueKey('admin-moderation-comments-rejected'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.loadComments,
            child: _list(context, controller),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, AdminModerationController controller) {
    if (!state.hasLoadedComments && state.isLoadingComments) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasLoadedComments && state.commentsErrorCode != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorRetryState(
            title: strings.adminLoadErrorTitle,
            message: strings.adminError(state.commentsErrorCode),
            retryLabel: strings.retry,
            onRetry: controller.loadComments,
            retryKey: const ValueKey('admin-moderation-comments-retry'),
          ),
        ],
      );
    }
    if (state.comments.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            key: const ValueKey('admin-moderation-comments-empty'),
            icon: Icons.forum_outlined,
            title: strings.adminModerationCommentsEmptyTitle,
            hint: strings.adminModerationEmptyHint,
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
        itemCount: state.comments.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          if (index == state.comments.length) {
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceSm),
              child: Text(
                strings.adminModerationLimitNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          final comment = state.comments[index];
          final author = comment.author(isArabic: isArabic);
          final (statusLabel, statusColor) = adminModerationStatusVisual(
            comment.moderationStatus,
            comment.moderationStatusValue,
            strings,
          );
          return _ModerationCard(
            id: comment.id,
            title: author.isEmpty
                ? strings.adminModerationCommentsTab
                : author,
            body: comment.body,
            author: '',
            createdAt: comment.createdAt,
            statusLabel: statusLabel,
            statusColor: statusColor,
            extraLine: null,
            isPending: state.isPendingComment(comment.id),
            strings: strings,
            isArabic: isArabic,
            keyPrefix: 'admin-moderation-comment',
            onModerate: onModerate,
          );
        },
      ),
    );
  }
}

class _ModerationCard extends StatelessWidget {
  const _ModerationCard({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.createdAt,
    required this.statusLabel,
    required this.statusColor,
    required this.extraLine,
    required this.isPending,
    required this.strings,
    required this.isArabic,
    required this.keyPrefix,
    required this.onModerate,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime createdAt;
  final String statusLabel;
  final Color statusColor;
  final String? extraLine;
  final bool isPending;
  final AppStrings strings;
  final bool isArabic;
  final String keyPrefix;
  final void Function(String id, AdminModerationAction action) onModerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppTheme.weightBold,
              ),
            ),
            if (author.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space2xs),
              Text(author, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              body,
              style: theme.textTheme.bodyMedium,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              adminIsolate(adminFormatDateTime(createdAt, isArabic: isArabic)),
              style: theme.textTheme.bodySmall,
            ),
            if (extraLine != null) ...[
              const SizedBox(height: AppTheme.space2xs),
              Text(extraLine!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppTheme.spaceMd),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusBadge(label: statusLabel, color: statusColor),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey('$keyPrefix-approve-$id'),
                  onPressed: isPending
                      ? null
                      : () => onModerate(id, AdminModerationAction.approve),
                  icon: const Icon(Icons.check_rounded, size: AppTheme.iconMd),
                  label: Text(strings.adminModerationApprove),
                ),
                OutlinedButton.icon(
                  key: ValueKey('$keyPrefix-hide-$id'),
                  onPressed: isPending
                      ? null
                      : () => onModerate(id, AdminModerationAction.hide),
                  icon: const Icon(
                    Icons.visibility_off_outlined,
                    size: AppTheme.iconMd,
                  ),
                  label: Text(strings.adminModerationHide),
                ),
                OutlinedButton.icon(
                  key: ValueKey('$keyPrefix-reject-$id'),
                  onPressed: isPending
                      ? null
                      : () => onModerate(id, AdminModerationAction.reject),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                  icon: const Icon(Icons.close_rounded, size: AppTheme.iconMd),
                  label: Text(strings.adminModerationReject),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
