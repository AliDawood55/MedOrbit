import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_doctor_applications_api.dart';
import '../models/admin_doctor_application.dart';

final adminDoctorApplicationsApiProvider = Provider<AdminDoctorApplicationsApi>(
  (ref) => AdminDoctorApplicationsApi(ref.watch(dioProvider)),
);

class AdminApplicationsState {
  const AdminApplicationsState({
    this.applications = const [],
    this.status = AdminApplicationStatus.pending,
    this.isLoading = true,
    this.isRefreshing = false,
    this.hasLoadedOnce = false,
    this.errorCode,
  });

  final List<AdminDoctorApplication> applications;

  /// `pending` by default, matching the web review page whose `<select>`
  /// opens on Pending.
  final AdminApplicationStatus? status;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasLoadedOnce;
  final String? errorCode;

  AdminApplicationsState copyWith({
    List<AdminDoctorApplication>? applications,
    AdminApplicationStatus? status,
    bool clearStatus = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoadedOnce,
    String? errorCode,
    bool clearError = false,
  }) => AdminApplicationsState(
    applications: applications ?? this.applications,
    status: clearStatus ? null : (status ?? this.status),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
  );
}

class AdminApplicationsController extends StateNotifier<AdminApplicationsState> {
  AdminApplicationsController(this._api)
    : super(const AdminApplicationsState()) {
    load();
  }

  final AdminDoctorApplicationsApi _api;
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
      final applications = await _api.list(status: state.status);
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        applications: applications,
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

  void setStatus(AdminApplicationStatus? status) {
    if (_disposed) return;
    state = state.copyWith(status: status, clearStatus: status == null);
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final adminDoctorApplicationsControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminApplicationsController,
      AdminApplicationsState
    >((ref) => AdminApplicationsController(
      ref.watch(adminDoctorApplicationsApiProvider),
    ));

// ── Review of one application ────────────────────────────────────────────

class AdminApplicationReviewState {
  const AdminApplicationReviewState({
    this.application,
    this.isLoading = true,
    this.errorCode,
    this.isSubmitting = false,
    this.actionErrorCode,
  });

  final AdminDoctorApplication? application;
  final bool isLoading;
  final String? errorCode;

  /// True while an approve/reject call is in flight — the single source of
  /// duplicate-tap protection for both buttons.
  final bool isSubmitting;
  final String? actionErrorCode;

  AdminApplicationReviewState copyWith({
    AdminDoctorApplication? application,
    bool? isLoading,
    String? errorCode,
    bool clearError = false,
    bool? isSubmitting,
    String? actionErrorCode,
    bool clearActionError = false,
  }) => AdminApplicationReviewState(
    application: application ?? this.application,
    isLoading: isLoading ?? this.isLoading,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    isSubmitting: isSubmitting ?? this.isSubmitting,
    actionErrorCode: clearActionError
        ? null
        : (actionErrorCode ?? this.actionErrorCode),
  );
}

class AdminApplicationReviewController
    extends StateNotifier<AdminApplicationReviewState> {
  AdminApplicationReviewController(this._api, this.applicationId)
    : super(const AdminApplicationReviewState()) {
    load();
  }

  final AdminDoctorApplicationsApi _api;
  final String applicationId;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final application = await _api.get(applicationId);
      if (_disposed) return;
      state = state.copyWith(application: application, isLoading: false);
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        errorCode: ApiException.from(error).code,
      );
    }
  }

  Future<bool> approve() => _decide(() => _api.approve(applicationId));

  Future<bool> reject(String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return Future.value(false);
    return _decide(() => _api.reject(applicationId, trimmed));
  }

  Future<bool> _decide(Future<void> Function() call) async {
    if (_disposed || state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearActionError: true);
    try {
      await call();
      if (_disposed) return true;
      // The decision endpoints answer with the application dto, but the
      // reviewed row is re-read instead so the screen shows exactly what the
      // server now holds (reviewed_at, rejection_reason, approved_doctor_id).
      await load();
      if (_disposed) return true;
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isSubmitting: false,
        actionErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The review screen always re-reads its application by id rather than
/// trusting a row handed over from the list: approve/reject are irreversible,
/// and the list may have been sitting on screen while another administrator
/// decided the same application.
final adminApplicationReviewControllerProvider =
    StateNotifierProvider.autoDispose
        .family<
          AdminApplicationReviewController,
          AdminApplicationReviewState,
          String
        >(
          (ref, applicationId) => AdminApplicationReviewController(
            ref.watch(adminDoctorApplicationsApiProvider),
            applicationId,
          ),
        );
