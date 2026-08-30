import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/doctor_workspace_api.dart';
import '../models/doctor_models.dart';

final doctorWorkspaceApiProvider = Provider<DoctorWorkspaceApi>(
  (ref) => DoctorWorkspaceApi(ref.watch(dioProvider)),
);

final doctorSessionKeyProvider = Provider<String>((ref) {
  final auth = ref.watch(authControllerProvider);
  return '${auth.status.name}:${auth.user?.id ?? ''}:${auth.user?.role ?? ''}';
});

class DoctorOperationResult<T> {
  const DoctorOperationResult.success(this.value) : error = null;
  DoctorOperationResult.failure(Object cause)
    : value = null,
      error = ApiException.from(cause);
  final T? value;
  final ApiException? error;
  bool get isSuccess => error == null;
}

abstract class _SafeController<T> extends StateNotifier<AsyncValue<T>> {
  _SafeController(super.state);
  bool alive = true;
  int generation = 0;
  final Set<String> busy = {};
  bool begin(String key) => alive && busy.add(key);
  void finish(String key) => busy.remove(key);
  @override
  void dispose() {
    alive = false;
    generation++;
    super.dispose();
  }
}

class DoctorProfileController extends _SafeController<DoctorProfile> {
  DoctorProfileController(this.api) : super(const AsyncValue.loading()) {
    load();
  }
  final DoctorWorkspaceApi api;
  Future<void> load() async {
    final request = ++generation;
    if (alive) state = const AsyncValue.loading();
    try {
      final value = await api.getProfile();
      if (alive && request == generation) state = AsyncValue.data(value);
    } catch (error, stack) {
      if (alive && request == generation) {
        state = AsyncValue.error(ApiException.from(error), stack);
      }
    }
  }

  Future<DoctorOperationResult<DoctorProfile>> save({
    required String headline,
    required String bio,
    required String subSpecialty,
    required int? yearsOfExperience,
    required List<String> expertise,
    required List<String> interests,
    required List<String> education,
    required List<String> certifications,
    required List<String> languages,
    required String city,
    required double? consultationFee,
    required int consultationDuration,
    required bool isAcceptingPatients,
  }) async {
    if (!begin('save')) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'An update is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      final value = await api.updateProfile(
        headline: headline,
        bio: bio,
        subSpecialty: subSpecialty,
        yearsOfExperience: yearsOfExperience,
        expertise: expertise,
        interests: interests,
        education: education,
        certifications: certifications,
        languages: languages,
        city: city,
        consultationFee: consultationFee,
        consultationDuration: consultationDuration,
        isAcceptingPatients: isAcceptingPatients,
      );
      if (alive) state = AsyncValue.data(value);
      return DoctorOperationResult.success(value);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish('save');
    }
  }
}

final doctorProfileProvider =
    StateNotifierProvider.autoDispose<
      DoctorProfileController,
      AsyncValue<DoctorProfile>
    >((ref) {
      ref.watch(doctorSessionKeyProvider);
      return DoctorProfileController(ref.watch(doctorWorkspaceApiProvider));
    });

class DoctorScheduleController extends _SafeController<DoctorSchedule> {
  DoctorScheduleController(this.api) : super(const AsyncValue.loading()) {
    load();
  }
  final DoctorWorkspaceApi api;
  Future<void> load() async {
    final request = ++generation;
    if (alive) state = const AsyncValue.loading();
    try {
      final value = await api.getSchedule();
      if (alive && request == generation) state = AsyncValue.data(value);
    } catch (error, stack) {
      if (alive && request == generation) {
        state = AsyncValue.error(ApiException.from(error), stack);
      }
    }
  }

  Future<DoctorOperationResult<void>> saveAvailability({
    String? id,
    required Map<String, dynamic> payload,
  }) async {
    final key = id == null ? 'availability:create' : 'availability:$id';
    if (!begin(key)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This availability change is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      if (id == null) {
        await api.createAvailability(payload);
      } else {
        await api.updateAvailability(id, payload);
      }
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(key);
    }
  }

  Future<DoctorOperationResult<void>> deleteAvailability(String id) async {
    final key = 'availability:$id';
    if (!begin(key)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This availability change is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      await api.deleteAvailability(id);
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(key);
    }
  }

  Future<DoctorOperationResult<void>> actOnAppointment(
    String id,
    String action, {
    String? reason,
  }) async {
    final key = 'appointment:$id';
    if (!begin(key)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This appointment action is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      if (action == 'confirm') {
        await api.confirmAppointment(id);
      } else if (action == 'complete') {
        await api.completeAppointment(id);
      } else if (action == 'cancel') {
        await api.cancelAppointment(id, reason: reason);
      } else {
        throw const ApiException(
          message: 'Unsupported action.',
          code: 'VALIDATION_ERROR',
        );
      }
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(key);
    }
  }
}

final doctorScheduleProvider =
    StateNotifierProvider.autoDispose<
      DoctorScheduleController,
      AsyncValue<DoctorSchedule>
    >((ref) {
      ref.watch(doctorSessionKeyProvider);
      return DoctorScheduleController(ref.watch(doctorWorkspaceApiProvider));
    });

class DoctorPatientsController extends _SafeController<List<DoctorPatient>> {
  DoctorPatientsController(this.api) : super(const AsyncValue.loading()) {
    load();
  }
  final DoctorWorkspaceApi api;
  String search = '';
  Future<void> load({String? query}) async {
    if (query != null) search = query.trim();
    final request = ++generation;
    if (alive) state = const AsyncValue.loading();
    try {
      final value = await api.getPatients(search: search);
      if (alive && request == generation) state = AsyncValue.data(value);
    } catch (error, stack) {
      if (alive && request == generation) {
        state = AsyncValue.error(ApiException.from(error), stack);
      }
    }
  }
}

final doctorPatientsProvider =
    StateNotifierProvider.autoDispose<
      DoctorPatientsController,
      AsyncValue<List<DoctorPatient>>
    >((ref) {
      ref.watch(doctorSessionKeyProvider);
      return DoctorPatientsController(ref.watch(doctorWorkspaceApiProvider));
    });

class DoctorPatientController extends _SafeController<DoctorPatientDetail> {
  DoctorPatientController(this.api, this.patientId)
    : super(const AsyncValue.loading()) {
    load();
  }
  final DoctorWorkspaceApi api;
  final String patientId;
  Future<void> load() async {
    final request = ++generation;
    if (alive) state = const AsyncValue.loading();
    try {
      final value = await api.getPatient(patientId);
      if (alive && request == generation) state = AsyncValue.data(value);
    } catch (error, stack) {
      if (alive && request == generation) {
        state = AsyncValue.error(ApiException.from(error), stack);
      }
    }
  }

  Future<DoctorOperationResult<void>> addNote({
    required String recordType,
    required String chiefComplaint,
    required String diagnosis,
    required String clinicalNotes,
    required bool isDraft,
    required bool visibleToPatient,
  }) async {
    if (!begin('note')) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'A note is already being saved.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      await api.createSessionNote(
        patientId,
        recordType: recordType,
        chiefComplaint: chiefComplaint,
        diagnosis: diagnosis,
        clinicalNotes: clinicalNotes,
        isDraft: isDraft,
        visibleToPatient: visibleToPatient,
      );
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish('note');
    }
  }

  Future<DoctorOperationResult<PrescriptionResult>> createPrescription({
    required String appointmentId,
    String? validUntil,
    required String diagnosis,
    required String instructions,
    required String doctorNotes,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!begin('prescription')) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'A prescription is already being saved.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      final value = await api.createPrescription(
        patientId: patientId,
        appointmentId: appointmentId,
        validUntil: validUntil,
        diagnosis: diagnosis,
        instructions: instructions,
        doctorNotes: doctorNotes,
        items: items,
      );
      await load();
      return DoctorOperationResult.success(value);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish('prescription');
    }
  }

  Future<DoctorOperationResult<void>> endRelationship(String reason) async {
    if (!begin('relationship')) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This change is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      await api.endRelationship(patientId, reason);
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish('relationship');
    }
  }
}

final doctorPatientProvider = StateNotifierProvider.autoDispose
    .family<DoctorPatientController, AsyncValue<DoctorPatientDetail>, String>((
      ref,
      id,
    ) {
      ref.watch(doctorSessionKeyProvider);
      return DoctorPatientController(ref.watch(doctorWorkspaceApiProvider), id);
    });

class DoctorPostsController extends _SafeController<List<DoctorPost>> {
  DoctorPostsController(this.api) : super(const AsyncValue.loading()) {
    load();
  }
  final DoctorWorkspaceApi api;
  Future<void> load() async {
    final request = ++generation;
    if (alive) state = const AsyncValue.loading();
    try {
      final value = await api.getPosts();
      if (alive && request == generation) state = AsyncValue.data(value);
    } catch (error, stack) {
      if (alive && request == generation) {
        state = AsyncValue.error(ApiException.from(error), stack);
      }
    }
  }

  Future<DoctorOperationResult<void>> save({
    String? id,
    required String title,
    required String category,
    required String body,
    required bool publish,
  }) async {
    final key = id ?? 'create';
    if (!begin(key)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This post is already being saved.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      await api.savePost(
        id: id,
        title: title,
        category: category,
        body: body,
        publish: publish,
      );
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(key);
    }
  }

  Future<DoctorOperationResult<void>> delete(String id) async {
    if (!begin(id)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This post change is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      await api.deletePost(id);
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(id);
    }
  }
}

final doctorPostsProvider =
    StateNotifierProvider.autoDispose<
      DoctorPostsController,
      AsyncValue<List<DoctorPost>>
    >((ref) {
      ref.watch(doctorSessionKeyProvider);
      return DoctorPostsController(ref.watch(doctorWorkspaceApiProvider));
    });

class DoctorRecordsController extends _SafeController<List<ClinicalRecord>> {
  DoctorRecordsController(this.api) : super(const AsyncValue.loading()) {
    load();
  }
  final DoctorWorkspaceApi api;
  Future<void> load() async {
    final request = ++generation;
    if (alive) state = const AsyncValue.loading();
    try {
      final value = await api.getRecords();
      if (alive && request == generation) state = AsyncValue.data(value);
    } catch (error, stack) {
      if (alive && request == generation) {
        state = AsyncValue.error(ApiException.from(error), stack);
      }
    }
  }

  Future<DoctorOperationResult<void>> save({
    String? id,
    String? appointmentId,
    required String recordType,
    required String chiefComplaint,
    required String diagnosis,
    required String treatmentPlan,
    required String clinicalNotes,
    required String doctorNotes,
    required bool isDraft,
  }) async {
    final key = id ?? 'create';
    if (!begin(key)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This record is already being saved.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      if (id == null) {
        if (appointmentId == null) {
          throw const ApiException(
            message: 'Appointment required.',
            code: 'VALIDATION_ERROR',
          );
        }
        await api.createRecord(
          appointmentId: appointmentId,
          recordType: recordType,
          chiefComplaint: chiefComplaint,
          diagnosis: diagnosis,
          treatmentPlan: treatmentPlan,
          clinicalNotes: clinicalNotes,
          doctorNotes: doctorNotes,
          isDraft: isDraft,
        );
      } else {
        await api.updateRecord(
          id,
          diagnosis: diagnosis,
          treatmentPlan: treatmentPlan,
          clinicalNotes: clinicalNotes,
          doctorNotes: doctorNotes,
          isDraft: isDraft,
        );
      }
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(key);
    }
  }

  Future<DoctorOperationResult<void>> delete(String id) async {
    if (!begin(id)) {
      return DoctorOperationResult.failure(
        const ApiException(
          message: 'This record change is already in progress.',
          code: 'DUPLICATE_IN_FLIGHT',
        ),
      );
    }
    try {
      await api.deleteRecord(id);
      await load();
      return const DoctorOperationResult.success(null);
    } catch (error) {
      return DoctorOperationResult.failure(error);
    } finally {
      finish(id);
    }
  }
}

final doctorRecordsProvider =
    StateNotifierProvider.autoDispose<
      DoctorRecordsController,
      AsyncValue<List<ClinicalRecord>>
    >((ref) {
      ref.watch(doctorSessionKeyProvider);
      return DoctorRecordsController(ref.watch(doctorWorkspaceApiProvider));
    });
