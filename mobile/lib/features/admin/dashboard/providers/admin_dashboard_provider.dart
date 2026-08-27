import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../data/admin_dashboard_api.dart';
import '../models/admin_dashboard_stats.dart';

final adminDashboardApiProvider = Provider<AdminDashboardApi>(
  (ref) => AdminDashboardApi(ref.watch(dioProvider)),
);

final adminDashboardStatsProvider =
    FutureProvider.autoDispose<AdminDashboardStats>((ref) {
      return ref.watch(adminDashboardApiProvider).getStats();
    });
