import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/report_summarizer_api.dart';
import '../models/report_summary_result.dart';

final reportSummarizerApiProvider = Provider<ReportSummarizerApi>(
  (ref) => ReportSummarizerApi(ref.watch(dioProvider)),
);

/// Below this many trimmed characters there isn't enough report text to
/// meaningfully summarize — the "very short text" guard, applied with the
/// same message as the empty-input case. Only checked when no file is
/// selected — a selected file is always sufficient input on its own.
const int minReportTextLength = 20;

/// Matches the AI service's actual OCR/extraction support — anything else is
/// rejected client-side before ever reaching the network.
const List<String> allowedReportFileExtensions = ['pdf', 'png', 'jpg', 'jpeg'];

const int maxReportFileSizeBytes = 10 * 1024 * 1024;

enum ReportSummarizerErrorKind { timeout, serviceUnavailable, generic }

enum ReportFileErrorKind { unsupportedType, tooLarge, pickFailed }

class ReportSummarizerState {
  const ReportSummarizerState({
    this.inputText = '',
    this.selectedFilePath,
    this.selectedFileName,
    this.selectedFileExtension,
    this.fileError,
    this.isLoading = false,
    this.result,
    this.error,
    this.showValidationError = false,
  });

  final String inputText;

  /// Null unless a file has passed client-side type/size validation. A
  /// non-null path takes priority over [inputText] on submit.
  final String? selectedFilePath;
  final String? selectedFileName;
  final String? selectedFileExtension;
  final ReportFileErrorKind? fileError;

  final bool isLoading;
  final ReportSummaryResult? result;
  final ReportSummarizerErrorKind? error;
  final bool showValidationError;

  bool get hasSelectedFile => selectedFilePath != null;

  ReportSummarizerState copyWith({
    String? inputText,
    String? selectedFilePath,
    String? selectedFileName,
    String? selectedFileExtension,
    ReportFileErrorKind? fileError,
    bool clearSelectedFile = false,
    bool clearFileError = false,
    bool? isLoading,
    ReportSummaryResult? result,
    ReportSummarizerErrorKind? error,
    bool clearError = false,
    bool? showValidationError,
  }) {
    return ReportSummarizerState(
      inputText: inputText ?? this.inputText,
      selectedFilePath: clearSelectedFile
          ? null
          : (selectedFilePath ?? this.selectedFilePath),
      selectedFileName: clearSelectedFile
          ? null
          : (selectedFileName ?? this.selectedFileName),
      selectedFileExtension: clearSelectedFile
          ? null
          : (selectedFileExtension ?? this.selectedFileExtension),
      fileError: clearFileError ? null : (fileError ?? this.fileError),
      isLoading: isLoading ?? this.isLoading,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
      showValidationError: showValidationError ?? this.showValidationError,
    );
  }
}

class ReportSummarizerController extends StateNotifier<ReportSummarizerState> {
  ReportSummarizerController(this._ref)
    : _api = _ref.read(reportSummarizerApiProvider),
      super(const ReportSummarizerState());

  final Ref _ref;
  final ReportSummarizerApi _api;

  /// Attaches the summary to the signed-in patient so it shows up in My
  /// Reports — read fresh at submit time rather than cached at construction,
  /// and read from the already-in-memory auth state (never a new network
  /// call). Null is a normal, safe value (Report Summarizer's route is
  /// protected, but this stays defensive rather than assuming).
  String? get _currentUserId => _ref.read(authControllerProvider).user?.id;

  /// Kept only in memory for the lifetime of this `autoDispose` controller —
  /// never written to storage — so [retry] can resubmit the exact same
  /// text or file without asking the user to redo it. Only one is ever set
  /// at a time.
  String? _lastSubmittedText;
  ({String path, String name})? _lastSubmittedFile;

  void updateInput(String value) {
    state = state.copyWith(inputText: value, showValidationError: false);
  }

  /// Validates a file already picked by the screen (this controller never
  /// touches a platform file-picker plugin directly, keeping it testable
  /// without platform channels — the screen calls this with whatever the
  /// picker returned). Rejects unsupported extensions and oversized files
  /// before ever storing a path.
  void selectFile({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
  }) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (!allowedReportFileExtensions.contains(extension)) {
      state = state.copyWith(
        fileError: ReportFileErrorKind.unsupportedType,
        clearSelectedFile: true,
      );
      return;
    }
    if (fileSizeBytes > maxReportFileSizeBytes) {
      state = state.copyWith(
        fileError: ReportFileErrorKind.tooLarge,
        clearSelectedFile: true,
      );
      return;
    }
    state = state.copyWith(
      selectedFilePath: filePath,
      selectedFileName: fileName,
      selectedFileExtension: extension,
      clearFileError: true,
      showValidationError: false,
    );
  }

  void clearSelectedFile() {
    state = state.copyWith(clearSelectedFile: true, clearFileError: true);
  }

  /// The screen calls this when the platform picker itself throws or is
  /// cancelled abnormally (not a plain "user cancelled" — that's silent).
  void reportPickFailure() {
    state = state.copyWith(fileError: ReportFileErrorKind.pickFailed);
  }

  /// A selected file always takes priority over typed text. Falls back to
  /// text validation (empty/too-short) only when nothing is selected.
  Future<bool> submit() async {
    if (state.isLoading) return false;

    final userId = _currentUserId;

    final filePath = state.selectedFilePath;
    final fileName = state.selectedFileName;
    if (filePath != null && fileName != null) {
      _lastSubmittedFile = (path: filePath, name: fileName);
      _lastSubmittedText = null;
      return _run(
        () => _api.summarizeFile(filePath: filePath, fileName: fileName, userId: userId),
      );
    }

    final text = state.inputText.trim();
    if (text.length < minReportTextLength) {
      state = state.copyWith(showValidationError: true);
      return false;
    }
    _lastSubmittedText = text;
    _lastSubmittedFile = null;
    return _run(() => _api.summarizeText(text: text, userId: userId));
  }

  /// Resubmits whichever of text or file was last submitted. A no-op if
  /// nothing has been submitted yet in this session.
  Future<bool> retry() async {
    if (state.isLoading) return false;
    final userId = _currentUserId;
    final file = _lastSubmittedFile;
    if (file != null) {
      return _run(
        () => _api.summarizeFile(filePath: file.path, fileName: file.name, userId: userId),
      );
    }
    final text = _lastSubmittedText;
    if (text != null) return _run(() => _api.summarizeText(text: text, userId: userId));
    return false;
  }

  Future<bool> _run(Future<ReportSummaryResult> Function() call) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await call();
      state = state.copyWith(isLoading: false, result: result);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: _categorize(error));
      return false;
    }
  }

  /// Clears input, selected file, result, and error — the only "summarize
  /// another report" mechanism. Nothing about a report is ever persisted.
  void reset() {
    _lastSubmittedText = null;
    _lastSubmittedFile = null;
    state = const ReportSummarizerState();
  }

  ReportSummarizerErrorKind _categorize(Object error) {
    final api = ApiException.from(error);
    return switch (api) {
      _ when api.isTimeout => ReportSummarizerErrorKind.timeout,
      _ when api.code == ApiException.codeServiceUnavailable =>
        ReportSummarizerErrorKind.serviceUnavailable,
      _ => ReportSummarizerErrorKind.generic,
    };
  }
}

final reportSummarizerControllerProvider =
    StateNotifierProvider.autoDispose<ReportSummarizerController, ReportSummarizerState>(
      (ref) => ReportSummarizerController(ref),
    );
