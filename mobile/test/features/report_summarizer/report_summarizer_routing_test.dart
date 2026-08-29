import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/features/report_summarizer/providers/report_summarizer_provider.dart';

/// Regression coverage for the P6A audit finding that Report Summarizer talks
/// to the AI service directly, unauthenticated. That finding was re-checked
/// for P6C and found stale: `reportSummarizerApiProvider` reads [dioProvider]
/// — the authenticated backend client, which is also what lets the backend
/// attribute a summary to the signed-in patient. There is no direct-AI-service
/// client in production anymore; this test exercises the real provider graph
/// (no `reportSummarizerApiProvider` override) so a future regression that
/// rewires it off the authenticated backend gateway fails here instead of
/// only showing up as a 401, or a summary silently missing from My Reports,
/// in the field.
void main() {
  test(
    'reportSummarizerApiProvider posts through the authenticated backend dioProvider',
    () async {
      final backend = _recordingDio(baseUrl: 'https://backend.example/api');

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(backend.dio)],
      );
      addTearDown(container.dispose);

      await container
          .read(reportSummarizerApiProvider)
          .summarizeText(text: 'Patient reports mild headache.');

      expect(
        backend.requests,
        hasLength(1),
        reason: 'the authenticated backend client must carry the request',
      );
      expect(backend.requests.single.path, '/ai/summarize');
    },
  );
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
              'id': 'summary-routing-1',
              'summary_ar': 'ملخص',
              'summary_en': 'Summary',
              'extracted_text': 'Patient reports mild headache.',
              'processing_time_ms': 500,
              'model_used': 'qwen2:7b',
              'source_file_type': 'text',
            },
          ),
        );
      },
    ),
  );
  return recorder;
}
