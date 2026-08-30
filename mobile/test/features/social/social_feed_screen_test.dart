import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/doctor_workspace/data/doctor_workspace_api.dart';
import 'package:mobile/features/doctor_workspace/models/doctor_models.dart';
import 'package:mobile/features/doctor_workspace/providers/doctor_workspace_providers.dart';
import 'package:mobile/features/social/data/social_api.dart';
import 'package:mobile/features/social/localization/social_strings.dart';
import 'package:mobile/features/social/models/social_models.dart';
import 'package:mobile/features/social/providers/social_providers.dart';
import 'package:mobile/features/social/screens/social_feed_screen.dart';
import 'package:mobile/features/social/widgets/feed_composer.dart';
import 'package:mobile/features/social/widgets/feed_post_card.dart';

void main() {
  group('feed states', () {
    testWidgets('shows a loading indicator before the first page arrives', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        holdFeed: true,
      );
      await _pump(tester, api: api, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FeedPostCard), findsNothing);

      api.releaseFeed();
      await tester.pumpAndSettle();
      expect(find.byType(FeedPostCard), findsOneWidget);
    });

    testWidgets('renders the server-sent post fields', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api);

      expect(find.text('Sara Khaled'), findsOneWidget);
      expect(find.text('English title'), findsOneWidget);
      expect(find.text('Body a'), findsOneWidget);
      expect(find.text('Health Tip'), findsOneWidget);
      expect(find.textContaining('Cardiology'), findsOneWidget);
      expect(find.text('Because you follow this doctor'), findsOneWidget);
      expect(find.text('Like · 3'), findsOneWidget);
      expect(find.text('Comment · 2'), findsOneWidget);
    });

    testWidgets('an unknown reason code renders no banner text', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], reason: FeedReason.unknown),
        ],
      );
      await _pump(tester, api: api);

      expect(find.textContaining('_'), findsNothing);
      expect(find.text('Trending'), findsNothing);
    });

    testWidgets('an empty feed shows the empty state, not an error', (
      tester,
    ) async {
      final api = _FakeSocialApi(pages: [_page([])]);
      await _pump(tester, api: api);

      expect(find.text('No health posts yet'), findsOneWidget);
      expect(find.text('Could not load posts right now'), findsNothing);
    });

    testWidgets('a failed load offers retry and never leaks server text', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        feedError: const ApiException(
          message: 'pg_connection refused at 10.0.0.4',
          code: 'SERVICE_UNAVAILABLE',
        ),
      );
      await _pump(tester, api: api);

      expect(find.text('Could not load posts right now'), findsOneWidget);
      expect(find.textContaining('pg_connection'), findsNothing);
      expect(find.byKey(const Key('socialFeedRetry')), findsOneWidget);

      api.feedError = null;
      api.pages = [
        _page(['a']),
      ];
      await tester.tap(find.byKey(const Key('socialFeedRetry')));
      await tester.pumpAndSettle();

      expect(find.byType(FeedPostCard), findsOneWidget);
    });
  });

  group('pagination', () {
    testWidgets('scrolling to the end appends the next page', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b'], cursor: 'p2', hasMore: true),
          _page(['c']),
        ],
      );
      await _pump(tester, api: api, size: const Size(390, 800));

      expect(find.byType(FeedPostCard), findsNWidgets(2));
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();

      expect(api.cursors, [null, 'p2']);
      expect(find.text('Body c'), findsOneWidget);
    });

    testWidgets('a pagination failure keeps the list and offers retry', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b'], cursor: 'p2', hasMore: true),
        ],
      );
      await _pump(tester, api: api, size: const Size(390, 800));

      api.feedError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();

      expect(find.byType(FeedPostCard), findsNWidgets(2));
      expect(find.text('Could not load more posts.'), findsOneWidget);
      expect(find.byKey(const Key('socialFeedLoadMoreRetry')), findsOneWidget);
    });
  });

  group('like', () {
    testWidgets('tapping like updates the card immediately', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        holdLike: true,
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Like · 3'));
      await tester.pump();

      expect(find.text('Liked · 4'), findsOneWidget);

      api.likeResult = const LikeResult(liked: true, likeCount: 9);
      api.releaseLike();
      await tester.pumpAndSettle();

      expect(find.text('Liked · 9'), findsOneWidget);
    });

    testWidgets('a failed like rolls the card back and tells the user', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      api.likeError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      await _pump(tester, api: api);

      await tester.tap(find.text('Like · 3'));
      await tester.pumpAndSettle();

      expect(find.text('Like · 3'), findsOneWidget);
      expect(find.text('Could not update like'), findsOneWidget);
    });

    testWidgets('the like control announces its toggled state', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api);

      expect(
        find.bySemanticsLabel('Like, 3 likes'),
        findsOneWidget,
        reason: 'state must be readable without relying on color',
      );
    });
  });

  group('follow', () {
    testWidgets('following updates every card from that doctor', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b']),
        ],
      );
      api.followResult = const FollowResult(following: true, followerCount: 5);
      await _pump(tester, api: api, size: const Size(390, 1400));

      expect(find.text('Follow'), findsNWidgets(2));
      await tester.tap(find.text('Follow').first);
      await tester.pumpAndSettle();

      expect(find.text('Following'), findsNWidgets(2));
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('a doctor never sees Follow on their own post', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a'], isOwnDoctor: true),
        ],
      );
      await _pump(tester, api: api, role: 'doctor');

      expect(find.text('Follow'), findsNothing);
      expect(find.text('Following'), findsNothing);
    });

    testWidgets('a failed follow reports without moving the card', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      api.followError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      await _pump(tester, api: api);

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();

      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('Could not update follow status'), findsOneWidget);
    });
  });

  group('comments', () {
    testWidgets('opening comments loads the approved thread', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: [
          const PostComment(
            id: 'c1',
            body: 'Very helpful',
            firstNameEn: 'Omar',
            lastNameEn: 'Nasser',
          ),
        ],
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Omar Nasser'), findsOneWidget);
      expect(find.text('Very helpful'), findsOneWidget);
    });

    testWidgets('the comment field enforces the 1000 character ceiling', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: const [],
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('socialCommentInput')),
      );
      expect(field.maxLength, 1000);
      expect(field.maxLength, SocialApi.maxCommentLength);
      expect(find.text('0 of 1000 characters'), findsOneWidget);
    });

    testWidgets('sending a comment appends it and bumps the card count', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: const [],
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('socialCommentInput')),
        'Thanks doctor',
      );
      await tester.tap(find.byKey(const Key('socialCommentSend')));
      await tester.pumpAndSettle();

      expect(find.text('Thanks doctor'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Comment · 3'), findsOneWidget);
    });

    testWidgets('an empty comment is refused with a visible reason', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: const [],
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('socialCommentSend')));
      await tester.pumpAndSettle();

      expect(find.text('Write a comment before sending'), findsOneWidget);
      expect(api.addCommentCalls, 0);
    });

    testWidgets('no delete is offered for a comment we did not author', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: [const PostComment(id: 'c1', body: 'Someone else')],
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();

      // The endpoint returns no ownership signal, so guessing is refused.
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('a comment this session posted can be deleted', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: const [],
      );
      await _pump(tester, api: api);

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('socialCommentInput')),
        'Mine',
      );
      await tester.tap(find.byKey(const Key('socialCommentSend')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Mine'), findsNothing);
      expect(api.deleteCommentCalls, 1);
    });

    testWidgets('the comments sheet exposes no moderation controls', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
        comments: [const PostComment(id: 'c1', body: 'Body')],
      );
      await _pump(tester, api: api, role: 'admin');

      await tester.tap(find.text('Comment · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Hide'), findsNothing);
    });
  });

  group('composer role rules', () {
    testWidgets('a doctor sees the quick composer', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'doctor');
      expect(find.byType(FeedComposer), findsOneWidget);
    });

    testWidgets('a patient sees no composer', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'patient');
      expect(find.byType(FeedComposer), findsNothing);
    });

    testWidgets('an admin sees no composer', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'admin');
      expect(find.byType(FeedComposer), findsNothing);
    });

    testWidgets('a super_admin sees no composer', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'super_admin');
      expect(find.byType(FeedComposer), findsNothing);
    });

    for (final role in ['patient', 'doctor', 'admin', 'super_admin']) {
      testWidgets('$role can read the feed', (tester) async {
        final api = _FakeSocialApi(
          pages: [
            _page(['a']),
          ],
        );
        await _pump(tester, api: api, role: role);
        expect(
          find.byType(FeedPostCard),
          findsOneWidget,
          reason: '$role must be able to read the feed',
        );
      });
    }

    testWidgets('an unauthenticated session sees no posts', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: '');

      expect(find.text('The health feed is unavailable'), findsOneWidget);
      expect(find.byType(FeedPostCard), findsNothing);
    });
  });

  group('composer behavior', () {
    testWidgets('publishing an empty body is refused inline', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      final workspace = _FakeWorkspaceApi();
      await _pump(tester, api: api, workspace: workspace, role: 'doctor');

      await tester.tap(find.byKey(const Key('socialComposerBody')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('socialComposerPublish')));
      await tester.pumpAndSettle();

      expect(
        find.text('Please write some content for the post'),
        findsOneWidget,
      );
      expect(workspace.saved, isEmpty);
    });

    testWidgets('publishing reuses the doctor-posts contract and reloads', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      final workspace = _FakeWorkspaceApi();
      await _pump(
        tester,
        api: api,
        workspace: workspace,
        role: 'doctor',
        size: const Size(390, 1000),
      );

      await tester.enterText(
        find.byKey(const Key('socialComposerBody')),
        'Drink more water',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('socialComposerPublish')));
      await tester.pumpAndSettle();

      expect(workspace.saved.single['body'], 'Drink more water');
      expect(workspace.saved.single['title'], 'Drink more water');
      expect(workspace.saved.single['publish'], true);
      expect(find.text('Post published successfully'), findsOneWidget);
      expect(api.feedCalls, 2, reason: 'the feed reloads after publishing');
    });

    testWidgets('without a route target the My posts action is absent', (
      tester,
    ) async {
      // The screen owns no routing: with no callback supplied it renders
      // nothing rather than pushing a route of its own.
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'doctor');
      expect(find.byKey(const Key('socialMyPostsAction')), findsNothing);
    });

    testWidgets('a doctor with a route target can open My posts', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      var opened = 0;
      await _pump(
        tester,
        api: api,
        role: 'doctor',
        onOpenMyPosts: () => opened++,
      );

      await tester.tap(find.byKey(const Key('socialMyPostsAction')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('a patient never gets the My posts action', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'patient', onOpenMyPosts: () {});
      expect(find.byKey(const Key('socialMyPostsAction')), findsNothing);
    });
  });

  group('localization and layout', () {
    testWidgets('Arabic renders RTL with Arabic copy and titles', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, arabic: true);

      expect(
        Directionality.of(tester.element(find.byType(SocialFeedScreen))),
        TextDirection.rtl,
      );
      expect(find.text('المنشورات الصحية'), findsWidgets);
      expect(find.text('عنوان عربي'), findsOneWidget);
      expect(find.text('نصيحة صحية'), findsOneWidget);
      expect(find.text('متابعة'), findsOneWidget);
    });

    testWidgets('English renders LTR with English copy', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api);

      expect(
        Directionality.of(tester.element(find.byType(SocialFeedScreen))),
        TextDirection.ltr,
      );
      expect(find.text('English title'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('a long mixed Arabic/English post fits a 320pt screen', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(
            ['a'],
            body:
                'ينصح الأطباء بشرب الماء بانتظام. Drink at least 2L of water '
                'daily — الترطيب يساعد على تحسين التركيز والوظائف الحيوية '
                'throughout the whole day, especially in summer.',
            titleAr: 'نصائح الترطيب اليومي مع Hydration tips',
          ),
        ],
      );
      await _pump(tester, api: api, arabic: true, size: const Size(320, 800));

      expect(tester.takeException(), isNull);
    });

    testWidgets('a 320pt screen at 2x text scale does not overflow', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(
        tester,
        api: api,
        role: 'doctor',
        size: const Size(320, 900),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FeedPostCard), findsOneWidget);
    });

    testWidgets('a 360pt screen at 2x text scale in Arabic does not overflow', (
      tester,
    ) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(
        tester,
        api: api,
        arabic: true,
        role: 'doctor',
        size: const Size(360, 900),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a 430pt screen renders without overflow', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a', 'b']),
        ],
      );
      await _pump(tester, api: api, size: const Size(430, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape renders without overflow', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api, role: 'doctor', size: const Size(800, 360));
      expect(tester.takeException(), isNull);
    });
  });

  group('view tracking', () {
    testWidgets('a visible post reports exactly one view', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      await _pump(tester, api: api);
      await tester.pumpAndSettle();

      expect(api.viewCalls, 1);
      expect(api.viewedIds, ['a']);
    });

    testWidgets('a view failure never disturbs the feed', (tester) async {
      final api = _FakeSocialApi(
        pages: [
          _page(['a']),
        ],
      );
      api.viewError = const ApiException(message: 'x', code: 'RATE_LIMITED');
      await _pump(tester, api: api);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FeedPostCard), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeSocialApi api,
  _FakeWorkspaceApi? workspace,
  String role = 'patient',
  bool arabic = false,
  Size size = const Size(390, 900),
  double textScale = 1,
  VoidCallback? onOpenMyPosts,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer(
    overrides: [
      socialApiProvider.overrideWithValue(api),
      doctorWorkspaceApiProvider.overrideWithValue(
        workspace ?? _FakeWorkspaceApi(),
      ),
      socialStringsProvider.overrideWithValue(SocialStrings(arabic)),
      activeOriginProvider.overrideWithValue('https://example.test'),
      authControllerProvider.overrideWith((ref) => _FakeAuth(role)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: SocialFeedScreen(onOpenMyPosts: onOpenMyPosts),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

FeedPage _page(
  List<String> ids, {
  String? cursor,
  bool hasMore = false,
  bool isOwnDoctor = false,
  FeedReason reason = FeedReason.followedDoctor,
  String? body,
  String titleAr = 'عنوان عربي',
}) => FeedPage(
  items: [
    for (final id in ids)
      FeedPost(
        id: id,
        body: body ?? 'Body $id',
        category: PostCategory.healthTip,
        titleAr: titleAr,
        titleEn: 'English title',
        publishedAt: '2026-08-01T09:00:00.000Z',
        likeCount: 3,
        commentCount: 2,
        reason: reason,
        isOwnDoctor: isOwnDoctor,
        doctor: const FeedDoctor(
          id: 'doc-1',
          firstNameAr: 'سارة',
          lastNameAr: 'خالد',
          firstNameEn: 'Sara',
          lastNameEn: 'Khaled',
          specialtyAr: 'قلب',
          specialtyEn: 'Cardiology',
        ),
      ),
  ],
  nextCursor: cursor,
  hasMore: hasMore,
);

class _FakeSocialApi implements SocialApi {
  _FakeSocialApi({
    this.pages = const [],
    this.comments = const [],
    this.feedError,
    this.holdFeed = false,
    this.holdLike = false,
  });

  List<FeedPage> pages;
  List<PostComment> comments;
  Object? feedError;
  Object? likeError;
  Object? followError;
  Object? viewError;

  LikeResult likeResult = const LikeResult(liked: true, likeCount: 4);
  FollowResult followResult = const FollowResult(
    following: true,
    followerCount: 1,
  );

  bool holdFeed;
  bool holdLike;
  Completer<void>? _feedGate;
  Completer<void>? _likeGate;

  int feedCalls = 0;
  int addCommentCalls = 0;
  int deleteCommentCalls = 0;
  int viewCalls = 0;
  final cursors = <String?>[];
  final viewedIds = <String>[];

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

  @override
  Future<FeedPage> getFeed({
    int limit = SocialApi.pageSize,
    String? cursor,
  }) async {
    feedCalls++;
    final token = cursor?.trim() ?? '';
    cursors.add(token.isEmpty ? null : token);
    if (holdFeed) {
      final gate = _feedGate ?? Completer<void>();
      _feedGate = gate;
      await gate.future;
    }
    if (feedError != null) throw feedError!;
    if (pages.isEmpty) {
      return const FeedPage(items: [], nextCursor: null, hasMore: false);
    }
    return pages.length == 1 ? pages.first : pages.removeAt(0);
  }

  @override
  Future<List<PostComment>> getComments(String postId) async =>
      List.of(comments);

  @override
  Future<LikeResult> like(String postId) async {
    if (holdLike) {
      final gate = _likeGate ?? Completer<void>();
      _likeGate = gate;
      await gate.future;
    }
    if (likeError != null) throw likeError!;
    return likeResult;
  }

  @override
  Future<LikeResult> unlike(String postId) async {
    if (likeError != null) throw likeError!;
    return const LikeResult(liked: false, likeCount: 2);
  }

  @override
  Future<PostComment> addComment(String postId, String body) async {
    addCommentCalls++;
    return PostComment(id: 'created-1', body: body.trim());
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteCommentCalls++;
  }

  @override
  Future<bool> recordView(String postId) async {
    viewCalls++;
    viewedIds.add(postId);
    if (viewError != null) throw viewError!;
    return true;
  }

  @override
  Future<FollowResult> follow(String doctorId) async {
    if (followError != null) throw followError!;
    return followResult;
  }

  @override
  Future<FollowResult> unfollow(String doctorId) async {
    if (followError != null) throw followError!;
    return const FollowResult(following: false, followerCount: 0);
  }
}

class _FakeWorkspaceApi extends DoctorWorkspaceApi {
  _FakeWorkspaceApi() : super(Dio());

  final saved = <Map<String, Object?>>[];

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
  _FakeAuth(String role)
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService()),
        GoogleAuthService(),
        SecureStorageService(),
      ) {
    state = role.isEmpty
        ? const AuthState(status: AuthStatus.unauthenticated)
        : AuthState(
            status: AuthStatus.authenticated,
            user: UserModel(
              id: 'user-1',
              email: 'user@example.test',
              role: role,
            ),
          );
  }
}
