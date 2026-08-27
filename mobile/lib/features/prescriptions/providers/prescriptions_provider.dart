import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/prescriptions_api.dart';
import '../models/prescription_model.dart';

final prescriptionsApiProvider = Provider<PrescriptionsApi>(
  (ref) => PrescriptionsApi(ref.watch(dioProvider)),
);

final prescriptionsListProvider =
    FutureProvider.autoDispose<List<PrescriptionModel>>((ref) {
      return ref.watch(prescriptionsApiProvider).list();
    });
