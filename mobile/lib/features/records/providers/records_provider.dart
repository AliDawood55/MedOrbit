import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/records_api.dart';
import '../models/record_entry_model.dart';

final recordsApiProvider = Provider<RecordsApi>((ref) => RecordsApi(ref.watch(dioProvider)));

final recordsTimelineProvider = FutureProvider.autoDispose<List<RecordEntryModel>>((ref) {
  return ref.watch(recordsApiProvider).getTimeline();
});
