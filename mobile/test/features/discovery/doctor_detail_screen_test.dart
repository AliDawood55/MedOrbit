import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';
import 'package:mobile/features/discovery/screens/doctor_detail_screen.dart';

void main() {
  testWidgets('loading and populated doctor detail show backend data without verification claims', (tester) async {
    final pending = Completer<DoctorDetailResponse>(); final api = _DetailApi()..details.add(pending.future);
    await tester.pumpWidget(_app(api)); await tester.pump(); expect(find.text('Loading doctor details...'), findsOneWidget);
    pending.complete(const DoctorDetailResponse(doctor: Doctor(id: 'd1', firstNameEn: 'Mariam', lastNameEn: 'Saleh', specialtyEn: 'Family medicine', professionalBioEn: 'Community physician', yearsOfExperience: 8, medicalLicenseNumber: 'LIC-1', education: ['Medical school'], certifications: ['Course']), clinics: [DoctorClinicSummary(id: 'c1', nameEn: 'Rafidia Clinic', latitude: 32.22, longitude: 35.25)], reviews: [DoctorReview(id: 'r1', rating: 5, comment: 'Helpful')]));
    await tester.pump();
    expect(find.text('Mariam Saleh'), findsOneWidget); expect(find.text('Medical school'), findsOneWidget); expect(find.text('Course'), findsOneWidget); expect(find.text('Rafidia Clinic'), findsOneWidget); expect(find.text('Helpful'), findsOneWidget); expect(find.textContaining('verified'), findsNothing);
    expect(find.byKey(const ValueKey('discovery-map-place-c1')), findsOneWidget);
  });
  testWidgets('missing optional detail, not found, error retry, and availability states are safe', (tester) async {
    final api = _DetailApi()..failures.add(const ApiException(message: 'Failed', code: 'FAILED'))..details.add(Future.value(const DoctorDetailResponse()));
    await tester.pumpWidget(_app(api)); await tester.pump(); await tester.pump(); expect(find.text('Could not load doctor'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry')); await tester.pump(); await tester.pump(); expect(find.text('Doctor not found'), findsOneWidget); expect(api.calls, hasLength(2));
  });
}
Widget _app(_DetailApi api) => ProviderScope(overrides: [discoveryApiProvider.overrideWithValue(api)], child: MaterialApp(theme: AppTheme.light(), home: const DoctorDetailScreen(doctorId: 'd1')));
class _DetailApi extends DiscoveryApi { _DetailApi() : super(Dio()); final details = <Future<DoctorDetailResponse>>[]; final failures = <Object>[]; final calls = <String>[];
  @override Future<DoctorDetailResponse> getDoctor(String id) { calls.add(id); if (failures.isNotEmpty) return Future.error(failures.removeAt(0)); return details.removeAt(0); }
}
