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
import 'package:mobile/features/drug_checker/data/drug_checker_api.dart';
import 'package:mobile/features/drug_checker/models/drug_check_result.dart';
import 'package:mobile/features/drug_checker/providers/drug_checker_provider.dart';
import 'package:mobile/features/drug_checker/screens/drug_checker_screen.dart';
import 'package:mobile/routes/route_paths.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

DrugCheckResult _result({
  bool hasInteractions = true,
  DrugSeverity severity = DrugSeverity.moderate,
}) {
  return DrugCheckResult(
    hasInteractions: hasInteractions,
    interactionCount: hasInteractions ? 1 : 0,
    interactions: hasInteractions
        ? [
            DrugInteraction(
              drug1NameEn: 'Aspirin',
              drug1NameAr: 'أسبرين',
              drug2NameEn: 'Warfarin',
              drug2NameAr: 'وارفارين',
              severity: severity,
              description: 'Increases bleeding risk.',
            ),
          ]
        : const [],
    severitySummary: hasInteractions ? {severity.name: 1} : const {},
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
  testWidgets('renders the disclaimer and the medication input', (tester) async {
    final api = _FakeDrugCheckerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.drugCheckerDisclaimer), findsOneWidget);
    expect(find.text(_strings.drugInputLabel), findsWidgets);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('submitting with fewer than 2 medications shows a validation message and does not call the API', (tester) async {
    final api = _FakeDrugCheckerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Aspirin');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();

    expect(find.text(_strings.drugCheckerErrorMinMeds), findsOneWidget);
    expect(api.checkInteractionsCalls, isEmpty);
  });

  testWidgets('shows a loading state on the submit button while a check is in flight', (tester) async {
    final completer = Completer<DrugCheckResult>();
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(completer.future);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Aspirin\nWarfarin');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_result());
    await tester.pump();
  });

  testWidgets('a successful check with no interactions renders the safe "no interactions found" state', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result(hasInteractions: false));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Paracetamol\nIbuprofen');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.drugNoInteractionsTitle), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing, reason: 'the input is replaced by the result, not shown alongside it');
  });

  testWidgets('a moderate interaction renders the severity and drug names, without the severe warning', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result(severity: DrugSeverity.moderate));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Aspirin\nWarfarin');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Aspirin'), findsWidgets);
    expect(find.textContaining('Warfarin'), findsWidgets);
    expect(find.textContaining(_strings.drugSeverityModerate), findsWidgets);
    expect(find.text(_strings.drugSevereWarning), findsNothing);
  });

  testWidgets('a severe interaction shows the extra prominent warning banner', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result(severity: DrugSeverity.severe));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Aspirin\nWarfarin');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.drugSevereWarning), findsOneWidget);
  });

  testWidgets('a failed check shows a safe error with retry, and retry can succeed', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()
      ..checkInteractionsResults.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      )
      ..checkInteractionsResults.add(_result(hasInteractions: false));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Aspirin\nWarfarin');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.drugCheckerServiceUnavailableError), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.drugNoInteractionsTitle), findsOneWidget);
    expect(api.checkInteractionsCalls, hasLength(2));
  });

  testWidgets('"check other medications" resets back to an empty input', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result(hasInteractions: false));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Paracetamol\nIbuprofen');
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.drugCheckAnotherAction));
    await tester.pump();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Paracetamol'), findsNothing);
    expect(find.text(_strings.drugNoInteractionsTitle), findsNothing);
  });

  testWidgets('the keyboard opening does not make the submit button unreachable', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result());
    await tester.pumpWidget(_app(api: api, viewInsetsBottom: 300));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'Aspirin\nWarfarin');
    final submitButton = find.widgetWithText(ElevatedButton, _strings.drugCheckerSubmit);
    await tester.ensureVisible(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result());
    await tester.pumpWidget(_app(api: api, isArabic: true, direction: TextDirection.rtl, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextFormField), 'أسبرين');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the home quick action navigates to the Drug Checker screen', (tester) async {
    final api = _FakeDrugCheckerApi();
    final router = GoRouter(
      initialLocation: '/home-stub',
      routes: [
        GoRoute(
          path: '/home-stub',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(RoutePaths.drugChecker),
              child: Text(_strings.drugCheckerTitle),
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.drugChecker,
          builder: (context, state) => const DrugCheckerScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          drugCheckerApiProvider.overrideWithValue(api),
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

    await tester.tap(find.text(_strings.drugCheckerTitle));
    await tester.pumpAndSettle();

    expect(find.text(_strings.drugCheckerDisclaimer), findsOneWidget);
  });
}

Widget _app({
  required DrugCheckerApi api,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  double viewInsetsBottom = 0,
}) {
  return ProviderScope(
    overrides: [
      drugCheckerApiProvider.overrideWithValue(api),
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
          child: const DrugCheckerScreen(),
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

class _FakeDrugCheckerApi extends DrugCheckerApi {
  _FakeDrugCheckerApi() : super(Dio());

  final checkInteractionsResults = <Object>[];
  final checkInteractionsCalls = <List<String>>[];

  @override
  Future<DrugCheckResult> checkInteractions(List<String> medicationNames) {
    checkInteractionsCalls.add(medicationNames);
    final next = checkInteractionsResults.removeAt(0);
    if (next is Future<DrugCheckResult>) return next;
    if (next is DrugCheckResult) return Future.value(next);
    return Future.error(next);
  }
}
