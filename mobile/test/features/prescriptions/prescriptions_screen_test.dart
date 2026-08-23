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
import 'package:mobile/features/prescriptions/data/prescription_pdf_service.dart';
import 'package:mobile/features/prescriptions/data/prescriptions_api.dart';
import 'package:mobile/features/prescriptions/models/prescription_model.dart';
import 'package:mobile/features/prescriptions/providers/prescriptions_provider.dart';
import 'package:mobile/features/prescriptions/screens/prescriptions_screen.dart';

const _strings = AppStrings(false); // English, matching the default direction used below
const _canary = 'INTERNAL_ONLY_DO_NOT_RENDER';

/// A prescription built the same way the app builds one: parsed from a raw
/// backend-shaped payload that (like the real API today) includes the
/// internal `doctor_notes` field.
PrescriptionModel _prescriptionWithCanary() {
  return PrescriptionModel.fromJson({
    'id': '1',
    'prescription_number': 'RX-2026-001',
    'prescription_date': '2026-08-01',
    'valid_until': null,
    'status': 'active',
    'diagnosis': 'Seasonal flu',
    'instructions': 'Take twice daily with food',
    'doctor_notes': _canary,
    'items': [
      {
        'medication_name_en': 'Amoxicillin',
        'medication_name_ar': 'أموكسيسيلين',
        'dosage': '500mg',
        'frequency': 'Twice daily',
      },
    ],
  });
}

Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('the prescription list card never renders the internal doctor note', (tester) async {
    await _useTallSurface(tester);
    final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.textContaining(_canary), findsNothing);
    expect(find.text(_strings.doctorNotes), findsNothing);
    // Legitimate prescription data still renders.
    expect(find.text('Amoxicillin'), findsOneWidget);
  });

  testWidgets('the prescription detail sheet never renders the internal doctor note', (tester) async {
    await _useTallSurface(tester);
    final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.text(_strings.viewPrescriptionDetails));
    await tester.pumpAndSettle();

    expect(find.textContaining(_canary), findsNothing);
    expect(find.text(_strings.doctorNotes), findsNothing);
    // Legitimate prescription data still renders in the expanded detail
    // sheet (the underlying list card stays mounted behind the modal sheet,
    // so these legitimately appear twice: once in the card, once in the sheet).
    expect(find.text(_strings.detailInstructions), findsWidgets);
    expect(find.text('Take twice daily with food'), findsWidgets);
    expect(find.text('Amoxicillin'), findsWidgets);
  });

  group('prescription PDF action', () {
    Future<void> openDetailSheet(WidgetTester tester) async {
      await tester.tap(find.text(_strings.viewPrescriptionDetails));
      await tester.pumpAndSettle();
    }

    testWidgets('is visible in the prescription detail sheet', (tester) async {
      await _useTallSurface(tester);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      await tester.pumpWidget(_app(api: api, pdfService: _FakePrescriptionPdfService()));
      await tester.pump();
      await openDetailSheet(tester);

      expect(find.text(_strings.openPrescriptionPdf), findsOneWidget);
    });

    testWidgets('tapping it calls download exactly once', (tester) async {
      await _useTallSurface(tester);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      final pdfService = _FakePrescriptionPdfService();
      await tester.pumpWidget(_app(api: api, pdfService: pdfService));
      await tester.pump();
      await openDetailSheet(tester);

      await tester.tap(find.text(_strings.openPrescriptionPdf));
      await tester.pumpAndSettle();

      expect(pdfService.callCount, 1);
    });

    testWidgets('shows a busy state and ignores repeated taps while downloading', (tester) async {
      await _useTallSurface(tester);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      final pdfService = _FakePrescriptionPdfService()..gate = Completer<void>();
      await tester.pumpWidget(_app(api: api, pdfService: pdfService));
      await tester.pump();
      await openDetailSheet(tester);

      await tester.tap(find.text(_strings.openPrescriptionPdf));
      await tester.pump();
      // Still in-flight: busy label shown, and a second rapid tap must not
      // start a second download.
      expect(find.text(_strings.preparingPrescriptionPdf), findsOneWidget);
      await tester.tap(find.text(_strings.preparingPrescriptionPdf), warnIfMissed: false);
      await tester.pump();
      expect(pdfService.callCount, 1);

      pdfService.gate!.complete();
      await tester.pumpAndSettle();
      expect(pdfService.callCount, 1);
      expect(find.text(_strings.openPrescriptionPdf), findsOneWidget);
    });

    testWidgets('a successful download shows no error feedback', (tester) async {
      await _useTallSurface(tester);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      final pdfService = _FakePrescriptionPdfService();
      await tester.pumpWidget(_app(api: api, pdfService: pdfService));
      await tester.pump();
      await openDetailSheet(tester);

      await tester.tap(find.text(_strings.openPrescriptionPdf));
      await tester.pumpAndSettle();

      expect(find.text(_strings.prescriptionPdfDownloadFailed), findsNothing);
      expect(find.text(_strings.prescriptionPdfOpenFailed), findsNothing);
    });

    testWidgets('a download failure shows localized feedback', (tester) async {
      await _useTallSurface(tester);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      final pdfService = _FakePrescriptionPdfService()
        ..errorToThrow = const ApiException(message: 'boom', code: 'HTTP_ERROR');
      await tester.pumpWidget(_app(api: api, pdfService: pdfService));
      await tester.pump();
      await openDetailSheet(tester);

      await tester.tap(find.text(_strings.openPrescriptionPdf));
      await tester.pumpAndSettle();

      expect(find.text(_strings.prescriptionPdfDownloadFailed), findsOneWidget);
    });

    testWidgets('an open failure shows localized feedback', (tester) async {
      await _useTallSurface(tester);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      final pdfService = _FakePrescriptionPdfService()
        ..errorToThrow = const PrescriptionPdfOpenException();
      await tester.pumpWidget(_app(api: api, pdfService: pdfService));
      await tester.pump();
      await openDetailSheet(tester);

      await tester.tap(find.text(_strings.openPrescriptionPdf));
      await tester.pumpAndSettle();

      expect(find.text(_strings.prescriptionPdfOpenFailed), findsOneWidget);
    });

    testWidgets('remains usable at 2x text scale in RTL without overflow', (tester) async {
      await _useTallSurface(tester);
      const arStrings = AppStrings(true);
      final api = _FakePrescriptionsApi()..results.add([_prescriptionWithCanary()]);
      await tester.pumpWidget(
        _app(
          api: api,
          pdfService: _FakePrescriptionPdfService(),
          isArabic: true,
          direction: TextDirection.rtl,
          textScale: 2,
        ),
      );
      await tester.pump();
      await tester.tap(find.text(arStrings.viewPrescriptionDetails));
      await tester.pumpAndSettle();

      expect(find.text(arStrings.openPrescriptionPdf), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _app({
  required PrescriptionsApi api,
  PrescriptionPdfService? pdfService,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      prescriptionsApiProvider.overrideWithValue(api),
      if (pdfService != null) prescriptionPdfServiceProvider.overrideWithValue(pdfService),
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
          child: const PrescriptionsScreen(),
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

class _FakePrescriptionsApi extends PrescriptionsApi {
  _FakePrescriptionsApi() : super(Dio());

  final results = <Object>[];

  @override
  Future<List<PrescriptionModel>> list() {
    final next = results.removeAt(0);
    if (next is Future<List<PrescriptionModel>>) return next;
    if (next is List<PrescriptionModel>) return Future.value(next);
    return Future.error(next);
  }
}

/// Fake for [PrescriptionPdfService]: never touches the filesystem, Dio, or
/// a real platform plugin. [gate], when set, lets a test hold the call
/// in-flight to inspect busy state before letting it resolve.
class _FakePrescriptionPdfService extends PrescriptionPdfService {
  _FakePrescriptionPdfService() : super(PrescriptionsApi(Dio()));

  int callCount = 0;
  Object? errorToThrow;
  Completer<void>? gate;

  @override
  Future<void> downloadAndOpen({
    required String prescriptionId,
    String? prescriptionNumber,
  }) async {
    callCount++;
    if (gate != null) await gate!.future;
    if (errorToThrow != null) throw errorToThrow!;
  }
}
