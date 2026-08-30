import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/social/data/social_api.dart';

void main() {
  group('feed', () {
    test('requests the mounted feed path with a clamped page size', () async {
      final fake = _RecordingDio([_ok(_feedPage())]);
      final page = await SocialApi(fake.dio).getFeed();

      expect(fake.requests.single.method, 'GET');
      expect(fake.requests.single.path, '/feed/posts');
      expect(fake.requests.single.queryParameters['limit'], SocialApi.pageSize);
      expect(SocialApi.pageSize, inInclusiveRange(1, 30));
      expect(page.items.single.id, 'post-1');
    });

    test('omits the cursor entirely on the first page', () async {
      final fake = _RecordingDio([_ok(_feedPage())]);
      await SocialApi(fake.dio).getFeed();
      expect(fake.requests.single.queryParameters, isNot(contains('cursor')));
    });

    test('sends the server cursor back verbatim', () async {
      final fake = _RecordingDio([_ok(_feedPage())]);
      await SocialApi(fake.dio).getFeed(cursor: 'eyJ2IjoxfQ.sig');
      expect(fake.requests.single.queryParameters['cursor'], 'eyJ2IjoxfQ.sig');
    });

    test('treats a blank cursor as no cursor', () async {
      final fake = _RecordingDio([_ok(_feedPage())]);
      await SocialApi(fake.dio).getFeed(cursor: '   ');
      expect(fake.requests.single.queryParameters, isNot(contains('cursor')));
    });

    test('reads next_cursor and has_more from the envelope', () async {
      final fake = _RecordingDio([
        _ok(_feedPage(nextCursor: 'page-2', hasMore: true)),
      ]);
      final page = await SocialApi(fake.dio).getFeed();
      expect(page.nextCursor, 'page-2');
      expect(page.hasMore, isTrue);
    });

    test('a non-list items field is an INVALID_RESPONSE', () async {
      final fake = _RecordingDio([
        _ok({'items': 'nope', 'has_more': false}),
      ]);
      await expectLater(
        SocialApi(fake.dio).getFeed(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.codeInvalidResponse,
          ),
        ),
      );
    });

    test('a post missing its required id is an INVALID_RESPONSE', () async {
      final fake = _RecordingDio([
        _ok({
          'items': [
            {'body': 'text', 'category': 'article', 'doctor': _doctor()},
          ],
          'has_more': false,
        }),
      ]);
      await expectLater(
        SocialApi(fake.dio).getFeed(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.codeInvalidResponse,
          ),
        ),
      );
    });

    test('a payload that is not an envelope is an INVALID_RESPONSE', () async {
      final fake = _RecordingDio([_raw('plain text')]);
      await expectLater(
        SocialApi(fake.dio).getFeed(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('comments', () {
    test('reads the approved comment list for a post', () async {
      final fake = _RecordingDio([
        _ok([_comment(), _comment(id: 'comment-2')]),
      ]);
      final comments = await SocialApi(fake.dio).getComments('post-1');

      expect(fake.requests.single.method, 'GET');
      expect(fake.requests.single.path, '/feed/posts/post-1/comments');
      expect(comments, hasLength(2));
      expect(comments.first.body, 'Helpful, thank you');
    });

    test('posts a trimmed body to the post comments path', () async {
      final fake = _RecordingDio([_ok(_comment())]);
      await SocialApi(fake.dio).addComment('post-1', '  Thanks  ');

      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/feed/posts/post-1/comments');
      expect(fake.requests.single.data, {'body': 'Thanks'});
    });

    test('deletes by comment id, not by post id', () async {
      final fake = _RecordingDio([
        _ok({'id': 'comment-1'}),
      ]);
      await SocialApi(fake.dio).deleteComment('comment-1');

      expect(fake.requests.single.method, 'DELETE');
      expect(fake.requests.single.path, '/feed/comments/comment-1');
    });

    test('a non-list comments payload is an INVALID_RESPONSE', () async {
      final fake = _RecordingDio([
        _ok({'rows': []}),
      ]);
      await expectLater(
        SocialApi(fake.dio).getComments('post-1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.codeInvalidResponse,
          ),
        ),
      );
    });

    test('the client ceiling matches the server ceiling', () {
      expect(SocialApi.maxCommentLength, 1000);
    });
  });

  group('like', () {
    test('like posts an empty body and returns the server count', () async {
      final fake = _RecordingDio([
        _ok({'liked': true, 'like_count': 4, 'created': true}),
      ]);
      final result = await SocialApi(fake.dio).like('post-1');

      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/feed/posts/post-1/like');
      expect(fake.requests.single.data, isEmpty);
      expect(result.liked, isTrue);
      expect(result.likeCount, 4);
    });

    test('unlike uses DELETE on the same path', () async {
      final fake = _RecordingDio([
        _ok({'liked': false, 'like_count': 3, 'removed': true}),
      ]);
      final result = await SocialApi(fake.dio).unlike('post-1');

      expect(fake.requests.single.method, 'DELETE');
      expect(fake.requests.single.path, '/feed/posts/post-1/like');
      expect(result.liked, isFalse);
      expect(result.likeCount, 3);
    });
  });

  group('follow', () {
    test('follow targets the doctors router, not the feed router', () async {
      final fake = _RecordingDio([
        _ok({'following': true, 'follower_count': 12, 'created': true}),
      ]);
      final result = await SocialApi(fake.dio).follow('doctor-1');

      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/doctors/doctor-1/follow');
      expect(result.following, isTrue);
      expect(result.followerCount, 12);
    });

    test('unfollow uses DELETE on the same path', () async {
      final fake = _RecordingDio([
        _ok({'following': false, 'follower_count': 11, 'removed': true}),
      ]);
      final result = await SocialApi(fake.dio).unfollow('doctor-1');

      expect(fake.requests.single.method, 'DELETE');
      expect(fake.requests.single.path, '/doctors/doctor-1/follow');
      expect(result.following, isFalse);
    });

    test('a self-follow rejection surfaces its structured code', () async {
      final fake = _RecordingDio([
        _failure(400, 'SELF_FOLLOW_NOT_ALLOWED', 'You cannot follow yourself'),
      ]);
      await expectLater(
        SocialApi(fake.dio).follow('doctor-1'),
        throwsA(
          isA<DioException>().having(
            (e) => ApiException.from(e).code,
            'normalized code',
            'SELF_FOLLOW_NOT_ALLOWED',
          ),
        ),
      );
    });

    test('an expired cursor surfaces INVALID_CURSOR', () async {
      final fake = _RecordingDio([
        _failure(400, 'INVALID_CURSOR', 'Invalid cursor'),
      ]);
      await expectLater(
        SocialApi(fake.dio).getFeed(cursor: 'stale'),
        throwsA(
          isA<DioException>().having(
            (e) => ApiException.from(e).code,
            'normalized code',
            'INVALID_CURSOR',
          ),
        ),
      );
    });
  });

  group('view', () {
    test('records a view and reports the server dedupe flag', () async {
      final fake = _RecordingDio([
        _ok({'recorded': true}),
      ]);
      final recorded = await SocialApi(fake.dio).recordView('post-1');

      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/feed/posts/post-1/view');
      expect(recorded, isTrue);
    });

    test('a deduplicated view reports false rather than throwing', () async {
      final fake = _RecordingDio([
        _ok({'recorded': false}),
      ]);
      expect(await SocialApi(fake.dio).recordView('post-1'), isFalse);
    });

    test('a malformed view payload reports false, never throws', () async {
      final fake = _RecordingDio([_raw('unexpected')]);
      expect(await SocialApi(fake.dio).recordView('post-1'), isFalse);
    });
  });
}

Map<String, dynamic> _doctor() => {
  'id': 'doctor-1',
  'first_name_ar': 'سارة',
  'last_name_ar': 'خالد',
  'first_name_en': 'Sara',
  'last_name_en': 'Khaled',
  'profile_image_url': 'uploads/avatar.png',
  'specialty_ar': 'قلب',
  'specialty_en': 'Cardiology',
};

Map<String, dynamic> _feedPage({String? nextCursor, bool hasMore = false}) => {
  'items': [
    {
      'id': 'post-1',
      'title': 'عنوان',
      'title_ar': 'عنوان',
      'title_en': 'Title',
      'body': 'Body text',
      'category': 'health_tip',
      'published_at': '2026-08-01T09:00:00.000Z',
      'like_count': 3,
      'comment_count': 1,
      'reason_code': 'TRENDING',
      'liked_by_me': false,
      'following_doctor': false,
      'is_own_doctor': false,
      'doctor': _doctor(),
    },
  ],
  'next_cursor': nextCursor,
  'has_more': hasMore,
};

Map<String, dynamic> _comment({String id = 'comment-1'}) => {
  'id': id,
  'body': 'Helpful, thank you',
  'created_at': '2026-08-02T10:00:00.000Z',
  'first_name_en': 'Omar',
  'last_name_en': 'Nasser',
};

class _Reply {
  const _Reply.ok(this.data) : status = 200, error = null;
  const _Reply.failure(this.status, this.error) : data = null;

  final Object? data;
  final int status;
  final Map<String, dynamic>? error;
}

_Reply _ok(Object? data) => _Reply.ok({'success': true, 'data': data});
_Reply _raw(Object? data) => _Reply.ok(data);
_Reply _failure(int status, String code, String message) =>
    _Reply.failure(status, {
      'success': false,
      'error': {'code': code, 'message': message},
    });

class _RecordingDio {
  _RecordingDio(List<_Reply> replies)
    : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    final queue = [...replies];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final reply = queue.removeAt(0);
          if (reply.error != null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: options,
                  statusCode: reply.status,
                  data: reply.error,
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: reply.status,
              data: reply.data,
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final requests = <RequestOptions>[];
}
