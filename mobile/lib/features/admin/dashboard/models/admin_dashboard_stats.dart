import '../../common/models/admin_parsing.dart';

/// One entry of the `analytics` map returned by `GET /dashboard/stats`.
///
/// `backend/src/services/report.service.js` runs each analytics query inside
/// `runAnalyticsSection`, which answers `{ data }` on success and
/// `{ error: true }` when that one query failed — so a single broken section
/// must degrade on its own instead of blanking the whole dashboard. A section
/// whose payload cannot be parsed is treated the same way: unavailable, not
/// fatal.
class AdminAnalyticsSection<T> {
  const AdminAnalyticsSection.available(T this.value) : unavailable = false;
  const AdminAnalyticsSection.unavailable() : value = null, unavailable = true;

  final T? value;
  final bool unavailable;

  bool get isAvailable => !unavailable && value != null;
}

/// A `{ labels: [...], counts: [...] }` analytics payload.
///
/// The two arrays are positional pairs. A length mismatch is a malformed
/// section rather than something to silently pad, so [tryParse] rejects it.
class AdminAnalyticsSeries {
  const AdminAnalyticsSeries({required this.labels, required this.counts});

  final List<String> labels;
  final List<int> counts;

  int get total => counts.fold(0, (sum, count) => sum + count);

  /// True when there is at least one non-zero bucket. The web page draws the
  /// "awaiting data" overlay on exactly this condition (`hasCounts`).
  bool get hasData => counts.any((count) => count > 0);

  int get maxCount => counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);

  static AdminAnalyticsSeries? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final rawLabels = json['labels'];
    final rawCounts = json['counts'];
    if (rawLabels is! List || rawCounts is! List) return null;
    if (rawLabels.length != rawCounts.length) return null;

    final labels = <String>[];
    for (final label in rawLabels) {
      if (label is! String) return null;
      labels.add(label);
    }
    final counts = <int>[];
    for (final count in rawCounts) {
      final parsed = adminOptionalInt(count);
      if (parsed == null) return null;
      counts.add(parsed);
    }
    return AdminAnalyticsSeries(labels: labels, counts: counts);
  }
}

/// One `topSpecialties.items[]` row: a bilingual specialty name and its
/// appointment count.
class AdminRankedItem {
  const AdminRankedItem({
    required this.nameAr,
    required this.nameEn,
    required this.count,
  });

  final String? nameAr;
  final String? nameEn;
  final int count;
}

class AdminAnalytics {
  const AdminAnalytics({
    required this.usersByRole,
    required this.appointmentsOverTime,
    required this.topSpecialties,
    required this.conversationsPerWeek,
    required this.triageLevels,
    required this.clinicTypes,
  });

  final AdminAnalyticsSection<AdminAnalyticsSeries> usersByRole;
  final AdminAnalyticsSection<AdminAnalyticsSeries> appointmentsOverTime;
  final AdminAnalyticsSection<List<AdminRankedItem>> topSpecialties;
  final AdminAnalyticsSection<AdminAnalyticsSeries> conversationsPerWeek;
  final AdminAnalyticsSection<AdminAnalyticsSeries> triageLevels;
  final AdminAnalyticsSection<AdminAnalyticsSeries> clinicTypes;

  static const AdminAnalytics empty = AdminAnalytics(
    usersByRole: AdminAnalyticsSection.unavailable(),
    appointmentsOverTime: AdminAnalyticsSection.unavailable(),
    topSpecialties: AdminAnalyticsSection.unavailable(),
    conversationsPerWeek: AdminAnalyticsSection.unavailable(),
    triageLevels: AdminAnalyticsSection.unavailable(),
    clinicTypes: AdminAnalyticsSection.unavailable(),
  );

  /// Whether every section failed or is missing — used to show one honest
  /// "analytics unavailable" state instead of six identical empty cards.
  bool get isEntirelyUnavailable =>
      !usersByRole.isAvailable &&
      !appointmentsOverTime.isAvailable &&
      !topSpecialties.isAvailable &&
      !conversationsPerWeek.isAvailable &&
      !triageLevels.isAvailable &&
      !clinicTypes.isAvailable;

  factory AdminAnalytics.fromJson(Object? value) {
    if (value is! Map) return empty;
    final json = Map<String, dynamic>.from(value);
    return AdminAnalytics(
      usersByRole: _series(json['usersByRole']),
      appointmentsOverTime: _series(json['appointmentsOverTime']),
      topSpecialties: _ranked(json['topSpecialties']),
      conversationsPerWeek: _series(json['conversationsPerWeek']),
      triageLevels: _series(json['triageLevels']),
      clinicTypes: _series(json['clinicTypes']),
    );
  }
}

Object? _sectionData(Object? section) {
  if (section is! Map) return null;
  if (section['error'] == true) return null;
  return section['data'];
}

AdminAnalyticsSection<AdminAnalyticsSeries> _series(Object? section) {
  final parsed = AdminAnalyticsSeries.tryParse(_sectionData(section));
  return parsed == null
      ? const AdminAnalyticsSection.unavailable()
      : AdminAnalyticsSection.available(parsed);
}

AdminAnalyticsSection<List<AdminRankedItem>> _ranked(Object? section) {
  final data = _sectionData(section);
  if (data is! Map) return const AdminAnalyticsSection.unavailable();
  final items = Map<String, dynamic>.from(data)['items'];
  if (items is! List) return const AdminAnalyticsSection.unavailable();

  final parsed = <AdminRankedItem>[];
  for (final item in items) {
    if (item is! Map) return const AdminAnalyticsSection.unavailable();
    final row = Map<String, dynamic>.from(item);
    final count = adminOptionalInt(row['count']);
    if (count == null) return const AdminAnalyticsSection.unavailable();
    parsed.add(
      AdminRankedItem(
        nameAr: adminOptionalString(row, 'nameAr'),
        nameEn: adminOptionalString(row, 'nameEn'),
        count: count,
      ),
    );
  }
  return AdminAnalyticsSection.available(List.unmodifiable(parsed));
}

/// Aggregate, non-clinical platform counts returned to an authorized
/// administrator by `GET /dashboard/stats`
/// (`backend/src/routes/report.routes.js:46-83`, `authorizeAdmin`).
///
/// The headline totals come from uncast `COUNT(*)` and `ROUND(AVG(...), 2)`
/// columns, which `node-postgres` delivers as strings — [adminInt] and
/// [adminOptionalDouble] accept both forms.
class AdminDashboardStats {
  const AdminDashboardStats({
    required this.usersTotal,
    required this.patients,
    required this.doctors,
    required this.appointmentsTotal,
    required this.recordsTotal,
    required this.prescriptionsTotal,
    this.appointmentsCompleted = 0,
    this.appointmentsScheduled = 0,
    this.appointmentsCancelled = 0,
    this.averageRating,
    this.analytics = AdminAnalytics.empty,
  });

  final int usersTotal;
  final int patients;
  final int doctors;
  final int appointmentsTotal;
  final int recordsTotal;
  final int prescriptionsTotal;
  final int appointmentsCompleted;
  final int appointmentsScheduled;
  final int appointmentsCancelled;
  final double? averageRating;
  final AdminAnalytics analytics;

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    final users = adminOptionalMap(json['users']);
    final appointments = adminOptionalMap(json['appointments']);
    final records = adminOptionalMap(json['medical_records']);
    final prescriptions = adminOptionalMap(json['prescriptions']);
    final ratings = adminOptionalMap(json['ratings']);

    return AdminDashboardStats(
      usersTotal: adminInt(users['total']),
      patients: adminInt(users['patients']),
      doctors: adminInt(users['doctors']),
      appointmentsTotal: adminInt(appointments['total']),
      appointmentsCompleted: adminInt(appointments['completed']),
      appointmentsScheduled: adminInt(appointments['scheduled']),
      appointmentsCancelled: adminInt(appointments['cancelled']),
      recordsTotal: adminInt(records['total']),
      prescriptionsTotal: adminInt(prescriptions['total']),
      averageRating: adminOptionalDouble(ratings['average']),
      analytics: AdminAnalytics.fromJson(json['analytics']),
    );
  }
}
