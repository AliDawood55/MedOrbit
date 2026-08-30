import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor_workspace/data/doctor_workspace_api.dart';
import '../../doctor_workspace/providers/doctor_workspace_providers.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';

final socialApiProvider = Provider<SocialApi>(
  (ref) => SocialApi(ref.watch(dioProvider)),
);

/// Identity of the current session. Every feed provider watches this, so a
/// sign-out or account switch disposes the old controller and rebuilds from
/// nothing — the previous account's posts can never flash into the new
/// session's feed.
final socialSessionKeyProvider = Provider<String>((ref) {
  final auth = ref.watch(authControllerProvider);
  return '${auth.status.name}:${auth.user?.id ?? ''}:${auth.user?.role ?? ''}';
});

/// Outcome of a one-shot mutation, mirroring `DoctorOperationResult` in the
/// doctor workspace so both features report failures the same way.
class SocialOperationResult<T> {
  const SocialOperationResult.success(this.value) : error = null;
  SocialOperationResult.failure(Object cause)
    : value = null,
      error = ApiException.from(cause);

  final T? value;
  final ApiException? error;

  bool get isSuccess => error == null;
}

const _duplicateInFlight = ApiException(
  message: 'This action is already in progress.',
  code: ApiException.codeDuplicateInFlight,
);

/// A rendered count is never negative, whatever arithmetic or server value
/// produced it.
int _atLeastZero(int value) => value < 0 ? 0 : value;

class SocialFeedState {
  const SocialFeedState({
    this.posts = const [],
    this.hasLoaded = false,
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.cursor,
    this.error,
    this.loadMoreError,
    this.pendingLikes = const {},
    this.pendingFollows = const {},
  });

  final List<FeedPost> posts;

  /// True once a load has completed successfully at least once — the only
  /// way to tell "genuinely empty" from "not fetched yet".
  final bool hasLoaded;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasMore;

  /// Opaque signed token from `next_cursor`. Never inspected or rebuilt.
  final String? cursor;

  /// Set only when there is nothing to show — a refresh that fails while
  /// posts are on screen surfaces through the returned result instead, so
  /// existing content stays put.
  final ApiException? error;
  final ApiException? loadMoreError;

  final Set<String> pendingLikes;
  final Set<String> pendingFollows;

  bool get isEmpty => hasLoaded && posts.isEmpty;

  SocialFeedState copyWith({
    List<FeedPost>? posts,
    bool? hasLoaded,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasMore,
    String? cursor,
    ApiException? error,
    ApiException? loadMoreError,
    Set<String>? pendingLikes,
    Set<String>? pendingFollows,
    bool clearCursor = false,
    bool clearError = false,
    bool clearLoadMoreError = false,
  }) => SocialFeedState(
    posts: posts ?? this.posts,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
    pendingLikes: pendingLikes ?? this.pendingLikes,
    pendingFollows: pendingFollows ?? this.pendingFollows,
  );
}

class SocialFeedController extends StateNotifier<SocialFeedState> {
  SocialFeedController(this._api, {bool autoLoad = true})
    : super(const SocialFeedState()) {
    if (autoLoad) load();
  }

  final SocialApi _api;

  bool _alive = true;

  /// Bumped by every first load and refresh. A page response whose token no
  /// longer matches is stale — it is dropped rather than merged, which is
  /// what stops a slow `loadMore` from appending onto a fresher list.
  int _generation = 0;

  /// Guards against a second first-load/refresh being started while one is
  /// already running (double `initState`, rapid pull-to-refresh).
  bool _listRequestActive = false;

  final Set<String> _pendingLikes = {};
  final Set<String> _pendingFollows = {};

  /// Posts already reported as viewed for this foreground session. The
  /// server deduplicates per user per day as well
  /// (`userEvent.service.js`'s `dedupeKey`); this simply avoids the request.
  final Set<String> _viewedPosts = {};

  @override
  void dispose() {
    _alive = false;
    _generation++;
    super.dispose();
  }

  /// First load. No-ops if a list request is already running so a rebuild
  /// cannot double-fetch.
  Future<void> load() => _loadFirstPage(refresh: false);

  /// Pull-to-refresh. Keeps the current posts on screen while it runs and
  /// only replaces them once a page actually arrives.
  Future<void> refresh() => _loadFirstPage(refresh: true);

  Future<void> _loadFirstPage({required bool refresh}) async {
    if (!_alive || _listRequestActive) return;
    _listRequestActive = true;

    final request = ++_generation;
    state = state.copyWith(
      isInitialLoading: !refresh && state.posts.isEmpty,
      isRefreshing: refresh,
      isLoadingMore: false,
      clearError: true,
      clearLoadMoreError: true,
    );

    try {
      final page = await _api.getFeed(limit: SocialApi.pageSize);
      if (!_alive || request != _generation) return;
      state = state.copyWith(
        posts: _dedupe(page.items),
        hasLoaded: true,
        isInitialLoading: false,
        isRefreshing: false,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        clearError: true,
      );
    } catch (cause) {
      if (!_alive || request != _generation) return;
      final failure = ApiException.from(cause);
      state = state.copyWith(
        isInitialLoading: false,
        isRefreshing: false,
        // A refresh failure must not wipe posts the user is already reading.
        error: state.posts.isEmpty ? failure : null,
      );
    } finally {
      if (request == _generation) _listRequestActive = false;
    }
  }

  /// Appends the next cursor page.
  ///
  /// Refuses while a first load or refresh is in flight, while another
  /// `loadMore` is running, and when the server said there is nothing left —
  /// the three ways a scroll-triggered pager normally double-fires.
  Future<void> loadMore() async {
    if (!_alive) return;
    if (state.isLoadingMore || state.isRefreshing || state.isInitialLoading) {
      return;
    }
    if (_listRequestActive) return;
    final cursor = state.cursor;
    if (!state.hasMore || cursor == null) return;

    final request = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final page = await _api.getFeed(
        limit: SocialApi.pageSize,
        cursor: cursor,
      );
      if (!_alive || request != _generation) return;
      state = state.copyWith(
        posts: _dedupe([...state.posts, ...page.items]),
        isLoadingMore: false,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
      );
    } catch (cause) {
      if (!_alive || request != _generation) return;
      state = state.copyWith(
        isLoadingMore: false,
        loadMoreError: ApiException.from(cause),
      );
    }
  }

  /// Optimistically flips the like state, then reconciles with the count the
  /// server recomputed. A failure rolls the card back to exactly what it
  /// showed before the tap.
  Future<SocialOperationResult<LikeResult>> toggleLike(String postId) async {
    if (!_alive) return SocialOperationResult.failure(_duplicateInFlight);
    if (!_pendingLikes.add(postId)) {
      return SocialOperationResult.failure(_duplicateInFlight);
    }

    final original = _postById(postId);
    if (original == null) {
      _pendingLikes.remove(postId);
      return SocialOperationResult.failure(
        const ApiException(
          message: 'This post is no longer available.',
          code: ApiException.codeNotFound,
        ),
      );
    }

    final wasLiked = original.likedByMe;
    _publishPendingLikes();
    _replacePost(
      postId,
      (post) => post.copyWith(
        likedByMe: !wasLiked,
        // Counts are never allowed below zero, even if the server-sent
        // baseline was already 0 when the user un-likes.
        likeCount: _atLeastZero(post.likeCount + (wasLiked ? -1 : 1)),
      ),
    );

    try {
      final result = wasLiked
          ? await _api.unlike(postId)
          : await _api.like(postId);
      if (_alive) {
        _replacePost(
          postId,
          (post) => post.copyWith(
            likedByMe: result.liked,
            likeCount: _atLeastZero(result.likeCount),
          ),
        );
      }
      return SocialOperationResult.success(result);
    } catch (cause) {
      if (_alive) {
        _replacePost(
          postId,
          (post) =>
              post.copyWith(likedByMe: wasLiked, likeCount: original.likeCount),
        );
      }
      return SocialOperationResult.failure(cause);
    } finally {
      _pendingLikes.remove(postId);
      _publishPendingLikes();
    }
  }

  /// Follow/unfollow a doctor. The follow state is applied to *every* post
  /// from that doctor currently in the list, so two cards from the same
  /// author never disagree.
  ///
  /// Self-follow is refused locally as well: the server answers
  /// `SELF_FOLLOW_NOT_ALLOWED`, and there is no reason to spend a request
  /// discovering what `is_own_doctor` already told us.
  Future<SocialOperationResult<FollowResult>> toggleFollow(
    String doctorId,
  ) async {
    if (!_alive) return SocialOperationResult.failure(_duplicateInFlight);

    final posts = state.posts.where((p) => p.doctor.id == doctorId).toList();
    if (posts.isEmpty) {
      return SocialOperationResult.failure(
        const ApiException(
          message: 'This doctor is no longer available.',
          code: ApiException.codeNotFound,
        ),
      );
    }
    if (posts.first.isOwnDoctor) {
      return SocialOperationResult.failure(
        const ApiException(
          message: 'You cannot follow your own account.',
          code: 'SELF_FOLLOW_NOT_ALLOWED',
        ),
      );
    }
    if (!_pendingFollows.add(doctorId)) {
      return SocialOperationResult.failure(_duplicateInFlight);
    }
    _publishPendingFollows();

    final wasFollowing = posts.first.followingDoctor;
    try {
      final result = wasFollowing
          ? await _api.unfollow(doctorId)
          : await _api.follow(doctorId);
      if (_alive) _applyFollowState(doctorId, result.following);
      return SocialOperationResult.success(result);
    } catch (cause) {
      // The web feed only mutates follow state after the call succeeds, so
      // there is nothing to roll back here — the cards never moved.
      return SocialOperationResult.failure(cause);
    } finally {
      _pendingFollows.remove(doctorId);
      _publishPendingFollows();
    }
  }

  /// Reports that [postId] was meaningfully viewed.
  ///
  /// Fire-and-forget by design: view telemetry must never interrupt reading.
  /// The id is marked before the request so a second exposure cannot queue a
  /// duplicate, and a failure is not retried — matching the web feed, which
  /// unobserves the element as soon as it fires.
  Future<void> recordView(String postId) async {
    if (!_alive || !_viewedPosts.add(postId)) return;
    try {
      await _api.recordView(postId);
    } catch (_) {
      // Intentionally silent.
    }
  }

  bool hasRecordedView(String postId) => _viewedPosts.contains(postId);

  /// Keeps a card's comment counter in step after the comments sheet posts a
  /// new comment, without refetching the whole page.
  void incrementCommentCount(String postId) {
    if (!_alive) return;
    _replacePost(
      postId,
      (post) => post.copyWith(commentCount: post.commentCount + 1),
    );
  }

  void decrementCommentCount(String postId) {
    if (!_alive) return;
    _replacePost(
      postId,
      (post) => post.copyWith(
        commentCount: post.commentCount > 0 ? post.commentCount - 1 : 0,
      ),
    );
  }

  void clearLoadMoreError() {
    if (_alive) state = state.copyWith(clearLoadMoreError: true);
  }

  FeedPost? _postById(String postId) {
    for (final post in state.posts) {
      if (post.id == postId) return post;
    }
    return null;
  }

  void _replacePost(String postId, FeedPost Function(FeedPost) transform) {
    var changed = false;
    final next = state.posts
        .map((post) {
          if (post.id != postId) return post;
          changed = true;
          return transform(post);
        })
        .toList(growable: false);
    if (changed) state = state.copyWith(posts: next);
  }

  void _applyFollowState(String doctorId, bool following) {
    state = state.copyWith(
      posts: state.posts
          .map(
            (post) => post.doctor.id == doctorId
                ? post.copyWith(followingDoctor: following)
                : post,
          )
          .toList(growable: false),
    );
  }

  void _publishPendingLikes() {
    if (_alive) state = state.copyWith(pendingLikes: {..._pendingLikes});
  }

  void _publishPendingFollows() {
    if (_alive) state = state.copyWith(pendingFollows: {..._pendingFollows});
  }

  /// Keeps the first occurrence of each post id. The ranker re-scores the
  /// whole corpus per request, so a retried or racing page can legitimately
  /// repeat a post the list already holds.
  static List<FeedPost> _dedupe(List<FeedPost> posts) {
    final seen = <String>{};
    final result = <FeedPost>[];
    for (final post in posts) {
      if (seen.add(post.id)) result.add(post);
    }
    return List.unmodifiable(result);
  }
}

final socialFeedProvider =
    StateNotifierProvider.autoDispose<SocialFeedController, SocialFeedState>((
      ref,
    ) {
      ref.watch(socialSessionKeyProvider);
      return SocialFeedController(ref.watch(socialApiProvider));
    });

class PostCommentsState {
  const PostCommentsState({
    this.comments = const [],
    this.hasLoaded = false,
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.sendError,
    this.ownComments = const {},
  });

  final List<PostComment> comments;
  final bool hasLoaded;
  final bool isLoading;
  final bool isSending;
  final ApiException? error;
  final ApiException? sendError;

  /// Ids of comments this session created. See [PostCommentsController] for
  /// why this is the only ownership signal the delete affordance trusts.
  final Set<String> ownComments;

  bool get isEmpty => hasLoaded && comments.isEmpty;

  PostCommentsState copyWith({
    List<PostComment>? comments,
    bool? hasLoaded,
    bool? isLoading,
    bool? isSending,
    ApiException? error,
    ApiException? sendError,
    Set<String>? ownComments,
    bool clearError = false,
    bool clearSendError = false,
  }) => PostCommentsState(
    comments: comments ?? this.comments,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isLoading: isLoading ?? this.isLoading,
    isSending: isSending ?? this.isSending,
    error: clearError ? null : (error ?? this.error),
    sendError: clearSendError ? null : (sendError ?? this.sendError),
    ownComments: ownComments ?? this.ownComments,
  );
}

/// Comments for one post.
///
/// `GET /feed/posts/:id/comments` returns author *names* but no user id and
/// no ownership flag, while `DELETE /feed/comments/:id` authorizes strictly
/// by the authenticated user. Matching on names would be a guess, and a
/// wrong guess offers a destructive action the server will reject — so the
/// only comments this controller marks as deletable are the ones it created
/// itself in this session, whose ids came back from our own POST.
class PostCommentsController extends StateNotifier<PostCommentsState> {
  PostCommentsController(this._api, this.postId, {bool autoLoad = true})
    : super(const PostCommentsState()) {
    if (autoLoad) load();
  }

  final SocialApi _api;
  final String postId;

  bool _alive = true;
  int _generation = 0;
  bool _sending = false;

  @override
  void dispose() {
    _alive = false;
    _generation++;
    super.dispose();
  }

  Future<void> load() async {
    if (!_alive || state.isLoading) return;
    final request = ++_generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final comments = await _api.getComments(postId);
      if (!_alive || request != _generation) return;
      state = state.copyWith(
        comments: List.unmodifiable(comments),
        hasLoaded: true,
        isLoading: false,
        clearError: true,
      );
    } catch (cause) {
      if (!_alive || request != _generation) return;
      state = state.copyWith(isLoading: false, error: ApiException.from(cause));
    }
  }

  /// Posts a comment and appends the created row. Single-flight: a second
  /// submit while one is in flight is refused rather than queued, so a
  /// double-tapped Send cannot post twice.
  Future<SocialOperationResult<PostComment>> send(String body) async {
    if (!_alive) return SocialOperationResult.failure(_duplicateInFlight);

    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > SocialApi.maxCommentLength) {
      return SocialOperationResult.failure(
        const ApiException(
          message: 'Comment must be between 1 and 1000 characters.',
          code: ApiException.codeValidationError,
        ),
      );
    }
    if (_sending) return SocialOperationResult.failure(_duplicateInFlight);
    _sending = true;
    state = state.copyWith(isSending: true, clearSendError: true);

    try {
      final created = await _api.addComment(postId, trimmed);
      if (_alive) {
        state = state.copyWith(
          comments: List.unmodifiable([...state.comments, created]),
          hasLoaded: true,
          isSending: false,
          ownComments: {...state.ownComments, created.id},
          clearSendError: true,
        );
      }
      return SocialOperationResult.success(created);
    } catch (cause) {
      final failure = ApiException.from(cause);
      if (_alive) {
        state = state.copyWith(isSending: false, sendError: failure);
      }
      return SocialOperationResult.failure(failure);
    } finally {
      _sending = false;
    }
  }

  /// Deletes a comment this session created. Callers must not offer this for
  /// any other comment — see the class doc.
  Future<SocialOperationResult<void>> delete(String commentId) async {
    if (!_alive) return SocialOperationResult.failure(_duplicateInFlight);
    if (!state.ownComments.contains(commentId)) {
      return SocialOperationResult.failure(
        const ApiException(
          message: 'This comment cannot be deleted from here.',
          code: ApiException.codeForbidden,
        ),
      );
    }
    try {
      await _api.deleteComment(commentId);
      if (_alive) {
        state = state.copyWith(
          comments: List.unmodifiable(
            state.comments.where((c) => c.id != commentId),
          ),
          ownComments: {...state.ownComments}..remove(commentId),
        );
      }
      return const SocialOperationResult.success(null);
    } catch (cause) {
      return SocialOperationResult.failure(cause);
    }
  }
}

final postCommentsProvider = StateNotifierProvider.autoDispose
    .family<PostCommentsController, PostCommentsState, String>((ref, postId) {
      ref.watch(socialSessionKeyProvider);
      return PostCommentsController(ref.watch(socialApiProvider), postId);
    });

class SocialComposerState {
  const SocialComposerState({
    this.category = PostCategory.healthTip,
    this.isSubmitting = false,
    this.error,
  });

  final PostCategory category;
  final bool isSubmitting;
  final ApiException? error;

  SocialComposerState copyWith({
    PostCategory? category,
    bool? isSubmitting,
    ApiException? error,
    bool clearError = false,
  }) => SocialComposerState(
    category: category ?? this.category,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Doctor quick composer.
///
/// Publishes through the *existing* doctor-posts contract
/// (`DoctorWorkspaceApi.savePost` → `POST /api/doctors/me/posts`) rather
/// than inventing a feed-specific create endpoint, exactly as the web
/// composer calls `API.care.createPost`. The title is derived from the first
/// 140 characters of the body — `title` is required server-side and capped
/// at 150, and the quick composer deliberately has no separate title field.
class SocialComposerController extends StateNotifier<SocialComposerState> {
  SocialComposerController(this._api) : super(const SocialComposerState());

  final DoctorWorkspaceApi _api;

  /// Web parity: `bodyValue.slice(0, 140)`.
  static const int derivedTitleLength = 140;

  bool _alive = true;
  bool _submitting = false;

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  void selectCategory(PostCategory category) {
    if (_alive) state = state.copyWith(category: category, clearError: true);
  }

  static String deriveTitle(String body) {
    final trimmed = body.trim();
    return trimmed.length <= derivedTitleLength
        ? trimmed
        : trimmed.substring(0, derivedTitleLength);
  }

  Future<SocialOperationResult<void>> publish(String body) async {
    if (!_alive) return SocialOperationResult.failure(_duplicateInFlight);

    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      const failure = ApiException(
        message: 'Please write some content for the post.',
        code: ApiException.codeValidationError,
      );
      state = state.copyWith(error: failure);
      return SocialOperationResult.failure(failure);
    }
    if (_submitting) return SocialOperationResult.failure(_duplicateInFlight);
    _submitting = true;
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      await _api.savePost(
        title: deriveTitle(trimmed),
        category: state.category.wireValue,
        body: trimmed,
        publish: true,
      );
      if (_alive) state = state.copyWith(isSubmitting: false, clearError: true);
      return const SocialOperationResult.success(null);
    } catch (cause) {
      final failure = ApiException.from(cause);
      if (_alive) {
        state = state.copyWith(isSubmitting: false, error: failure);
      }
      return SocialOperationResult.failure(failure);
    } finally {
      _submitting = false;
    }
  }
}

final socialComposerProvider =
    StateNotifierProvider.autoDispose<
      SocialComposerController,
      SocialComposerState
    >((ref) {
      ref.watch(socialSessionKeyProvider);
      return SocialComposerController(ref.watch(doctorWorkspaceApiProvider));
    });
