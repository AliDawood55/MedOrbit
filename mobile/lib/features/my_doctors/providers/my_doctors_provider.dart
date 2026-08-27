import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/my_doctors_api.dart';
import '../models/patient_doctor_models.dart';

final myDoctorsApiProvider = Provider<MyDoctorsApi>(
  (ref) => MyDoctorsApi(ref.watch(dioProvider)),
);
final myDoctorsProvider = FutureProvider.autoDispose<List<PatientDoctor>>(
  (ref) => ref.watch(myDoctorsApiProvider).listDoctors(),
);
final sharedDoctorNotesProvider = FutureProvider.autoDispose
    .family<List<SharedDoctorNote>, String>(
      (ref, doctorId) =>
          ref.watch(myDoctorsApiProvider).listSharedNotes(doctorId),
    );
