import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../discovery/data/discovery_api.dart';
import '../../discovery/models/doctor_models.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../data/booking_api.dart';
import '../models/appointment_model.dart';
import '../models/availability_slot_model.dart';
import '../models/booking_draft_model.dart';
import '../utils/slot_generation.dart';
import 'appointments_provider.dart';

final bookingApiProvider = Provider<BookingApi>((ref) => BookingApi(ref.watch(dioProvider)));

enum BookingWizardStep { doctor, slot, confirm }

/// Why loading the doctor named by `?doctorId=` on the route failed —
/// mirrors the web wizard's `wizardNotFound` vs `wizardError` split so the
/// screen can show "doctor not found" instead of a generic error when that's
/// specifically what happened (`err.status === 404` in book-appointment.js).
enum PreselectDoctorFailure { notFound, loadError }

enum BookingSubmitErrorKind { slotBusy, patientNotFound, timeout, serviceUnavailable, validation, generic }

class BookingSubmitError {
  const BookingSubmitError(this.kind);
  final BookingSubmitErrorKind kind;
}

class BookingState {
  const BookingState({
    this.step = BookingWizardStep.doctor,
    this.draft = const BookingDraft(),
    this.isLoadingPreselectedDoctor = false,
    this.preselectFailure,
    this.doctorQuery = '',
    this.doctorResults = const <Doctor>[],
    this.isLoadingDoctors = false,
    this.doctorListFailed = false,
    this.isLoadingDoctorDetail = false,
    this.doctorDetailFailed = false,
    this.slots = const <GeneratedSlot>[],
    this.isLoadingSlots = false,
    this.slotsFailed = false,
    this.isSubmitting = false,
    this.submitError,
    this.result,
  });

  final BookingWizardStep step;
  final BookingDraft draft;

  final bool isLoadingPreselectedDoctor;
  final PreselectDoctorFailure? preselectFailure;

  final String doctorQuery;
  final List<Doctor> doctorResults;
  final bool isLoadingDoctors;
  final bool doctorListFailed;

  final bool isLoadingDoctorDetail;
  final bool doctorDetailFailed;

  final List<GeneratedSlot> slots;
  final bool isLoadingSlots;
  final bool slotsFailed;

  final bool isSubmitting;
  final BookingSubmitError? submitError;

  /// Set once `POST /appointments` succeeds — the wizard shows the success
  /// sheet whenever this is non-null.
  final AppointmentModel? result;

  BookingState copyWith({
    BookingWizardStep? step,
    BookingDraft? draft,
    bool? isLoadingPreselectedDoctor,
    PreselectDoctorFailure? preselectFailure,
    bool clearPreselectFailure = false,
    String? doctorQuery,
    List<Doctor>? doctorResults,
    bool? isLoadingDoctors,
    bool? doctorListFailed,
    bool? isLoadingDoctorDetail,
    bool? doctorDetailFailed,
    List<GeneratedSlot>? slots,
    bool? isLoadingSlots,
    bool? slotsFailed,
    bool? isSubmitting,
    BookingSubmitError? submitError,
    bool clearSubmitError = false,
    AppointmentModel? result,
    bool clearResult = false,
  }) {
    return BookingState(
      step: step ?? this.step,
      draft: draft ?? this.draft,
      isLoadingPreselectedDoctor: isLoadingPreselectedDoctor ?? this.isLoadingPreselectedDoctor,
      preselectFailure: clearPreselectFailure ? null : (preselectFailure ?? this.preselectFailure),
      doctorQuery: doctorQuery ?? this.doctorQuery,
      doctorResults: doctorResults ?? this.doctorResults,
      isLoadingDoctors: isLoadingDoctors ?? this.isLoadingDoctors,
      doctorListFailed: doctorListFailed ?? this.doctorListFailed,
      isLoadingDoctorDetail: isLoadingDoctorDetail ?? this.isLoadingDoctorDetail,
      doctorDetailFailed: doctorDetailFailed ?? this.doctorDetailFailed,
      slots: slots ?? this.slots,
      isLoadingSlots: isLoadingSlots ?? this.isLoadingSlots,
      slotsFailed: slotsFailed ?? this.slotsFailed,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: clearSubmitError ? null : (submitError ?? this.submitError),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

class BookingController extends StateNotifier<BookingState> {
  BookingController(this._ref)
      : _api = _ref.read(bookingApiProvider),
        _discoveryApi = _ref.read(discoveryApiProvider),
        super(const BookingState());

  final Ref _ref;
  final BookingApi _api;
  final DiscoveryApi _discoveryApi;

  bool _disposed = false;
  int _doctorSearchRequestId = 0;
  int _slotsRequestId = 0;

  /// Call once when the wizard opens. With [doctorId] (deep link from the
  /// doctor detail screen), loads that doctor and jumps straight to the slot
  /// step; otherwise loads the initial browse list for the doctor step.
  Future<void> init({String? doctorId}) async {
    if (doctorId != null && doctorId.isNotEmpty) {
      state = state.copyWith(isLoadingPreselectedDoctor: true, clearPreselectFailure: true);
      try {
        final detail = await _discoveryApi.getDoctor(doctorId);
        if (_disposed) return;
        final doctor = detail.doctor;
        if (doctor == null) {
          state = state.copyWith(
            isLoadingPreselectedDoctor: false,
            preselectFailure: PreselectDoctorFailure.notFound,
          );
          await loadInitialDoctors();
          return;
        }
        _applyDoctorSelection(doctor, detail.clinics);
        state = state.copyWith(isLoadingPreselectedDoctor: false);
        goToSlotStep();
      } catch (error) {
        if (_disposed) return;
        final isNotFound = ApiException.from(error).statusCode == 404;
        state = state.copyWith(
          isLoadingPreselectedDoctor: false,
          preselectFailure: isNotFound ? PreselectDoctorFailure.notFound : PreselectDoctorFailure.loadError,
        );
        await loadInitialDoctors();
      }
    } else {
      await loadInitialDoctors();
    }
  }

  Future<void> loadInitialDoctors() async {
    final requestId = ++_doctorSearchRequestId;
    state = state.copyWith(isLoadingDoctors: true, doctorListFailed: false);
    try {
      final response = await _discoveryApi.listDoctors(limit: 20);
      if (_disposed || requestId != _doctorSearchRequestId) return;
      state = state.copyWith(doctorResults: response.doctors, isLoadingDoctors: false);
    } catch (_) {
      if (_disposed || requestId != _doctorSearchRequestId) return;
      state = state.copyWith(isLoadingDoctors: false, doctorListFailed: true);
    }
  }

  /// Debouncing lives in the screen (matching `doctor_directory_screen.dart`
  /// and the web's 300ms timer) — this always issues the request immediately.
  Future<void> searchDoctors(String query) async {
    final trimmed = query.trim();
    final requestId = ++_doctorSearchRequestId;
    state = state.copyWith(doctorQuery: query, isLoadingDoctors: true, doctorListFailed: false);
    try {
      final response = await _discoveryApi.listDoctors(search: trimmed.isEmpty ? null : trimmed, limit: 20);
      if (_disposed || requestId != _doctorSearchRequestId) return;
      state = state.copyWith(doctorResults: response.doctors, isLoadingDoctors: false);
    } catch (_) {
      if (_disposed || requestId != _doctorSearchRequestId) return;
      state = state.copyWith(isLoadingDoctors: false, doctorListFailed: true);
    }
  }

  /// Doctor list results never carry clinics, so selecting one always
  /// re-fetches the detail (same as `book-appointment.js`'s `loadDoctorById`).
  Future<void> selectDoctor(Doctor doctor) async {
    state = state.copyWith(isLoadingDoctorDetail: true, doctorDetailFailed: false);
    try {
      final detail = await _discoveryApi.getDoctor(doctor.id);
      if (_disposed) return;
      _applyDoctorSelection(detail.doctor ?? doctor, detail.clinics);
      state = state.copyWith(isLoadingDoctorDetail: false);
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(isLoadingDoctorDetail: false, doctorDetailFailed: true);
    }
  }

  void _applyDoctorSelection(Doctor doctor, List<DoctorClinicSummary> clinics) {
    final soleClinic = clinics.length == 1 ? clinics.first : null;
    state = state.copyWith(
      draft: state.draft.copyWith(
        doctor: doctor,
        clinics: clinics,
        clinic: soleClinic,
        clearClinic: soleClinic == null,
        clearDate: true,
        clearSlot: true,
      ),
      slots: const [],
    );
  }

  /// Mirrors the web's `onChangeDoctor`: back to step 1 with a clean slate.
  Future<void> changeDoctor() async {
    state = state.copyWith(
      step: BookingWizardStep.doctor,
      draft: const BookingDraft(),
      slots: const [],
      doctorQuery: '',
    );
    await loadInitialDoctors();
  }

  void goToSlotStep() {
    if (state.draft.doctor == null) return;
    state = state.copyWith(step: BookingWizardStep.slot);
    if (state.draft.date == null) {
      selectDate(DateTime.now());
    } else {
      loadSlots();
    }
  }

  void backToDoctorStep() => state = state.copyWith(step: BookingWizardStep.doctor);

  void backToSlotStep() => state = state.copyWith(step: BookingWizardStep.slot);

  void selectClinic(DoctorClinicSummary clinic) {
    state = state.copyWith(draft: state.draft.copyWith(clinic: clinic, clearSlot: true), slots: const []);
    loadSlots();
  }

  void selectDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    state = state.copyWith(draft: state.draft.copyWith(date: normalized, clearSlot: true), slots: const []);
    loadSlots();
  }

  Future<void> loadSlots() async {
    final doctor = state.draft.doctor;
    final clinic = state.draft.clinic;
    final date = state.draft.date;
    if (doctor == null || clinic == null || date == null) return;

    final requestId = ++_slotsRequestId;
    state = state.copyWith(isLoadingSlots: true, slotsFailed: false);
    try {
      final windows = await _api.availableSlots(doctorId: doctor.id, clinicId: clinic.id, date: formatDateOnly(date));
      if (_disposed || requestId != _slotsRequestId) return;
      state = state.copyWith(slots: generateSlotsFromWindows(windows, forDate: date), isLoadingSlots: false);
    } catch (_) {
      if (_disposed || requestId != _slotsRequestId) return;
      state = state.copyWith(isLoadingSlots: false, slotsFailed: true);
    }
  }

  void selectSlot(GeneratedSlot slot) {
    state = state.copyWith(draft: state.draft.copyWith(slot: slot));
  }

  void setReason(String value) => state = state.copyWith(draft: state.draft.copyWith(reason: value));

  void setNotes(String value) => state = state.copyWith(draft: state.draft.copyWith(notes: value));

  void goToConfirm() {
    if (state.draft.clinic == null || state.draft.slot == null) return;
    state = state.copyWith(step: BookingWizardStep.confirm);
  }

  /// Prevents a duplicate submit by checking-then-flipping [BookingState.isSubmitting]
  /// synchronously, before the first `await` — a second call made before this
  /// one suspends sees the flag already set and bails out.
  Future<bool> submit() async {
    if (state.isSubmitting) return false;
    final doctor = state.draft.doctor;
    final clinic = state.draft.clinic;
    final date = state.draft.date;
    final slot = state.draft.slot;
    if (doctor == null || clinic == null || date == null || slot == null) {
      state = state.copyWith(submitError: const BookingSubmitError(BookingSubmitErrorKind.validation));
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearSubmitError: true);
    try {
      final reason = state.draft.reason.trim();
      final notes = state.draft.notes.trim();
      final appointment = await _api.create(
        doctorId: doctor.id,
        clinicId: clinic.id,
        scheduledDate: formatDateOnly(date),
        startTime: slot.startTime,
        endTime: slot.endTime,
        durationMinutes: slot.durationMinutes,
        appointmentType: slot.isTelemedicine ? 'telemedicine' : 'in_person',
        reasonForVisit: reason.isEmpty ? null : reason,
        notes: notes.isEmpty ? null : notes,
      );
      if (_disposed) return true;

      // That controller is `autoDispose`. Only invalidate it if it's already
      // alive (i.e. the appointments screen is mounted somewhere beneath this
      // one and currently watching it) — invalidating or reading it when
      // nothing watches it would construct a fresh instance just to have
      // Riverpod dispose it again moments later, racing its own constructor
      // `load()`. If it isn't alive, there's nothing to refresh: the
      // controller always calls `load()` unconditionally in its constructor,
      // so the next time that screen opens it fetches fresh data anyway.
      if (_ref.exists(appointmentsControllerProvider)) {
        _ref.invalidate(appointmentsControllerProvider);
      }

      state = state.copyWith(
        isSubmitting: false,
        result: appointment,
        draft: const BookingDraft(),
        slots: const [],
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      final api = ApiException.from(error);

      if (api.code == 'SLOT_BUSY') {
        state = state.copyWith(
          isSubmitting: false,
          step: BookingWizardStep.slot,
          draft: state.draft.copyWith(clearSlot: true),
          submitError: const BookingSubmitError(BookingSubmitErrorKind.slotBusy),
        );
        loadSlots();
        return false;
      }

      final kind = switch (api.code) {
        'PATIENT_NOT_FOUND' => BookingSubmitErrorKind.patientNotFound,
        ApiException.codeServiceUnavailable => BookingSubmitErrorKind.serviceUnavailable,
        _ => api.isTimeout ? BookingSubmitErrorKind.timeout : BookingSubmitErrorKind.generic,
      };
      state = state.copyWith(isSubmitting: false, submitError: BookingSubmitError(kind));
      return false;
    }
  }

  /// Discards the current draft — used when the patient explicitly abandons
  /// the wizard (leaving the screen also disposes this `autoDispose`
  /// provider, but an explicit cancel action should not wait for that).
  void discardDraft() {
    state = state.copyWith(step: BookingWizardStep.doctor, draft: const BookingDraft(), slots: const []);
  }

  /// "Book another appointment" from the success sheet — clears [BookingState.result]
  /// (which is what keeps that sheet on screen) and reloads the doctor step
  /// from scratch.
  Future<void> startOver() async {
    state = state.copyWith(step: BookingWizardStep.doctor, draft: const BookingDraft(), slots: const [], clearResult: true);
    await loadInitialDoctors();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final bookingControllerProvider = StateNotifierProvider.autoDispose<BookingController, BookingState>(
  (ref) => BookingController(ref),
);
