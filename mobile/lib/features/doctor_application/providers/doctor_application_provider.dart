import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../discovery/models/doctor_models.dart';
import '../data/doctor_application_api.dart';
import '../models/doctor_application_model.dart';

final doctorApplicationApiProvider = Provider<DoctorApplicationApi>(
  (ref) => DoctorApplicationApi(ref.watch(dioProvider)),
);

class DoctorApplicationState {
  const DoctorApplicationState({
    this.applications = const [],
    this.specialties = const [],
    this.isLoading = true,
    this.isRefreshing = false,
    this.isSubmitting = false,
    this.withdrawingApplicationId,
    this.errorCode,
  });

  final List<DoctorApplication> applications;
  final List<Specialty> specialties;
  final bool isLoading;
  final bool isRefreshing;
  final bool isSubmitting;
  final String? withdrawingApplicationId;
  final String? errorCode;

  DoctorApplication? get pendingApplication {
    for (final application in applications) {
      if (application.status == DoctorApplicationStatus.pending) return application;
    }
    return null;
  }

  DoctorApplicationState copyWith({
    List<DoctorApplication>? applications,
    List<Specialty>? specialties,
    bool? isLoading,
    bool? isRefreshing,
    bool? isSubmitting,
    String? withdrawingApplicationId,
    bool clearWithdrawingApplicationId = false,
    String? errorCode,
    bool clearError = false,
  }) => DoctorApplicationState(
    applications: applications ?? this.applications,
    specialties: specialties ?? this.specialties,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    withdrawingApplicationId: clearWithdrawingApplicationId ? null : withdrawingApplicationId ?? this.withdrawingApplicationId,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
  );
}

class DoctorApplicationController extends StateNotifier<DoctorApplicationState> {
  DoctorApplicationController(this._api) : super(const DoctorApplicationState()) { load(); }

  final DoctorApplicationApi _api;
  bool _disposed = false;
  int _loadGeneration = 0;

  Future<void> load({bool refresh = false}) async {
    final generation = ++_loadGeneration;
    if (!_disposed) {
      state = state.copyWith(isLoading: !refresh, isRefreshing: refresh, clearError: true);
    }
    try {
      final result = await Future.wait([_api.loadMyApplications(), _api.loadSpecialties()]);
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWith(
        applications: result[0] as List<DoctorApplication>,
        specialties: result[1] as List<Specialty>,
        isLoading: false,
        isRefreshing: false,
      );
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWith(isLoading: false, isRefreshing: false, errorCode: ApiException.from(error).code);
    }
  }

  Future<void> refresh() => load(refresh: true);

  Future<bool> submit(DoctorApplicationRequest request) async {
    if (state.isSubmitting || _disposed) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final application = await _api.submitApplication(request);
      if (_disposed) return true;
      state = state.copyWith(
        applications: [application, ...state.applications.where((item) => item.id != application.id)],
        isSubmitting: false,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(isSubmitting: false, errorCode: ApiException.from(error).code);
      return false;
    }
  }

  Future<bool> withdraw(String applicationId) async {
    if (_disposed || state.withdrawingApplicationId != null) return false;
    state = state.copyWith(withdrawingApplicationId: applicationId, clearError: true);
    try {
      final application = await _api.withdrawApplication(applicationId);
      if (_disposed) return true;
      state = state.copyWith(
        applications: [for (final item in state.applications) if (item.id == application.id) application else item],
        clearWithdrawingApplicationId: true,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(clearWithdrawingApplicationId: true, errorCode: ApiException.from(error).code);
      return false;
    }
  }

  @override
  void dispose() { _disposed = true; super.dispose(); }
}

final doctorApplicationControllerProvider = StateNotifierProvider.autoDispose<DoctorApplicationController, DoctorApplicationState>(
  (ref) => DoctorApplicationController(ref.watch(doctorApplicationApiProvider)),
);
