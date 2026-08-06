import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../data/symptom_checker_api.dart';
import '../models/symptom_check_result.dart';

final symptomCheckerApiProvider = Provider<SymptomCheckerApi>(
  (ref) => SymptomCheckerApi(ref.watch(aiDioProvider)),
);

enum SymptomCheckErrorKind { timeout, serviceUnavailable, generic }

class SymptomCheckerState {
  const SymptomCheckerState({
    this.symptomsInput = '',
    this.isSubmitting = false,
    this.result,
    this.error,
    this.showValidationError = false,
  });

  final String symptomsInput;
  final bool isSubmitting;
  final SymptomCheckResult? result;
  final SymptomCheckErrorKind? error;
  final bool showValidationError;

  SymptomCheckerState copyWith({
    String? symptomsInput,
    bool? isSubmitting,
    SymptomCheckResult? result,
    SymptomCheckErrorKind? error,
    bool clearError = false,
    bool? showValidationError,
  }) {
    return SymptomCheckerState(
      symptomsInput: symptomsInput ?? this.symptomsInput,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
      showValidationError: showValidationError ?? this.showValidationError,
    );
  }
}

class SymptomCheckerController extends StateNotifier<SymptomCheckerState> {
  SymptomCheckerController(this._api) : super(const SymptomCheckerState());

  final SymptomCheckerApi _api;

  /// Kept only in memory for the lifetime of this `autoDispose` controller —
  /// never written to storage — so [retry] can resubmit the exact same
  /// symptom list without asking the user to retype it.
  List<String>? _lastSubmitted;

  void updateInput(String value) {
    state = state.copyWith(symptomsInput: value, showValidationError: false);
  }

  /// Splits free-text input into a deduplicated symptom list: one symptom
  /// per line or comma-separated segment, trimmed, empty entries dropped,
  /// case-insensitive dedup — mirroring the web chip input's own dedup
  /// behavior (`frontend/src/js/chip-input.js`) despite the different UI.
  List<String> _parseSymptoms(String raw) {
    final seen = <String>{};
    final symptoms = <String>[];
    for (final part in raw.split(RegExp(r'[\n,]+'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) symptoms.add(trimmed);
    }
    return symptoms;
  }

  Future<bool> submit() async {
    if (state.isSubmitting) return false;
    final symptoms = _parseSymptoms(state.symptomsInput);
    if (symptoms.isEmpty) {
      state = state.copyWith(showValidationError: true);
      return false;
    }
    _lastSubmitted = symptoms;
    return _run(symptoms);
  }

  /// Resubmits the last successfully-parsed symptom list. A no-op if nothing
  /// has been submitted yet in this session (e.g. a stale error state).
  Future<bool> retry() async {
    final symptoms = _lastSubmitted;
    if (state.isSubmitting || symptoms == null) return false;
    return _run(symptoms);
  }

  Future<bool> _run(List<String> symptoms) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final result = await _api.checkSymptoms(symptoms);
      state = state.copyWith(isSubmitting: false, result: result);
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: _categorize(error));
      return false;
    }
  }

  /// Clears input, result, and error — the only "check other symptoms"
  /// mechanism. Nothing about a check is ever persisted, so this is also
  /// what a fresh visit to the screen effectively looks like.
  void reset() {
    _lastSubmitted = null;
    state = const SymptomCheckerState();
  }

  SymptomCheckErrorKind _categorize(Object error) {
    final api = ApiException.from(error);
    return switch (api) {
      _ when api.isTimeout => SymptomCheckErrorKind.timeout,
      _ when api.code == ApiException.codeServiceUnavailable =>
        SymptomCheckErrorKind.serviceUnavailable,
      _ => SymptomCheckErrorKind.generic,
    };
  }
}

final symptomCheckerControllerProvider =
    StateNotifierProvider.autoDispose<SymptomCheckerController, SymptomCheckerState>(
      (ref) => SymptomCheckerController(ref.read(symptomCheckerApiProvider)),
    );
