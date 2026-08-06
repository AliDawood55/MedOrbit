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
import 'package:mobile/features/report_summarizer/data/report_summarizer_api.dart';
import 'package:mobile/features/report_summarizer/models/report_summary_result.dart';
import 'package:mobile/features/report_summarizer/providers/report_summarizer_provider.dart';
import 'package:mobile/features/report_summarizer/screens/report_summarizer_screen.dart';
import 'package:mobile/routes/route_paths.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

const _longEnoughReport =
    'Patient has blood pressure 150/95, headache, dizziness, and no chest pain.';

ReportSummaryResult _result() {
  return const ReportSummaryResult(
    id: 'summary-1',
    summaryAr: 'ملخص الحالة',
    summaryEn: 'Patient summary text',
    extractedText: 'Extracted report text goes here.',
    processingTimeMs: 16050,
    modelUsed: 'qwen2:7b',
    sourceFileType: 'text',
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
  testWidgets('renders the disclaimer and the report input', (tester) async {
    final api = _FakeReportSummarizerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.reportSummaryDisclaimer), findsOneWidget);
    expect(find.text(_strings.reportInputLabel), findsWidgets);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('submitting empty text shows a validation message and does not call the API', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, _strings.summarizeReport));
    await tester.pump();

    expect(find.text(_strings.reportSummaryEmptyError), findsOneWidget);
    expect(api.summarizeTextCalls, isEmpty);
  });

  testWidgets('shows a loading state on the submit button while a summary is in flight', (tester) async {
    await _useTallSurface(tester);
    final completer = Completer<ReportSummaryResult>();
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(completer.future);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), _longEnoughReport);
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.summarizeReport));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_result());
    await tester.pump();
  });

  testWidgets('a successful summary renders both language summaries and the metadata', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), _longEnoughReport);
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.summarizeReport));
    await tester.pump();
    await tester.pump();

    expect(find.text('ملخص الحالة'), findsOneWidget);
    expect(find.text('Patient summary text'), findsOneWidget);
    expect(find.text('qwen2:7b'), findsOneWidget);
    expect(find.text('16.1s'), findsOneWidget);
    expect(find.text('text'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing, reason: 'the input is replaced by the result, not shown alongside it');
  });

  testWidgets('a failed check shows a safe error with retry, and retry can succeed', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi()
      ..summarizeTextResults.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      )
      ..summarizeTextResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), _longEnoughReport);
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.summarizeReport));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.reportSummarizerServiceUnavailableError), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry));
    await tester.pump();
    await tester.pump();

    expect(find.text('Patient summary text'), findsOneWidget);
    expect(api.summarizeTextCalls, hasLength(2));
  });

  testWidgets('"summarize another report" resets back to an empty input', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), _longEnoughReport);
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.summarizeReport));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.reportSummarizeAnotherAction));
    await tester.pump();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text(_longEnoughReport), findsNothing);
    expect(find.text('Patient summary text'), findsNothing);
  });

  testWidgets('the keyboard opening does not make the submit button unreachable', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    await tester.pumpWidget(_app(api: api, viewInsetsBottom: 300));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), _longEnoughReport);
    final submitButton = find.widgetWithText(ElevatedButton, _strings.summarizeReport);
    await tester.ensureVisible(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    await tester.pumpWidget(_app(api: api, isArabic: true, direction: TextDirection.rtl, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextFormField), 'نص تقرير طبي كافٍ للاختبار.');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping upload does not crash when the platform file picker is unavailable', (tester) async {
    final api = _FakeReportSummarizerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.uploadReportFile));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(api.summarizeFileCalls, isEmpty);
  });

  testWidgets('a selected file shows its name, disables the text field, and submit summarizes the file', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi()..summarizeFileResults.add(_result());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReportSummarizerScreen)),
    );

    container
        .read(reportSummarizerControllerProvider.notifier)
        .selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);
    await tester.pump();

    expect(find.text(_strings.selectedReportFile('report.pdf')), findsOneWidget);
    final textField = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(textField.enabled, isFalse);

    await tester.tap(find.widgetWithText(ElevatedButton, _strings.summarizeUploadedReport));
    await tester.pump();
    await tester.pump();

    expect(api.summarizeFileCalls.single, (path: '/tmp/report.pdf', name: 'report.pdf'));
    expect(api.summarizeTextCalls, isEmpty);
  });

  testWidgets('selecting an unsupported file type shows a safe inline error', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReportSummarizerScreen)),
    );

    container
        .read(reportSummarizerControllerProvider.notifier)
        .selectFile(filePath: '/tmp/report.docx', fileName: 'report.docx', fileSizeBytes: 1024);
    await tester.pump();

    expect(find.text(_strings.unsupportedReportFile), findsOneWidget);
  });

  testWidgets('removing a selected file re-enables the text field and clears the selection', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeReportSummarizerApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReportSummarizerScreen)),
    );
    container
        .read(reportSummarizerControllerProvider.notifier)
        .selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, _strings.removeSelectedFile));
    await tester.pump();

    expect(find.text(_strings.selectedReportFile('report.pdf')), findsNothing);
    final textField = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(textField.enabled, isTrue);
    expect(find.widgetWithText(ElevatedButton, _strings.summarizeReport), findsOneWidget);
  });

  testWidgets('the home quick action navigates to the Report Summarizer screen', (tester) async {
    final api = _FakeReportSummarizerApi();
    final router = GoRouter(
      initialLocation: '/home-stub',
      routes: [
        GoRoute(
          path: '/home-stub',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(RoutePaths.reportSummarizer),
              child: Text(_strings.reportSummarizerTitle),
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.reportSummarizer,
          builder: (context, state) => const ReportSummarizerScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportSummarizerApiProvider.overrideWithValue(api),
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

    await tester.tap(find.text(_strings.reportSummarizerTitle));
    await tester.pumpAndSettle();

    expect(find.text(_strings.reportSummaryDisclaimer), findsOneWidget);
  });
}

Widget _app({
  required ReportSummarizerApi api,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  double viewInsetsBottom = 0,
}) {
  return ProviderScope(
    overrides: [
      reportSummarizerApiProvider.overrideWithValue(api),
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
          child: const ReportSummarizerScreen(),
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

class _FakeReportSummarizerApi extends ReportSummarizerApi {
  _FakeReportSummarizerApi() : super(Dio());

  final summarizeTextResults = <Object>[];
  final summarizeTextCalls = <String>[];
  final summarizeFileResults = <Object>[];
  final summarizeFileCalls = <({String path, String name})>[];

  @override
  Future<ReportSummaryResult> summarizeText({
    required String text,
    String? userId,
    String? recordId,
  }) {
    summarizeTextCalls.add(text);
    final next = summarizeTextResults.removeAt(0);
    if (next is Future<ReportSummaryResult>) return next;
    if (next is ReportSummaryResult) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<ReportSummaryResult> summarizeFile({
    required String filePath,
    required String fileName,
    String? userId,
    String? recordId,
  }) {
    summarizeFileCalls.add((path: filePath, name: fileName));
    final next = summarizeFileResults.removeAt(0);
    if (next is Future<ReportSummaryResult>) return next;
    if (next is ReportSummaryResult) return Future.value(next);
    return Future.error(next);
  }
}
