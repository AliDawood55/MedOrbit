import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/symptom_checker/data/symptom_checker_api.dart';
import 'package:mobile/features/symptom_checker/models/symptom_check_result.dart';
import 'package:mobile/features/symptom_checker/providers/symptom_checker_provider.dart';
import 'package:mobile/features/symptom_checker/screens/symptom_checker_screen.dart';
import 'package:mobile/routes/route_paths.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

SymptomCheckResult _result({TriageLevel triageLevel = TriageLevel.routine}) {
  return SymptomCheckResult(
    id: 'triage-1',
    symptoms: const ['headache'],
    triageLevel: triageLevel,
    confidenceScore: 0.5,
    recommendations: 'See a general practitioner if symptoms persist.',
    followUpAction: 'book_appointment',
    recommendedSpecialtyNameEn: 'General Practice',
    recommendedSpecialtyNameAr: 'طب عام',
  );
}

/// The screen is long — disclaimer, input, and (once submitted) a result
/// card laid out end-to-end exceed the default 800x600 test surface, which
/// makes `tester.tap()` fail to hit-test below-the-fold widgets.
Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('renders the disclaimer and the symptom input', (tester) async {
    final api = _FakeSymptomCheckerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.symptomCheckerDisclaimer), findsOneWidget);
    expect(find.text(_strings.symptomInputLabel), findsWidgets);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('submitting with no symptoms shows a validation message and does not call the API', (tester) async {
    final api = _FakeSymptomCheckerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit));
    await tester.pump();

    expect(find.text(_strings.symptomCheckerErrorMinSymptoms), findsOneWidget);
    expect(api.checkSymptomsCalls, isEmpty);
  });

  testWidgets('shows a loading state on the submit button while a check is in flight', (tester) async {
    final completer = Completer<SymptomCheckResult>();
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(completer.future);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'headache');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_result());
    await tester.pump();
  });

  testWidgets('a successful check renders the result: level, specialty, confidence, recommendations', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'headache');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.symptomRoutineTitle), findsOneWidget);
    expect(find.text('General Practice'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('See a general practitioner if symptoms persist.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing, reason: 'the input is replaced by the result, not shown alongside it');
  });

  testWidgets('an emergency result shows the emergency banner and the PRCS 101 message', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result(triageLevel: TriageLevel.emergency));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'severe chest pain');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.symptomEmergencyTitle), findsOneWidget);
    expect(find.text(_strings.symptomEmergencyMessage), findsOneWidget);
    expect(find.textContaining('101'), findsOneWidget);
  });

  testWidgets('a failed check shows a safe error with retry, and retry can succeed', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeSymptomCheckerApi()
      ..checkSymptomsResults.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      )
      ..checkSymptomsResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'headache');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.symptomCheckerServiceUnavailableError), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.symptomRoutineTitle), findsOneWidget);
    expect(api.checkSymptomsCalls, hasLength(2));
  });

  testWidgets('"check other symptoms" resets back to an empty input', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'headache');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.symptomCheckAnotherAction));
    await tester.pump();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('headache'), findsNothing);
    expect(find.text(_strings.symptomRoutineTitle), findsNothing);
  });

  testWidgets('the keyboard opening does not make the submit button unreachable', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    await tester.pumpWidget(_app(api: api, viewInsetsBottom: 300));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'headache');
    final submitButton = find.widgetWithText(ElevatedButton, _strings.symptomCheckerSubmit);
    await tester.ensureVisible(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    await tester.pumpWidget(_app(api: api, isArabic: true, direction: TextDirection.rtl, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextFormField), 'صداع');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the home quick action navigates to the Symptom Checker screen', (tester) async {
    final api = _FakeSymptomCheckerApi();
    final router = GoRouter(
      initialLocation: '/home-stub',
      routes: [
        GoRoute(
          path: '/home-stub',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(RoutePaths.symptomChecker),
              child: Text(_strings.symptomCheckerTitle),
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.symptomChecker,
          builder: (context, state) => const SymptomCheckerScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          symptomCheckerApiProvider.overrideWithValue(api),
          secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
        ],
        child: MaterialApp.router(
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(_strings.symptomCheckerTitle));
    await tester.pumpAndSettle();

    expect(find.text(_strings.symptomCheckerDisclaimer), findsOneWidget);
  });
}

Widget _app({
  required SymptomCheckerApi api,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  double viewInsetsBottom = 0,
}) {
  return ProviderScope(
    overrides: [
      symptomCheckerApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: isArabic),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
        ),
        child: Directionality(
          textDirection: direction,
          child: const SymptomCheckerScreen(),
        ),
      ),
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}

  @override
  Future<String?> getThemeMode() async => null;

  @override
  Future<void> saveThemeMode(String mode) async {}
}

class _FakeSymptomCheckerApi extends SymptomCheckerApi {
  _FakeSymptomCheckerApi() : super(Dio());

  final checkSymptomsResults = <Object>[];
  final checkSymptomsCalls = <List<String>>[];

  @override
  Future<SymptomCheckResult> checkSymptoms(List<String> symptoms) {
    checkSymptomsCalls.add(symptoms);
    final next = checkSymptomsResults.removeAt(0);
    if (next is Future<SymptomCheckResult>) return next;
    if (next is SymptomCheckResult) return Future.value(next);
    return Future.error(next);
  }
}
