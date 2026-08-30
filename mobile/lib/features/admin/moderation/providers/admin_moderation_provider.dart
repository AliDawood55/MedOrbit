import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_moderation_api.dart';
import '../models/admin_moderation_models.dart';

final adminModerationApiProvider = Provider<AdminModerationApi>(
  (ref) => AdminModerationApi(ref.watch(dioProvider)),
);

class AdminModerationState {
  const AdminModerationState({
    this.posts = const [],
    this.comments = const [],
    this.postsFilter,
    this.commentsFilter,
    this.isLoadingPosts = true,
    this.isLoadingComments = true,
    this.hasLoadedPosts = false,
    this.hasLoadedComments = false,
    this.postsErrorCode,
    this.commentsErrorCode,
    this.pendingKeys = const {},
    this.actionErrorCode,
  });

  final List<AdminModeratedPost> posts;
  final List<AdminModeratedComment> comments;
  final AdminModerationStatus? postsFilter;
  final AdminModerationStatus? commentsFilter;
  final bool isLoadingPosts;
  final bool isLoadingComments;
  final bool hasLoadedPosts;
  final bool hasLoadedComments;
  final String? postsErrorCode;
  final String? commentsErrorCode;

  /// `post:<id>` / `comment:<id>` keys for calls in flight.
  final Set<String> pendingKeys;
  final String? actionErrorCode;

  bool isPendingPost(String id) => pendingKeys.contains('post:$id');
  bool isPendingComment(String id) => pendingKeys.contains('comment:$id');

  AdminModerationState copyWith({
    List<AdminModeratedPost>? posts,
    List<AdminModeratedComment>? comments,
    AdminModerationStatus? postsFilter,
    bool clearPostsFilter = false,
    AdminModerationStatus? commentsFilter,
    bool clearCommentsFilter = false,
    bool? isLoadingPosts,
    bool? isLoadingComments,
    bool? hasLoadedPosts,
    bool? hasLoadedComments,
    String? postsErrorCode,
    bool clearPostsError = false,
    String? commentsErrorCode,
    bool clearCommentsError = false,
    Set<String>? pendingKeys,
    String? actionErrorCode,
    bool clearActionError = false,
  }) => AdminModerationState(
    posts: posts ?? this.posts,
    comments: comments ?? this.comments,
    postsFilter: clearPostsFilter ? null : (postsFilter ?? this.postsFilter),
    commentsFilter: clearCommentsFilter
        ? null
        : (commentsFilter ?? this.commentsFilter),
    isLoadingPosts: isLoadingPosts ?? this.isLoadingPosts,
    isLoadingComments: isLoadingComments ?? this.isLoadingComments,
    hasLoadedPosts: hasLoadedPosts ?? this.hasLoadedPosts,
    hasLoadedComments: hasLoadedComments ?? this.hasLoadedComments,
    postsErrorCode: clearPostsError
        ? null
        : (postsErrorCode ?? this.postsErrorCode),
    commentsErrorCode: clearCommentsError
        ? null
        : (commentsErrorCode ?? this.commentsErrorCode),
    pendingKeys: pendingKeys ?? this.pendingKeys,
    actionErrorCode: clearActionError
        ? null
        : (actionErrorCode ?? this.actionErrorCode),
  );
}

class AdminModerationController extends StateNotifier<AdminModerationState> {
  AdminModerationController(this._api) : super(const AdminModerationState()) {
    loadPosts();
    loadComments();
  }

  final AdminModerationApi _api;
  bool _disposed = false;
  int _postsGeneration = 0;
  int _commentsGeneration = 0;

  Future<void> loadPosts() async {
    final generation = ++_postsGeneration;
    if (_disposed) return;
    state = state.copyWith(isLoadingPosts: true, clearPostsError: true);
    try {
      final posts = await _api.listPosts(status: state.postsFilter);
      if (_disposed || generation != _postsGeneration) return;
      state = state.copyWith(
        posts: posts,
        isLoadingPosts: false,
        hasLoadedPosts: true,
      );
    } catch (error) {
      if (_disposed || generation != _postsGeneration) return;
      state = state.copyWith(
        isLoadingPosts: false,
        postsErrorCode: ApiException.from(error).code,
      );
    }
  }

  Future<void> loadComments() async {
    final generation = ++_commentsGeneration;
    if (_disposed) return;
    state = state.copyWith(isLoadingComments: true, clearCommentsError: true);
    try {
      final comments = await _api.listComments(status: state.commentsFilter);
      if (_disposed || generation != _commentsGeneration) return;
      state = state.copyWith(
        comments: comments,
        isLoadingComments: false,
        hasLoadedComments: true,
      );
    } catch (error) {
      if (_disposed || generation != _commentsGeneration) return;
      state = state.copyWith(
        isLoadingComments: false,
        commentsErrorCode: ApiException.from(error).code,
      );
    }
  }

  Future<void> refresh() async {
    await Future.wait([loadPosts(), loadComments()]);
  }

  void setPostsFilter(AdminModerationStatus? status) {
    if (_disposed) return;
    state = state.copyWith(
      postsFilter: status,
      clearPostsFilter: status == null,
    );
    loadPosts();
  }

  void setCommentsFilter(AdminModerationStatus? status) {
    if (_disposed) return;
    state = state.copyWith(
      commentsFilter: status,
      clearCommentsFilter: status == null,
    );
    loadComments();
  }

  void clearActionError() {
    if (_disposed || state.actionErrorCode == null) return;
    state = state.copyWith(clearActionError: true);
  }

  Future<bool> moderatePost(String id, AdminModerationAction action) async {
    if (_disposed || state.isPendingPost(id)) return false;
    state = state.copyWith(
      pendingKeys: {...state.pendingKeys, 'post:$id'},
      clearActionError: true,
    );
    try {
      await _api.moderatePost(id, action);
      if (_disposed) return true;
      final next = adminModerationResultStatus(action);
      state = state.copyWith(
        posts: _reconcilePosts(id, next),
        pendingKeys: _without('post:$id'),
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        pendingKeys: _without('post:$id'),
        actionErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  Future<bool> moderateComment(String id, AdminModerationAction action) async {
    if (_disposed || state.isPendingComment(id)) return false;
    state = state.copyWith(
      pendingKeys: {...state.pendingKeys, 'comment:$id'},
      clearActionError: true,
    );
    try {
      await _api.moderateComment(id, action);
      if (_disposed) return true;
      final next = adminModerationResultStatus(action);
      state = state.copyWith(
        comments: _reconcileComments(id, next),
        pendingKeys: _without('comment:$id'),
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        pendingKeys: _without('comment:$id'),
        actionErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  /// A moderated row that no longer matches the active filter is dropped, so
  /// the queue does not keep showing an item the filter says is not in it.
  /// With no filter, the row stays and its badge updates.
  List<AdminModeratedPost> _reconcilePosts(
    String id,
    AdminModerationStatus next,
  ) {
    final filter = state.postsFilter;
    return [
      for (final post in state.posts)
        if (post.id != id)
          post
        else if (filter == null || filter == next)
          post.withModerationStatus(next),
    ];
  }

  List<AdminModeratedComment> _reconcileComments(
    String id,
    AdminModerationStatus next,
  ) {
    final filter = state.commentsFilter;
    return [
      for (final comment in state.comments)
        if (comment.id != id)
          comment
        else if (filter == null || filter == next)
          comment.withModerationStatus(next),
    ];
  }

  Set<String> _without(String key) =>
      {...state.pendingKeys}..removeWhere((value) => value == key);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final adminModerationControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminModerationController,
      AdminModerationState
    >((ref) => AdminModerationController(ref.watch(adminModerationApiProvider)));
