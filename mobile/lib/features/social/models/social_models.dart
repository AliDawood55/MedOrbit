import '../../../shared/utils/json_parsing.dart';
import '../../../shared/utils/localized_field.dart';

/// Models for the social feed contract served by
/// `backend/src/routes/social.routes.js` and shaped by
/// `recommendation.service.js`'s `getRankedFeed`. Field names mirror the
/// wire payload exactly — this app never renames or re-derives what the
/// server already computed (counts, reason codes, follow state).

int _integer(Object? value) => value is int
    ? value
    : value is num
    ? value.toInt()
    : 0;

bool _boolean(Object? value) => value is bool && value;

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Missing or invalid object "$field"');
}

/// Recommendation reasons emitted by `scorePost` in
/// `recommendation.service.js`. [unknown] covers any code a newer backend
/// starts sending — the UI renders nothing rather than leaking the raw
/// internal identifier.
enum FeedReason {
  followedDoctor('FOLLOWED_DOCTOR'),
  interestSpecialty('INTEREST_SPECIALTY'),
  interestCategory('INTEREST_CATEGORY'),
  trending('TRENDING'),
  recent('RECENT'),
  unknown('');

  const FeedReason(this.wireValue);

  final String wireValue;

  static FeedReason fromCode(String? code) {
    final normalized = code?.trim().toUpperCase() ?? '';
    for (final reason in FeedReason.values) {
      if (reason != FeedReason.unknown && reason.wireValue == normalized) {
        return reason;
      }
    }
    return FeedReason.unknown;
  }
}

/// The four categories `POST /doctors/me/posts` accepts
/// (`doctor.routes.js:288`). Nothing else is a valid post category, so
/// [unknown] exists only to render an unexpected server value safely.
enum PostCategory {
  healthTip('health_tip'),
  announcement('announcement'),
  clinicNews('clinic_news'),
  article('article'),
  unknown('');

  const PostCategory(this.wireValue);

  final String wireValue;

  /// The categories a doctor may choose in the quick composer, in the same
  /// order as the web composer's `<select>` (`frontend/public/feed.html`).
  static const List<PostCategory> composable = [
    PostCategory.healthTip,
    PostCategory.announcement,
    PostCategory.clinicNews,
    PostCategory.article,
  ];

  static PostCategory fromWire(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final category in PostCategory.values) {
      if (category != PostCategory.unknown &&
          category.wireValue == normalized) {
        return category;
      }
    }
    return PostCategory.unknown;
  }
}

/// The `doctor` object nested in every feed item. Profile names come from a
/// `LEFT JOIN` on `user_profiles`, so every name part is genuinely optional.
class FeedDoctor {
  const FeedDoctor({
    required this.id,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.profileImageUrl,
    this.specialtyAr,
    this.specialtyEn,
  });

  final String id;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? profileImageUrl;
  final String? specialtyAr;
  final String? specialtyEn;

  /// Same fallback chain as the web feed's `doctorName()` — preferred
  /// language first, then the other language, then empty.
  String displayName({required bool isArabic}) {
    final preferred = [
      if (isArabic) firstNameAr else firstNameEn,
      if (isArabic) lastNameAr else lastNameEn,
    ].whereType<String>().map((part) => part.trim()).where((p) => p.isNotEmpty);
    if (preferred.isNotEmpty) return preferred.join(' ');

    final fallback = [
      if (isArabic) firstNameEn else firstNameAr,
      if (isArabic) lastNameEn else lastNameAr,
    ].whereType<String>().map((part) => part.trim()).where((p) => p.isNotEmpty);
    return fallback.join(' ');
  }

  String specialty({required bool isArabic}) =>
      localizedField(isArabic: isArabic, ar: specialtyAr, en: specialtyEn);

  factory FeedDoctor.fromJson(Map<String, dynamic> json) => FeedDoctor(
    id: requireExactString(json, 'id'),
    firstNameAr: optionalExactString(json, 'first_name_ar'),
    lastNameAr: optionalExactString(json, 'last_name_ar'),
    firstNameEn: optionalExactString(json, 'first_name_en'),
    lastNameEn: optionalExactString(json, 'last_name_en'),
    profileImageUrl: optionalExactString(json, 'profile_image_url'),
    specialtyAr: optionalExactString(json, 'specialty_ar'),
    specialtyEn: optionalExactString(json, 'specialty_en'),
  );
}

/// One ranked feed item.
class FeedPost {
  const FeedPost({
    required this.id,
    required this.body,
    required this.category,
    required this.doctor,
    this.titleAr,
    this.titleEn,
    this.publishedAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.reason = FeedReason.unknown,
    this.likedByMe = false,
    this.followingDoctor = false,
    this.isOwnDoctor = false,
  });

  final String id;
  final String body;
  final PostCategory category;
  final FeedDoctor doctor;
  final String? titleAr;
  final String? titleEn;
  final String? publishedAt;
  final int likeCount;
  final int commentCount;
  final FeedReason reason;
  final bool likedByMe;
  final bool followingDoctor;
  final bool isOwnDoctor;

  /// Arabic prefers `title_ar` then falls back to `title_en`; English the
  /// other way round — the same rule the web feed's `card()` applies.
  String localizedTitle({required bool isArabic}) =>
      localizedField(isArabic: isArabic, ar: titleAr, en: titleEn);

  FeedPost copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
    bool? followingDoctor,
  }) => FeedPost(
    id: id,
    body: body,
    category: category,
    doctor: doctor,
    titleAr: titleAr,
    titleEn: titleEn,
    publishedAt: publishedAt,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    reason: reason,
    likedByMe: likedByMe ?? this.likedByMe,
    followingDoctor: followingDoctor ?? this.followingDoctor,
    isOwnDoctor: isOwnDoctor,
  );

  factory FeedPost.fromJson(Map<String, dynamic> json) => FeedPost(
    id: requireExactString(json, 'id'),
    body: requireExactString(json, 'body'),
    category: PostCategory.fromWire(optionalExactString(json, 'category')),
    doctor: FeedDoctor.fromJson(_map(json['doctor'], 'doctor')),
    titleAr: optionalExactString(json, 'title_ar'),
    titleEn: optionalExactString(json, 'title_en'),
    publishedAt: optionalExactString(json, 'published_at'),
    likeCount: _integer(json['like_count']),
    commentCount: _integer(json['comment_count']),
    reason: FeedReason.fromCode(optionalExactString(json, 'reason_code')),
    likedByMe: _boolean(json['liked_by_me']),
    followingDoctor: _boolean(json['following_doctor']),
    isOwnDoctor: _boolean(json['is_own_doctor']),
  );
}

/// One cursor page. [nextCursor] is an opaque signed token — it is passed
/// back verbatim and never parsed or reconstructed on the client.
class FeedPage {
  const FeedPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<FeedPost> items;
  final String? nextCursor;
  final bool hasMore;

  factory FeedPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Missing or invalid list "items"');
    }
    return FeedPage(
      items: rawItems
          .map((entry) => FeedPost.fromJson(_map(entry, 'items')))
          .toList(growable: false),
      nextCursor: optionalExactString(json, 'next_cursor'),
      hasMore: _boolean(json['has_more']),
    );
  }
}

/// An approved comment. The endpoint returns author name parts but no user
/// id, so ownership cannot be derived here — see `SocialFeedScreen`'s
/// delete-affordance note.
class PostComment {
  const PostComment({
    required this.id,
    required this.body,
    this.createdAt,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.profileImageUrl,
  });

  final String id;
  final String body;
  final String? createdAt;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? profileImageUrl;

  String authorName({required bool isArabic}) => FeedDoctor(
    id: id,
    firstNameAr: firstNameAr,
    lastNameAr: lastNameAr,
    firstNameEn: firstNameEn,
    lastNameEn: lastNameEn,
  ).displayName(isArabic: isArabic);

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
    id: requireExactString(json, 'id'),
    body: requireExactString(json, 'body'),
    createdAt: optionalExactString(json, 'created_at'),
    firstNameAr: optionalExactString(json, 'first_name_ar'),
    lastNameAr: optionalExactString(json, 'last_name_ar'),
    firstNameEn: optionalExactString(json, 'first_name_en'),
    lastNameEn: optionalExactString(json, 'last_name_en'),
    profileImageUrl: optionalExactString(json, 'profile_image_url'),
  );
}

/// Authoritative like state returned by the like/unlike endpoints. The
/// server recounts the row after every mutation, so this always wins over
/// the optimistic value the UI showed while the request was in flight.
class LikeResult {
  const LikeResult({required this.liked, required this.likeCount});

  final bool liked;
  final int likeCount;

  factory LikeResult.fromJson(Map<String, dynamic> json) => LikeResult(
    liked: _boolean(json['liked']),
    likeCount: _integer(json['like_count']),
  );
}

/// Authoritative follow state returned by the follow/unfollow endpoints.
class FollowResult {
  const FollowResult({required this.following, required this.followerCount});

  final bool following;
  final int followerCount;

  factory FollowResult.fromJson(Map<String, dynamic> json) => FollowResult(
    following: _boolean(json['following']),
    followerCount: _integer(json['follower_count']),
  );
}
