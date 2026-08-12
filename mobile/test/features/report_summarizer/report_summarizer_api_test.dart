import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/report_summarizer/data/report_summarizer_api.dart';

Future<File> _writeTempReportFile() async {
  final file = File(
    '${Directory.systemTemp.path}/medorbit_report_test_${DateTime.now().microsecondsSinceEpoch}.pdf',
  );
  await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]); // PDF magic bytes — content doesn't matter
  return file;
}

Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

void main() {
  test('summarizeText() POSTs /summarize as multipart with exactly the text field', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'summary-1',
        'summary_ar': 'ملخص',
        'summary_en': 'Summary',
        'extracted_text': 'Patient has blood pressure 150/95...',
        'processing_time_ms': 16050,
        'model_used': 'qwen2:7b',
        'source_file_type': 'text',
      }),
    ]);
    final api = ReportSummarizerApi(fake.dio);

    final result = await api.summarizeText(text: 'Patient has blood pressure 150/95.');

    expect(fake.requests.single.method, 'POST');
    expect(fake.requests.single.path, '/ai/summarize');
    final fields = {for (final e in fake.requests.single.data.fields) e.key: e.value};
    expect(fields['text'], 'Patient has blood pressure 150/95.');
    expect(fields.containsKey('user_id'), isFalse);
    expect(fields.containsKey('record_id'), isFalse);
    expect(result.id, 'summary-1');
    expect(result.summaryAr, 'ملخص');
    expect(result.summaryEn, 'Summary');
    expect(result.processingTimeMs, 16050);
    expect(result.modelUsed, 'qwen2:7b');
    expect(result.sourceFileType, 'text');
  });

  test('summarizeText() never sends user_id and forwards record_id only', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'summary-2',
        'summary_ar': 'ملخص',
        'summary_en': 'Summary',
        'extracted_text': 'text',
        'processing_time_ms': 1000,
        'model_used': 'qwen2:7b',
        'source_file_type': 'text',
      }),
    ]);
    final api = ReportSummarizerApi(fake.dio);

    await api.summarizeText(text: 'Report body', userId: 'user-1', recordId: 'record-1');

    final fields = {for (final e in fake.requests.single.data.fields) e.key: e.value};
    expect(fields.containsKey('user_id'), isFalse);
    expect(fields['record_id'], 'record-1');
  });

  test('summarizeFile() POSTs /summarize as multipart with the file field, no text field', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'summary-file-1',
        'summary_ar': 'ملخص',
        'summary_en': 'Summary',
        'extracted_text': 'Extracted from the PDF.',
        'processing_time_ms': 20000,
        'model_used': 'qwen2:7b',
        'source_file_type': 'pdf',
      }),
    ]);
    final api = ReportSummarizerApi(fake.dio);
    final tempFile = await _writeTempReportFile();
    addTearDown(() => tempFile.delete());

    final result = await api.summarizeFile(filePath: tempFile.path, fileName: 'report.pdf');

    expect(fake.requests.single.method, 'POST');
    expect(fake.requests.single.path, '/ai/summarize');
    final formData = fake.requests.single.data as FormData;
    expect(formData.files, hasLength(1));
    expect(formData.files.single.key, 'file');
    expect(formData.files.single.value.filename, 'report.pdf');
    final fields = {for (final e in formData.fields) e.key: e.value};
    expect(fields.containsKey('text'), isFalse);
    expect(result.id, 'summary-file-1');
    expect(result.sourceFileType, 'pdf');
  });

  test('summarizeFile() never sends user_id and forwards record_id only', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'summary-file-2',
        'summary_ar': 'ملخص',
        'summary_en': 'Summary',
        'extracted_text': 'text',
        'processing_time_ms': 1000,
        'model_used': 'qwen2:7b',
        'source_file_type': 'pdf',
      }),
    ]);
    final api = ReportSummarizerApi(fake.dio);
    final tempFile = await _writeTempReportFile();
    addTearDown(() => tempFile.delete());

    await api.summarizeFile(
      filePath: tempFile.path,
      fileName: 'report.pdf',
      userId: 'user-1',
      recordId: 'record-1',
    );

    final formData = fake.requests.single.data as FormData;
    final fields = {for (final e in formData.fields) e.key: e.value};
    expect(fields.containsKey('user_id'), isFalse);
    expect(fields['record_id'], 'record-1');
  });

  test('handles a response with missing optional fields without throwing', () async {
    final fake = _FakeDio([
      _ok({'id': 'summary-3'}),
    ]);
    final api = ReportSummarizerApi(fake.dio);

    final result = await api.summarizeText(text: 'text');

    expect(result.id, 'summary-3');
    expect(result.summaryAr, isEmpty);
    expect(result.summaryEn, isEmpty);
    expect(result.extractedText, isEmpty);
    expect(result.processingTimeMs, 0);
    expect(result.modelUsed, isEmpty);
    expect(result.sourceFileType, isEmpty);
  });

  test('a FastAPI {"detail": ...} 500 body normalizes to a safe generic error with no raw text', () async {
    final fake = _FakeDio([
      _httpError(statusCode: 500, body: {'detail': 'Summarization failed: internal engine error'}),
    ]);
    final api = ReportSummarizerApi(fake.dio);

    final dioError = await _captureDioException(api.summarizeText(text: 'text'));
    final normalized = ApiException.fromDioException(dioError);

    expect(normalized.code, ApiException.codeHttpError);
    expect(normalized.message, isNot(contains('Summarization failed')));
    expect(normalized.message, isNot(contains('internal engine error')));
  });

  test('a receive timeout propagates untouched and normalizes to codeReceiveTimeout', () async {
    final fake = _FakeDio([_timeout()]);
    final api = ReportSummarizerApi(fake.dio);

    final dioError = await _captureDioException(api.summarizeText(text: 'text'));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeReceiveTimeout);
  });

  test('an unreachable service normalizes to codeServiceUnavailable', () async {
    final fake = _FakeDio([_connectionError()]);
    final api = ReportSummarizerApi(fake.dio);

    final dioError = await _captureDioException(api.summarizeText(text: 'text'));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeServiceUnavailable);
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'summary-4',
        'summary_ar': 'ملخص خاص',
        'summary_en': 'A private summary',
        'extracted_text': 'A private medical report body',
        'processing_time_ms': 500,
        'model_used': 'qwen2:7b',
        'source_file_type': 'text',
      }),
    ]);
    final api = ReportSummarizerApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      () => api.summarizeText(text: 'A private medical report body'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

class _QueuedResponse {
  const _QueuedResponse.ok(this.body) : error = null;
  const _QueuedResponse.error(this.error) : body = null;

  final Map<String, dynamic>? body;
  final DioException Function(RequestOptions options)? error;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

_QueuedResponse _httpError({required int statusCode, required Map<String, dynamic> body}) {
  return _QueuedResponse.error(
    (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: statusCode,
        data: body,
      ),
    ),
  );
}

_QueuedResponse _timeout() {
  return _QueuedResponse.error(
    (options) => DioException(requestOptions: options, type: DioExceptionType.receiveTimeout),
  );
}

_QueuedResponse _connectionError() {
  return _QueuedResponse.error(
    (options) => DioException(requestOptions: options, type: DioExceptionType.connectionError),
  );
}

class _FakeDio {
  _FakeDio(List<_QueuedResponse> responses) : dio = Dio(BaseOptions(baseUrl: 'https://ai.example.test')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(_RecordedRequest(method: options.method, path: options.path, data: options.data));
          final next = responses.removeAt(0);
          if (next.error != null) {
            handler.reject(next.error!(options));
          } else {
            handler.resolve(
              Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: next.body),
            );
          }
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_RecordedRequest>[];
}

class _RecordedRequest {
  const _RecordedRequest({required this.method, required this.path, required this.data});

  final String method;
  final String path;
  final dynamic data;
}
