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
import 'package:mobile/features/auth/screens/reset_password_screen.dart';
import 'package:mobile/routes/route_paths.dart';

void main() {
  test('uses the verified reset endpoint and exact payload', () async {
    final dio = Dio();
    RequestOptions? request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<void>(requestOptions: options, statusCode: 200),
          );
        },
      ),
    );

    await AuthApi(
      dio,
    ).resetPassword(token: 'token+/_=-value', newPassword: 'Strong1!');

    expect(request?.method, 'POST');
    expect(request?.path, '/auth/reset-password');
    expect(request?.data, {
      'token': 'token+/_=-value',
      'newPassword': 'Strong1!',
    });
  });

  testWidgets('preserves and populates the supplied reset token', (
    tester,
  ) async {
    const token = 'token+/_=-value';
    final controller = _ResetController(_storage());
    await _pumpReset(tester, controller: controller, initialToken: token);

    final tokenField = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).at(0),
        matching: find.byType(EditableText),
      ),
    );
    expect(tokenField.controller.text, token);
  });

  testWidgets('validates token, password policy, and confirmation', (
    tester,
  ) async {
    final controller = _ResetController(_storage());
    await _pumpReset(tester, controller: controller);
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(1), 'Strong1!');
    await tester.enterText(fields.at(2), 'Strong1!');
    await tester.tap(find.text('Set New Password'));
    await tester.pump();
    expect(find.text('Reset token is required.'), findsOneWidget);

    await tester.enterText(fields.at(0), 'reset-token');
    await tester.enterText(fields.at(1), 'weakpass');
    await tester.enterText(fields.at(2), 'weakpass');
    await tester.tap(find.text('Set New Password'));
    await tester.pump();
    expect(
      find.text(
        'Use 8+ characters including uppercase, lowercase, a number, and a special character.',
      ),
      findsOneWidget,
    );

    await tester.enterText(fields.at(1), 'Strong1!');
    await tester.enterText(fields.at(2), 'Different1!');
    await tester.tap(find.text('Set New Password'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(controller.calls, 0);
  });

  testWidgets('submits exact values, shows success, and returns to Login', (
    tester,
  ) async {
    const token = 'token+/_=-value';
    const password = 'Strong1!';
    final controller = _ResetController(_storage());
    await _pumpReset(tester, controller: controller, initialToken: token);
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(1), password);
    await tester.enterText(fields.at(2), password);
    await tester.tap(find.text('Set New Password'));
    await tester.pumpAndSettle();

    expect(controller.tokens, [token]);
    expect(controller.passwords, [password]);
    expect(find.text('Password updated'), findsOneWidget);
    expect(find.text('You can log in now.'), findsOneWidget);

    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-destination')), findsOneWidget);
  });

  testWidgets('button and keyboard Done cannot duplicate an in-flight reset', (
    tester,
  ) async {
    final pending = Completer<void>();
    final controller = _ResetController(_storage(), pending: pending);
    await _pumpReset(
      tester,
      controller: controller,
      initialToken: 'reset-token',
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Strong1!');
    await tester.enterText(fields.at(2), 'Strong1!');
    await tester.tap(fields.at(2));

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(controller.calls, 1);

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('maps verified reset errors and never renders raw server text', (
    tester,
  ) async {
    for (final testCase in [
      ('INVALID_TOKEN', 'This reset link is invalid or has expired.'),
      (
        'VALIDATION_ERROR',
        'Check the reset token and password requirements, then try again.',
      ),
      ('RATE_LIMITED', 'Too many attempts. Please try again later.'),
      (
        ApiException.codeServiceUnavailable,
        'Could not reach the service. Check your connection and try again.',
      ),
      ('INTERNAL_ERROR', 'Could not complete the request. Please try again.'),
    ]) {
      final controller = _ResetController(_storage(), failureCode: testCase.$1);
      await _pumpReset(
        tester,
        controller: controller,
        initialToken: 'reset-token',
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'Strong1!');
      await tester.enterText(fields.at(2), 'Strong1!');
      await tester.tap(find.text('Set New Password'));
      await tester.pumpAndSettle();

      expect(find.text(testCase.$2), findsOneWidget);
      expect(find.text('raw reset server failure'), findsNothing);

      await tester.enterText(fields.at(2), 'Strong2@');
      await tester.pump();
      expect(find.text(testCase.$2), findsNothing);
    }
  });

  testWidgets(
    'stale auth error never flashes and a new reset failure is safely mapped',
    (tester) async {
      final controller = _ResetController(
        _storage(),
        initialErrorCode: 'INVALID_CREDENTIALS',
        failureCode: 'INVALID_TOKEN',
      );
      await _pumpReset(
        tester,
        controller: controller,
        initialToken: 'reset-token',
        settle: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('stale auth failure'), findsNothing);
      expect(
        find.text('Could not complete the request. Please try again.'),
        findsNothing,
      );

      await tester.pump();
      expect(controller.state.errorMessage, isNull);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'Strong1!');
      await tester.enterText(fields.at(2), 'Strong1!');
      await tester.tap(find.text('Set New Password'));
      await tester.pumpAndSettle();

      expect(
        find.text('This reset link is invalid or has expired.'),
        findsOneWidget,
      );
      expect(find.text('raw reset server failure'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('is RTL-safe, keeps fields LTR, and has no scaled overflow', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _ResetController(_storage());
    await _pumpReset(
      tester,
      controller: controller,
      initialToken: 'reset-token',
      locale: const Locale('ar'),
      textScale: 1.8,
    );

    expect(
      Directionality.of(tester.element(find.byType(ResetPasswordScreen))),
      TextDirection.rtl,
    );
    final editables = find.descendant(
      of: find.byType(TextFormField),
      matching: find.byType(EditableText),
    );
    expect(editables, findsNWidgets(3));
    for (var index = 0; index < 3; index++) {
      expect(
        tester.widget<EditableText>(editables.at(index)).textDirection,
        TextDirection.ltr,
      );
    }

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
  });
}

Future<void> _pumpReset(
  WidgetTester tester, {
  required _ResetController controller,
  String? initialToken,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool settle = true,
}) async {
  final localeStorage = _storage();
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(localeStorage),
      authControllerProvider.overrideWith((ref) => controller),
    ],
  );
  addTearDown(container.dispose);
  await container.read(localeControllerProvider.notifier).setLocale(locale);

  final router = GoRouter(
    initialLocation: RoutePaths.resetPassword,
    routes: [
      GoRoute(
        path: RoutePaths.resetPassword,
        builder: (_, _) => ResetPasswordScreen(initialToken: initialToken),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) => const Scaffold(
          body: Text('Login', key: ValueKey('login-destination')),
        ),
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
  if (settle) await tester.pump();
}

class _ResetController extends AuthController {
  _ResetController(
    SecureStorageService storage, {
    this.pending,
    this.failureCode,
    String? initialErrorCode,
  }) : super(
         AuthRepository(AuthApi(Dio()), storage),
         GoogleAuthService(),
         storage,
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
  final List<String> tokens = [];
  final List<String> passwords = [];
  int calls = 0;

  @override
  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    if (state.isSubmitting) return false;
    calls++;
    tokens.add(token);
    passwords.add(newPassword);
    state = state.copyWith(isSubmitting: true, clearError: true);
    await pending?.future;
    if (failureCode != null) {
      state = state.copyWith(
        isSubmitting: false,
        errorCode: failureCode,
        errorMessage: 'raw reset server failure',
      );
      return false;
    }
    state = state.copyWith(isSubmitting: false);
    return true;
  }
}

SecureStorageService _storage() =>
    SecureStorageService(storage: _MemoryStorage());

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
