import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/moderation/data/admin_moderation_api.dart';
import 'package:mobile/features/admin/moderation/models/admin_moderation_models.dart';
import 'package:mobile/features/admin/moderation/providers/admin_moderation_provider.dart';

AdminModeratedPost _post(String id, {String status = 'pending'}) =>
    AdminModeratedPost.fromJson({
      'id': id,
      'title_en': 'Post $id',
      'body': 'Body $id',
      'status': 'published',
      'moderation_status': status,
      'created_at': '2026-02-01T09:00:00Z',
    });

AdminModeratedComment _comment(String id, {String status = 'approved'}) =>
    AdminModeratedComment.fromJson({
      'id': id,
      'post_id': 'post-1',
      'body': 'Comment $id',
      'moderation_status': status,
      'created_at': '2026-02-02T09:00:00Z',
    });

void main() {
  test('both queues load independently on construction', () async {
    final api = _FakeApi()
      ..posts = [_post('p1')]
      ..comments = [_comment('c1')];
    final controller = AdminModerationController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.state.posts.length, 1);
    expect(controller.state.comments.length, 1);
    expect(api.postCalls, 1);
    expect(api.commentCalls, 1);
  });

  test('a failure in one queue never blanks the other', () async {
    final api = _FakeApi()
      ..comments = [_comment('c1')]
      ..postsError = const ApiException(
        message: 'raw backend detail',
        code: 'INTERNAL_ERROR',
      );
    final controller = AdminModerationController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.state.postsErrorCode, 'INTERNAL_ERROR');
    expect(controller.state.hasLoadedPosts, isFalse);
    expect(controller.state.commentsErrorCode, isNull);
    expect(controller.state.comments.length, 1);
  });

  test('each filter reloads only its own queue', () async {
    final api = _FakeApi();
    final controller = AdminModerationController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    controller.setPostsFilter(AdminModerationStatus.hidden);
    await pumpEventQueue();
    expect(api.postCalls, 2);
    expect(api.commentCalls, 1);
    expect(api.lastPostsFilter, AdminModerationStatus.hidden);

    controller.setCommentsFilter(AdminModerationStatus.rejected);
    await pumpEventQueue();
    expect(api.postCalls, 2);
    expect(api.commentCalls, 2);
    expect(api.lastCommentsFilter, AdminModerationStatus.rejected);
  });

  test('a slow earlier queue response never overwrites a newer one', () async {
    final api = _FakeApi()..posts = [_post('old')];
    final gate = Completer<List<AdminModeratedPost>>();
    api.postsGate = gate;

    final controller = AdminModerationController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    api.postsGate = null;
    api.posts = [_post('fresh')];
    controller.setPostsFilter(AdminModerationStatus.approved);
    await pumpEventQueue();
    expect(controller.state.posts.single.id, 'fresh');

    gate.complete([_post('stale')]);
    await pumpEventQueue();
    expect(controller.state.posts.single.id, 'fresh');
  });

  group('moderation actions', () {
    test('with no filter the row stays and its badge updates', () async {
      final api = _FakeApi()..posts = [_post('p1')];
      final controller = AdminModerationController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(
        await controller.moderatePost('p1', AdminModerationAction.hide),
        isTrue,
      );
      expect(
        controller.state.posts.single.moderationStatus,
        AdminModerationStatus.hidden,
      );
      expect(controller.state.pendingKeys, isEmpty);
    });

    test('a row that leaves the active filter is removed from the queue', () async {
      final api = _FakeApi()..posts = [_post('p1'), _post('p2')];
      final controller = AdminModerationController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.setPostsFilter(AdminModerationStatus.pending);
      await pumpEventQueue();

      await controller.moderatePost('p1', AdminModerationAction.approve);
      expect(controller.state.posts.map((p) => p.id), ['p2']);
    });

    test('a second tap on the same row while in flight is dropped', () async {
      final api = _FakeApi()
        ..posts = [_post('p1')]
        ..actionGate = Completer<void>();
      final controller = AdminModerationController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final first = controller.moderatePost('p1', AdminModerationAction.hide);
      await pumpEventQueue();
      expect(controller.state.isPendingPost('p1'), isTrue);

      expect(
        await controller.moderatePost('p1', AdminModerationAction.hide),
        isFalse,
      );
      expect(api.moderatePostCalls, 1);

      api.actionGate!.complete();
      expect(await first, isTrue);
    });

    test('a failure records the code and leaves the row unchanged', () async {
      final api = _FakeApi()
        ..posts = [_post('p1')]
        ..actionError = const ApiException(
          message: 'Post not found for doctor lina@example.test',
          code: 'NOT_FOUND',
        );
      final controller = AdminModerationController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(
        await controller.moderatePost('p1', AdminModerationAction.approve),
        isFalse,
      );
      expect(controller.state.actionErrorCode, 'NOT_FOUND');
      expect(
        controller.state.posts.single.moderationStatus,
        AdminModerationStatus.pending,
      );
      expect(controller.state.pendingKeys, isEmpty);

      controller.clearActionError();
      expect(controller.state.actionErrorCode, isNull);
    });

    test('comment moderation is tracked under its own pending key', () async {
      final api = _FakeApi()
        ..posts = [_post('p1')]
        ..comments = [_comment('c1')]
        ..actionGate = Completer<void>();
      final controller = AdminModerationController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final pending = controller.moderateComment(
        'c1',
        AdminModerationAction.hide,
      );
      await pumpEventQueue();

      expect(controller.state.isPendingComment('c1'), isTrue);
      // A post that happens to share the id is unaffected.
      expect(controller.state.isPendingPost('c1'), isFalse);

      api.actionGate!.complete();
      await pending;
      expect(
        controller.state.comments.single.moderationStatus,
        AdminModerationStatus.hidden,
      );
    });

    test('an action completing after disposal does not throw', () async {
      final gate = Completer<void>();
      final api = _FakeApi()
        ..posts = [_post('p1')]
        ..actionGate = gate;
      final controller = AdminModerationController(api);
      await pumpEventQueue();

      final pending = controller.moderatePost('p1', AdminModerationAction.hide);
      controller.dispose();
      gate.complete();
      await expectLater(pending, completion(isTrue));
    });
  });
}

class _FakeApi extends AdminModerationApi {
  _FakeApi() : super(Dio());

  List<AdminModeratedPost> posts = const [];
  List<AdminModeratedComment> comments = const [];
  Object? postsError;
  Object? commentsError;
  Completer<List<AdminModeratedPost>>? postsGate;
  Object? actionError;
  Completer<void>? actionGate;

  int postCalls = 0;
  int commentCalls = 0;
  int moderatePostCalls = 0;
  AdminModerationStatus? lastPostsFilter;
  AdminModerationStatus? lastCommentsFilter;

  @override
  Future<List<AdminModeratedPost>> listPosts({
    AdminModerationStatus? status,
  }) {
    postCalls++;
    lastPostsFilter = status;
    if (postsGate != null) return postsGate!.future;
    if (postsError != null) return Future.error(postsError!);
    return Future.value(posts);
  }

  @override
  Future<List<AdminModeratedComment>> listComments({
    AdminModerationStatus? status,
  }) {
    commentCalls++;
    lastCommentsFilter = status;
    if (commentsError != null) return Future.error(commentsError!);
    return Future.value(comments);
  }

  @override
  Future<void> moderatePost(String postId, AdminModerationAction action) {
    moderatePostCalls++;
    return _act();
  }

  @override
  Future<void> moderateComment(
    String commentId,
    AdminModerationAction action,
  ) => _act();

  Future<void> _act() {
    if (actionGate != null) return actionGate!.future;
    if (actionError != null) return Future.error(actionError!);
    return Future.value();
  }
}
