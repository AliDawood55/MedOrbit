import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/moderation/data/admin_moderation_api.dart';
import 'package:mobile/features/admin/moderation/models/admin_moderation_models.dart';
import 'package:mobile/features/admin/moderation/providers/admin_moderation_provider.dart';
import 'package:mobile/features/admin/moderation/screens/admin_moderation_screen.dart';

import '../admin_test_support.dart';

AdminModeratedPost _post(String id, {String status = 'pending'}) =>
    AdminModeratedPost.fromJson({
      'id': id,
      'title_en': 'Heart tips $id',
      'title_ar': 'نصائح القلب',
      'body': 'Walk thirty minutes a day.',
      'status': 'published',
      'moderation_status': status,
      'created_at': '2026-02-01T09:00:00Z',
      'first_name_en': 'Lina',
      'last_name_en': 'Haddad',
    });

AdminModeratedComment _comment(String id, {String status = 'approved'}) =>
    AdminModeratedComment.fromJson({
      'id': id,
      'post_id': 'post-1',
      'body': 'Thank you $id.',
      'moderation_status': status,
      'created_at': '2026-02-02T09:00:00Z',
      'first_name_en': 'Omar',
      'last_name_en': 'Ali',
    });

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 1800),
}) => pumpAdminScreen(
  tester,
  screen: const AdminModerationScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminModerationApiProvider.overrideWithValue(api)],
);

void main() {
  testWidgets('a patient is refused and no queue is fetched', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(api.postCalls, 0);
    expect(api.commentCalls, 0);
  });

  testWidgets('renders the posts queue with its moderation actions', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi()..posts = [_post('p1')]);

    expect(find.text('Heart tips p1'), findsOneWidget);
    expect(find.text('Lina Haddad'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-moderation-post-approve-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-moderation-post-hide-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-moderation-post-reject-p1')),
      findsOneWidget,
    );
  });

  testWidgets('an empty posts queue shows the empty state', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(
      find.byKey(const ValueKey('admin-moderation-posts-empty')),
      findsOneWidget,
    );
  });

  testWidgets('a posts failure shows safe copy and retry reloads', (
    tester,
  ) async {
    final api = _FakeApi()
      ..postsError = const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      );
    await _pump(tester, api: api);

    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    api.postsError = null;
    api.posts = [_post('p1')];
    await tapByKey(tester, const ValueKey('admin-moderation-posts-retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Heart tips p1'), findsOneWidget);
  });

  testWidgets('moderation is confirmed before the request is sent', (
    tester,
  ) async {
    final api = _FakeApi()..posts = [_post('p1')];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-moderation-post-hide-p1'));
    await tester.pumpAndSettle();
    expect(find.text(en.adminModerationHideTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, en.cancel));
    await tester.pumpAndSettle();
    expect(api.moderatePostCalls, 0);

    await tapByKey(tester, const ValueKey('admin-moderation-post-hide-p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-moderation-confirm')));
    await tester.pumpAndSettle();

    expect(api.moderatePostCalls, 1);
    expect(api.lastAction, AdminModerationAction.hide);
    expect(find.text(en.adminModerationSuccess), findsOneWidget);
  });

  testWidgets('every action button on a row is disabled while one is running', (
    tester,
  ) async {
    final api = _FakeApi()
      ..posts = [_post('p1')]
      ..actionGate = Completer<void>();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-moderation-post-approve-p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-moderation-confirm')));
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('admin-moderation-post-hide-p1')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('admin-moderation-post-reject-p1')),
          )
          .onPressed,
      isNull,
    );
    expect(api.moderatePostCalls, 1);
  });

  testWidgets('a failed action shows mapped copy, never the raw message', (
    tester,
  ) async {
    final api = _FakeApi()
      ..posts = [_post('p1')]
      ..actionError = const ApiException(
        message: 'Post not found for doctor lina@example.test',
        code: 'NOT_FOUND',
      );
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-moderation-post-reject-p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-moderation-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(en.adminError('NOT_FOUND')), findsOneWidget);
    expect(find.textContaining('lina@example.test'), findsNothing);
  });

  testWidgets('the comments tab has its own queue and filters', (tester) async {
    final api = _FakeApi()
      ..posts = [_post('p1')]
      ..comments = [_comment('c1')];
    await _pump(tester, api: api);

    await tester.tap(find.text(en.adminModerationCommentsTab));
    await tester.pumpAndSettle();

    expect(find.text('Thank you c1.'), findsOneWidget);
    // The web comment filter offers no "pending" option, and neither does this.
    expect(
      find.byKey(const ValueKey('admin-moderation-comments-approved')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-moderation-posts-pending')),
      findsNothing,
    );
  });

  testWidgets('a comment can be moderated from its own tab', (tester) async {
    final api = _FakeApi()
      ..posts = [_post('p1')]
      ..comments = [_comment('c1')];
    await _pump(tester, api: api);

    await tester.tap(find.text(en.adminModerationCommentsTab));
    await tester.pumpAndSettle();

    await tapByKey(tester, const ValueKey('admin-moderation-comment-hide-c1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-moderation-confirm')));
    await tester.pumpAndSettle();

    expect(api.moderateCommentCalls, 1);
    expect(api.lastAction, AdminModerationAction.hide);
  });

  testWidgets('the server-side 100-row cap is disclosed', (tester) async {
    await _pump(tester, api: _FakeApi()..posts = [_post('p1')]);
    expect(find.text(en.adminModerationLimitNote), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..posts = [_post('p1')],
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 2400),
    );

    expect(find.text('نصائح القلب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminModerationApi {
  _FakeApi() : super(Dio());

  List<AdminModeratedPost> posts = const [];
  List<AdminModeratedComment> comments = const [];
  Object? postsError;
  Object? actionError;
  Completer<void>? actionGate;

  int postCalls = 0;
  int commentCalls = 0;
  int moderatePostCalls = 0;
  int moderateCommentCalls = 0;
  AdminModerationAction? lastAction;

  @override
  Future<List<AdminModeratedPost>> listPosts({
    AdminModerationStatus? status,
  }) {
    postCalls++;
    if (postsError != null) return Future.error(postsError!);
    return Future.value(posts);
  }

  @override
  Future<List<AdminModeratedComment>> listComments({
    AdminModerationStatus? status,
  }) {
    commentCalls++;
    return Future.value(comments);
  }

  @override
  Future<void> moderatePost(String postId, AdminModerationAction action) {
    moderatePostCalls++;
    lastAction = action;
    return _act();
  }

  @override
  Future<void> moderateComment(
    String commentId,
    AdminModerationAction action,
  ) {
    moderateCommentCalls++;
    lastAction = action;
    return _act();
  }

  Future<void> _act() {
    if (actionGate != null) return actionGate!.future;
    if (actionError != null) return Future.error(actionError!);
    return Future.value();
  }
}
