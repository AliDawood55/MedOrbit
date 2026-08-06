import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/my_reports_api.dart';
import '../models/my_report_item.dart';

final myReportsApiProvider = Provider<MyReportsApi>(
  (ref) => MyReportsApi(ref.watch(dioProvider)),
);

/// Mirrors `AppointmentsController`'s shape — a bare
/// `StateNotifier<AsyncValue<List<T>>>`, no wrapper state class, since My
/// Reports has no per-item pending/optimistic-update state to track.
class MyReportsController extends StateNotifier<AsyncValue<List<MyReportItem>>> {
  MyReportsController(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  final MyReportsApi _api;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _api.listReportSummaries());
  }
}

final myReportsControllerProvider =
    StateNotifierProvider.autoDispose<MyReportsController, AsyncValue<List<MyReportItem>>>(
      (ref) => MyReportsController(ref.watch(myReportsApiProvider)),
    );
