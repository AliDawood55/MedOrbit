import 'dart:async';

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
import 'package:mobile/features/auth/screens/register_screen.dart';
import 'package:mobile/routes/route_paths.dart';

void main() {
  testWidgets(
    'Register remains usable at supported widths, large text, and both directions',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final direction in TextDirection.values) {
        final container = _container();
        addTearDown(container.dispose);
        await container
            .read(localeControllerProvider.notifier)
            .setLocale(Locale(direction == TextDirection.rtl ? 'ar' : 'en'));

        for (final size in const [
          Size(320, 700),
          Size(430, 700),
          Size(600, 430),
        ]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light(isArabic: direction == TextDirection.rtl),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(1.8),
                  ),
                  child: Directionality(
                    textDirection: direction,
                    child: const RegisterScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(find.byType(RegisterScreen), findsOneWidget);
          expect(find.byType(AutofillGroup), findsOneWidget);
          expect(find.byType(TextFormField), findsNWidgets(8));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'requires the creation password policy, confirmation, and consent',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pumpRegister(tester, container);

      await _fillRequiredFields(tester, password: 'password');
      final submit = find.text('Continue to verification');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(
        find.text(
          'Use 8+ characters including uppercase, lowercase, a number, and a special character.',
        ),
        findsOneWidget,
      );
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(find.text('You must agree before continuing.'), findsOneWidget);
    },
  );

  testWidgets(
    'success routes to Verify Code with the normalized entered email',
    (tester) async {
      final storage = SecureStorageService(storage: _MemoryStorage());
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          authControllerProvider.overrideWith(
            (ref) => _SuccessController(storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('en'));

      final router = GoRouter(
        initialLocation: RoutePaths.register,
        routes: [
          GoRoute(
            path: RoutePaths.register,
            builder: (context, state) => const RegisterScreen(),
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

      await _fillRequiredFields(
        tester,
        email: ' Patient@MedOrbit.com ',
        password: 'Strong1!x',
        confirmPassword: 'Strong1!x',
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      final submit = find.text('Continue to verification');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('prefilled-email')), findsOneWidget);
      expect(find.text('patient@medorbit.com'), findsOneWidget);
    },
  );

  testWidgets(
    'shows a safe VALIDATION_ERROR message and clears it on correction',
    (tester) async {
      final storage = SecureStorageService(storage: _MemoryStorage());
      final controller = _FailingController(storage);
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          authControllerProvider.overrideWith((ref) => controller),
        ],
      );
      addTearDown(container.dispose);
      await _pumpRegister(tester, container);

      await _fillRequiredFields(
        tester,
        password: 'Strong1!x',
        confirmPassword: 'Strong1!x',
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      final submit = find.text('Continue to verification');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(
        find.text('Please review the information you entered and try again.'),
        findsOneWidget,
      );
      expect(find.text('Email already registered'), findsNothing);
      expect(controller.calls, 1);

      await tester.enterText(
        find.byType(TextFormField).at(4),
        'other@medorbit.com',
      );
      await tester.pump();
      expect(
        find.text('Please review the information you entered and try again.'),
        findsNothing,
      );
    },
  );

  testWidgets('maps RATE_LIMITED to a friendly localized message', (
    tester,
  ) async {
    final storage = SecureStorageService(storage: _MemoryStorage());
    final controller = _FailingController(storage, code: 'RATE_LIMITED');
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith((ref) => controller),
      ],
    );
    addTearDown(container.dispose);
    await _pumpRegister(tester, container);

    await _fillRequiredFields(
      tester,
      password: 'Strong1!x',
      confirmPassword: 'Strong1!x',
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    final submit = find.text('Continue to verification');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text('Too many attempts. Please try again later.'),
      findsOneWidget,
    );
    expect(find.text('Email already registered'), findsNothing);
  });

  testWidgets('disables registration while its request is in flight', (
    tester,
  ) async {
    final storage = SecureStorageService(storage: _MemoryStorage());
    final controller = _PendingController(storage);
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith((ref) => controller),
      ],
    );
    addTearDown(() {
      controller.complete();
      container.dispose();
    });
    await _pumpRegister(tester, container);

    await _fillRequiredFields(
      tester,
      password: 'Strong1!x',
      confirmPassword: 'Strong1!x',
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    final submit = find.text('Continue to verification');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(controller.calls, 1);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ElevatedButton && widget.onPressed == null,
      ),
      findsOneWidget,
    );
  });
}

ProviderContainer _container() {
  final storage = SecureStorageService(storage: _MemoryStorage());
  return ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(storage)],
  );
}

Future<void> _pumpRegister(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await container
      .read(localeControllerProvider.notifier)
      .setLocale(const Locale('en'));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(isArabic: false),
        home: const RegisterScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredFields(
  WidgetTester tester, {
  String email = 'patient@medorbit.com',
  required String password,
  String? confirmPassword,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'أحمد');
  await tester.enterText(fields.at(1), 'محمد');
  await tester.enterText(fields.at(2), 'Ahmed');
  await tester.enterText(fields.at(3), 'Mohammed');
  await tester.enterText(fields.at(4), email);
  await tester.enterText(fields.at(6), password);
  await tester.enterText(fields.at(7), confirmPassword ?? 'Different1!');
}

class _SuccessController extends AuthController {
  _SuccessController(SecureStorageService storage)
    : super(
        AuthRepository(AuthApi(Dio()), storage),
        GoogleAuthService(),
        storage,
      );

  @override
  Future<bool> register({
    required String email,
    required String password,
    required String firstNameAr,
    required String lastNameAr,
    required String firstNameEn,
    required String lastNameEn,
    String? phone,
    String? gender,
  }) async => true;
}

class _FailingController extends _SuccessController {
  _FailingController(super.storage, {this.code = 'VALIDATION_ERROR'});

  final String code;
  int calls = 0;

  @override
  Future<bool> register({
    required String email,
    required String password,
    required String firstNameAr,
    required String lastNameAr,
    required String firstNameEn,
    required String lastNameEn,
    String? phone,
    String? gender,
  }) async {
    calls++;
    state = state.copyWith(
      errorMessage: 'Email already registered',
      errorCode: code,
    );
    return false;
  }
}

class _PendingController extends _SuccessController {
  _PendingController(super.storage);

  final _completion = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> register({
    required String email,
    required String password,
    required String firstNameAr,
    required String lastNameAr,
    required String firstNameEn,
    required String lastNameEn,
    String? phone,
    String? gender,
  }) {
    calls++;
    state = state.copyWith(isSubmitting: true, clearError: true);
    return _completion.future;
  }

  void complete() {
    if (!_completion.isCompleted) _completion.complete(false);
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
