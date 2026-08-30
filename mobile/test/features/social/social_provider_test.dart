import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/doctor_workspace/data/doctor_workspace_api.dart';
import 'package:mobile/features/doctor_workspace/models/doctor_models.dart';
import 'package:mobile/features/social/data/social_api.dart';
import 'package:mobile/features/social/models/social_models.dart';
import 'package:mobile/features/social/providers/social_providers.dart';

void main() {
  group('first load', () {
    test('loads one page and stores the server cursor', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b'], cursor: 'p2', hasMore: true),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      expect(controller.state.posts.map((p) => p.id), ['a', 'b']);
      expect(controller.state.cursor, 'p2');
      expect(controller.state.hasMore, isTrue);
      expect(controller.state.hasLoaded, isTrue);
      expect(controller.state.isInitialLoading, isFalse);
      expect(api.feedCalls, 1);
      controller.dispose();
    });

    test(
      'a second load while the first is in flight does not refetch',
      () async {
        final api = _FakeSocialApi(
          pages: [
            _page(['a']),
          ],
          holdFeed: true,
        );
        final controller = SocialFeedController(api);

        await controller.load();
        await controller.refresh();
        expect(api.feedCalls, 1);

        api.releaseFeed();
        await pumpEventQueue();
        expect(controller.state.posts.map((p) => p.id), ['a']);
        controller.dispose();
      },
    );

    test('a failed first load surfaces a structured error', () async {
      final api = _FakeSocialApi(
        feedError: const ApiException(
          message: 'internal detail',
          code: 'SERVICE_UNAVAILABLE',
        ),
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      expect(controller.state.error?.code, 'SERVICE_UNAVAILABLE');
      expect(controller.state.posts, isEmpty);
      expect(controller.state.isInitialLoading, isFalse);
      controller.dispose();
    });

    test('an empty feed is loaded, not errored', () async {
      final api = _FakeSocialApi(pages: [_page([])]);
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.error, isNull);
      controller.dispose();
    });

    test('a retry after failure recovers', () async {
      final api = _FakeSocialApi(
        feedError: const ApiException(
          message: 'x',
          code: 'SERVICE_UNAVAILABLE',
        ),
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      expect(controller.state.error, isNotNull);

      api.feedError = null;
      api.pages = [
        _page(['a']),
      ];
      await controller.refresh();

      expect(controller.state.error, isNull);
      expect(controller.state.posts.map((p) => p.id), ['a']);
      controller.dispose();
    });
  });

  group('refresh', () {
    test('replaces the list and resets the cursor', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], cursor: 'p2', hasMore: true),
          _page(['c'], hasMore: false),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      await controller.refresh();

      expect(controller.state.posts.map((p) => p.id), ['c']);
      expect(controller.state.cursor, isNull);
      expect(controller.state.hasMore, isFalse);
      controller.dispose();
    });

    test('a failed refresh keeps the posts already on screen', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.feedError = const ApiException(message: 'x', code: 'RECEIVE_TIMEOUT');
      await controller.refresh();

      expect(controller.state.posts.map((p) => p.id), ['a', 'b']);
      // No full-screen error takes over while there is still content.
      expect(controller.state.error, isNull);
      expect(controller.state.isRefreshing, isFalse);
      controller.dispose();
    });
  });

  group('pagination', () {
    test('appends the next page and advances the cursor', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], cursor: 'p2', hasMore: true),
          _page(['b'], cursor: 'p3', hasMore: true),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      await controller.loadMore();

      expect(controller.state.posts.map((p) => p.id), ['a', 'b']);
      expect(controller.state.cursor, 'p3');
      expect(api.cursors, [null, 'p2']);
      controller.dispose();
    });

    test('never computes an offset — only the opaque cursor is sent', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], cursor: 'signed.token', hasMore: true),
          _page(['b']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      await controller.loadMore();

      expect(api.limits, [SocialApi.pageSize, SocialApi.pageSize]);
      expect(api.cursors.last, 'signed.token');
      controller.dispose();
    });

    test('refuses to page when the server said there is no more', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], hasMore: false),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      await controller.loadMore();

      expect(api.feedCalls, 1);
      controller.dispose();
    });

    test('a duplicate loadMore while one is in flight is dropped', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], cursor: 'p2', hasMore: true),
          _page(['b']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.holdFeed = true;
      final first = controller.loadMore();
      final second = controller.loadMore();
      expect(api.feedCalls, 2, reason: 'only the first page-2 request fires');

      api.releaseFeed();
      await first;
      await second;
      expect(controller.state.posts.map((p) => p.id), ['a', 'b']);
      controller.dispose();
    });

    test('duplicate posts across pages are deduplicated by id', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b'], cursor: 'p2', hasMore: true),
          _page(['b', 'c']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      await controller.loadMore();

      expect(controller.state.posts.map((p) => p.id), ['a', 'b', 'c']);
      controller.dispose();
    });

    test(
      'a failed page keeps the list and reports a pagination error',
      () async {
        final api = _FakeSocialApi(
          pages: [
            _page(['a'], cursor: 'p2', hasMore: true),
          ],
        );
        final controller = SocialFeedController(api);
        await pumpEventQueue();

        api.feedError = const ApiException(message: 'x', code: 'RATE_LIMITED');
        await controller.loadMore();

        expect(controller.state.posts.map((p) => p.id), ['a']);
        expect(controller.state.loadMoreError?.code, 'RATE_LIMITED');
        expect(controller.state.error, isNull);
        controller.dispose();
      },
    );

    test('a stale page arriving after a refresh is discarded', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], cursor: 'p2', hasMore: true),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      // Page 2 goes out and hangs.
      api.holdFeed = true;
      api.pages = [
        _page(['stale']),
      ];
      final pending = controller.loadMore();

      // The user refreshes; the refresh completes first.
      api.releaseFeed();
      api.pages = [
        _page(['fresh']),
      ];
      await controller.refresh();
      await pending;
      await pumpEventQueue();

      expect(controller.state.posts.map((p) => p.id), ['fresh']);
      controller.dispose();
    });

    test('loadMore is refused while a refresh is running', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], cursor: 'p2', hasMore: true),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.holdFeed = true;
      api.pages = [
        _page(['fresh'], cursor: 'p9', hasMore: true),
      ];
      final refreshing = controller.refresh();
      final callsBefore = api.feedCalls;
      await controller.loadMore();
      expect(api.feedCalls, callsBefore);

      api.releaseFeed();
      await refreshing;
      controller.dispose();
    });
  });

  group('likes', () {
    test('optimistically flips state, then takes the server count', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], likeCount: 4),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.holdLike = true;
      api.likeResult = const LikeResult(liked: true, likeCount: 9);
      final pending = controller.toggleLike('a');

      expect(controller.state.posts.single.likedByMe, isTrue);
      expect(controller.state.posts.single.likeCount, 5);
      expect(controller.state.pendingLikes, contains('a'));

      api.releaseLike();
      await pending;

      // The authoritative recount wins over the optimistic guess.
      expect(controller.state.posts.single.likeCount, 9);
      expect(controller.state.pendingLikes, isEmpty);
      controller.dispose();
    });

    test('a failure rolls back to the pre-tap state', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], likeCount: 4),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.likeError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      final result = await controller.toggleLike('a');

      expect(result.isSuccess, isFalse);
      expect(result.error?.code, 'RATE_LIMITED');
      expect(controller.state.posts.single.likedByMe, isFalse);
      expect(controller.state.posts.single.likeCount, 4);
      controller.dispose();
    });

    test('a fast double tap fires exactly one request', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.holdLike = true;
      final first = controller.toggleLike('a');
      final second = await controller.toggleLike('a');

      expect(second.isSuccess, isFalse);
      expect(second.error?.code, ApiException.codeDuplicateInFlight);
      expect(api.likeCalls, 1);

      api.releaseLike();
      await first;
      controller.dispose();
    });

    test('unliking sends the DELETE branch and never goes negative', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], likeCount: 0, likedByMe: true),
        ],
      );
      api.likeResult = const LikeResult(liked: false, likeCount: 0);
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      await controller.toggleLike('a');
      expect(api.unlikeCalls, 1);
      expect(api.likeCalls, 0);
      expect(controller.state.posts.single.likeCount, 0);
      controller.dispose();
    });

    test(
      'liking a post that is gone reports NOT_FOUND without a call',
      () async {
        final api = _FakeSocialApi(
          pages: [
            _page(['a']),
          ],
        );
        final controller = SocialFeedController(api);
        await pumpEventQueue();

        final result = await controller.toggleLike('missing');
        expect(result.error?.code, ApiException.codeNotFound);
        expect(api.likeCalls, 0);
        controller.dispose();
      },
    );
  });

  group('follow', () {
    test('applies the new state to every post from that doctor', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b'], doctorId: 'doc-1'),
        ],
      );
      api.followResult = const FollowResult(following: true, followerCount: 3);
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      await controller.toggleFollow('doc-1');
      expect(
        controller.state.posts.every((p) => p.followingDoctor),
        isTrue,
        reason: 'two cards from one doctor must never disagree',
      );
      controller.dispose();
    });

    test('a failure leaves the cards exactly as they were', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], doctorId: 'doc-1'),
        ],
      );
      api.followError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      final result = await controller.toggleFollow('doc-1');
      expect(result.isSuccess, isFalse);
      expect(controller.state.posts.single.followingDoctor, isFalse);
      expect(controller.state.pendingFollows, isEmpty);
      controller.dispose();
    });

    test('a duplicate follow while one is in flight is dropped', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], doctorId: 'doc-1'),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      api.holdFollow = true;
      final first = controller.toggleFollow('doc-1');
      final second = await controller.toggleFollow('doc-1');

      expect(second.error?.code, ApiException.codeDuplicateInFlight);
      expect(api.followCalls, 1);

      api.releaseFollow();
      await first;
      controller.dispose();
    });

    test('following your own posts is refused before any request', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], doctorId: 'doc-1', isOwnDoctor: true),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      final result = await controller.toggleFollow('doc-1');
      expect(result.error?.code, 'SELF_FOLLOW_NOT_ALLOWED');
      expect(api.followCalls, 0);
      controller.dispose();
    });

    test('unfollowing sends the DELETE branch', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], doctorId: 'doc-1', following: true),
        ],
      );
      api.followResult = const FollowResult(following: false, followerCount: 2);
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      await controller.toggleFollow('doc-1');
      expect(api.unfollowCalls, 1);
      expect(api.followCalls, 0);
      expect(controller.state.posts.single.followingDoctor, isFalse);
      controller.dispose();
    });
  });

  group('view tracking', () {
    test('a post is reported at most once per session', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      await controller.recordView('a');
      await controller.recordView('a');
      await controller.recordView('a');

      expect(api.viewCalls, 1);
      expect(controller.hasRecordedView('a'), isTrue);
      controller.dispose();
    });

    test('a failed view never surfaces to the feed', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      api.viewError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      await controller.recordView('a');
      expect(controller.state.error, isNull);
      expect(controller.state.loadMoreError, isNull);
      controller.dispose();
    });
  });

  group('lifecycle', () {
    test('a response arriving after dispose changes nothing', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        holdFeed: true,
      );
      final controller = SocialFeedController(api);
      final before = controller.state;

      controller.dispose();
      api.releaseFeed();
      await pumpEventQueue();

      expect(before.posts, isEmpty);
    });

    test('mutations after dispose are refused, not thrown', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();
      controller.dispose();

      final like = await controller.toggleLike('a');
      final follow = await controller.toggleFollow('doc-1');
      expect(like.isSuccess, isFalse);
      expect(follow.isSuccess, isFalse);
      await controller.recordView('a');
      expect(api.viewCalls, 0);
    });

    test('switching account rebuilds the feed from nothing', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      final auth = _FakeAuth('user-1', 'patient');
      final container = ProviderContainer(
        overrides: [
          socialApiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith((ref) => auth),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(socialFeedProvider, (_, _) {});
      await pumpEventQueue();
      expect(sub.read().posts.map((p) => p.id), ['a']);

      api.pages = [
        _page(['b']),
      ];
      auth.switchTo('user-2', 'doctor');
      await pumpEventQueue();

      expect(
        sub.read().posts.map((p) => p.id),
        ['b'],
        reason: 'the previous account feed must not survive the switch',
      );
      expect(api.feedCalls, 2);
    });
  });

  group('comments', () {
    test('loads the approved comments for a post', () async {
      final api = _FakeSocialApi(comments: [_comment('c1'), _comment('c2')]);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      expect(controller.state.comments.map((c) => c.id), ['c1', 'c2']);
      expect(controller.state.hasLoaded, isTrue);
      expect(api.commentPostIds, ['post-1']);
      controller.dispose();
    });

    test('a load failure is structured and retryable', () async {
      final api = _FakeSocialApi(
        commentsError: const ApiException(message: 'x', code: 'NOT_FOUND'),
      );
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();
      expect(controller.state.error?.code, 'NOT_FOUND');

      api.commentsError = null;
      api.comments = [_comment('c1')];
      await controller.load();
      expect(controller.state.comments, hasLength(1));
      expect(controller.state.error, isNull);
      controller.dispose();
    });

    test('an empty thread is loaded, not errored', () async {
      final api = _FakeSocialApi(comments: const []);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.error, isNull);
      controller.dispose();
    });

    test('sending appends the created comment and marks it own', () async {
      final api = _FakeSocialApi(comments: const []);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      final result = await controller.send('  Thanks  ');
      expect(result.isSuccess, isTrue);
      expect(api.sentBodies, ['Thanks']);
      expect(controller.state.comments.single.id, 'created-1');
      expect(controller.state.ownComments, contains('created-1'));
      controller.dispose();
    });

    test('a double-tapped send posts exactly once', () async {
      final api = _FakeSocialApi(comments: const []);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      api.holdComment = true;
      final first = controller.send('Thanks');
      final second = await controller.send('Thanks');

      expect(second.error?.code, ApiException.codeDuplicateInFlight);
      expect(api.addCommentCalls, 1);

      api.releaseComment();
      await first;
      controller.dispose();
    });

    test('an empty comment is refused before any request', () async {
      final api = _FakeSocialApi(comments: const []);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      final result = await controller.send('   ');
      expect(result.error?.code, ApiException.codeValidationError);
      expect(api.addCommentCalls, 0);
      controller.dispose();
    });

    test('a comment past the server ceiling is refused locally', () async {
      final api = _FakeSocialApi(comments: const []);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      final result = await controller.send(
        'x' * (SocialApi.maxCommentLength + 1),
      );
      expect(result.error?.code, ApiException.codeValidationError);
      expect(api.addCommentCalls, 0);

      final atLimit = await controller.send('x' * SocialApi.maxCommentLength);
      expect(atLimit.isSuccess, isTrue);
      controller.dispose();
    });

    test('a send failure is reported without dropping the draft', () async {
      final api = _FakeSocialApi(comments: const []);
      api.addCommentError = const ApiException(
        message: 'x',
        code: 'RATE_LIMITED',
      );
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      final result = await controller.send('Thanks');
      expect(result.isSuccess, isFalse);
      expect(controller.state.sendError?.code, 'RATE_LIMITED');
      expect(controller.state.comments, isEmpty);
      controller.dispose();
    });

    test('only a comment this session created may be deleted', () async {
      final api = _FakeSocialApi(comments: [_comment('someone-else')]);
      final controller = PostCommentsController(api, 'post-1');
      await pumpEventQueue();

      final refused = await controller.delete('someone-else');
      expect(refused.error?.code, ApiException.codeForbidden);
      expect(api.deleteCommentCalls, 0);

      await controller.send('Mine');
      final allowed = await controller.delete('created-1');
      expect(allowed.isSuccess, isTrue);
      expect(api.deleteCommentCalls, 1);
      expect(controller.state.comments.map((c) => c.id), ['someone-else']);
      controller.dispose();
    });

    test('the feed comment counter follows send and delete', () async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], commentCount: 2),
        ],
      );
      final controller = SocialFeedController(api);
      await pumpEventQueue();

      controller.incrementCommentCount('a');
      expect(controller.state.posts.single.commentCount, 3);
      controller.decrementCommentCount('a');
      controller.decrementCommentCount('a');
      controller.decrementCommentCount('a');
      controller.decrementCommentCount('a');
      expect(controller.state.posts.single.commentCount, 0);
      controller.dispose();
    });
  });

  group('doctor quick composer', () {
    test('publishes through the existing doctor-posts contract', () async {
      final api = _FakeWorkspaceApi();
      final controller = SocialComposerController(api);

      controller.selectCategory(PostCategory.announcement);
      final result = await controller.publish('  Drink more water  ');

      expect(result.isSuccess, isTrue);
      expect(api.saved.single['category'], 'announcement');
      expect(api.saved.single['body'], 'Drink more water');
      expect(api.saved.single['publish'], true);
      expect(api.saved.single['id'], isNull);
      controller.dispose();
    });

    test('derives the title from the first 140 characters of the body', () {
      final long = 'a' * 200;
      expect(SocialComposerController.deriveTitle(long).length, 140);
      expect(SocialComposerController.deriveTitle('  short  '), 'short');
      expect(SocialComposerController.derivedTitleLength, 140);
    });

    test('the derived title stays inside the server title ceiling', () async {
      final api = _FakeWorkspaceApi();
      final controller = SocialComposerController(api);
      await controller.publish('b' * 500);

      // `POST /doctors/me/posts` caps the title at 150.
      expect((api.saved.single['title'] as String).length, 140);
      controller.dispose();
    });

    test('an empty body is refused before any request', () async {
      final api = _FakeWorkspaceApi();
      final controller = SocialComposerController(api);

      final result = await controller.publish('   ');
      expect(result.error?.code, ApiException.codeValidationError);
      expect(api.saved, isEmpty);
      expect(controller.state.error, isNotNull);
      controller.dispose();
    });

    test('a double-tapped publish posts exactly once', () async {
      final api = _FakeWorkspaceApi(hold: true);
      final controller = SocialComposerController(api);

      final first = controller.publish('Body');
      final second = await controller.publish('Body');
      expect(second.error?.code, ApiException.codeDuplicateInFlight);

      api.release();
      await first;
      expect(api.saved, hasLength(1));
      controller.dispose();
    });

    test('a publish failure is structured, not a raw server string', () async {
      final api = _FakeWorkspaceApi(
        error: const ApiException(message: 'db detail', code: 'FORBIDDEN'),
      );
      final controller = SocialComposerController(api);

      final result = await controller.publish('Body');
      expect(result.isSuccess, isFalse);
      expect(controller.state.error?.code, 'FORBIDDEN');
      expect(controller.state.isSubmitting, isFalse);
      controller.dispose();
    });
  });
}

FeedPage _page(
  List<String> ids, {
  String? cursor,
  bool hasMore = false,
  String doctorId = 'doc-1',
  int likeCount = 0,
  int commentCount = 0,
  bool likedByMe = false,
  bool following = false,
  bool isOwnDoctor = false,
}) => FeedPage(
  items: [
    for (final id in ids)
      FeedPost(
        id: id,
        body: 'Body $id',
        category: PostCategory.healthTip,
        doctor: FeedDoctor(id: doctorId, firstNameEn: 'Sara'),
        likeCount: likeCount,
        commentCount: commentCount,
        likedByMe: likedByMe,
        followingDoctor: following,
        isOwnDoctor: isOwnDoctor,
      ),
  ],
  nextCursor: cursor,
  hasMore: hasMore,
);

PostComment _comment(String id) => PostComment(id: id, body: 'Body $id');

class _FakeSocialApi implements SocialApi {
  _FakeSocialApi({
    this.pages = const [],
    this.comments = const [],
    this.feedError,
    this.commentsError,
    this.holdFeed = false,
  });

  List<FeedPage> pages;
  List<PostComment> comments;
  Object? feedError;
  Object? commentsError;
  Object? likeError;
  Object? followError;
  Object? viewError;
  Object? addCommentError;

  LikeResult likeResult = const LikeResult(liked: true, likeCount: 1);
  FollowResult followResult = const FollowResult(
    following: true,
    followerCount: 1,
  );

  bool holdFeed;
  bool holdLike = false;
  bool holdFollow = false;
  bool holdComment = false;

  Completer<void>? _feedGate;
  Completer<void>? _likeGate;
  Completer<void>? _followGate;
  Completer<void>? _commentGate;

  int feedCalls = 0;
  int likeCalls = 0;
  int unlikeCalls = 0;
  int followCalls = 0;
  int unfollowCalls = 0;
  int viewCalls = 0;
  int addCommentCalls = 0;
  int deleteCommentCalls = 0;

  final cursors = <String?>[];
  final limits = <int>[];
  final commentPostIds = <String>[];
  final sentBodies = <String>[];

  void releaseFeed() {
    holdFeed = false;
    _feedGate?.complete();
    _feedGate = null;
  }

  void releaseLike() {
    holdLike = false;
    _likeGate?.complete();
    _likeGate = null;
  }

  void releaseFollow() {
    holdFollow = false;
    _followGate?.complete();
    _followGate = null;
  }

  void releaseComment() {
    holdComment = false;
    _commentGate?.complete();
    _commentGate = null;
  }

  Future<void> _gate(
    bool hold,
    Completer<void>? Function() read,
    void Function(Completer<void>) write,
  ) async {
    if (!hold) return;
    final existing = read() ?? Completer<void>();
    write(existing);
    await existing.future;
  }

  @override
  Future<FeedPage> getFeed({
    int limit = SocialApi.pageSize,
    String? cursor,
  }) async {
    feedCalls++;
    limits.add(limit);
    final token = cursor?.trim() ?? '';
    cursors.add(token.isEmpty ? null : token);
    await _gate(holdFeed, () => _feedGate, (c) => _feedGate = c);
    if (feedError != null) throw feedError!;
    if (pages.isEmpty) {
      return const FeedPage(items: [], nextCursor: null, hasMore: false);
    }
    return pages.length == 1 ? pages.first : pages.removeAt(0);
  }

  @override
  Future<List<PostComment>> getComments(String postId) async {
    commentPostIds.add(postId);
    if (commentsError != null) throw commentsError!;
    return List.of(comments);
  }

  @override
  Future<LikeResult> like(String postId) async {
    likeCalls++;
    await _gate(holdLike, () => _likeGate, (c) => _likeGate = c);
    if (likeError != null) throw likeError!;
    return likeResult;
  }

  @override
  Future<LikeResult> unlike(String postId) async {
    unlikeCalls++;
    await _gate(holdLike, () => _likeGate, (c) => _likeGate = c);
    if (likeError != null) throw likeError!;
    return likeResult;
  }

  @override
  Future<PostComment> addComment(String postId, String body) async {
    addCommentCalls++;
    sentBodies.add(body.trim());
    await _gate(holdComment, () => _commentGate, (c) => _commentGate = c);
    if (addCommentError != null) throw addCommentError!;
    return PostComment(id: 'created-1', body: body.trim());
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteCommentCalls++;
  }

  @override
  Future<bool> recordView(String postId) async {
    viewCalls++;
    if (viewError != null) throw viewError!;
    return true;
  }

  @override
  Future<FollowResult> follow(String doctorId) async {
    followCalls++;
    await _gate(holdFollow, () => _followGate, (c) => _followGate = c);
    if (followError != null) throw followError!;
    return followResult;
  }

  @override
  Future<FollowResult> unfollow(String doctorId) async {
    unfollowCalls++;
    await _gate(holdFollow, () => _followGate, (c) => _followGate = c);
    if (followError != null) throw followError!;
    return followResult;
  }
}

class _FakeWorkspaceApi extends DoctorWorkspaceApi {
  _FakeWorkspaceApi({this.error, this.hold = false}) : super(Dio());

  final Object? error;
  bool hold;
  Completer<void>? _gate;

  final saved = <Map<String, Object?>>[];

  void release() {
    hold = false;
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<DoctorPost> savePost({
    String? id,
    required String title,
    required String category,
    required String body,
    required bool publish,
  }) async {
    saved.add({
      'id': id,
      'title': title,
      'category': category,
      'body': body,
      'publish': publish,
    });
    if (hold) {
      final gate = _gate ?? Completer<void>();
      _gate = gate;
      await gate.future;
    }
    if (error != null) throw error!;
    return const DoctorPost(
      id: 'post-new',
      title: 'Title',
      category: 'health_tip',
      body: 'Body',
      isPublished: true,
      status: 'published',
      moderationStatus: 'approved',
    );
  }
}

class _FakeAuth extends AuthController {
  _FakeAuth(String id, String role)
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService()),
        GoogleAuthService(),
        SecureStorageService(),
      ) {
    switchTo(id, role);
  }

  void switchTo(String id, String role) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: UserModel(id: id, email: '$id@example.test', role: role),
    );
  }
}
