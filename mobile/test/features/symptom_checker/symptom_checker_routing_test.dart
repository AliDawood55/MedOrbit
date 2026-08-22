import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/features/symptom_checker/providers/symptom_checker_provider.dart';

/// Regression coverage for the P6A audit finding that Symptom Checker talks
/// to the AI service directly, unauthenticated. That finding was re-checked
/// for P6C and found stale: `symptomCheckerApiProvider` already reads
/// [dioProvider] — the authenticated backend client — not [aiDioProvider].
/// This test exercises the real provider graph (no `symptomCheckerApiProvider`
/// override) so a future regression that rewires it onto [aiDioProvider]
/// fails here instead of only showing up as a 401 in the field.
void main() {
  test('symptomCheckerApiProvider posts through dioProvider, never aiDioProvider', () async {
    final backend = _recordingDio(baseUrl: 'https://backend.example/api');
    final aiService = _recordingDio(baseUrl: 'https://ai.example:8001');

    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(backend.dio),
        aiDioProvider.overrideWithValue(aiService.dio),
      ],
    );
    addTearDown(container.dispose);

    await container.read(symptomCheckerApiProvider).checkSymptoms(['headache']);

    expect(backend.requests, hasLength(1), reason: 'the authenticated backend client must carry the request');
    expect(backend.requests.single.path, '/ai/triage');
    expect(aiService.requests, isEmpty, reason: 'the direct AI-service client must never see this request');
  });
}

class _RecordingDio {
  _RecordingDio(this.dio);
  final Dio dio;
  final requests = <RequestOptions>[];
}

_RecordingDio _recordingDio({required String baseUrl}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  final recorder = _RecordingDio(dio);
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        recorder.requests.add(options);
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: const {
              'id': 'triage-routing-1',
              'symptoms': ['headache'],
              'triage_level': 'routine',
              'confidence_score': 0.5,
              'recommendations': 'General guidance.',
              'follow_up_action': 'book_appointment',
            },
          ),
        );
      },
    ),
  );
  return recorder;
}
