import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/utils/date_formatting.dart';
import '../../appointments/models/enriched_appointment.dart';
import '../../appointments/providers/appointments_provider.dart';
import '../../appointments/utils/appointment_filters.dart';
import '../data/care_api.dart';
import '../models/my_doctor_model.dart';
import '../models/shared_note_model.dart';

final careApiProvider = Provider<CareApi>((ref) => CareApi(ref.watch(dioProvider)));

/// Patient's active treating doctors — `GET /patients/me/doctors`. An empty
/// list is a legitimate "no active doctors" state, not an error.
final myDoctorsProvider = FutureProvider.autoDispose<List<MyDoctorModel>>((ref) {
  return ref.watch(careApiProvider).myDoctors();
});

/// Pairs a shared note with the doctor who wrote it, for a merged/sorted
/// display across every treating doctor.
class SharedNoteEntry {
  const SharedNoteEntry({required this.doctor, required this.note});

  final MyDoctorModel doctor;
  final SharedNoteModel note;
}

/// Shared notes across every active treating doctor, merged and sorted
/// newest first.
///
/// Deliberately does *not* catch a per-doctor failure and fold it into `[]`
/// the way the web app does (`my-doctor.js#loadSharedNotes`) — `Future.wait`
/// here lets a single failing fetch fail the whole provider, so "no shared
/// notes" (legitimate empty list) and "could not load shared notes"
/// (retryable error) never collapse into the same on-screen state.
final sharedNotesProvider = FutureProvider.autoDispose<List<SharedNoteEntry>>((ref) async {
  final doctors = await ref.watch(myDoctorsProvider.future);
  final api = ref.watch(careApiProvider);

  final perDoctor = await Future.wait(doctors.map((doctor) async {
    final notes = await api.sharedNotes(doctor.id);
    return notes.map((note) => SharedNoteEntry(doctor: doctor, note: note));
  }));

  final merged = perDoctor.expand((entries) => entries).toList()
    ..sort((a, b) => (b.note.createdAt ?? '').compareTo(a.note.createdAt ?? ''));
  return merged;
});

/// Appointments with the patient's active treating doctors, filtered from
/// the existing appointments list to upcoming statuses/dates only — reuses
/// `appointmentsControllerProvider` rather than a new endpoint or model.
final upcomingWithMyDoctorsProvider = Provider.autoDispose<AsyncValue<List<EnrichedAppointment>>>((ref) {
  final appointmentsAsync = ref.watch(appointmentsControllerProvider);
  final doctorsAsync = ref.watch(myDoctorsProvider);

  if (appointmentsAsync.isLoading || doctorsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (appointmentsAsync.hasError) {
    return AsyncValue.error(appointmentsAsync.error!, appointmentsAsync.stackTrace ?? StackTrace.current);
  }
  if (doctorsAsync.hasError) {
    return AsyncValue.error(doctorsAsync.error!, doctorsAsync.stackTrace ?? StackTrace.current);
  }

  final doctorIds = doctorsAsync.value!.map((doctor) => doctor.id).toSet();
  final upcoming = appointmentsAsync.value!
      .where((entry) => doctorIds.contains(entry.appointment.doctorId) && isUpcomingAppointment(entry))
      .toList()
    ..sort((a, b) {
      final byDate = parseDateOnly(
        a.appointment.scheduledDate,
      ).compareTo(parseDateOnly(b.appointment.scheduledDate));
      return byDate != 0 ? byDate : a.appointment.startTime.compareTo(b.appointment.startTime);
    });
  return AsyncValue.data(upcoming);
});
