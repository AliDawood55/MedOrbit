import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../models/social_models.dart';

/// Feature-local Arabic/English strings for the social feed.
///
/// Deliberately kept out of `core/localization/app_strings.dart`: the feed
/// is a self-contained module, and a separate table keeps its copy from
/// colliding with concurrent edits to the shared table. It follows the same
/// `_t(ar, en)` idiom as [AppStrings] and reads the same
/// [localeControllerProvider], so the two always agree on language.
///
/// Copy is ported from the web `feed.*` and `doctorPosts.category*` keys in
/// `frontend/src/js/i18n.js`.
class SocialStrings {
  const SocialStrings(this.isArabic);

  final bool isArabic;

  String _t(String ar, String en) => isArabic ? ar : en;

  // Screen chrome
  String get feedTitle => _t('المنشورات الصحية', 'Health Feed');
  String get loading => _t('جارٍ التحميل...', 'Loading...');
  String get retry => _t('إعادة المحاولة', 'Retry');
  String get cancel => _t('إلغاء', 'Cancel');
  String get close => _t('إغلاق', 'Close');
  String get delete => _t('حذف', 'Delete');
  String get myPosts => _t('منشوراتي', 'My posts');
  String get refresh => _t('تحديث', 'Refresh');

  // Feed states
  String get emptyTitle =>
      _t('لا توجد منشورات صحية حالياً', 'No health posts yet');
  String get emptyHint => _t(
    'ستظهر هنا منشورات الأطباء الذين تتابعهم.',
    'Posts from doctors you follow will appear here.',
  );
  String get errorTitle =>
      _t('تعذر تحميل المنشورات حالياً', 'Could not load posts right now');
  String get errorHint => _t(
    'تحقق من الاتصال وحاول مرة أخرى.',
    'Check your connection and try again.',
  );
  String get loadMore => _t('تحميل المزيد', 'Load more');
  String get loadingMore => _t('جارٍ تحميل المزيد...', 'Loading more posts...');
  String get loadMoreError =>
      _t('تعذر تحميل المزيد من المنشورات.', 'Could not load more posts.');
  String get feedLoading => _t('جارٍ تحميل المنشورات', 'Loading posts');
  String get unavailableTitle =>
      _t('المنشورات الصحية غير متاحة', 'The health feed is unavailable');
  String get unavailableHint => _t(
    'سجّل الدخول بحساب فعّال لعرض المنشورات الصحية.',
    'Sign in with an active account to view the health feed.',
  );

  // Post actions
  String get like => _t('إعجاب', 'Like');
  String get liked => _t('أعجبني', 'Liked');
  String get comment => _t('تعليق', 'Comment');
  String get follow => _t('متابعة', 'Follow');
  String get following => _t('تتابعه', 'Following');
  String get likeError => _t('تعذر تحديث الإعجاب', 'Could not update like');
  String get followError =>
      _t('تعذر تحديث حالة المتابعة', 'Could not update follow status');

  String likeSemantics({required bool isLiked, required int count}) => isLiked
      ? _t('أعجبني، $count إعجاب', 'Liked, $count likes')
      : _t('إعجاب، $count إعجاب', 'Like, $count likes');

  String commentSemantics(int count) =>
      _t('التعليقات، $count تعليق', 'Comments, $count comments');

  String followSemantics({required bool isFollowing, required String doctor}) =>
      isFollowing
      ? _t('تتابع $doctor', 'Following $doctor')
      : _t('متابعة $doctor', 'Follow $doctor');

  String postAuthorSemantics({
    required String doctor,
    required String specialty,
  }) => specialty.isEmpty
      ? _t('منشور من $doctor', 'Post by $doctor')
      : _t('منشور من $doctor، $specialty', 'Post by $doctor, $specialty');

  // Comments
  String get commentsTitle => _t('التعليقات', 'Comments');
  String get commentPlaceholder => _t('أضف تعليقاً', 'Add a comment');
  String get commentSend => _t('إرسال', 'Send');
  String get commentsEmpty => _t('لا توجد تعليقات بعد', 'No comments yet');
  String get commentsEmptyHint => _t(
    'كن أول من يعلّق على هذا المنشور.',
    'Be the first to comment on this post.',
  );
  String get commentsError =>
      _t('تعذر تحميل التعليقات', 'Could not load comments');
  String get commentSendError =>
      _t('تعذر إرسال التعليق', 'Could not send the comment');
  String get commentEmptyValidation =>
      _t('اكتب تعليقاً قبل الإرسال', 'Write a comment before sending');
  String get commentUnknownAuthor => _t('مستخدم', 'A user');

  String commentLengthCounter(int used, int max) =>
      _t('$used من $max حرفاً', '$used of $max characters');

  String commentLengthSemantics(int max) =>
      _t('الحد الأقصى $max حرف', 'Maximum $max characters');

  // Composer (doctor only)
  String get composerLabel => _t('إنشاء منشور', 'Create post');
  String get composerPlaceholder =>
      _t('شارك معلومة أو تحديثاً صحياً...', 'Share a health tip or update...');
  String get composerCategory => _t('التصنيف', 'Category');
  String get publish => _t('نشر', 'Publish');
  String get publishing => _t('جارٍ النشر...', 'Publishing...');
  String get publishSuccess =>
      _t('تم نشر المنشور بنجاح', 'Post published successfully');
  String get publishError => _t(
    'تعذر نشر المنشور، حاول مرة أخرى',
    'Could not publish the post, please try again',
  );
  String get composerBodyRequired => _t(
    'الرجاء كتابة محتوى المنشور',
    'Please write some content for the post',
  );

  /// Recommendation reason banner, mirroring `reasonLabel()` in
  /// `frontend/src/js/feed.js`. An unrecognized code renders nothing rather
  /// than exposing the internal identifier.
  String reasonLabel(FeedReason reason) => switch (reason) {
    FeedReason.followedDoctor => _t(
      'لأنك تتابع هذا الطبيب',
      'Because you follow this doctor',
    ),
    FeedReason.interestSpecialty => _t(
      'بناءً على اهتمامك بهذا التخصص',
      'Based on your specialty interest',
    ),
    FeedReason.interestCategory => _t(
      'بناءً على اهتماماتك',
      'Based on your interests',
    ),
    FeedReason.trending => _t('رائج', 'Trending'),
    FeedReason.recent => _t('حديث', 'Recent'),
    FeedReason.unknown => '',
  };

  /// Category label, ported from the shared `doctorPosts.category*` keys the
  /// web feed reuses. An unrecognized category renders nothing.
  String categoryLabel(PostCategory category) => switch (category) {
    PostCategory.healthTip => _t('نصيحة صحية', 'Health Tip'),
    PostCategory.announcement => _t('إعلان', 'Announcement'),
    PostCategory.clinicNews => _t('أخبار العيادة', 'Clinic News'),
    PostCategory.article => _t('مقال', 'Article'),
    PostCategory.unknown => '',
  };

  /// Maps the structured `error.code` values the social routes and the Dio
  /// layer can produce onto user-facing copy. Raw server messages are never
  /// rendered — a backend string can carry internal detail.
  String socialError(String? code) => switch (code) {
    'UNAUTHORIZED' => _t(
      'انتهت جلستك. سجّل الدخول من جديد ثم حاول مرة أخرى.',
      'Your session has expired. Sign in again and retry.',
    ),
    'FORBIDDEN' => _t(
      'لا يملك هذا الحساب صلاحية تنفيذ هذا الإجراء.',
      'This account cannot perform this action.',
    ),
    'NOT_FOUND' => _t(
      'لم يعد هذا المحتوى متاحاً.',
      'This content is no longer available.',
    ),
    'VALIDATION_ERROR' => _t(
      'تحقق مما أدخلته ثم حاول مرة أخرى.',
      'Check what you entered and try again.',
    ),
    'INVALID_CURSOR' => _t(
      'انتهت صلاحية هذه الصفحة. حدّث المنشورات لعرض أحدث المحتوى.',
      'This page expired. Refresh the feed to see the latest posts.',
    ),
    'SELF_FOLLOW_NOT_ALLOWED' => _t(
      'لا يمكنك متابعة حسابك الخاص.',
      'You cannot follow your own account.',
    ),
    'RATE_LIMITED' => _t(
      'تم إجراء محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
      'Too many attempts. Wait a little while and try again.',
    ),
    'DUPLICATE_IN_FLIGHT' => _t(
      'هذا الإجراء قيد التنفيذ بالفعل.',
      'This action is already in progress.',
    ),
    'CONNECT_TIMEOUT' || 'SEND_TIMEOUT' || 'RECEIVE_TIMEOUT' => _t(
      'استغرقت الاستجابة وقتاً أطول من المتوقع. حاول مرة أخرى.',
      'The response took longer than expected. Please try again.',
    ),
    'SERVICE_UNAVAILABLE' => _t(
      'تعذر الوصول إلى الخدمة. تحقق من اتصالك ثم حاول مرة أخرى.',
      'Could not reach the service. Check your connection and try again.',
    ),
    'INVALID_RESPONSE' => _t(
      'وصل رد غير مكتمل من الخدمة. حاول مرة أخرى.',
      'The service returned an incomplete response. Please retry.',
    ),
    _ => _t(
      'تعذر إكمال الإجراء. حاول مرة أخرى.',
      'The action could not be completed. Please try again.',
    ),
  };
}

final socialStringsProvider = Provider<SocialStrings>((ref) {
  final locale = ref.watch(localeControllerProvider);
  return SocialStrings(locale.languageCode == 'ar');
});
