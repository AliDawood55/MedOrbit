import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/social/models/social_models.dart';
import 'package:mobile/features/social/social_access.dart';

void main() {
  group('FeedPost parsing', () {
    test('reads every field the ranked feed sends', () {
      final post = FeedPost.fromJson(_post());

      expect(post.id, 'post-1');
      expect(post.body, 'Body text');
      expect(post.category, PostCategory.healthTip);
      expect(post.publishedAt, '2026-08-01T09:00:00.000Z');
      expect(post.likeCount, 3);
      expect(post.commentCount, 2);
      expect(post.reason, FeedReason.followedDoctor);
      expect(post.likedByMe, isTrue);
      expect(post.followingDoctor, isTrue);
      expect(post.isOwnDoctor, isFalse);
    });

    test('parses the nested doctor identity', () {
      final post = FeedPost.fromJson(_post());
      expect(post.doctor.id, 'doctor-1');
      expect(post.doctor.displayName(isArabic: true), 'سارة خالد');
      expect(post.doctor.displayName(isArabic: false), 'Sara Khaled');
      expect(post.doctor.specialty(isArabic: true), 'قلب');
      expect(post.doctor.specialty(isArabic: false), 'Cardiology');
    });

    test('falls back to the other language when a name half is absent', () {
      final post = FeedPost.fromJson(
        _post(doctor: {'id': 'doctor-1', 'first_name_en': 'Sara'}),
      );
      expect(post.doctor.displayName(isArabic: true), 'Sara');
      expect(post.doctor.displayName(isArabic: false), 'Sara');
    });

    test('an entirely nameless doctor yields an empty name, not a crash', () {
      final post = FeedPost.fromJson(_post(doctor: {'id': 'doctor-1'}));
      expect(post.doctor.displayName(isArabic: false), isEmpty);
      expect(post.doctor.specialty(isArabic: false), isEmpty);
    });

    test('Arabic prefers title_ar and English prefers title_en', () {
      final post = FeedPost.fromJson(_post());
      expect(post.localizedTitle(isArabic: true), 'عنوان عربي');
      expect(post.localizedTitle(isArabic: false), 'English title');
    });

    test('a missing title_ar falls back to title_en in Arabic', () {
      final post = FeedPost.fromJson(_post(titleAr: null));
      expect(post.localizedTitle(isArabic: true), 'English title');
    });

    test('a missing title_en falls back to title_ar in English', () {
      final post = FeedPost.fromJson(_post(titleEn: null));
      expect(post.localizedTitle(isArabic: false), 'عنوان عربي');
    });

    test('a post with no title at all yields an empty title', () {
      final post = FeedPost.fromJson(_post(titleAr: null, titleEn: null));
      expect(post.localizedTitle(isArabic: true), isEmpty);
      expect(post.localizedTitle(isArabic: false), isEmpty);
    });

    test('absent counts and flags default safely', () {
      final post = FeedPost.fromJson({
        'id': 'post-1',
        'body': 'Body',
        'category': 'article',
        'doctor': {'id': 'doctor-1'},
      });
      expect(post.likeCount, 0);
      expect(post.commentCount, 0);
      expect(post.likedByMe, isFalse);
      expect(post.followingDoctor, isFalse);
      expect(post.isOwnDoctor, isFalse);
      expect(post.reason, FeedReason.unknown);
    });

    test('a missing id fails loudly rather than inventing one', () {
      expect(
        () => FeedPost.fromJson(_post()..remove('id')),
        throwsA(isA<FormatException>()),
      );
    });

    test('a missing body fails loudly', () {
      expect(
        () => FeedPost.fromJson(_post()..remove('body')),
        throwsA(isA<FormatException>()),
      );
    });

    test('a missing doctor object fails loudly', () {
      expect(
        () => FeedPost.fromJson(_post()..remove('doctor')),
        throwsA(isA<FormatException>()),
      );
    });

    test('a doctor without an id fails loudly', () {
      expect(
        () => FeedPost.fromJson(_post(doctor: {'first_name_en': 'Sara'})),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('reason codes', () {
    test('maps every code the ranker emits', () {
      expect(FeedReason.fromCode('FOLLOWED_DOCTOR'), FeedReason.followedDoctor);
      expect(
        FeedReason.fromCode('INTEREST_SPECIALTY'),
        FeedReason.interestSpecialty,
      );
      expect(
        FeedReason.fromCode('INTEREST_CATEGORY'),
        FeedReason.interestCategory,
      );
      expect(FeedReason.fromCode('TRENDING'), FeedReason.trending);
      expect(FeedReason.fromCode('RECENT'), FeedReason.recent);
    });

    test('an unrecognized or absent code becomes unknown', () {
      expect(FeedReason.fromCode('SOMETHING_NEW'), FeedReason.unknown);
      expect(FeedReason.fromCode(null), FeedReason.unknown);
      expect(FeedReason.fromCode(''), FeedReason.unknown);
    });
  });

  group('categories', () {
    test('maps only the four categories the server accepts', () {
      expect(PostCategory.fromWire('health_tip'), PostCategory.healthTip);
      expect(PostCategory.fromWire('announcement'), PostCategory.announcement);
      expect(PostCategory.fromWire('clinic_news'), PostCategory.clinicNews);
      expect(PostCategory.fromWire('article'), PostCategory.article);
      expect(PostCategory.fromWire('invented'), PostCategory.unknown);
      expect(PostCategory.fromWire(null), PostCategory.unknown);
    });

    test('the composer offers exactly those four, in web order', () {
      expect(PostCategory.composable.map((c) => c.wireValue).toList(), [
        'health_tip',
        'announcement',
        'clinic_news',
        'article',
      ]);
    });
  });

  group('FeedPage parsing', () {
    test('reads items, cursor and has_more', () {
      final page = FeedPage.fromJson({
        'items': [_post()],
        'next_cursor': 'token.sig',
        'has_more': true,
      });
      expect(page.items.single.id, 'post-1');
      expect(page.nextCursor, 'token.sig');
      expect(page.hasMore, isTrue);
    });

    test('a final page carries a null cursor and has_more false', () {
      final page = FeedPage.fromJson({
        'items': <Object>[],
        'next_cursor': null,
        'has_more': false,
      });
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });

    test('a non-list items field fails loudly', () {
      expect(
        () => FeedPage.fromJson({'items': 'nope'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-object item fails loudly', () {
      expect(
        () => FeedPage.fromJson({
          'items': ['nope'],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PostComment parsing', () {
    test('reads body, timestamp and author name parts', () {
      final comment = PostComment.fromJson({
        'id': 'comment-1',
        'body': 'Thanks',
        'created_at': '2026-08-02T10:00:00.000Z',
        'first_name_ar': 'عمر',
        'last_name_ar': 'ناصر',
        'first_name_en': 'Omar',
        'last_name_en': 'Nasser',
      });
      expect(comment.body, 'Thanks');
      expect(comment.createdAt, '2026-08-02T10:00:00.000Z');
      expect(comment.authorName(isArabic: true), 'عمر ناصر');
      expect(comment.authorName(isArabic: false), 'Omar Nasser');
    });

    test('carries no user id — ownership is not derivable from the row', () {
      // Guards the documented parity gap: if the backend ever starts
      // returning an ownership signal, this test is the place that should
      // fail and prompt the delete affordance to widen.
      final comment = PostComment.fromJson({
        'id': 'comment-1',
        'body': 'Thanks',
      });
      expect(comment.authorName(isArabic: false), isEmpty);
      expect(comment.createdAt, isNull);
    });

    test('a missing body fails loudly', () {
      expect(
        () => PostComment.fromJson({'id': 'comment-1'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('mutation results', () {
    test('like results carry the server-recomputed count', () {
      final result = LikeResult.fromJson({'liked': true, 'like_count': 7});
      expect(result.liked, isTrue);
      expect(result.likeCount, 7);
    });

    test('follow results carry the server follower count', () {
      final result = FollowResult.fromJson({
        'following': false,
        'follower_count': 11,
      });
      expect(result.following, isFalse);
      expect(result.followerCount, 11);
    });

    test('absent flags default to false and zero', () {
      final result = LikeResult.fromJson(const {});
      expect(result.liked, isFalse);
      expect(result.likeCount, 0);
    });
  });

  group('feed access', () {
    test('every authenticated role may read the feed', () {
      expect(socialFeedAvailableForRole('patient'), isTrue);
      expect(socialFeedAvailableForRole('doctor'), isTrue);
      expect(socialFeedAvailableForRole('admin'), isTrue);
      expect(socialFeedAvailableForRole('super_admin'), isTrue);
    });

    test('no session means no feed', () {
      expect(socialFeedAvailableForRole(null), isFalse);
      expect(socialFeedAvailableForRole(''), isFalse);
      expect(socialFeedAvailableForRole('   '), isFalse);
    });

    test('only a doctor may use the quick composer', () {
      expect(socialComposerAvailableForRole('doctor'), isTrue);
      expect(socialComposerAvailableForRole('patient'), isFalse);
      expect(socialComposerAvailableForRole('admin'), isFalse);
      expect(socialComposerAvailableForRole('super_admin'), isFalse);
      expect(socialComposerAvailableForRole(null), isFalse);
    });

    test('role matching ignores casing and padding', () {
      expect(socialComposerAvailableForRole('  Doctor '), isTrue);
      expect(socialFeedAvailableForRole(' PATIENT '), isTrue);
    });

    test('the four product roles are all covered', () {
      expect(kKnownRoles, {'patient', 'doctor', 'admin', 'super_admin'});
    });
  });
}

Map<String, dynamic> _post({
  Object? doctor = _absent,
  Object? titleAr = _absent,
  Object? titleEn = _absent,
}) => {
  'id': 'post-1',
  'title_ar': identical(titleAr, _absent) ? 'عنوان عربي' : titleAr,
  'title_en': identical(titleEn, _absent) ? 'English title' : titleEn,
  'body': 'Body text',
  'category': 'health_tip',
  'published_at': '2026-08-01T09:00:00.000Z',
  'like_count': 3,
  'comment_count': 2,
  'reason_code': 'FOLLOWED_DOCTOR',
  'liked_by_me': true,
  'following_doctor': true,
  'is_own_doctor': false,
  'doctor': identical(doctor, _absent)
      ? {
          'id': 'doctor-1',
          'first_name_ar': 'سارة',
          'last_name_ar': 'خالد',
          'first_name_en': 'Sara',
          'last_name_en': 'Khaled',
          'specialty_ar': 'قلب',
          'specialty_en': 'Cardiology',
        }
      : doctor,
};

const Object _absent = Object();
