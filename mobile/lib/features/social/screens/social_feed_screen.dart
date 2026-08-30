import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../localization/social_strings.dart';
import '../providers/social_providers.dart';
import '../social_access.dart';
import '../widgets/feed_composer.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/post_comments_sheet.dart';
import '../widgets/post_view_tracker.dart';

/// The social feed.
///
/// Independently instantiable — it takes no route arguments and reads
/// everything else from providers, so it can be dropped into a router, a
/// tab shell, or a test without further wiring. Navigation to the doctor's
/// own post management is delegated through [onOpenMyPosts] rather than
/// pushed from here, so this screen owns no routes.
class SocialFeedScreen extends ConsumerStatefulWidget {
  const SocialFeedScreen({super.key, this.onOpenMyPosts});

  /// Invoked by the doctor-only "My posts" action. When null the action is
  /// not rendered at all, which is what keeps this screen usable before the
  /// route exists.
  final VoidCallback? onOpenMyPosts;

  @override
  ConsumerState<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends ConsumerState<SocialFeedScreen> {
  final ScrollController _scroll = ScrollController();

  /// Distance from the bottom at which the next page starts loading.
  static const double _loadMoreThreshold = 480;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThreshold) return;
    // Every guard that matters (already loading, refreshing, no cursor,
    // exhausted) lives in the controller, so a scroll storm cannot outrun
    // it by calling from here.
    ref.read(socialFeedProvider.notifier).loadMore();
  }

  Future<void> _toggleLike(String postId) async {
    final strings = ref.read(socialStringsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(socialFeedProvider.notifier)
        .toggleLike(postId);
    if (!mounted || result.isSuccess) return;
    // A duplicate tap is not a failure worth telling the user about — the
    // first tap is still in flight and will report its own outcome.
    if (result.error?.code == 'DUPLICATE_IN_FLIGHT') return;
    messenger?.showSnackBar(SnackBar(content: Text(strings.likeError)));
  }

  Future<void> _toggleFollow(String doctorId) async {
    final strings = ref.read(socialStringsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(socialFeedProvider.notifier)
        .toggleFollow(doctorId);
    if (!mounted || result.isSuccess) return;
    if (result.error?.code == 'DUPLICATE_IN_FLIGHT') return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.error?.code == 'SELF_FOLLOW_NOT_ALLOWED'
              ? strings.socialError('SELF_FOLLOW_NOT_ALLOWED')
              : strings.followError,
        ),
      ),
    );
  }

  Future<void> _refresh() => ref.read(socialFeedProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(socialStringsProvider);
    final role = ref.watch(authControllerProvider).user?.role;
    final canRead = socialFeedAvailableForRole(role);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.feedTitle),
        actions: [
          if (canRead &&
              socialComposerAvailableForRole(role) &&
              widget.onOpenMyPosts != null)
            IconButton(
              key: const Key('socialMyPostsAction'),
              tooltip: strings.myPosts,
              onPressed: widget.onOpenMyPosts,
              icon: const Icon(Icons.article_outlined),
            ),
        ],
      ),
      body: canRead
          ? _FeedBody(
              strings: strings,
              role: role,
              scrollController: _scroll,
              onRefresh: _refresh,
              onToggleLike: _toggleLike,
              onToggleFollow: _toggleFollow,
            )
          : EmptyState(
              icon: Icons.lock_outline_rounded,
              title: strings.unavailableTitle,
              hint: strings.unavailableHint,
            ),
    );
  }
}

class _FeedBody extends ConsumerWidget {
  const _FeedBody({
    required this.strings,
    required this.role,
    required this.scrollController,
    required this.onRefresh,
    required this.onToggleLike,
    required this.onToggleFollow,
  });

  final SocialStrings strings;
  final String? role;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String postId) onToggleLike;
  final Future<void> Function(String doctorId) onToggleFollow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socialFeedProvider);
    final showComposer = socialComposerAvailableForRole(role);
    final origin = ref.watch(activeOriginProvider);
    final isArabic = strings.isArabic;

    if (state.isInitialLoading && state.posts.isEmpty) {
      return Semantics(
        liveRegion: true,
        label: strings.feedLoading,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // A failed load only takes over the screen when there is nothing to
    // read; a failed *refresh* leaves the existing posts in place.
    if (state.error != null && state.posts.isEmpty) {
      return ErrorRetryState(
        title: strings.errorTitle,
        message: strings.socialError(state.error!.code),
        retryLabel: strings.retry,
        onRetry: onRefresh,
        retryKey: const Key('socialFeedRetry'),
      );
    }

    // The composer sits inside the scroll view rather than above it so the
    // whole surface is still pull-to-refreshable, and an empty feed still
    // lets a doctor publish their first post.
    final headerCount = showComposer ? 1 : 0;
    final footerCount = 1;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        // Always scrollable, so pull-to-refresh works on an empty or
        // error-free-but-short feed too.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.pageHorizontalPadding(
            MediaQuery.sizeOf(context).width,
          ),
          vertical: AppTheme.spaceLg,
        ),
        itemCount: headerCount + state.posts.length + footerCount,
        itemBuilder: (context, index) {
          if (showComposer && index == 0) {
            return FeedComposer(onPublished: onRefresh);
          }
          final postIndex = index - headerCount;
          if (postIndex >= state.posts.length) {
            return _FeedFooter(
              state: state,
              strings: strings,
              onRetry: () => ref.read(socialFeedProvider.notifier).loadMore(),
            );
          }

          final post = state.posts[postIndex];
          return PostViewTracker(
            key: ValueKey('view-${post.id}'),
            onViewed: () =>
                ref.read(socialFeedProvider.notifier).recordView(post.id),
            child: FeedPostCard(
              key: ValueKey(post.id),
              post: post,
              strings: strings,
              isArabic: isArabic,
              assetOrigin: origin,
              isLikePending: state.pendingLikes.contains(post.id),
              isFollowPending: state.pendingFollows.contains(post.doctor.id),
              onToggleLike: () => onToggleLike(post.id),
              onToggleFollow: () => onToggleFollow(post.doctor.id),
              onOpenComments: () =>
                  showPostCommentsSheet(context, postId: post.id),
            ),
          );
        },
      ),
    );
  }
}

/// Trailing slot: the empty state, the pagination spinner, or the
/// pagination error with its own retry — never more than one at a time.
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.state,
    required this.strings,
    required this.onRetry,
  });

  final SocialFeedState state;
  final SocialStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isEmpty && !state.isRefreshing) {
      return Padding(
        padding: const EdgeInsets.only(top: AppTheme.space2xl),
        child: EmptyState(
          icon: Icons.newspaper_rounded,
          title: strings.emptyTitle,
          hint: strings.emptyHint,
        ),
      );
    }

    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        child: ErrorRetryState(
          variant: ErrorRetryVariant.compact,
          title: strings.loadMoreError,
          message: strings.socialError(state.loadMoreError!.code),
          retryLabel: strings.loadMore,
          onRetry: onRetry,
          retryKey: const Key('socialFeedLoadMoreRetry'),
        ),
      );
    }

    if (state.isLoadingMore) {
      return Semantics(
        liveRegion: true,
        label: strings.loadingMore,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppTheme.spaceXl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Nothing to append and nothing left to fetch.
    return const SizedBox(height: AppTheme.spaceLg);
  }
}
