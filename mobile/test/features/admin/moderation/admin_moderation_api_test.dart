import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/moderation/data/admin_moderation_api.dart';
import 'package:mobile/features/admin/moderation/models/admin_moderation_models.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _post({String status = 'pending'}) => {
  'id': 'post-1',
  'title_ar': 'نصائح القلب',
  'title_en': 'Heart tips',
  'body': 'Walk thirty minutes a day.',
  'category': 'wellness',
  'status': 'published',
  'moderation_status': status,
  'published_at': '2026-02-01T09:00:00Z',
  'created_at': '2026-02-01T09:00:00Z',
  'doctor_id': 'doc-1',
  'first_name_ar': 'لينا',
  'last_name_ar': 'حداد',
  'first_name_en': 'Lina',
  'last_name_en': 'Haddad',
};

Map<String, dynamic> _comment({String status = 'approved'}) => {
  'id': 'comment-1',
  'post_id': 'post-1',
  'body': 'Thank you.',
  'moderation_status': status,
  'created_at': '2026-02-02T09:00:00Z',
  'first_name_en': 'Omar',
  'last_name_en': 'Ali',
};

void main() {
  test('lists send only the moderation_status filter', () async {
    final dio = RecordingDio()
      ..enqueue({'success': true, 'data': <dynamic>[]})
      ..enqueue({'success': true, 'data': <dynamic>[]})
      ..enqueue({'success': true, 'data': <dynamic>[]});

    final api = AdminModerationApi(dio.dio);
    await api.listPosts();
    await api.listPosts(status: AdminModerationStatus.pending);
    await api.listComments(status: AdminModerationStatus.hidden);

    expect(dio.paths, [
      '/admin/social/posts',
      '/admin/social/posts',
      '/admin/social/comments',
    ]);
    expect(dio.queries.first, isEmpty);
    expect(dio.queries[1], {'moderation_status': 'pending'});
    expect(dio.queries[2], {'moderation_status': 'hidden'});
  });

  test('only the three server-accepted actions can be sent', () {
    expect(
      adminModerationActionWireValue(AdminModerationAction.approve),
      'approve',
    );
    expect(
      adminModerationActionWireValue(AdminModerationAction.reject),
      'reject',
    );
    expect(adminModerationActionWireValue(AdminModerationAction.hide), 'hide');
    expect(AdminModerationAction.values.length, 3);
  });

  test('each action maps to the status the server records', () {
    expect(
      adminModerationResultStatus(AdminModerationAction.approve),
      AdminModerationStatus.approved,
    );
    expect(
      adminModerationResultStatus(AdminModerationAction.reject),
      AdminModerationStatus.rejected,
    );
    expect(
      adminModerationResultStatus(AdminModerationAction.hide),
      AdminModerationStatus.hidden,
    );
  });

  test('moderation posts to the exact paths with the action payload', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          'id': 'post-1',
          'status': 'published',
          'moderation_status': 'hidden',
        },
      })
      ..enqueue({
        'success': true,
        'data': {'id': 'comment-1', 'moderation_status': 'rejected'},
      });

    final api = AdminModerationApi(dio.dio);
    await api.moderatePost('post-1', AdminModerationAction.hide);
    await api.moderateComment('comment-1', AdminModerationAction.reject);

    expect(dio.paths, [
      '/admin/social/posts/post-1/moderate',
      '/admin/social/comments/comment-1/moderate',
    ]);
    expect(dio.methods, ['POST', 'POST']);
    expect(dio.bodies, [
      {'action': 'hide'},
      {'action': 'reject'},
    ]);
  });

  test('parses a post with its bilingual title, author and publish state', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_post()],
      });

    final post = (await AdminModerationApi(dio.dio).listPosts()).single;

    expect(post.title(isArabic: true), 'نصائح القلب');
    expect(post.title(isArabic: false), 'Heart tips');
    expect(post.author(isArabic: true), 'لينا حداد');
    expect(post.author(isArabic: false), 'Lina Haddad');
    expect(post.moderationStatus, AdminModerationStatus.pending);
    expect(post.publishStatus, 'published');
  });

  test('parses a comment and keeps its post reference', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_comment()],
      });

    final comment = (await AdminModerationApi(dio.dio).listComments()).single;

    expect(comment.postId, 'post-1');
    expect(comment.body, 'Thank you.');
    expect(comment.moderationStatus, AdminModerationStatus.approved);
    expect(comment.author(isArabic: false), 'Omar Ali');
    // No Arabic profile name in this row: it falls back to the English one.
    expect(comment.author(isArabic: true), 'Omar Ali');
  });

  test('an unknown moderation status keeps its raw value', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_post(status: 'quarantined')],
      });

    final post = (await AdminModerationApi(dio.dio).listPosts()).single;
    expect(post.moderationStatus, AdminModerationStatus.unknown);
    expect(post.moderationStatusValue, 'quarantined');
  });

  test('a local status update keeps every other field intact', () {
    final post = AdminModeratedPost.fromJson(_post());
    final hidden = post.withModerationStatus(AdminModerationStatus.hidden);

    expect(hidden.moderationStatus, AdminModerationStatus.hidden);
    expect(hidden.moderationStatusValue, 'hidden');
    expect(hidden.title(isArabic: false), 'Heart tips');
    expect(hidden.publishStatus, 'published');
  });

  test('a malformed row fails the read', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [
          {'id': 'post-1', 'created_at': '2026-02-01T09:00:00Z'},
        ],
      });

    await expectLater(
      AdminModerationApi(dio.dio).listPosts(),
      throwsA(isA<FormatException>()),
    );
  });

  test('an invalid action is refused by the server with its own code', () async {
    final dio = RecordingDio()..enqueueFailure(400, 'VALIDATION_ERROR');

    try {
      await AdminModerationApi(
        dio.dio,
      ).moderatePost('post-1', AdminModerationAction.approve);
      fail('expected a failure');
    } catch (error) {
      expect(ApiException.from(error).code, 'VALIDATION_ERROR');
    }
  });
}
