import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/clinic_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';
import 'package:mobile/features/discovery/screens/clinic_detail_screen.dart';

void main() {
  testWidgets('loading state is visible', (tester) async {
    final pending = Completer<ClinicDetailResponse>();
    final api = _FakeDiscoveryApi()..detailResults.add(pending.future);

    await tester.pumpWidget(_app(api));
    await tester.pump();

    expect(find.text('Loading clinic details...'), findsOneWidget);
    pending.complete(const ClinicDetailResponse());
    await tester.pump();
  });

  testWidgets('populated verified detail shows sections without unverified disclaimer', (tester) async {
    final api = _FakeDiscoveryApi()
      ..detailResults.add(
        Future.value(
          const ClinicDetailResponse(
            clinic: Clinic(
              id: 'clinic-1',
              nameEn: 'Nablus Health Center',
              type: 'clinic',
              verificationStatus: ClinicVerificationStatus.verified,
              verificationStatusValue: 'verified',
              addressEn: 'Main Street',
              city: 'Nablus',
              region: 'Nablus',
              phone: '092345678',
              email: 'info@example.test',
              website: 'https://example.test',
              latitude: 32.2211,
              longitude: 35.2544,
              services: ['Family medicine'],
              insuranceAccepted: ['Public insurance'],
              operatingHours: ClinicOperatingHours(
                days: {
                  'monday': ClinicDayHours(open: '08:00', close: '16:00'),
                },
              ),
            ),
            doctors: [
              ClinicDoctorSummary(
                id: 'doctor-1',
                firstNameEn: 'Mariam',
                lastNameEn: 'Saleh',
                specialtyEn: 'Family medicine',
                averageRating: 4.7,
                isAcceptingPatients: true,
              ),
            ],
          ),
        ),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nablus Health Center'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Family medicine'), findsWidgets);
    expect(find.text('Public insurance'), findsOneWidget);
    expect(find.text('Listed hours'), findsOneWidget);
    expect(find.textContaining('Contact the clinic to confirm before visiting'), findsOneWidget);
    expect(find.text('Mariam Saleh'), findsOneWidget);
    expect(find.byKey(const ValueKey('discovery-map-place-clinic-1')), findsOneWidget);
    expect(find.textContaining('may not be verified'), findsNothing);
  });

  testWidgets('pending and unknown facilities show cautious disclaimer', (tester) async {
    final api = _FakeDiscoveryApi()
      ..detailResults.add(
        Future.value(
          const ClinicDetailResponse(
            clinic: Clinic(
              id: 'pending',
              nameEn: 'Community Pharmacy',
              type: 'pharmacy',
              verificationStatus: ClinicVerificationStatus.pending,
              verificationStatusValue: 'pending',
            ),
          ),
        ),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.text('Pending verification'), findsOneWidget);
    expect(find.textContaining('Hours and facility details may not be verified'), findsOneWidget);
  });

  testWidgets('missing optional fields and no coordinates show safe fallbacks', (tester) async {
    final api = _FakeDiscoveryApi()
      ..detailResults.add(
        Future.value(const ClinicDetailResponse(clinic: Clinic(id: 'minimal'))),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.text('Healthcare facility'), findsOneWidget);
    expect(find.text('No contact details are listed.'), findsOneWidget);
    expect(find.text('No operating hours are listed.'), findsOneWidget);
    expect(find.text('No map coordinates are listed for this clinic.'), findsOneWidget);
  });

  testWidgets('error, retry, and not-found states render safely', (tester) async {
    final api = _FakeDiscoveryApi()
      ..detailFailures.add(const ApiException(message: 'Detail failed', code: 'DETAIL_FAILED'))
      ..detailResults.add(Future.value(const ClinicDetailResponse()));

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not load clinic'), findsOneWidget);
    expect(api.detailCalls, ['clinic-1']);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Clinic not found'), findsOneWidget);
    expect(api.detailCalls, ['clinic-1', 'clinic-1']);
  });

  testWidgets('RTL and large text detail layout does not overflow', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    final api = _FakeDiscoveryApi()
      ..detailResults.add(
        Future.value(
          const ClinicDetailResponse(
            clinic: Clinic(
              id: 'rtl',
              nameAr: 'عيادة نابلس',
              verificationStatus: ClinicVerificationStatus.pending,
            ),
          ),
        ),
      );

    await tester.pumpWidget(_app(api, textDirection: TextDirection.rtl, textScale: 2));
    await tester.pump();
    await tester.pump();

    expect(errors.where((error) => error.exceptionAsString().contains('overflowed')), isEmpty);
  });
}

Widget _app(
  _FakeDiscoveryApi api, {
  TextDirection textDirection = TextDirection.ltr,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [discoveryApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: textDirection == TextDirection.rtl),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: textDirection,
          child: const ClinicDetailScreen(clinicId: 'clinic-1'),
        ),
      ),
    ),
  );
}

class _FakeDiscoveryApi extends DiscoveryApi {
  _FakeDiscoveryApi() : super(Dio());

  final detailResults = <Future<ClinicDetailResponse>>[];
  final detailFailures = <Object>[];
  final detailCalls = <String>[];

  @override
  Future<ClinicDetailResponse> getClinic(String id) {
    detailCalls.add(id);
    if (detailFailures.isNotEmpty) {
      return Future<ClinicDetailResponse>.error(detailFailures.removeAt(0));
    }
    return detailResults.removeAt(0);
  }
}
