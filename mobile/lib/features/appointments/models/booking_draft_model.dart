import '../../discovery/models/doctor_models.dart';
import 'availability_slot_model.dart';

/// The patient's in-progress selections for the booking wizard.
///
/// Kept separate from [BookingState] (in `booking_provider.dart`), which
/// wraps this with transient loading/error flags, so "clear the draft" —
/// required on successful booking, explicit cancel, and logout — is always a
/// single `BookingDraft()` reset rather than picking fields apart by hand.
/// Never persisted to disk.
class BookingDraft {
  const BookingDraft({
    this.doctor,
    this.clinics = const [],
    this.clinic,
    this.date,
    this.slot,
    this.reason = '',
    this.notes = '',
  });

  final Doctor? doctor;
  final List<DoctorClinicSummary> clinics;
  final DoctorClinicSummary? clinic;
  final DateTime? date;
  final GeneratedSlot? slot;
  final String reason;
  final String notes;

  BookingDraft copyWith({
    Doctor? doctor,
    bool clearDoctor = false,
    List<DoctorClinicSummary>? clinics,
    DoctorClinicSummary? clinic,
    bool clearClinic = false,
    DateTime? date,
    bool clearDate = false,
    GeneratedSlot? slot,
    bool clearSlot = false,
    String? reason,
    String? notes,
  }) {
    return BookingDraft(
      doctor: clearDoctor ? null : (doctor ?? this.doctor),
      clinics: clinics ?? this.clinics,
      clinic: clearClinic ? null : (clinic ?? this.clinic),
      date: clearDate ? null : (date ?? this.date),
      slot: clearSlot ? null : (slot ?? this.slot),
      reason: reason ?? this.reason,
      notes: notes ?? this.notes,
    );
  }
}
