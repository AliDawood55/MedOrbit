import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/doctor_application/data/doctor_application_api.dart';
import 'package:mobile/features/doctor_application/models/doctor_application_model.dart';
import 'package:mobile/features/doctor_application/providers/doctor_application_provider.dart';
import 'package:mobile/features/doctor_application/screens/doctor_application_screen.dart';

const _en = AppStrings(false);
const _ar = AppStrings(true);

final _cardiology = Specialty(id: 'spec-cardio', nameEn: 'Cardiology', nameAr: 'طب القلب');

DoctorApplication _application(
  String id, {
  String status = 'pending',
  String? rejectionReason,
  String? reviewedAt,
  int? years,
  String? subSpecialty,
}) =>
    DoctorApplication.fromJson({
      'id': id,
      'user_id': 'user-1',
      'specialty_id': 'spec-cardio',
      'medical_license_number': 'LIC-$id',
      'status': status,
      'submitted_at': '2026-02-01T09:00:00Z',
      'reviewed_at': ?reviewedAt,
      'rejection_reason': ?rejectionReason,
      'years_of_experience': ?years,
      'sub_specialty': ?subSpecialty,
      'education': <String>[],
      'certifications': <String>[],
    });

Finder _statusCard() => find.ancestor(
      of: find.text(_en.doctorApplicationStatusHeading),
      matching: find.byType(Card),
    );

void main() {
  testWidgets('shows an intentional loading state before history is known', (tester) async {
    final api = _FakeApi()..applicationsGate = Completer<List<DoctorApplication>>();
    await _pump(tester, api: api);

    expect(find.text(_en.doctorApplicationLoading), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsNothing);
  });

  testWidgets('initial load failure shows safe error copy and Retry reloads', (tester) async {
    final api = _FakeApi()
      ..applicationsError = const ApiException(message: 'raw backend boom', code: 'INTERNAL_ERROR');
    await _pump(tester, api: api);

    expect(find.text(_en.doctorApplicationLoadErrorTitle), findsOneWidget);
    expect(find.textContaining('raw backend boom'), findsNothing);

    api.applicationsError = null;
    await tester.tap(find.widgetWithText(OutlinedButton, _en.retry));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('doctor-application-submit')), findsOneWidget);
    expect(api.applicationLoads, 2);
  });

  testWidgets('no applications: form is shown without an empty-history warning', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(find.byKey(const ValueKey('doctor-application-specialty-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsOneWidget);
    expect(find.text(_en.doctorApplicationHistoryTitle), findsNothing);
    expect(find.text(_en.doctorApplicationStatusHeading), findsNothing);
  });

  testWidgets('web parity: license and sub-specialty are capped at 255, privacy note is shown', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(tester.widget<TextField>(_license()).maxLength, 255);
    expect(tester.widget<TextField>(_field(_en.doctorApplicationSubSpecialtyLabel)).maxLength, 255);
    expect(find.text(_en.doctorApplicationPrivacyNote), findsOneWidget);
  });

  testWidgets('pending: status + withdraw shown, submit form hidden', (tester) async {
    await _pump(tester, api: _FakeApi()..applicationsValue = [_application('a1')]);

    expect(find.text(_en.doctorApplicationStatusHeading), findsOneWidget);
    expect(find.descendant(of: _statusCard(), matching: find.text(_en.doctorApplicationStatusPending)), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-withdraw')), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsNothing);
    expect(find.text(_en.doctorApplicationHistoryTitle), findsOneWidget);
  });

  testWidgets('rejected: reason is visible and a new application form is available', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()
        ..applicationsValue = [
          _application('a1', status: 'rejected', rejectionReason: 'License could not be verified'),
        ],
    );

    expect(find.descendant(of: _statusCard(), matching: find.text(_en.doctorApplicationStatusRejected)), findsOneWidget);
    expect(find.textContaining('License could not be verified'), findsWidgets);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsOneWidget);
  });

  testWidgets('withdrawn: history visible and a new application form is available', (tester) async {
    await _pump(tester, api: _FakeApi()..applicationsValue = [_application('a1', status: 'withdrawn')]);

    expect(find.text(_en.doctorApplicationWithdrawnBody), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsOneWidget);
    expect(find.text(_en.doctorApplicationHistoryTitle), findsOneWidget);
  });

  testWidgets('approved: an explicit approved state is shown', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()..applicationsValue = [_application('a1', status: 'approved', reviewedAt: '2026-02-05T09:00:00Z')],
    );

    expect(find.descendant(of: _statusCard(), matching: find.text(_en.doctorApplicationStatusApproved)), findsOneWidget);
    expect(find.text(_en.doctorApplicationApprovedBody), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-sign-in-again')), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsNothing);
  });

  testWidgets('non-patient roles get a safe unavailable state, not the form', (tester) async {
    await _pump(tester, api: _FakeApi(), role: 'doctor');

    expect(find.text(_en.doctorApplicationPatientOnlyTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsNothing);
  });

  testWidgets('required specialty and license are validated before any network call', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);

    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();
    expect(find.text(_en.doctorApplicationSpecialtyRequired), findsWidgets);
    expect(find.text(_en.doctorApplicationLicenseRequired), findsOneWidget);
    expect(api.submitCalls, 0);

    await _selectSpecialty(tester);
    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();
    expect(find.text(_en.doctorApplicationLicenseRequired), findsOneWidget);
    expect(api.submitCalls, 0);
  });

  testWidgets('years of experience validation rejects non-integers and out-of-range values', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);
    await _selectSpecialty(tester);
    await tester.enterText(_license(), 'LIC-123');

    Future<void> submitWith(String years) async {
      await tester.enterText(_years(), years);
      await _tap(tester, const ValueKey('doctor-application-submit'));
      await tester.pump();
    }

    await submitWith('abc');
    expect(find.text(_en.doctorApplicationExperienceInvalid), findsOneWidget);
    await submitWith('-5');
    expect(find.text(_en.doctorApplicationExperienceRange), findsOneWidget);
    await submitWith('81');
    expect(find.text(_en.doctorApplicationExperienceRange), findsOneWidget);
    expect(api.submitCalls, 0);

    await submitWith('80');
    await tester.pump();
    expect(api.submitCalls, 1);
    expect(api.lastRequest?.yearsOfExperience, 80);
  });

  testWidgets('years of experience keeps 0 as 0, not null', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);
    await _selectSpecialty(tester);
    await tester.enterText(_license(), 'LIC-1');
    await tester.enterText(_years(), '0');
    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();

    expect(api.submitCalls, 1);
    expect(api.lastRequest?.yearsOfExperience, 0);
  });

  testWidgets('submit sends the exact form values once and renders the authoritative pending state', (tester) async {
    final gate = Completer<DoctorApplication>();
    final api = _FakeApi()..submitGate = gate;
    await _pump(tester, api: api);

    await _selectSpecialty(tester);
    await tester.enterText(_license(), '  LIC-9  ');
    await tester.enterText(_field(_en.doctorApplicationSubSpecialtyLabel), 'Interventional');
    await tester.enterText(_years(), '12');
    await tester.enterText(_field(_en.doctorApplicationEducationLabel), 'Med school\n\nResidency');
    await tester.enterText(_field(_en.doctorApplicationCertificationsLabel), 'Board');
    await tester.enterText(_field(_en.doctorApplicationBioLabel), 'Bio text');

    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('doctor-application-submit')), warnIfMissed: false);
    await tester.pump();

    expect(api.submitCalls, 1);
    final request = api.lastRequest!;
    expect(request.specialtyId, 'spec-cardio');
    expect(request.medicalLicenseNumber, 'LIC-9');
    expect(request.subSpecialty, 'Interventional');
    expect(request.yearsOfExperience, 12);
    expect(request.education, ['Med school', 'Residency']);
    expect(request.certifications, ['Board']);
    expect(request.bio, 'Bio text');

    gate.complete(_application('new'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.doctorApplicationStatusHeading), findsOneWidget);
    expect(find.text(_en.doctorApplicationPendingBody), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsNothing);
  });

  testWidgets('submit ApiException renders safe localized copy, never the raw message', (tester) async {
    final api = _FakeApi()
      ..submitError = const ApiException(message: 'raw server validation text', code: 'VALIDATION_ERROR');
    await _pump(tester, api: api);
    await _selectSpecialty(tester);
    await tester.enterText(_license(), 'LIC-1');
    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.doctorApplicationError('VALIDATION_ERROR')), findsOneWidget);
    expect(find.textContaining('raw server validation text'), findsNothing);
  });

  testWidgets('unexpected submit exception maps to the generic safe message', (tester) async {
    final api = _FakeApi()..submitError = StateError('kaboom');
    await _pump(tester, api: api);
    await _selectSpecialty(tester);
    await tester.enterText(_license(), 'LIC-1');
    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.doctorApplicationError(ApiException.codeUnknown)), findsOneWidget);
    expect(find.textContaining('kaboom'), findsNothing);
  });

  testWidgets('withdraw: cancelling the confirmation does not call the API', (tester) async {
    final api = _FakeApi()..applicationsValue = [_application('a1')];
    await _pump(tester, api: api);

    await _tap(tester, const ValueKey('doctor-application-withdraw'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, _en.cancel));
    await tester.pumpAndSettle();

    expect(api.withdrawCalls, 0);
    expect(find.descendant(of: _statusCard(), matching: find.text(_en.doctorApplicationStatusPending)), findsOneWidget);
  });

  testWidgets('withdraw: confirming calls the API once with the right id and renders withdrawn', (tester) async {
    final api = _FakeApi()..applicationsValue = [_application('a1')];
    await _pump(tester, api: api);

    await _tap(tester, const ValueKey('doctor-application-withdraw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doctor-application-withdraw-confirm')));
    await tester.pumpAndSettle();

    expect(api.withdrawCalls, 1);
    expect(api.lastWithdrawId, 'a1');
    expect(find.text(_en.doctorApplicationWithdrawnBody), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-application-submit')), findsOneWidget);
  });

  testWidgets('withdraw failure shows safe localized error', (tester) async {
    final api = _FakeApi()
      ..applicationsValue = [_application('a1')]
      ..withdrawError = const ApiException(message: 'raw withdraw failure', code: 'NOT_FOUND');
    await _pump(tester, api: api);

    await _tap(tester, const ValueKey('doctor-application-withdraw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doctor-application-withdraw-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(_en.doctorApplicationError('NOT_FOUND')), findsOneWidget);
    expect(find.textContaining('raw withdraw failure'), findsNothing);
  });

  testWidgets('renders in Arabic RTL', (tester) async {
    await _pump(tester, api: _FakeApi(), isArabic: true);
    expect(Directionality.of(tester.element(find.byType(DoctorApplicationScreen))), TextDirection.rtl);
    expect(find.text(_ar.doctorApplicationTitle), findsOneWidget);
  });

  testWidgets('renders in English LTR', (tester) async {
    await _pump(tester, api: _FakeApi());
    expect(Directionality.of(tester.element(find.byType(DoctorApplicationScreen))), TextDirection.ltr);
    expect(find.text(_en.doctorApplicationTitle), findsOneWidget);
  });

  testWidgets('narrow viewport and large text scale do not overflow', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()
        ..applicationsValue = [_application('a1', status: 'rejected', rejectionReason: 'A' * 220)],
      isArabic: true,
      textScale: 1.9,
    );

    for (final size in const [Size(320, 900), Size(360, 900), Size(430, 900), Size(720, 380)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('disposing the screen during an in-flight submit does not throw', (tester) async {
    final gate = Completer<DoctorApplication>();
    final api = _FakeApi()..submitGate = gate;
    await _pump(tester, api: api);
    await _selectSpecialty(tester);
    await tester.enterText(_license(), 'LIC-1');
    await _tap(tester, const ValueKey('doctor-application-submit'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    gate.complete(_application('new'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

// ── helpers ──────────────────────────────────────────────────────────────


Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'patient',
  bool isArabic = false,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(620, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer(overrides: [
    doctorApplicationApiProvider.overrideWithValue(api),
    secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
    authControllerProvider.overrideWith((ref) => _FakeAuth(role)),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/doctor-application',
    routes: [
      GoRoute(path: '/doctor-application', builder: (_, _) => const DoctorApplicationScreen()),
      GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('login', key: ValueKey('login')))),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light(isArabic: isArabic),
      routerConfig: router,
      builder: (context, child) => Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Future<void> _selectSpecialty(WidgetTester tester) async {
  await _tap(tester, const ValueKey('doctor-application-specialty-field'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('specialty-option-spec-cardio')));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );

Finder _license() => _field(_en.doctorApplicationLicenseLabel);
Finder _years() => _field(_en.doctorApplicationExperienceLabel);

class _FakeApi extends DoctorApplicationApi {
  _FakeApi() : super(Dio());

  List<DoctorApplication> applicationsValue = const [];
  Object? applicationsError;
  Completer<List<DoctorApplication>>? applicationsGate;

  List<Specialty> specialtyValue = [_cardiology];

  Completer<DoctorApplication>? submitGate;
  Object? submitError;

  Object? withdrawError;

  int applicationLoads = 0;
  int submitCalls = 0;
  int withdrawCalls = 0;
  DoctorApplicationRequest? lastRequest;
  String? lastWithdrawId;

  @override
  Future<List<DoctorApplication>> loadMyApplications() {
    applicationLoads++;
    if (applicationsGate != null) return applicationsGate!.future;
    if (applicationsError != null) return Future.error(applicationsError!);
    return Future.value(applicationsValue);
  }

  @override
  Future<List<Specialty>> loadSpecialties() => Future.value(specialtyValue);

  @override
  Future<DoctorApplication> submitApplication(DoctorApplicationRequest request) {
    submitCalls++;
    lastRequest = request;
    if (submitGate != null) return submitGate!.future;
    if (submitError != null) return Future.error(submitError!);
    return Future.value(_application('new'));
  }

  @override
  Future<DoctorApplication> withdrawApplication(String id) {
    withdrawCalls++;
    lastWithdrawId = id;
    if (withdrawError != null) return Future.error(withdrawError!);
    return Future.value(_application(id, status: 'withdrawn'));
  }
}

class _FakeAuth extends AuthController {
  _FakeAuth(String role)
      : super(
          AuthRepository(AuthApi(Dio()), SecureStorageService(storage: _MemoryStorage())),
          GoogleAuthService(),
          SecureStorageService(storage: _MemoryStorage()),
        ) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: UserModel(id: 'user-1', email: 'p@example.com', role: role),
    );
  }

  @override
  Future<void> logout() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
