import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/doctor_workspace/data/doctor_workspace_api.dart';
import 'package:mobile/features/doctor_workspace/models/doctor_models.dart';
import 'package:mobile/features/doctor_workspace/providers/doctor_workspace_providers.dart';
import 'package:mobile/features/doctor_workspace/screens/doctor_appointments_screen.dart';
import 'package:mobile/features/doctor_workspace/screens/doctor_posts_screen.dart';
import 'package:mobile/features/doctor_workspace/screens/doctor_workspace_screen.dart';

void main() {
  testWidgets('approved doctor sees all workspace entry points', (
    tester,
  ) async {
    final api = _UiApi();
    await _pump(tester, api: api, child: const DoctorWorkspaceScreen());
    expect(find.text('Professional profile'), findsOneWidget);
    expect(find.text('Schedule & availability'), findsOneWidget);
    expect(find.text('Doctor appointments'), findsOneWidget);
    expect(find.text('My patients'), findsOneWidget);
    expect(find.text('My posts'), findsOneWidget);
    expect(find.text('Medical records'), findsOneWidget);
  });

  testWidgets('non-doctor is denied without loading doctor data', (
    tester,
  ) async {
    final api = _UiApi();
    await _pump(
      tester,
      api: api,
      role: 'patient',
      child: const DoctorWorkspaceScreen(),
    );
    expect(
      find.text('The doctor workspace is not available for this account.'),
      findsOneWidget,
    );
    expect(api.profileCalls, 0);
  });

  testWidgets('unapproved profile renders intentional eligibility state', (
    tester,
  ) async {
    final api = _UiApi(profile: _profile(approved: false));
    await _pump(tester, api: api, child: const DoctorWorkspaceScreen());
    expect(
      find.text(
        'Your doctor profile must be approved before using this workspace.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('raw backend error text is never rendered', (tester) async {
    final api = _UiApi(
      profileError: const ApiException(
        message: 'secret database detail',
        code: 'SERVICE_UNAVAILABLE',
      ),
    );
    await _pump(tester, api: api, child: const DoctorWorkspaceScreen());
    expect(find.textContaining('secret database'), findsNothing);
    expect(
      find.text(
        'Could not reach the service. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('workspace supports Arabic RTL on a narrow high-scale phone', (
    tester,
  ) async {
    final api = _UiApi();
    await _pump(
      tester,
      api: api,
      arabic: true,
      size: const Size(320, 700),
      textScale: 1.6,
      child: const DoctorWorkspaceScreen(),
    );
    expect(find.text('مساحة عمل الطبيب'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.byType(DoctorWorkspaceScreen))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('posts render server title and moderation state', (tester) async {
    final api = _UiApi(posts: [_post()]);
    await _pump(tester, api: api, child: const DoctorPostsScreen());
    expect(find.text('Server-authored title'), findsOneWidget);
    expect(find.text('Published'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Health tip'), findsOneWidget);
  });

  testWidgets('doctor appointment lifecycle actions follow server status', (
    tester,
  ) async {
    final api = _UiApi(schedule: _schedule());
    await _pump(tester, api: api, child: const DoctorAppointmentsScreen());
    expect(find.text('Noor'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _UiApi api,
  required Widget child,
  String role = 'doctor',
  bool arabic = false,
  Size size = const Size(700, 1600),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      appStringsProvider.overrideWithValue(AppStrings(arabic)),
      doctorWorkspaceApiProvider.overrideWithValue(api),
      authControllerProvider.overrideWith((ref) => _FakeAuth(role)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

DoctorProfile _profile({bool approved = true}) => DoctorProfile(
  id: 'doctor-1',
  approvalStatus: approved ? 'approved' : 'pending',
  isAcceptingPatients: true,
);
DoctorPost _post() => const DoctorPost(
  id: 'post-1',
  title: 'Server-authored title',
  category: 'health_tip',
  body: 'Server body',
  isPublished: true,
  status: 'published',
  moderationStatus: 'approved',
);
DoctorSchedule _schedule() => DoctorSchedule(
  bookingHorizonDays: 90,
  weekly: const [],
  overrides: const [],
  clinics: const [],
  appointments: [
    const DoctorAppointment(
      id: 'appt-1',
      number: 'APT-1',
      date: '2026-09-01',
      startTime: '09:00:00',
      endTime: '09:30:00',
      type: 'telemedicine',
      status: 'scheduled',
      firstNameEn: 'Noor',
    ),
  ],
);

class _UiApi extends DoctorWorkspaceApi {
  _UiApi({
    DoctorProfile? profile,
    this.profileError,
    this.posts = const [],
    DoctorSchedule? schedule,
  }) : profile = profile ?? _profile(),
       schedule =
           schedule ??
           DoctorSchedule(
             bookingHorizonDays: 90,
             weekly: const [],
             overrides: const [],
             clinics: const [],
             appointments: const [],
           ),
       super(Dio());
  final DoctorProfile profile;
  final Object? profileError;
  final List<DoctorPost> posts;
  final DoctorSchedule schedule;
  int profileCalls = 0;
  @override
  Future<DoctorProfile> getProfile() {
    profileCalls++;
    return profileError == null
        ? Future.value(profile)
        : Future.error(profileError!);
  }

  @override
  Future<List<DoctorPost>> getPosts() async => posts;
  @override
  Future<DoctorSchedule> getSchedule() async => schedule;
}

class _FakeAuth extends AuthController {
  _FakeAuth(String role)
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService()),
        GoogleAuthService(),
        SecureStorageService(),
      ) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: UserModel(id: 'user-1', email: 'doctor@example.test', role: role),
    );
  }
}
