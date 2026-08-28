import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../data/doctor_schedule_api.dart';
import '../models/doctor_schedule_models.dart';

final doctorScheduleApiProvider = Provider<DoctorScheduleApi>((ref) => DoctorScheduleApi(ref.watch(dioProvider)));

final doctorScheduleProvider = FutureProvider.autoDispose<DoctorSchedule>(
  (ref) => ref.watch(doctorScheduleApiProvider).load(),
);
