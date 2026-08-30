import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../models/admin_moderation_models.dart';

/// Client for `/api/admin/social` (`authorizeAdmin`).
///
/// Exactly the four operations the backend exposes: list posts, moderate a
/// post, list comments, moderate a comment. Deletion, editing, and author
/// suspension are not admin capabilities in this product and are not invented
/// here — the only mutation is the `moderation_status` transition.
class AdminModerationApi {
  AdminModerationApi(this._dio);

  final Dio _dio;

  Future<List<AdminModeratedPost>> listPosts({
    AdminModerationStatus? status,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/social/posts',
      queryParameters: _statusQuery(status),
    );
    return adminEnvelopeList(
      response.data,
    ).map(AdminModeratedPost.fromJson).toList(growable: false);
  }

  Future<List<AdminModeratedComment>> listComments({
    AdminModerationStatus? status,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/social/comments',
      queryParameters: _statusQuery(status),
    );
    return adminEnvelopeList(
      response.data,
    ).map(AdminModeratedComment.fromJson).toList(growable: false);
  }

  Future<void> moderatePost(String postId, AdminModerationAction action) async {
    await _dio.post<Map<String, dynamic>>(
      '/admin/social/posts/${Uri.encodeComponent(postId)}/moderate',
      data: {'action': adminModerationActionWireValue(action)},
    );
  }

  Future<void> moderateComment(
    String commentId,
    AdminModerationAction action,
  ) async {
    await _dio.post<Map<String, dynamic>>(
      '/admin/social/comments/${Uri.encodeComponent(commentId)}/moderate',
      data: {'action': adminModerationActionWireValue(action)},
    );
  }

  Map<String, dynamic>? _statusQuery(AdminModerationStatus? status) {
    final value = adminModerationStatusWireValue(status);
    return value == null ? null : {'moderation_status': value};
  }
}
