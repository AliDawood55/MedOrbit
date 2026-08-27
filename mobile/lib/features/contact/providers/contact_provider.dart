import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/contact_api.dart';

final contactApiProvider = Provider<ContactApi>(
  (ref) => ContactApi(ref.watch(dioProvider)),
);

class ContactState {
  const ContactState({
    this.isSubmitting = false,
    this.sent = false,
    this.error,
  });
  final bool isSubmitting;
  final bool sent;
  final String? error;
  ContactState copyWith({
    bool? isSubmitting,
    bool? sent,
    String? error,
    bool clearError = false,
  }) => ContactState(
    isSubmitting: isSubmitting ?? this.isSubmitting,
    sent: sent ?? this.sent,
    error: clearError ? null : (error ?? this.error),
  );
}

class ContactController extends StateNotifier<ContactState> {
  ContactController(this._api) : super(const ContactState());
  final ContactApi _api;

  Future<bool> submit({
    required String subject,
    required String message,
  }) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, sent: false, clearError: true);
    try {
      await _api.submit(subject: subject.trim(), message: message.trim());
      state = state.copyWith(isSubmitting: false, sent: true);
      return true;
    } catch (_) {
      state = state.copyWith(isSubmitting: false, error: 'submit_failed');
      return false;
    }
  }
}

final contactControllerProvider =
    StateNotifierProvider.autoDispose<ContactController, ContactState>(
      (ref) => ContactController(ref.watch(contactApiProvider)),
    );
