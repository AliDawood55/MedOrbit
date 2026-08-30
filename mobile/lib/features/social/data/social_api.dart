import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/social_models.dart';

const _invalidResponse = ApiException(
  message: 'Unexpected response from server. Please try again.',
  code: ApiException.codeInvalidResponse,
);

/// Thin transport for the social endpoints mounted in `backend/src/app.js`
/// as `/api/feed` (`feedRoutes`) and `/api/doctors` (`socialDoctorRoutes`).
/// Every method returns a parsed model or throws an [ApiException] — no raw
/// maps and no Dio types escape this class.
class SocialApi {
  SocialApi(this._dio);

  final Dio _dio;

  /// `getRankedFeed` clamps `limit` to 1..30 server-side; the client sends a
  /// page size inside that range so the two never disagree.
  static const int pageSize = 10;

  /// `POST /feed/posts/:id/comments` rejects anything longer
  /// (`social.routes.js:69`). Enforced client-side purely so the user gets
  /// immediate feedback — the server stays authoritative.
  static const int maxCommentLength = 1000;

  Object? _payload(Response<dynamic> response) =>
      response.data is Map ? (response.data as Map)['data'] : null;

  Map<String, dynamic> _dataMap(Response<dynamic> response) {
    final value = _payload(response);
    if (value is! Map<String, dynamic>) throw _invalidResponse;
    return value;
  }

  List<Map<String, dynamic>> _dataList(Response<dynamic> response) {
    final value = _payload(response);
    if (value is! List) throw _invalidResponse;
    return value
        .map((entry) {
          if (entry is! Map<String, dynamic>) throw _invalidResponse;
          return entry;
        })
        .toList(growable: false);
  }

  T _parse<T>(T Function() parser) {
    try {
      return parser();
    } on FormatException {
      throw _invalidResponse;
    } on TypeError {
      throw _invalidResponse;
    }
  }

  Future<FeedPage> getFeed({int limit = pageSize, String? cursor}) async {
    final token = cursor?.trim() ?? '';
    final response = await _dio.get<dynamic>(
      '/feed/posts',
      queryParameters: {'limit': limit, if (token.isNotEmpty) 'cursor': token},
    );
    return _parse(() => FeedPage.fromJson(_dataMap(response)));
  }

  Future<List<PostComment>> getComments(String postId) async {
    final response = await _dio.get<dynamic>('/feed/posts/$postId/comments');
    return _parse(
      () =>
          _dataList(response).map(PostComment.fromJson).toList(growable: false),
    );
  }

  Future<LikeResult> like(String postId) async {
    final response = await _dio.post<dynamic>(
      '/feed/posts/$postId/like',
      data: const <String, dynamic>{},
    );
    return _parse(() => LikeResult.fromJson(_dataMap(response)));
  }

  Future<LikeResult> unlike(String postId) async {
    final response = await _dio.delete<dynamic>('/feed/posts/$postId/like');
    return _parse(() => LikeResult.fromJson(_dataMap(response)));
  }

  Future<PostComment> addComment(String postId, String body) async {
    final response = await _dio.post<dynamic>(
      '/feed/posts/$postId/comments',
      data: {'body': body.trim()},
    );
    return _parse(() => PostComment.fromJson(_dataMap(response)));
  }

  Future<void> deleteComment(String commentId) async {
    await _dio.delete<dynamic>('/feed/comments/$commentId');
  }

  /// Returns the server's `recorded` flag: `false` means the view was
  /// deduplicated for today by `userEvent.service.js`, not that it failed.
  Future<bool> recordView(String postId) async {
    final response = await _dio.post<dynamic>(
      '/feed/posts/$postId/view',
      data: const <String, dynamic>{},
    );
    final data = _payload(response);
    return data is Map<String, dynamic> && data['recorded'] == true;
  }

  Future<FollowResult> follow(String doctorId) async {
    final response = await _dio.post<dynamic>(
      '/doctors/$doctorId/follow',
      data: const <String, dynamic>{},
    );
    return _parse(() => FollowResult.fromJson(_dataMap(response)));
  }

  Future<FollowResult> unfollow(String doctorId) async {
    final response = await _dio.delete<dynamic>('/doctors/$doctorId/follow');
    return _parse(() => FollowResult.fromJson(_dataMap(response)));
  }
}
