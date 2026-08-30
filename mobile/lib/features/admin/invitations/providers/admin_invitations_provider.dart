import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_invitations_api.dart';
import '../models/admin_invitation.dart';

final adminInvitationsApiProvider = Provider<AdminInvitationsApi>(
  (ref) => AdminInvitationsApi(ref.watch(dioProvider)),
);

class AdminInvitationsState {
  const AdminInvitationsState({
    this.invitations = const [],
    this.isLoading = true,
    this.isRefreshing = false,
    this.hasLoadedOnce = false,
    this.errorCode,
    this.isCreating = false,
    this.createErrorCode,
    this.lastCreation,
    this.revokingIds = const {},
    this.revokeErrorCode,
  });

  final List<AdminInvitation> invitations;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasLoadedOnce;
  final String? errorCode;
  final bool isCreating;
  final String? createErrorCode;

  /// The one-time acceptance link from the most recent creation, held in
  /// memory only for as long as this screen lives.
  final AdminInvitationCreation? lastCreation;
  final Set<String> revokingIds;
  final String? revokeErrorCode;

  List<AdminInvitation> get pending =>
      invitations.where((invitation) => invitation.isRevocable).toList();

  List<AdminInvitation> get history =>
      invitations.where((invitation) => !invitation.isRevocable).toList();

  AdminInvitationsState copyWith({
    List<AdminInvitation>? invitations,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoadedOnce,
    String? errorCode,
    bool clearError = false,
    bool? isCreating,
    String? createErrorCode,
    bool clearCreateError = false,
    AdminInvitationCreation? lastCreation,
    bool clearLastCreation = false,
    Set<String>? revokingIds,
    String? revokeErrorCode,
    bool clearRevokeError = false,
  }) => AdminInvitationsState(
    invitations: invitations ?? this.invitations,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    isCreating: isCreating ?? this.isCreating,
    createErrorCode: clearCreateError
        ? null
        : (createErrorCode ?? this.createErrorCode),
    lastCreation: clearLastCreation ? null : (lastCreation ?? this.lastCreation),
    revokingIds: revokingIds ?? this.revokingIds,
    revokeErrorCode: clearRevokeError
        ? null
        : (revokeErrorCode ?? this.revokeErrorCode),
  );
}

class AdminInvitationsController extends StateNotifier<AdminInvitationsState> {
  AdminInvitationsController(this._api)
    : super(const AdminInvitationsState()) {
    load();
  }

  final AdminInvitationsApi _api;
  bool _disposed = false;
  int _generation = 0;

  Future<void> load({bool refresh = false}) async {
    final generation = ++_generation;
    if (_disposed) return;
    state = state.copyWith(
      isLoading: !refresh && !state.hasLoadedOnce,
      isRefreshing: refresh || state.hasLoadedOnce,
      clearError: true,
    );
    try {
      final invitations = await _api.list();
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        invitations: invitations,
        isLoading: false,
        isRefreshing: false,
        hasLoadedOnce: true,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorCode: ApiException.from(error).code,
      );
    }
  }

  Future<void> refresh() => load(refresh: true);

  /// Creates an invitation. Returns true on success; the one-time acceptance
  /// link then lives on [AdminInvitationsState.lastCreation].
  Future<bool> create(String email) async {
    if (_disposed || state.isCreating) return false;
    state = state.copyWith(
      isCreating: true,
      clearCreateError: true,
      clearLastCreation: true,
    );
    try {
      final creation = await _api.create(email);
      if (_disposed) return true;
      state = state.copyWith(isCreating: false, lastCreation: creation);
      await load(refresh: true);
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isCreating: false,
        createErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  /// Clears the one-time link from memory once the super admin has delivered
  /// it, so it is not left sitting on screen.
  void dismissCreationLink() {
    if (_disposed || state.lastCreation == null) return;
    state = state.copyWith(clearLastCreation: true);
  }

  void clearCreateError() {
    if (_disposed || state.createErrorCode == null) return;
    state = state.copyWith(clearCreateError: true);
  }

  Future<bool> revoke(String invitationId) async {
    if (_disposed || state.revokingIds.contains(invitationId)) return false;
    state = state.copyWith(
      revokingIds: {...state.revokingIds, invitationId},
      clearRevokeError: true,
    );
    try {
      final updated = await _api.revoke(invitationId);
      if (_disposed) return true;
      state = state.copyWith(
        invitations: [
          for (final invitation in state.invitations)
            if (invitation.id == updated.id) updated else invitation,
        ],
        revokingIds: _without(invitationId),
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        revokingIds: _without(invitationId),
        revokeErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  Set<String> _without(String id) =>
      {...state.revokingIds}..removeWhere((value) => value == id);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final adminInvitationsControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminInvitationsController,
      AdminInvitationsState
    >(
      (ref) =>
          AdminInvitationsController(ref.watch(adminInvitationsApiProvider)),
    );

// ── Acceptance (performed by the invited account) ────────────────────────

class AdminInvitationAcceptState {
  const AdminInvitationAcceptState({
    this.isSubmitting = false,
    this.accepted = false,
    this.errorCode,
  });

  final bool isSubmitting;
  final bool accepted;
  final String? errorCode;

  AdminInvitationAcceptState copyWith({
    bool? isSubmitting,
    bool? accepted,
    String? errorCode,
    bool clearError = false,
  }) => AdminInvitationAcceptState(
    isSubmitting: isSubmitting ?? this.isSubmitting,
    accepted: accepted ?? this.accepted,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
  );
}

class AdminInvitationAcceptController
    extends StateNotifier<AdminInvitationAcceptState> {
  AdminInvitationAcceptController(this._api)
    : super(const AdminInvitationAcceptState());

  final AdminInvitationsApi _api;
  bool _disposed = false;

  /// Accepts using the token parsed out of [input] (a pasted link or the bare
  /// token). Returns false without a request when nothing usable was pasted.
  Future<bool> accept(String input) async {
    if (_disposed || state.isSubmitting || state.accepted) return false;
    final token = adminInvitationTokenFromInput(input);
    if (token == null) {
      state = state.copyWith(errorCode: 'INVALID_INVITATION');
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _api.accept(token);
      if (_disposed) return true;
      state = state.copyWith(isSubmitting: false, accepted: true);
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isSubmitting: false,
        errorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  void clearError() {
    if (_disposed || state.errorCode == null) return;
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final adminInvitationAcceptControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminInvitationAcceptController,
      AdminInvitationAcceptState
    >(
      (ref) => AdminInvitationAcceptController(
        ref.watch(adminInvitationsApiProvider),
      ),
    );
