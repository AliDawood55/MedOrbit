import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../data/drug_checker_api.dart';
import '../models/drug_check_result.dart';

final drugCheckerApiProvider = Provider<DrugCheckerApi>(
  (ref) => DrugCheckerApi(ref.watch(aiDioProvider)),
);

enum DrugCheckErrorKind { timeout, serviceUnavailable, generic }

class DrugCheckerState {
  const DrugCheckerState({
    this.medicationsInput = '',
    this.isSubmitting = false,
    this.result,
    this.error,
    this.showValidationError = false,
  });

  final String medicationsInput;
  final bool isSubmitting;
  final DrugCheckResult? result;
  final DrugCheckErrorKind? error;
  final bool showValidationError;

  DrugCheckerState copyWith({
    String? medicationsInput,
    bool? isSubmitting,
    DrugCheckResult? result,
    DrugCheckErrorKind? error,
    bool clearError = false,
    bool? showValidationError,
  }) {
    return DrugCheckerState(
      medicationsInput: medicationsInput ?? this.medicationsInput,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
      showValidationError: showValidationError ?? this.showValidationError,
    );
  }
}

class DrugCheckerController extends StateNotifier<DrugCheckerState> {
  DrugCheckerController(this._api) : super(const DrugCheckerState());

  final DrugCheckerApi _api;

  /// Kept only in memory for the lifetime of this `autoDispose` controller —
  /// never written to storage — so [retry] can resubmit the exact same
  /// medication list without asking the user to retype it.
  List<String>? _lastSubmitted;

  void updateInput(String value) {
    state = state.copyWith(medicationsInput: value, showValidationError: false);
  }

  /// Splits free-text input into a deduplicated medication list: one name
  /// per line or comma-separated segment, trimmed, empty entries dropped,
  /// case-insensitive dedup — mirroring the web chip input's own dedup
  /// behavior (`frontend/src/js/chip-input.js`) despite the different UI.
  List<String> _parseMedications(String raw) {
    final seen = <String>{};
    final medications = <String>[];
    for (final part in raw.split(RegExp(r'[\n,]+'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) medications.add(trimmed);
    }
    return medications;
  }

  /// Requires at least 2 distinct medications — a single drug has nothing to
  /// interact with — mirroring web's own `medications.length < 2` guard.
  Future<bool> submit() async {
    if (state.isSubmitting) return false;
    final medications = _parseMedications(state.medicationsInput);
    if (medications.length < 2) {
      state = state.copyWith(showValidationError: true);
      return false;
    }
    _lastSubmitted = medications;
    return _run(medications);
  }

  /// Resubmits the last successfully-parsed medication list. A no-op if
  /// nothing has been submitted yet in this session.
  Future<bool> retry() async {
    final medications = _lastSubmitted;
    if (state.isSubmitting || medications == null) return false;
    return _run(medications);
  }

  Future<bool> _run(List<String> medications) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final result = await _api.checkInteractions(medications);
      state = state.copyWith(isSubmitting: false, result: result);
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: _categorize(error));
      return false;
    }
  }

  /// Clears input, result, and error — the only "check other medications"
  /// mechanism. Nothing about a check is ever persisted.
  void reset() {
    _lastSubmitted = null;
    state = const DrugCheckerState();
  }

  DrugCheckErrorKind _categorize(Object error) {
    final api = ApiException.from(error);
    return switch (api) {
      _ when api.isTimeout => DrugCheckErrorKind.timeout,
      _ when api.code == ApiException.codeServiceUnavailable =>
        DrugCheckErrorKind.serviceUnavailable,
      _ => DrugCheckErrorKind.generic,
    };
  }
}

final drugCheckerControllerProvider =
    StateNotifierProvider.autoDispose<DrugCheckerController, DrugCheckerState>(
      (ref) => DrugCheckerController(ref.read(drugCheckerApiProvider)),
    );
