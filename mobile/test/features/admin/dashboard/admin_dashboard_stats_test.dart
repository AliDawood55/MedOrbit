import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/dashboard/models/admin_dashboard_stats.dart';

Map<String, dynamic> _section(Object? data) => {'data': data};

void main() {
  group('AdminAnalyticsSeries', () {
    test('parses positional label/count pairs', () {
      final series = AdminAnalyticsSeries.tryParse({
        'labels': ['patient', 'doctor'],
        'counts': [28, 5],
      })!;

      expect(series.labels, ['patient', 'doctor']);
      expect(series.counts, [28, 5]);
      expect(series.total, 33);
      expect(series.maxCount, 28);
      expect(series.hasData, isTrue);
    });

    test('an all-zero series has no data, matching the web overlay rule', () {
      final series = AdminAnalyticsSeries.tryParse({
        'labels': ['a', 'b'],
        'counts': [0, 0],
      })!;
      expect(series.hasData, isFalse);
      expect(series.total, 0);
    });

    test('rejects mismatched lengths rather than padding', () {
      expect(
        AdminAnalyticsSeries.tryParse({
          'labels': ['a', 'b'],
          'counts': [1],
        }),
        isNull,
      );
    });

    test('rejects non-string labels and unparseable counts', () {
      expect(
        AdminAnalyticsSeries.tryParse({
          'labels': [1],
          'counts': [1],
        }),
        isNull,
      );
      expect(
        AdminAnalyticsSeries.tryParse({
          'labels': ['a'],
          'counts': ['many'],
        }),
        isNull,
      );
      expect(AdminAnalyticsSeries.tryParse('nope'), isNull);
    });
  });

  group('AdminAnalytics', () {
    test('a section marked {error:true} is unavailable, and the rest survive', () {
      final analytics = AdminAnalytics.fromJson({
        'usersByRole': {'error': true},
        'appointmentsOverTime': _section({
          'labels': ['2026-01-05'],
          'counts': [4],
        }),
      });

      expect(analytics.usersByRole.isAvailable, isFalse);
      expect(analytics.usersByRole.unavailable, isTrue);
      expect(analytics.appointmentsOverTime.isAvailable, isTrue);
      expect(analytics.appointmentsOverTime.value!.counts, [4]);
      expect(analytics.isEntirelyUnavailable, isFalse);
    });

    test('a malformed section degrades to unavailable, never fatal', () {
      final analytics = AdminAnalytics.fromJson({
        'triageLevels': _section({'labels': 'oops'}),
        'clinicTypes': _section({
          'labels': ['clinic'],
          'counts': [2],
        }),
      });

      expect(analytics.triageLevels.isAvailable, isFalse);
      expect(analytics.clinicTypes.isAvailable, isTrue);
    });

    test('topSpecialties parses ranked bilingual items', () {
      final analytics = AdminAnalytics.fromJson({
        'topSpecialties': _section({
          'items': [
            {'nameAr': 'طب القلب', 'nameEn': 'Cardiology', 'count': 9},
            {'nameAr': null, 'nameEn': 'Dermatology', 'count': 3},
          ],
        }),
      });

      final items = analytics.topSpecialties.value!;
      expect(items.length, 2);
      expect(items.first.nameAr, 'طب القلب');
      expect(items.first.count, 9);
      expect(items[1].nameAr, isNull);
    });

    test('one malformed specialty row invalidates that section only', () {
      final analytics = AdminAnalytics.fromJson({
        'topSpecialties': _section({
          'items': [
            {'nameEn': 'Cardiology', 'count': 'nine'},
          ],
        }),
        'usersByRole': _section({
          'labels': ['patient'],
          'counts': [1],
        }),
      });

      expect(analytics.topSpecialties.isAvailable, isFalse);
      expect(analytics.usersByRole.isAvailable, isTrue);
    });

    test('a completely absent analytics block is entirely unavailable', () {
      expect(AdminAnalytics.fromJson(null).isEntirelyUnavailable, isTrue);
      expect(AdminAnalytics.empty.isEntirelyUnavailable, isTrue);
    });
  });

  group('AdminDashboardStats', () {
    test('missing aggregate groups read as zero rather than failing', () {
      final stats = AdminDashboardStats.fromJson(const {});

      expect(stats.usersTotal, 0);
      expect(stats.appointmentsTotal, 0);
      expect(stats.averageRating, isNull);
      expect(stats.analytics.isEntirelyUnavailable, isTrue);
    });

    test('carries the analytics block through', () {
      final stats = AdminDashboardStats.fromJson({
        'users': {'total': 3},
        'analytics': {
          'conversationsPerWeek': _section({
            'labels': ['2026-01-05', '2026-01-12'],
            'counts': [1, 7],
          }),
        },
      });

      expect(stats.usersTotal, 3);
      expect(stats.analytics.conversationsPerWeek.value!.total, 8);
    });
  });
}
