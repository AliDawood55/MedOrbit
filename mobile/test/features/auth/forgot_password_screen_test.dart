import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/locale/locale_controller.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/auth/screens/forgot_password_screen.dart';
import 'package:mobile/routes/route_paths.dart';

void main() {
  test('uses the verified forgot-password endpoint and email-only payload', () async {
    final dio = Dio();
    RequestOptions? request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(Response<void>(requestOptions: options, statusCode: 200));
        },
      ),
    );

    await AuthApi(dio).forgotPassword('patient@medorbit.com');

    expect(request?.method, 'POST');
    expect(request?.path, '/auth/forgot-password');
    expect(request?.data, {'email': 'patient@medorbit.com'});
  });

  testWidgets('validates required and malformed email locally', (tester) async {
    final controller = _ForgotPasswordController();
    await _pumpForgotPassword(tester, controller: controller);

    await tester.tap(find.text('Send Reset Link'));
    await tester.pump();
    expect(find.text('Email is required.'), findsOneWidget);
    expect(controller.calls, 0);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(controller.calls, 0);
  });

  testWidgets(
    'stale auth error never flashes and a new recovery failure is safely mapped',
    (tester) async {
      final controller = _ForgotPasswordController(
        initialErrorCode: 'INVALID_CREDENTIALS',
        failureCode: 'RATE_LIMITED',
      );

      await _pumpForgotPassword(
        tester,
        controller: controller,
        settle: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Could not complete the request. Please try again.'), findsNothing);
      expect(find.text('stale auth failure'), findsNothing);

      await tester.pump();
      expect(controller.state.errorMessage, isNull);

      await tester.enterText(find.byType(TextFormField), 'patient@medorbit.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Too many attempts. Please try again later.'), findsOneWidget);
      expect(find.text('raw backend failure'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('submits a trimmed email once and shows privacy-safe success', (tester) async {
    final controller = _ForgotPasswordController();
    await _pumpForgotPassword(tester, controller: controller);

    await tester.enterText(find.byType(TextFormField), '  patient@medorbit.com  ');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(controller.emails, ['patient@medorbit.com']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('If the email exists, a reset link has been sent.'), findsOneWidget);
    expect(find.textContaining('registered'), findsNothing);
  });

  testWidgets('prevents duplicate in-flight submissions', (tester) async {
    final pending = Completer<void>();
    final controller = _ForgotPasswordController(pending: pending);
    await _pumpForgotPassword(tester, controller: controller);

    await tester.enterText(find.byType(TextFormField), 'patient@medorbit.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(controller.calls, 1);

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('maps rate limits and transport failures without raw backend text', (tester) async {
    for (final testCase in [
      ('RATE_LIMITED', 'Too many attempts. Please try again later.'),
      (ApiException.codeServiceUnavailable, 'Could not reach the service. Check your connection and try again.'),
    ]) {
      final controller = _ForgotPasswordController(failureCode: testCase.$1);
      await _pumpForgotPassword(tester, controller: controller);
      await tester.enterText(find.byType(TextFormField), 'patient@medorbit.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text(testCase.$2), findsOneWidget);
      expect(find.text('raw backend failure'), findsNothing);

      await tester.enterText(find.byType(TextFormField), 'next@medorbit.com');
      await tester.pump();
      expect(find.text(testCase.$2), findsNothing);

      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      expect(controller.calls, 2);
    }
  });

  testWidgets('returns to Login and remains usable with Arabic large text across supported sizes', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _ForgotPasswordController();
    await _pumpForgotPassword(tester, controller: controller, locale: const Locale('ar'), textScale: 1.8);

    expect(Directionality.of(tester.element(find.byType(ForgotPasswordScreen))), TextDirection.rtl);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.textDirection, TextDirection.ltr);
    for (final size in const [
      Size(320, 700),
      Size(360, 700),
      Size(390, 700),
      Size(430, 700),
      Size(600, 700),
      Size(700, 360),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await tester.binding.setSurfaceSize(const Size(390, 700));
    await tester.pump();
    await tester.ensureVisible(find.byType(TextButton));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-destination')), findsOneWidget);
  });
}

Future<void> _pumpForgotPassword(
  WidgetTester tester, {
  required _ForgotPasswordController controller,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool settle = true,
}) async {
  final storage = SecureStorageService(storage: _MemoryStorage());
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      authControllerProvider.overrideWith((ref) => controller),
    ],
  );
  addTearDown(container.dispose);
  await container.read(localeControllerProvider.notifier).setLocale(locale);
  final router = GoRouter(
    initialLocation: RoutePaths.forgotPassword,
    routes: [
      GoRoute(path: RoutePaths.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) => const Scaffold(body: Text('Login', key: ValueKey('login-destination'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(isArabic: locale.languageCode == 'ar'),
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
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
  if (settle) await tester.pumpAndSettle();
}

class _ForgotPasswordController extends AuthController {
  _ForgotPasswordController({
    this.pending,
    this.failureCode,
    String? initialErrorCode,
  })
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService(storage: _MemoryStorage())),
        GoogleAuthService(),
        SecureStorageService(storage: _MemoryStorage()),
      ) {
    if (initialErrorCode != null) {
      state = state.copyWith(
        errorCode: initialErrorCode,
        errorMessage: 'stale auth failure',
      );
    }
  }

  final Completer<void>? pending;
  final String? failureCode;
  final List<String> emails = [];
  int calls = 0;

  @override
  Future<bool> forgotPassword(String email) async {
    if (state.isSubmitting) return false;
    calls++;
    emails.add(email);
    state = state.copyWith(isSubmitting: true, clearError: true);
    await pending?.future;
    if (failureCode != null) {
      state = state.copyWith(
        isSubmitting: false,
        errorCode: failureCode,
        errorMessage: 'raw backend failure',
      );
      return false;
    }
    state = state.copyWith(isSubmitting: false);
    return true;
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
