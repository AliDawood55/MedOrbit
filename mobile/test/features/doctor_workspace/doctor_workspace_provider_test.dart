import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/doctor_workspace/data/doctor_workspace_api.dart';
import 'package:mobile/features/doctor_workspace/models/doctor_models.dart';
import 'package:mobile/features/doctor_workspace/providers/doctor_workspace_providers.dart';

void main() {
  group('DoctorProfileController', () {
    test('loads initial server snapshot', () async {
      final api = _ProfileApi()..loads.add(Future.value(_profile('first')));
      final controller = DoctorProfileController(api);
      await _settle();
      expect(controller.state.asData?.value.headline, 'first');
      controller.dispose();
    });

    test('newer refresh wins over stale response', () async {
      final first = Completer<DoctorProfile>(),
          second = Completer<DoctorProfile>();
      final api = _ProfileApi()..loads.addAll([first.future, second.future]);
      final controller = DoctorProfileController(api);
      final refresh = controller.load();
      second.complete(_profile('new'));
      await refresh;
      first.complete(_profile('stale'));
      await _settle();
      expect(controller.state.asData?.value.headline, 'new');
      controller.dispose();
    });

    test('dispose prevents a late response from mutating state', () async {
      final pending = Completer<DoctorProfile>();
      final api = _ProfileApi()..loads.add(pending.future);
      final controller = DoctorProfileController(api);
      controller.dispose();
      pending.complete(_profile('late'));
      await _settle();
    });

    test('duplicate save creates one request', () async {
      final update = Completer<DoctorProfile>();
      final api = _ProfileApi()
        ..loads.add(Future.value(_profile('old')))
        ..update = update;
      final controller = DoctorProfileController(api);
      await _settle();
      final first = controller.save(
        headline: 'new',
        bio: '',
        subSpecialty: '',
        yearsOfExperience: null,
        expertise: const [],
        interests: const [],
        education: const [],
        certifications: const [],
        languages: const [],
        city: '',
        consultationFee: null,
        consultationDuration: 30,
        isAcceptingPatients: true,
      );
      final duplicate = await controller.save(
        headline: 'again',
        bio: '',
        subSpecialty: '',
        yearsOfExperience: null,
        expertise: const [],
        interests: const [],
        education: const [],
        certifications: const [],
        languages: const [],
        city: '',
        consultationFee: null,
        consultationDuration: 30,
        isAcceptingPatients: true,
      );
      expect(duplicate.error?.code, 'DUPLICATE_IN_FLIGHT');
      expect(api.updateCalls, 1);
      update.complete(_profile('new'));
      expect((await first).isSuccess, isTrue);
      controller.dispose();
    });

    test('preserves backend error code safely', () async {
      final api = _ProfileApi()
        ..loads.add(
          Future.error(
            const ApiException(
              message: 'raw server text',
              code: 'DOCTOR_NOT_APPROVED',
            ),
          ),
        );
      final controller = DoctorProfileController(api);
      await _settle();
      expect(
        (controller.state.error as ApiException).code,
        'DOCTOR_NOT_APPROVED',
      );
      controller.dispose();
    });
  });

  group('operation duplicate protection', () {
    test('schedule blocks a second action on the same appointment', () async {
      final pending = Completer<DoctorAppointment>();
      final api = _ScheduleApi()..confirm = pending;
      final controller = DoctorScheduleController(api);
      await _settle();
      final first = controller.actOnAppointment('appt-1', 'confirm');
      final second = await controller.actOnAppointment('appt-1', 'confirm');
      expect(second.error?.code, 'DUPLICATE_IN_FLIGHT');
      expect(api.confirmCalls, 1);
      pending.complete(_appointment('confirmed'));
      expect((await first).isSuccess, isTrue);
      controller.dispose();
    });

    test('patient controller blocks duplicate note creation', () async {
      final pending = Completer<ClinicalRecord>();
      final api = _PatientApi()..note = pending;
      final controller = DoctorPatientController(api, 'patient-1');
      await _settle();
      final first = controller.addNote(
        recordType: 'consultation',
        chiefComplaint: '',
        diagnosis: '',
        clinicalNotes: 'note',
        isDraft: true,
        visibleToPatient: false,
      );
      final second = await controller.addNote(
        recordType: 'consultation',
        chiefComplaint: '',
        diagnosis: '',
        clinicalNotes: 'note',
        isDraft: true,
        visibleToPatient: false,
      );
      expect(second.error?.code, 'DUPLICATE_IN_FLIGHT');
      expect(api.noteCalls, 1);
      pending.complete(_record());
      expect((await first).isSuccess, isTrue);
      controller.dispose();
    });

    test('posts controller blocks duplicate save', () async {
      final pending = Completer<DoctorPost>();
      final api = _PostApi()..save = pending;
      final controller = DoctorPostsController(api);
      await _settle();
      final first = controller.save(
        title: 'Title',
        category: 'article',
        body: 'Body',
        publish: false,
      );
      final second = await controller.save(
        title: 'Title',
        category: 'article',
        body: 'Body',
        publish: false,
      );
      expect(second.error?.code, 'DUPLICATE_IN_FLIGHT');
      pending.complete(_post());
      expect((await first).isSuccess, isTrue);
      controller.dispose();
    });

    test('records controller blocks duplicate mutation', () async {
      final pending = Completer<ClinicalRecord>();
      final api = _RecordApi()..create = pending;
      final controller = DoctorRecordsController(api);
      await _settle();
      Future<DoctorOperationResult<void>> save() => controller.save(
        appointmentId: 'appt-1',
        recordType: 'consultation',
        chiefComplaint: '',
        diagnosis: 'Dx',
        treatmentPlan: '',
        clinicalNotes: '',
        doctorNotes: '',
        isDraft: true,
      );
      final first = save();
      final second = await save();
      expect(second.error?.code, 'DUPLICATE_IN_FLIGHT');
      pending.complete(_record());
      expect((await first).isSuccess, isTrue);
      controller.dispose();
    });
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);
DoctorProfile _profile(String headline) => DoctorProfile(
  id: 'doctor-1',
  approvalStatus: 'approved',
  isAcceptingPatients: true,
  headline: headline,
);
DoctorAppointment _appointment(String status) => DoctorAppointment(
  id: 'appt-1',
  number: 'APT-1',
  date: '2026-09-01',
  startTime: '09:00:00',
  endTime: '09:30:00',
  type: 'telemedicine',
  status: status,
);
DoctorSchedule _schedule() => DoctorSchedule(
  bookingHorizonDays: 90,
  weekly: const [],
  overrides: const [],
  clinics: const [],
  appointments: [_appointment('scheduled')],
);
ClinicalRecord _record() => const ClinicalRecord(
  id: 'record-1',
  recordNumber: 'MR-1',
  recordType: 'consultation',
  isDraft: true,
  visibleToPatient: false,
);
DoctorPatientDetail _detail() => DoctorPatientDetail(
  patient: const DoctorPatient(
    id: 'patient-1',
    email: 'p@example.test',
    hasUpcoming: false,
  ),
  appointments: const [],
  notes: const [],
  prescriptions: const [],
);
DoctorPost _post() => const DoctorPost(
  id: 'post-1',
  title: 'Title',
  category: 'article',
  body: 'Body',
  isPublished: false,
  status: 'draft',
  moderationStatus: 'pending',
);

class _ProfileApi extends DoctorWorkspaceApi {
  _ProfileApi() : super(Dio());
  final loads = <Future<DoctorProfile>>[];
  Completer<DoctorProfile>? update;
  int updateCalls = 0;
  @override
  Future<DoctorProfile> getProfile() => loads.removeAt(0);
  @override
  Future<DoctorProfile> updateProfile({
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
  }) {
    updateCalls++;
    return update!.future;
  }
}

class _ScheduleApi extends DoctorWorkspaceApi {
  _ScheduleApi() : super(Dio());
  Completer<DoctorAppointment>? confirm;
  int confirmCalls = 0;
  @override
  Future<DoctorSchedule> getSchedule() async => _schedule();
  @override
  Future<DoctorAppointment> confirmAppointment(String id) {
    confirmCalls++;
    return confirm!.future;
  }
}

class _PatientApi extends DoctorWorkspaceApi {
  _PatientApi() : super(Dio());
  Completer<ClinicalRecord>? note;
  int noteCalls = 0;
  @override
  Future<DoctorPatientDetail> getPatient(String id) async => _detail();
  @override
  Future<ClinicalRecord> createSessionNote(
    String patientId, {
    required String recordType,
    required String chiefComplaint,
    required String diagnosis,
    required String clinicalNotes,
    required bool isDraft,
    required bool visibleToPatient,
  }) {
    noteCalls++;
    return note!.future;
  }
}

class _PostApi extends DoctorWorkspaceApi {
  _PostApi() : super(Dio());
  Completer<DoctorPost>? save;
  @override
  Future<List<DoctorPost>> getPosts() async => const [];
  @override
  Future<DoctorPost> savePost({
    String? id,
    required String title,
    required String category,
    required String body,
    required bool publish,
  }) => save!.future;
}

class _RecordApi extends DoctorWorkspaceApi {
  _RecordApi() : super(Dio());
  Completer<ClinicalRecord>? create;
  @override
  Future<List<ClinicalRecord>> getRecords() async => const [];
  @override
  Future<ClinicalRecord> createRecord({
    required String appointmentId,
    required String recordType,
    required String chiefComplaint,
    required String diagnosis,
    required String treatmentPlan,
    required String clinicalNotes,
    required String doctorNotes,
    required bool isDraft,
  }) => create!.future;
}
