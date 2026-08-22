import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/records/data/records_api.dart';
import 'package:mobile/features/records/models/record_entry_model.dart';
import 'package:mobile/features/records/providers/records_provider.dart';
import 'package:mobile/features/records/screens/records_screen.dart';

const _strings = AppStrings(false); // English, matching the default direction used below
const _canary = 'INTERNAL_ONLY_DO_NOT_RENDER';

/// A prescription-type record entry built the same way the app builds one:
/// parsed from a raw backend-shaped payload that (like the real timeline
/// entry today) includes the internal `doctor_notes` field as dormant
/// defense-in-depth coverage, even though the live endpoint doesn't send it.
RecordEntryModel _recordEntryWithCanary() {
  return RecordEntryModel.fromJson({
    'entry_type': 'prescription',
    'id': '1',
    'entry_date': '2026-08-01',
    'prescription_number': 'RX-2026-001',
    'prescription_date': '2026-08-01',
    'valid_until': null,
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
  testWidgets('the record list card never renders the internal doctor note', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeRecordsApi()..results.add([_recordEntryWithCanary()]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.textContaining(_canary), findsNothing);
    expect(find.text(_strings.doctorNotes), findsNothing);
    // Legitimate record data still renders (the note preview falls back to
    // instructions once doctor_notes is out of the picture).
    expect(find.text('Take twice daily with food'), findsOneWidget);
  });

  testWidgets('the record detail sheet never renders the internal doctor note', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeRecordsApi()..results.add([_recordEntryWithCanary()]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.text(_strings.viewRecordDetails));
    await tester.pumpAndSettle();

    expect(find.textContaining(_canary), findsNothing);
    expect(find.text(_strings.doctorNotes), findsNothing);
    // Legitimate record data still renders in the expanded detail sheet
    // (the underlying list card stays mounted behind the modal sheet, so
    // the shared instructions text legitimately appears twice).
    expect(find.text(_strings.detailInstructions), findsWidgets);
    expect(find.text('Take twice daily with food'), findsWidgets);
    expect(find.text('Amoxicillin'), findsWidgets);
  });
}

Widget _app({required RecordsApi api}) {
  return ProviderScope(
    overrides: [
      recordsApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: false),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Directionality(
        textDirection: TextDirection.ltr,
        child: RecordsScreen(),
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

class _FakeRecordsApi extends RecordsApi {
  _FakeRecordsApi() : super(Dio());

  final results = <Object>[];

  @override
  Future<List<RecordEntryModel>> getTimeline() {
    final next = results.removeAt(0);
    if (next is Future<List<RecordEntryModel>>) return next;
    if (next is List<RecordEntryModel>) return Future.value(next);
    return Future.error(next);
  }
}
