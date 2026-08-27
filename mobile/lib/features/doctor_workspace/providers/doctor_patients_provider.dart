import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/doctor_patients_api.dart';
import '../models/doctor_patient_models.dart';

final doctorPatientsApiProvider = Provider<DoctorPatientsApi>(
  (ref) => DoctorPatientsApi(ref.watch(dioProvider)),
);
final doctorPatientsProvider = FutureProvider.autoDispose<List<DoctorPatient>>(
  (ref) => ref.watch(doctorPatientsApiProvider).list(),
);
