import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/my_reports/data/my_reports_api.dart';
import 'package:mobile/features/my_reports/models/my_report_item.dart';
import 'package:mobile/features/my_reports/providers/my_reports_provider.dart';
import 'package:mobile/features/my_reports/screens/my_reports_screen.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

MyReportItem _item({String id = 'summary-1'}) {
  return MyReportItem(
    id: id,
    type: MyReportType.reportSummary,
    createdAt: DateTime.parse('2026-08-01T09:00:00.000Z'),
    summaryAr: 'ملخص الحالة',
    summaryEn: 'Patient summary text',
    extractedTextPreview: 'Extracted text preview',
    modelUsed: 'qwen2:7b',
    sourceFileType: 'text',
  );
}

Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('shows a loading indicator while the initial list is in flight', (tester) async {
    final completer = Completer<List<MyReportItem>>();
    final api = _FakeMyReportsApi()..results.add(completer.future);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete([_item()]);
  });

  testWidgets('shows the empty state when there are no reports', (tester) async {
    final api = _FakeMyReportsApi()..results.add(<MyReportItem>[]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.myReportsEmptyTitle), findsOneWidget);
  });

  testWidgets('renders a card per report on success', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeMyReportsApi()..results.add([_item(), _item(id: 'summary-2')]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.myReportTypeSummary), findsNWidgets(2));
    expect(find.text(_strings.myReportsEmptyTitle), findsNothing);
  });

  testWidgets('"view details" expands a card to show the full summaries', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeMyReportsApi()..results.add([_item()]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.arabicSummary), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, _strings.myReportViewDetails));
    await tester.pump();

    expect(find.text(_strings.arabicSummary), findsOneWidget);
    expect(find.text(_strings.englishSummary), findsOneWidget);
  });

  testWidgets('shows a safe error with retry, and retry reloads the list', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeMyReportsApi()
      ..results.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      )
      ..results.add([_item()]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.myReportsLoadError), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry));
    await tester.pump();

    expect(find.text(_strings.myReportTypeSummary), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeMyReportsApi()..results.add([_item()]);
    await tester.pumpWidget(_app(api: api, isArabic: true, direction: TextDirection.rtl, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required MyReportsApi api,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      myReportsApiProvider.overrideWithValue(api),
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
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: const MyReportsScreen(),
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

class _FakeMyReportsApi extends MyReportsApi {
  _FakeMyReportsApi() : super(Dio());

  final results = <Object>[];

  @override
  Future<List<MyReportItem>> listReportSummaries() {
    final next = results.removeAt(0);
    if (next is Future<List<MyReportItem>>) return next;
    if (next is List<MyReportItem>) return Future.value(next);
    return Future.error(next);
  }
}
