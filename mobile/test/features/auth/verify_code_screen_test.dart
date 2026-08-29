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
import 'package:mobile/features/auth/screens/verify_code_screen.dart';
import 'package:mobile/features/auth/widgets/otp_code_input.dart';
import 'package:mobile/routes/route_paths.dart';

// Shape of a real verification link token: 32 random bytes as hex (64 chars).
final _link = 'a1b2c3d4' * 8;

Finder _otpBox(int index) =>
    find.descendant(of: find.byType(OtpCodeInput), matching: find.byType(TextField)).at(index);

void main() {
  group('AuthApi payload shape', () {
    test('link verification sends the exact token and no email', () async {
      final request = await _capture(
        (dio) => AuthApi(dio).verifyEmail(token: _link),
      );
      expect(request.method, 'POST');
      expect(request.path, '/auth/verify-email');
      expect(request.data, {'token': _link});
    });

    test('OTP verification sends token plus the normalized email', () async {
      final request = await _capture(
        (dio) => AuthApi(dio).verifyEmail(token: '123456', email: 'user@example.com'),
      );
      expect(request.data, {'token': '123456', 'email': 'user@example.com'});
    });

    test('resend sends only the email', () async {
      final request = await _capture(
        (dio) => AuthApi(dio).resendVerification('user@example.com'),
      );
      expect(request.path, '/auth/resend-verification');
      expect(request.data, {'email': 'user@example.com'});
    });
  });

  testWidgets('a link token auto-verifies exactly once, sends the raw token, no email', (tester) async {
    final pending = Completer<void>();
    final controller = _VerifyController(_storage(), pending: pending);
    await _pump(tester, controller: controller, initialToken: _link);

    // Auto-verify fires on the first frame and shows an intentional loading state.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(controller.verifyCalls, [(token: _link, email: null)]);

    // Extra frames must not schedule a second verification.
    await tester.pump();
    await tester.pump();
    expect(controller.verifyCalls, hasLength(1));

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Email verified'), findsOneWidget);
    expect(find.text('Your account is ready. You can log in now.'), findsOneWidget);

    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-destination')), findsOneWidget);
  });

  testWidgets('a failed link verification maps safely and reveals the manual form', (tester) async {
    final controller = _VerifyController(
      _storage(),
      failureCode: 'INVALID_VERIFICATION_TOKEN',
    );
    await _pump(tester, controller: controller, initialToken: _link);
    await tester.pumpAndSettle();

    expect(find.text('That verification code is incorrect. Try again.'), findsOneWidget);
    expect(find.text('raw verify server failure'), findsNothing);
    expect(find.byType(OtpCodeInput), findsOneWidget); // manual form is now visible
  });

  testWidgets('validates the code length and the email before calling the API', (tester) async {
    final controller = _VerifyController(_storage());
    await _pump(tester, controller: controller);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Verify Now'));
    await tester.pump();
    expect(find.text('Enter all six digits.'), findsOneWidget);
    expect(controller.verifyCalls, isEmpty);

    // A full code auto-submits; verification is still blocked with no email.
    await tester.enterText(_otpBox(0), '123456');
    await tester.pump();
    expect(find.text('Email is required.'), findsOneWidget);
    expect(controller.verifyCalls, isEmpty);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Verify Now'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(controller.verifyCalls, isEmpty);
  });

  testWidgets('OTP + typed email sends the exact normalized payload and shows success', (tester) async {
    final controller = _VerifyController(_storage());
    await _pump(tester, controller: controller);

    await tester.enterText(find.byType(TextFormField).first, '  User@Example.COM ');
    await tester.enterText(_otpBox(0), '123456'); // auto-submits
    await tester.pumpAndSettle();

    expect(controller.verifyCalls, [(token: '123456', email: 'user@example.com')]);
    expect(find.text('Email verified'), findsOneWidget);
  });

  testWidgets('auto-complete and the Verify button cannot submit twice', (tester) async {
    final pending = Completer<void>();
    final controller = _VerifyController(_storage(), pending: pending);
    await _pump(tester, controller: controller, initialEmail: 'user@example.com');

    // Typing the whole code into the first box auto-completes and submits once.
    await tester.enterText(_otpBox(0), '123456');
    await tester.pump();
    // The button is a disabled loading spinner while the verify is in flight —
    // tapping it must not queue a second request.
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    expect(controller.verifyCalls, hasLength(1));

    pending.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('a double Verify tap cannot duplicate an in-flight request', (tester) async {
    final pending = Completer<void>();
    final controller = _VerifyController(_storage(), pending: pending);
    await _pump(
      tester,
      controller: controller,
      initialToken: '123456',
      initialEmail: 'user@example.com',
    );

    final button = find.widgetWithText(ElevatedButton, 'Verify Now');
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(controller.verifyCalls, hasLength(1));

    pending.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('maps verified verification errors and never renders raw server text', (tester) async {
    for (final testCase in const [
      ('INVALID_VERIFICATION_TOKEN', 'That verification code is incorrect. Try again.'),
      ('VERIFICATION_TOKEN_EXPIRED', 'That code has expired. Request a new one.'),
      ('VERIFICATION_TOKEN_USED', 'That code was already used. Try logging in.'),
      ('RATE_LIMITED', 'Too many attempts. Wait a while and try again.'),
      ('VALIDATION_ERROR', 'Check the email and code, then try again.'),
      (ApiException.codeServiceUnavailable, 'Could not reach the service. Check your connection and try again.'),
      ('INTERNAL_ERROR', 'Something went wrong. Please try again.'),
    ]) {
      final controller = _VerifyController(_storage(), failureCode: testCase.$1);
      await _pump(tester, controller: controller, initialEmail: 'user@example.com');

      await tester.enterText(_otpBox(0), '123456'); // auto-submits
      await tester.pump();
      await tester.pump();

      expect(find.text(testCase.$2), findsOneWidget);
      expect(find.text('raw verify server failure'), findsNothing);
    }
  });

  testWidgets('a stale auth error from another screen never flashes and no lifecycle exception is thrown', (tester) async {
    final controller = _VerifyController(
      _storage(),
      initialErrorCode: 'INVALID_CREDENTIALS',
    );
    await _pump(tester, controller: controller, initialEmail: 'user@example.com', settle: false);

    expect(tester.takeException(), isNull);
    expect(find.text('stale auth failure'), findsNothing);
    expect(find.text('Incorrect email or password.'), findsNothing);

    await tester.pump();
    expect(controller.state.errorMessage, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resend sends the exact normalized email, is single-flight, and restarts the countdown', (tester) async {
    final pending = Completer<void>();
    final controller = _VerifyController(_storage(), resendPending: pending);
    await _pump(tester, controller: controller);

    await tester.enterText(find.byType(TextFormField).first, ' User@Example.COM ');
    await tester.pump();

    final resend = find.widgetWithText(TextButton, 'Resend code');
    await tester.tap(resend);
    await tester.tap(resend, warnIfMissed: false);
    await tester.pump();
    expect(controller.resendCalls, ['user@example.com']);

    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('A new code was sent if the account is eligible.'), findsOneWidget);
    expect(find.textContaining('Resend in'), findsOneWidget); // countdown restarted
  });

  testWidgets('verify and resend cannot run at the same time', (tester) async {
    final verifyPending = Completer<void>();
    final controller = _VerifyController(_storage(), pending: verifyPending);
    // No registration email → no countdown, so resend is gated only by the
    // in-flight guard we are exercising here.
    await _pump(tester, controller: controller);

    await tester.enterText(find.byType(TextFormField).first, 'user@example.com');
    await tester.enterText(_otpBox(0), '123456'); // auto-submits
    await tester.pump();
    expect(controller.verifyCalls, hasLength(1));

    // Resend is disabled while a verify is in flight.
    await tester.tap(find.widgetWithText(TextButton, 'Resend code'), warnIfMissed: false);
    await tester.pump();
    expect(controller.resendCalls, isEmpty);

    verifyPending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('is RTL-safe, keeps the email field LTR, and has no scaled/small/landscape overflow', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _VerifyController(_storage());
    await _pump(
      tester,
      controller: controller,
      locale: const Locale('ar'),
      textScale: 1.8,
    );

    expect(
      Directionality.of(tester.element(find.byType(VerifyCodeScreen))),
      TextDirection.rtl,
    );

    final emailEditable = find.descendant(
      of: find.byType(TextFormField),
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(emailEditable.first).textDirection,
      TextDirection.ltr,
    );

    for (final size in const [
      Size(320, 720),
      Size(360, 720),
      Size(390, 720),
      Size(430, 720),
      Size(600, 720),
      Size(720, 380),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}

Future<RequestOptions> _capture(Future<void> Function(Dio dio) run) async {
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
  await run(dio);
  return request!;
}

Future<void> _pump(
  WidgetTester tester, {
  required _VerifyController controller,
  String? initialToken,
  String? initialEmail,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      // LocaleController persists through secureStorageProvider; without a fake
      // the real flutter_secure_storage platform channel never answers in a
      // widget test and setLocale() hangs.
      secureStorageProvider.overrideWithValue(_storage()),
      authControllerProvider.overrideWith((ref) => controller),
    ],
  );
  addTearDown(container.dispose);
  await container.read(localeControllerProvider.notifier).setLocale(locale);

  final router = GoRouter(
    initialLocation: RoutePaths.verifyCode,
    routes: [
      GoRoute(
        path: RoutePaths.verifyCode,
        builder: (_, _) => VerifyCodeScreen(
          initialToken: initialToken,
          initialEmail: initialEmail,
        ),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) =>
            const Scaffold(body: Text('Login', key: ValueKey('login-destination'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  // Unmount before the container/router teardowns so VerifyCodeScreen.dispose()
  // cancels its resend-countdown Timer (a leaked periodic Timer fails the test).
  addTearDown(() => tester.pumpWidget(const SizedBox()));

  // The default 800x600 test surface leaves the Verify / Resend controls below
  // the fold; a taller surface keeps every control hit-testable.
  await tester.binding.setSurfaceSize(const Size(600, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(isArabic: locale.languageCode == 'ar'),
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection:
              locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pump();
}

class _VerifyController extends AuthController {
  _VerifyController(
    SecureStorageService storage, {
    this.pending,
    this.resendPending,
    this.failureCode,
    String? initialErrorCode,
  }) : super(AuthRepository(AuthApi(Dio()), storage), GoogleAuthService(), storage) {
    if (initialErrorCode != null) {
      state = state.copyWith(
        errorCode: initialErrorCode,
        errorMessage: 'stale auth failure',
      );
    }
  }

  final Completer<void>? pending;
  final Completer<void>? resendPending;
  final String? failureCode;
  final List<({String token, String? email})> verifyCalls = [];
  final List<String> resendCalls = [];

  @override
  Future<bool> verifyEmail({required String token, String? email}) async {
    if (state.isSubmitting) return false;
    verifyCalls.add((token: token, email: email));
    state = state.copyWith(isSubmitting: true, clearError: true);
    await pending?.future;
    if (failureCode != null) {
      state = state.copyWith(
        isSubmitting: false,
        errorCode: failureCode,
        errorMessage: 'raw verify server failure',
      );
      return false;
    }
    state = state.copyWith(isSubmitting: false);
    return true;
  }

  @override
  Future<bool> resendVerification(String email) async {
    if (state.isSubmitting) return false;
    resendCalls.add(email);
    state = state.copyWith(isSubmitting: true, clearError: true);
    await resendPending?.future;
    state = state.copyWith(isSubmitting: false);
    return true;
  }
}

SecureStorageService _storage() => SecureStorageService(storage: _MemoryStorage());

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
