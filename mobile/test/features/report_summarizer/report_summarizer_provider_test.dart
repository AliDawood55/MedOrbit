import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/report_summarizer/data/report_summarizer_api.dart';
import 'package:mobile/features/report_summarizer/models/report_summary_result.dart';
import 'package:mobile/features/report_summarizer/providers/report_summarizer_provider.dart';

ReportSummaryResult _result({String id = 'summary-1'}) {
  return ReportSummaryResult(
    id: id,
    summaryAr: 'ملخص',
    summaryEn: 'Summary',
    extractedText: 'Patient has blood pressure 150/95, headache, dizziness.',
    processingTimeMs: 16050,
    modelUsed: 'qwen2:7b',
    sourceFileType: 'text',
  );
}

const _longEnoughReport =
    'Patient has blood pressure 150/95, headache, dizziness, and no chest pain.';

void main() {
  test('initial state is empty with nothing submitted yet', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);

    final state = container.read(reportSummarizerControllerProvider);

    expect(state.inputText, isEmpty);
    expect(state.isLoading, isFalse);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('submitting empty text shows a validation error and never calls the API', () async {
    final api = _FakeReportSummarizerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(container.read(reportSummarizerControllerProvider).showValidationError, isTrue);
    expect(api.summarizeTextCalls, isEmpty);
  });

  test('submitting text shorter than the minimum shows a validation error and never calls the API', () async {
    final api = _FakeReportSummarizerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput('too short');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(container.read(reportSummarizerControllerProvider).showValidationError, isTrue);
    expect(api.summarizeTextCalls, isEmpty);
  });

  test('whitespace-only text also fails validation after trimming', () async {
    final api = _FakeReportSummarizerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput('     \n\n   ');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(api.summarizeTextCalls, isEmpty);
  });

  test('updateInput clears a previously shown validation error', () async {
    final api = _FakeReportSummarizerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    await notifier.submit();
    expect(container.read(reportSummarizerControllerProvider).showValidationError, isTrue);

    notifier.updateInput(_longEnoughReport);

    expect(container.read(reportSummarizerControllerProvider).showValidationError, isFalse);
  });

  test('a successful submit populates the result', () async {
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);

    final ok = await notifier.submit();

    expect(ok, isTrue);
    expect(api.summarizeTextCalls.single, _longEnoughReport);
    final state = container.read(reportSummarizerControllerProvider);
    expect(state.result, isNotNull);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
  });

  test('submit omits user_id when nobody is signed in', () async {
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);

    await notifier.submit();

    expect(api.summarizeTextUserIds, [null]);
  });

  test('submit attaches the signed-in user\'s id so the summary is linked to their account', () async {
    const user = UserModel(id: 'patient-42', email: 'p@example.com', role: 'patient');
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    final container = _container(api, signedInUser: user);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).checkAuthStatus();
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);

    await notifier.submit();

    expect(api.summarizeTextUserIds, ['patient-42']);
  });

  test('retry re-reads the current user id rather than reusing a stale one', () async {
    const user = UserModel(id: 'patient-42', email: 'p@example.com', role: 'patient');
    final api = _FakeReportSummarizerApi()
      ..summarizeTextResults.add(
        const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
      )
      ..summarizeTextResults.add(_result());
    final container = _container(api, signedInUser: user);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).checkAuthStatus();
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);
    await notifier.submit();

    await notifier.retry();

    expect(api.summarizeTextUserIds, ['patient-42', 'patient-42']);
  });

  test('a second submit while one is in flight is ignored', () async {
    final completer = Completer<ReportSummaryResult>();
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);

    final first = notifier.submit();
    final second = await notifier.submit();

    expect(second, isFalse);
    completer.complete(_result());
    await first;
    expect(api.summarizeTextCalls, hasLength(1));
  });

  test('a submit failure sets a categorized, safe error and keeps no stale result', () async {
    final api = _FakeReportSummarizerApi()
      ..summarizeTextResults.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);

    final ok = await notifier.submit();

    expect(ok, isFalse);
    final state = container.read(reportSummarizerControllerProvider);
    expect(state.error, ReportSummarizerErrorKind.serviceUnavailable);
    expect(state.result, isNull);
    expect(state.isLoading, isFalse);
  });

  test('a timeout failure categorizes as timeout', () async {
    final api = _FakeReportSummarizerApi()
      ..summarizeTextResults.add(
        const ApiException(message: 'Too slow', code: ApiException.codeReceiveTimeout),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);

    await notifier.submit();

    expect(
      container.read(reportSummarizerControllerProvider).error,
      ReportSummarizerErrorKind.timeout,
    );
  });

  test('retry resubmits the last report text without requiring the input again', () async {
    final api = _FakeReportSummarizerApi()
      ..summarizeTextResults.add(
        const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
      )
      ..summarizeTextResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);
    await notifier.submit();
    expect(container.read(reportSummarizerControllerProvider).error, ReportSummarizerErrorKind.generic);

    final ok = await notifier.retry();

    expect(ok, isTrue);
    expect(container.read(reportSummarizerControllerProvider).result, isNotNull);
    expect(container.read(reportSummarizerControllerProvider).error, isNull);
    expect(api.summarizeTextCalls, [_longEnoughReport, _longEnoughReport]);
  });

  test('retry before anything has been submitted is a no-op', () async {
    final api = _FakeReportSummarizerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    final ok = await notifier.retry();

    expect(ok, isFalse);
    expect(api.summarizeTextCalls, isEmpty);
  });

  test('reset clears input, result, and error', () async {
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);
    await notifier.submit();
    expect(container.read(reportSummarizerControllerProvider).result, isNotNull);

    notifier.reset();

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.inputText, isEmpty);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('reset() also clears whatever retry() would have resubmitted', () async {
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);
    await notifier.submit();

    notifier.reset();
    final ok = await notifier.retry();

    expect(ok, isFalse, reason: 'reset must forget the last submitted report text too');
    expect(api.summarizeTextCalls, hasLength(1));
  });

  test('selectFile accepts a supported extension and stores it', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.hasSelectedFile, isTrue);
    expect(state.selectedFilePath, '/tmp/report.pdf');
    expect(state.selectedFileName, 'report.pdf');
    expect(state.selectedFileExtension, 'pdf');
    expect(state.fileError, isNull);
  });

  test('selectFile is case-insensitive about the extension', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    notifier.selectFile(filePath: '/tmp/scan.JPG', fileName: 'scan.JPG', fileSizeBytes: 1024);

    expect(container.read(reportSummarizerControllerProvider).hasSelectedFile, isTrue);
  });

  test('selectFile rejects an unsupported extension and does not store a path', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    notifier.selectFile(filePath: '/tmp/report.docx', fileName: 'report.docx', fileSizeBytes: 1024);

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.hasSelectedFile, isFalse);
    expect(state.fileError, ReportFileErrorKind.unsupportedType);
  });

  test('selectFile rejects a file over the size limit and does not store a path', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    notifier.selectFile(
      filePath: '/tmp/report.pdf',
      fileName: 'report.pdf',
      fileSizeBytes: maxReportFileSizeBytes + 1,
    );

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.hasSelectedFile, isFalse);
    expect(state.fileError, ReportFileErrorKind.tooLarge);
  });

  test('selecting a valid file clears a previous file error and text-validation error', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.selectFile(filePath: '/tmp/x.docx', fileName: 'x.docx', fileSizeBytes: 1);
    await notifier.submit(); // nothing selected after rejection, empty text -> validation error
    expect(container.read(reportSummarizerControllerProvider).showValidationError, isTrue);

    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.fileError, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('clearSelectedFile removes the file and its error', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);

    notifier.clearSelectedFile();

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.hasSelectedFile, isFalse);
    expect(state.fileError, isNull);
  });

  test('reportPickFailure sets a file error without a selected file', () async {
    final container = _container(_FakeReportSummarizerApi());
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);

    notifier.reportPickFailure();

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.fileError, ReportFileErrorKind.pickFailed);
    expect(state.hasSelectedFile, isFalse);
  });

  test('submit prefers a selected file over typed text and calls summarizeFile', () async {
    final api = _FakeReportSummarizerApi()..summarizeFileResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.updateInput(_longEnoughReport);
    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);

    final ok = await notifier.submit();

    expect(ok, isTrue);
    expect(api.summarizeFileCalls.single, (path: '/tmp/report.pdf', name: 'report.pdf'));
    expect(api.summarizeTextCalls, isEmpty);
  });

  test('a failed file submit sets a categorized, safe error', () async {
    final api = _FakeReportSummarizerApi()
      ..summarizeFileResults.add(
        const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(
      container.read(reportSummarizerControllerProvider).error,
      ReportSummarizerErrorKind.generic,
    );
  });

  test('retry after a file submit resubmits the file, not text', () async {
    final api = _FakeReportSummarizerApi()
      ..summarizeFileResults.add(
        const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
      )
      ..summarizeFileResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);
    await notifier.submit();

    final ok = await notifier.retry();

    expect(ok, isTrue);
    expect(api.summarizeFileCalls, hasLength(2));
    expect(api.summarizeTextCalls, isEmpty);
  });

  test('reset clears the selected file along with everything else', () async {
    final api = _FakeReportSummarizerApi()..summarizeFileResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(reportSummarizerControllerProvider.notifier);
    notifier.selectFile(filePath: '/tmp/report.pdf', fileName: 'report.pdf', fileSizeBytes: 1024);
    await notifier.submit();

    notifier.reset();

    final state = container.read(reportSummarizerControllerProvider);
    expect(state.hasSelectedFile, isFalse);
    expect(state.result, isNull);
    final ok = await notifier.retry();
    expect(ok, isFalse, reason: 'reset must forget the last submitted file too');
  });

  test('file names and file errors are never printed', () async {
    final api = _FakeReportSummarizerApi()..summarizeFileResults.add(_result());
    final printed = <String>[];

    await runZoned(
      () async {
        final container = _container(api);
        addTearDown(container.dispose);
        final notifier = container.read(reportSummarizerControllerProvider.notifier);
        notifier.selectFile(
          filePath: '/private/path/a-patients-report.pdf',
          fileName: 'a-patients-report.pdf',
          fileSizeBytes: 1024,
        );
        await notifier.submit();
        notifier.reset();
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });

  test('report text and results are never printed', () async {
    final api = _FakeReportSummarizerApi()..summarizeTextResults.add(_result());
    final printed = <String>[];

    await runZoned(
      () async {
        final container = _container(api);
        addTearDown(container.dispose);
        final notifier = container.read(reportSummarizerControllerProvider.notifier);
        notifier.updateInput('A very private medical report about the patient.');
        await notifier.submit();
        notifier.reset();
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

ProviderContainer _container(ReportSummarizerApi api, {UserModel? signedInUser}) {
  final container = ProviderContainer(
    overrides: [
      reportSummarizerApiProvider.overrideWithValue(api),
      if (signedInUser != null)
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository(signedInUser)),
    ],
  );
  // `reportSummarizerControllerProvider` is `autoDispose` — keep it alive
  // across `await` boundaries the same way every other autoDispose provider
  // test does.
  container.listen(reportSummarizerControllerProvider, (previous, next) {});
  return container;
}

/// Only overridden when a test needs `authControllerProvider.user` to be
/// non-null — every other test leaves the real (unauthenticated-by-default)
/// `AuthController` construct, which is safe: it never performs I/O merely
/// by being constructed, only when a method like `login`/`checkAuthStatus`
/// is actually called.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this._user) : super(AuthApi(Dio()), SecureStorageService());

  final UserModel _user;

  @override
  Future<bool> hasValidSession() async => true;

  @override
  Future<UserModel?> getPersistedUser() async => _user;
}

class _FakeReportSummarizerApi extends ReportSummarizerApi {
  _FakeReportSummarizerApi() : super(Dio());

  final summarizeTextResults = <Object>[];
  final summarizeTextCalls = <String>[];
  final summarizeTextUserIds = <String?>[];
  final summarizeFileResults = <Object>[];
  final summarizeFileCalls = <({String path, String name})>[];
  final summarizeFileUserIds = <String?>[];

  @override
  Future<ReportSummaryResult> summarizeText({
    required String text,
    String? userId,
    String? recordId,
  }) {
    summarizeTextCalls.add(text);
    summarizeTextUserIds.add(userId);
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
    summarizeFileUserIds.add(userId);
    final next = summarizeFileResults.removeAt(0);
    if (next is Future<ReportSummaryResult>) return next;
    if (next is ReportSummaryResult) return Future.value(next);
    return Future.error(next);
  }
}
