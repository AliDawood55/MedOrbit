import '../../../../shared/utils/localized_field.dart';
import '../../common/models/admin_parsing.dart';

/// `moderation_status` on `doctor_posts` and `post_comments`.
enum AdminModerationStatus { pending, approved, rejected, hidden, unknown }

AdminModerationStatus adminModerationStatusFromWire(String value) =>
    switch (value) {
      'pending' => AdminModerationStatus.pending,
      'approved' => AdminModerationStatus.approved,
      'rejected' => AdminModerationStatus.rejected,
      'hidden' => AdminModerationStatus.hidden,
      _ => AdminModerationStatus.unknown,
    };

String? adminModerationStatusWireValue(AdminModerationStatus? status) =>
    switch (status) {
      AdminModerationStatus.pending => 'pending',
      AdminModerationStatus.approved => 'approved',
      AdminModerationStatus.rejected => 'rejected',
      AdminModerationStatus.hidden => 'hidden',
      _ => null,
    };

/// The three actions `POST .../moderate` accepts. Anything else is rejected
/// server-side with `VALIDATION_ERROR`, so no other value is ever sent.
enum AdminModerationAction { approve, reject, hide }

String adminModerationActionWireValue(AdminModerationAction action) =>
    switch (action) {
      AdminModerationAction.approve => 'approve',
      AdminModerationAction.reject => 'reject',
      AdminModerationAction.hide => 'hide',
    };

/// Resulting `moderation_status` for an action — used to update the cached row
/// without a refetch, mirroring the server's own mapping.
AdminModerationStatus adminModerationResultStatus(
  AdminModerationAction action,
) => switch (action) {
  AdminModerationAction.approve => AdminModerationStatus.approved,
  AdminModerationAction.reject => AdminModerationStatus.rejected,
  AdminModerationAction.hide => AdminModerationStatus.hidden,
};

/// Author name shared by both queues: the projection joins `user_profiles`
/// for the bilingual name pair only.
String _authorName({
  required bool isArabic,
  required Map<String, dynamic> json,
}) {
  final first = localizedField(
    isArabic: isArabic,
    ar: adminOptionalString(json, 'first_name_ar'),
    en: adminOptionalString(json, 'first_name_en'),
  );
  final last = localizedField(
    isArabic: isArabic,
    ar: adminOptionalString(json, 'last_name_ar'),
    en: adminOptionalString(json, 'last_name_en'),
  );
  return adminJoinName(first, last);
}

/// One row of `GET /api/admin/social/posts`.
class AdminModeratedPost {
  const AdminModeratedPost({
    required this.id,
    required this.body,
    required this.moderationStatus,
    required this.moderationStatusValue,
    required this.createdAt,
    this.titleAr,
    this.titleEn,
    this.category,
    this.publishStatus,
    this.authorNameAr = '',
    this.authorNameEn = '',
  });

  final String id;
  final String body;
  final AdminModerationStatus moderationStatus;
  final String moderationStatusValue;
  final DateTime createdAt;
  final String? titleAr;
  final String? titleEn;
  final String? category;

  /// `doctor_posts.status` — the author's own draft/published state, distinct
  /// from the moderation decision.
  final String? publishStatus;
  final String authorNameAr;
  final String authorNameEn;

  String title({required bool isArabic}) =>
      localizedField(isArabic: isArabic, ar: titleAr, en: titleEn);

  String author({required bool isArabic}) =>
      isArabic ? (authorNameAr.isEmpty ? authorNameEn : authorNameAr)
               : (authorNameEn.isEmpty ? authorNameAr : authorNameEn);

  factory AdminModeratedPost.fromJson(Map<String, dynamic> json) {
    final statusValue = adminRequireString(json, 'moderation_status');
    return AdminModeratedPost(
      id: adminRequireString(json, 'id'),
      body: adminOptionalString(json, 'body') ?? '',
      moderationStatus: adminModerationStatusFromWire(statusValue),
      moderationStatusValue: statusValue,
      createdAt: adminRequireDate(json, 'created_at'),
      titleAr: adminOptionalString(json, 'title_ar'),
      titleEn: adminOptionalString(json, 'title_en'),
      category: adminOptionalString(json, 'category'),
      publishStatus: adminOptionalString(json, 'status'),
      authorNameAr: _authorName(isArabic: true, json: json),
      authorNameEn: _authorName(isArabic: false, json: json),
    );
  }

  AdminModeratedPost withModerationStatus(AdminModerationStatus status) =>
      AdminModeratedPost(
        id: id,
        body: body,
        moderationStatus: status,
        moderationStatusValue: adminModerationStatusWireValue(status) ??
            moderationStatusValue,
        createdAt: createdAt,
        titleAr: titleAr,
        titleEn: titleEn,
        category: category,
        publishStatus: publishStatus,
        authorNameAr: authorNameAr,
        authorNameEn: authorNameEn,
      );
}

/// One row of `GET /api/admin/social/comments`.
class AdminModeratedComment {
  const AdminModeratedComment({
    required this.id,
    required this.postId,
    required this.body,
    required this.moderationStatus,
    required this.moderationStatusValue,
    required this.createdAt,
    this.authorNameAr = '',
    this.authorNameEn = '',
  });

  final String id;
  final String postId;
  final String body;
  final AdminModerationStatus moderationStatus;
  final String moderationStatusValue;
  final DateTime createdAt;
  final String authorNameAr;
  final String authorNameEn;

  String author({required bool isArabic}) =>
      isArabic ? (authorNameAr.isEmpty ? authorNameEn : authorNameAr)
               : (authorNameEn.isEmpty ? authorNameAr : authorNameEn);

  factory AdminModeratedComment.fromJson(Map<String, dynamic> json) {
    final statusValue = adminRequireString(json, 'moderation_status');
    return AdminModeratedComment(
      id: adminRequireString(json, 'id'),
      postId: adminRequireString(json, 'post_id'),
      body: adminOptionalString(json, 'body') ?? '',
      moderationStatus: adminModerationStatusFromWire(statusValue),
      moderationStatusValue: statusValue,
      createdAt: adminRequireDate(json, 'created_at'),
      authorNameAr: _authorName(isArabic: true, json: json),
      authorNameEn: _authorName(isArabic: false, json: json),
    );
  }

  AdminModeratedComment withModerationStatus(AdminModerationStatus status) =>
      AdminModeratedComment(
        id: id,
        postId: postId,
        body: body,
        moderationStatus: status,
        moderationStatusValue: adminModerationStatusWireValue(status) ??
            moderationStatusValue,
        createdAt: createdAt,
        authorNameAr: authorNameAr,
        authorNameEn: authorNameEn,
      );
}
