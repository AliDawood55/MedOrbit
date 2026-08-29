import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/locale/locale_controller.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/auth/screens/login_screen.dart';
import 'package:mobile/routes/route_paths.dart';

void main() {
  testWidgets(
    'Login stays usable at supported widths, large text, and both directions',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final direction in TextDirection.values) {
        final storage = SecureStorageService(storage: _MemoryStorage());
        final container = ProviderContainer(
          overrides: [secureStorageProvider.overrideWithValue(storage)],
        );
        addTearDown(container.dispose);
        await container
            .read(localeControllerProvider.notifier)
            .setLocale(Locale(direction == TextDirection.rtl ? 'ar' : 'en'));

        for (final width in const [320.0, 360.0, 390.0, 430.0]) {
          await tester.binding.setSurfaceSize(Size(width, 700));
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light(isArabic: direction == TextDirection.rtl),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.8)),
                    child: Directionality(
                      textDirection: direction,
                      child: const LoginScreen(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(find.byType(LoginScreen), findsOneWidget);
          expect(find.byType(AutofillGroup), findsOneWidget);
          expect(find.byType(TextFormField), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'unverified email offers verification and passes the entered email',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = SecureStorageService(storage: _MemoryStorage());
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          authControllerProvider.overrideWith(
            (ref) => _EmailNotVerifiedController(storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('en'));

      final router = GoRouter(
        initialLocation: RoutePaths.login,
        routes: [
          GoRoute(
            path: RoutePaths.login,
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: RoutePaths.verifyCode,
            builder: (context, state) => Scaffold(
              body: Text(
                state.uri.queryParameters['email'] ?? '',
                key: const ValueKey('prefilled-email'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(isArabic: false),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const email = 'patient@medorbit.com';
      await tester.enterText(find.byType(TextFormField).at(0), email);
      await tester.enterText(find.byType(TextFormField).at(1), 'password');
      final loginButton = find.text('Log In');
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      final verificationAction = find.byKey(
        const ValueKey('verify-email-action'),
      );
      expect(verificationAction, findsOneWidget);
      expect(
        find.text('Please verify your email before signing in.'),
        findsOneWidget,
      );

      await tester.tap(verificationAction);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('prefilled-email')), findsOneWidget);
      expect(find.text(email), findsOneWidget);
    },
  );
}

class _EmailNotVerifiedController extends AuthController {
  _EmailNotVerifiedController(SecureStorageService storage)
    : super(
        AuthRepository(AuthApi(Dio()), storage),
        GoogleAuthService(),
        storage,
      );

  @override
  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    await Future<void>.delayed(Duration.zero);
    state = state.copyWith(
      isSubmitting: false,
      errorMessage: 'technical backend text',
      errorCode: 'EMAIL_NOT_VERIFIED',
    );
    return false;
  }
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
