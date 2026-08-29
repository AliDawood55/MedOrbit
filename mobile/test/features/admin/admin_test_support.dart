import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/routes/route_paths.dart';

/// Shared harness for the administration screen tests.
///
/// Every admin screen sits behind `AdminGate`, which reads the canonical auth
/// state — so a screen test is only meaningful when the signed-in role is
/// controlled explicitly. [pumpAdminScreen] does that, plus locale, viewport
/// and text-scale control, without any screen needing a bespoke setup.
const AppStrings en = AppStrings(false);
const AppStrings ar = AppStrings(true);

const String adminActorId = 'actor-1';

/// A route the admin screens can pop to / redirect to during a test.
const String fallbackRoutePath = RoutePaths.home;

Future<void> pumpAdminScreen(
  WidgetTester tester, {
  required Widget screen,
  List<Override> overrides = const [],
  String role = 'admin',
  String actorId = adminActorId,
  bool isArabic = false,
  double textScale = 1,
  Size surfaceSize = const Size(420, 1400),
  List<GoRoute> extraRoutes = const [],
  String initialLocation = '/screen',
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(
        FakeLocaleStorage(isArabic ? 'ar' : 'en'),
      ),
      authControllerProvider.overrideWith(
        (ref) => FakeAuthController(role: role, userId: actorId),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/screen', builder: (_, _) => screen),
      GoRoute(
        path: fallbackRoutePath,
        builder: (_, _) =>
            const Scaffold(body: Text('home', key: ValueKey('home'))),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) =>
            const Scaffold(body: Text('login', key: ValueKey('login'))),
      ),
      GoRoute(
        path: RoutePaths.profile,
        builder: (_, _) =>
            const Scaffold(body: Text('profile', key: ValueKey('profile'))),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        builder: (_, _) => const Scaffold(
          body: Text('notifications', key: ValueKey('notifications')),
        ),
      ),
      ...extraRoutes,
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(isArabic: isArabic),
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

/// Taps [key] after scrolling it into view — admin lists are long enough that
/// a target is often off-screen at the default surface size.
Future<void> tapByKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

class FakeAuthController extends AuthController {
  FakeAuthController({required String role, required String userId})
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService(storage: _Memory())),
        GoogleAuthService(),
        SecureStorageService(storage: _Memory()),
      ) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: UserModel(
        id: userId,
        email: 'operator@medorbit.test',
        role: role,
      ),
    );
  }

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

class FakeLocaleStorage extends SecureStorageService {
  FakeLocaleStorage(this._languageCode);

  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

class _Memory implements FlutterSecureStorage {
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

/// Records every request a feature API makes and answers it from a queue of
/// canned responses, so tests can assert exact paths, methods and payloads.
class RecordingDio {
  RecordingDio({this.baseUrl = 'https://medorbit.test/api'})
    : dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          paths.add(options.path);
          methods.add(options.method);
          bodies.add(options.data);
          queries.add(Map<String, dynamic>.from(options.queryParameters));

          final responder = _responders.isEmpty
              ? _fallback
              : _responders.removeAt(0);
          final result = responder(options);
          if (result is DioException) {
            handler.reject(result);
            return;
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: result as Map<String, dynamic>,
            ),
          );
        },
      ),
    );
  }

  final String baseUrl;
  final Dio dio;
  final paths = <String>[];
  final methods = <String>[];
  final bodies = <Object?>[];
  final queries = <Map<String, dynamic>>[];

  final List<Object Function(RequestOptions)> _responders = [];
  Object Function(RequestOptions) _fallback =
      (_) => <String, dynamic>{'success': true, 'data': <dynamic>[]};

  void enqueue(Map<String, dynamic> body) => _responders.add((_) => body);

  void enqueueFailure(int statusCode, String code) {
    _responders.add(
      (options) => DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: statusCode,
          data: {
            'success': false,
            'error': {'code': code, 'message': 'raw backend detail'},
          },
        ),
      ),
    );
  }

  set fallback(Object Function(RequestOptions) responder) =>
      _fallback = responder;
}
