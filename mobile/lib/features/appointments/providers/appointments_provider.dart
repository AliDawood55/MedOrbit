import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/app_role_capabilities_provider.dart';
import '../data/appointments_api.dart';
import '../models/enriched_appointment.dart';

final appointmentsApiProvider = Provider<AppointmentsApi>(
  (ref) => AppointmentsApi(ref.watch(dioProvider)),
);

class AppointmentsController
    extends StateNotifier<AsyncValue<List<EnrichedAppointment>>> {
  AppointmentsController(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  final AppointmentsApi _api;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final appointments = await _api.list();

      final doctorIds = appointments.map((a) => a.doctorId).toSet();
      final clinicIds = appointments
          .map((a) => a.clinicId)
          .whereType<String>()
          .toSet();

      final doctorNames = <String, (String?, String?)>{};
      final clinicNames = <String, (String?, String?)>{};

      await Future.wait([
        ...doctorIds.map(
          (id) async => doctorNames[id] = await _api.getDoctorName(id),
        ),
        ...clinicIds.map(
          (id) async => clinicNames[id] = await _api.getClinicName(id),
        ),
      ]);

      return appointments.map((a) {
        final doctor = doctorNames[a.doctorId];
        final clinic = a.clinicId == null ? null : clinicNames[a.clinicId];
        return EnrichedAppointment(
          appointment: a,
          doctorNameAr: doctor?.$1,
          doctorNameEn: doctor?.$2,
          clinicNameAr: clinic?.$1,
          clinicNameEn: clinic?.$2,
        );
      }).toList();
    });
  }

  /// Cancels, then flips the local status in place — matches the web app's
  /// behavior (no full list refetch needed after a cancel).
  Future<bool> cancel(String appointmentId, {String? reason}) async {
    try {
      final updated = await _api.cancel(appointmentId, reason: reason);
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data([
          for (final entry in current)
            if (entry.appointment.id == appointmentId)
              entry.copyWith(appointment: updated)
            else
              entry,
        ]);
      }
      return true;
    } catch (error) {
      // A 404 here means the appointment is no longer cancellable by this
      // caller (already cancelled/actioned elsewhere, or never existed) —
      // reload so the stale card converges to server truth instead of
      // continuing to show a cancel button that will just fail again.
      if (ApiException.from(error).statusCode == 404) {
        await load();
      }
      return false;
    }
  }
}

final appointmentsControllerProvider =
    StateNotifierProvider.autoDispose<
      AppointmentsController,
      AsyncValue<List<EnrichedAppointment>>
    >((ref) {
      ref.watch(appAccountSessionKeyProvider);
      return AppointmentsController(ref.watch(appointmentsApiProvider));
    });
