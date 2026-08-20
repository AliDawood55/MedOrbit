import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../data/discovery_api.dart';
import '../models/clinic_models.dart';
import '../models/doctor_models.dart';

final discoveryApiProvider = Provider<DiscoveryApi>((ref) => DiscoveryApi(ref.watch(dioProvider)));

class DiscoveryError {
  const DiscoveryError({required this.message, required this.code, this.statusCode, this.retryable = true});

  final String message;
  final String code;
  final int? statusCode;
  final bool retryable;
}

class ClinicFilters {
  const ClinicFilters({
    this.region,
    this.service,
    this.insurance,
    this.search,
    this.type,
    this.page = 1,
    this.limit = 10,
  });

  final String? region;
  final String? service;
  final String? insurance;
  final String? search;
  final String? type;
  final int page;
  final int limit;

  ClinicFilters copyWith({
    String? region,
    bool clearRegion = false,
    String? service,
    bool clearService = false,
    String? insurance,
    bool clearInsurance = false,
    String? search,
    bool clearSearch = false,
    String? type,
    bool clearType = false,
    int? page,
    int? limit,
  }) {
    return ClinicFilters(
      region: clearRegion ? null : (region ?? this.region),
      service: clearService ? null : (service ?? this.service),
      insurance: clearInsurance ? null : (insurance ?? this.insurance),
      search: clearSearch ? null : (search ?? this.search),
      type: clearType ? null : (type ?? this.type),
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClinicFilters &&
        other.region == region &&
        other.service == service &&
        other.insurance == insurance &&
        other.search == search &&
        other.type == type &&
        other.page == page &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(region, service, insurance, search, type, page, limit);
}

class DoctorFilters {
  const DoctorFilters({
    this.specialty,
    this.region,
    this.minRating,
    this.minFee,
    this.maxFee,
    this.search,
    this.page = 1,
    this.limit = 10,
  });

  final String? specialty;
  final String? region;
  final double? minRating;
  final double? minFee;
  final double? maxFee;
  final String? search;
  final int page;
  final int limit;

  DoctorFilters copyWith({
    String? specialty,
    bool clearSpecialty = false,
    String? region,
    bool clearRegion = false,
    double? minRating,
    bool clearMinRating = false,
    double? minFee,
    bool clearMinFee = false,
    double? maxFee,
    bool clearMaxFee = false,
    String? search,
    bool clearSearch = false,
    int? page,
    int? limit,
  }) {
    return DoctorFilters(
      specialty: clearSpecialty ? null : (specialty ?? this.specialty),
      region: clearRegion ? null : (region ?? this.region),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      minFee: clearMinFee ? null : (minFee ?? this.minFee),
      maxFee: clearMaxFee ? null : (maxFee ?? this.maxFee),
      search: clearSearch ? null : (search ?? this.search),
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DoctorFilters &&
        other.specialty == specialty &&
        other.region == region &&
        other.minRating == minRating &&
        other.minFee == minFee &&
        other.maxFee == maxFee &&
        other.search == search &&
        other.page == page &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(specialty, region, minRating, minFee, maxFee, search, page, limit);
}

class DiscoveryState {
  const DiscoveryState({
    this.clinicFilters = const ClinicFilters(),
    this.clinics = const [],
    this.clinicPagination,
    this.nearbyClinics = const [],
    this.selectedClinicDetail,
    this.doctorFilters = const DoctorFilters(),
    this.doctors = const [],
    this.doctorPagination,
    this.selectedDoctorDetail,
    this.doctorAvailability = const [],
    this.isLoadingClinics = false,
    this.isLoadingMoreClinics = false,
    this.isLoadingNearbyClinics = false,
    this.isLoadingClinicDetail = false,
    this.isLoadingDoctors = false,
    this.isLoadingMoreDoctors = false,
    this.isLoadingDoctorDetail = false,
    this.isLoadingDoctorAvailability = false,
    this.clinicListError,
    this.nearbyError,
    this.clinicDetailError,
    this.doctorListError,
    this.doctorDetailError,
    this.doctorAvailabilityError,
  });

  final ClinicFilters clinicFilters;
  final List<Clinic> clinics;
  final ClinicPagination? clinicPagination;
  final List<Clinic> nearbyClinics;
  final ClinicDetailResponse? selectedClinicDetail;
  final DoctorFilters doctorFilters;
  final List<Doctor> doctors;
  final DoctorPagination? doctorPagination;
  final DoctorDetailResponse? selectedDoctorDetail;
  final List<DoctorAvailabilitySlot> doctorAvailability;
  final bool isLoadingClinics;
  final bool isLoadingMoreClinics;
  final bool isLoadingNearbyClinics;
  final bool isLoadingClinicDetail;
  final bool isLoadingDoctors;
  final bool isLoadingMoreDoctors;
  final bool isLoadingDoctorDetail;
  final bool isLoadingDoctorAvailability;
  final DiscoveryError? clinicListError;
  final DiscoveryError? nearbyError;
  final DiscoveryError? clinicDetailError;
  final DiscoveryError? doctorListError;
  final DiscoveryError? doctorDetailError;
  final DiscoveryError? doctorAvailabilityError;

  bool get clinicsEmpty => !isLoadingClinics && clinics.isEmpty;
  bool get doctorsEmpty => !isLoadingDoctors && doctors.isEmpty;
  bool get canLoadMoreClinics {
    final value = clinicPagination;
    if (value == null) return false;
    if (value.hasNext != null) return value.hasNext!;
    if (value.page != null && value.totalPages != null) return value.page! < value.totalPages!;
    return false;
  }

  bool get canLoadMoreDoctors {
    final value = doctorPagination;
    if (value == null) return false;
    if (value.hasNext != null) return value.hasNext!;
    if (value.page != null && value.totalPages != null) return value.page! < value.totalPages!;
    return false;
  }

  DiscoveryState copyWith({
    ClinicFilters? clinicFilters,
    List<Clinic>? clinics,
    ClinicPagination? clinicPagination,
    bool clearClinicPagination = false,
    List<Clinic>? nearbyClinics,
    ClinicDetailResponse? selectedClinicDetail,
    bool clearSelectedClinicDetail = false,
    DoctorFilters? doctorFilters,
    List<Doctor>? doctors,
    DoctorPagination? doctorPagination,
    bool clearDoctorPagination = false,
    DoctorDetailResponse? selectedDoctorDetail,
    bool clearSelectedDoctorDetail = false,
    List<DoctorAvailabilitySlot>? doctorAvailability,
    bool? isLoadingClinics,
    bool? isLoadingMoreClinics,
    bool? isLoadingNearbyClinics,
    bool? isLoadingClinicDetail,
    bool? isLoadingDoctors,
    bool? isLoadingMoreDoctors,
    bool? isLoadingDoctorDetail,
    bool? isLoadingDoctorAvailability,
    DiscoveryError? clinicListError,
    bool clearClinicListError = false,
    DiscoveryError? nearbyError,
    bool clearNearbyError = false,
    DiscoveryError? clinicDetailError,
    bool clearClinicDetailError = false,
    DiscoveryError? doctorListError,
    bool clearDoctorListError = false,
    DiscoveryError? doctorDetailError,
    bool clearDoctorDetailError = false,
    DiscoveryError? doctorAvailabilityError,
    bool clearDoctorAvailabilityError = false,
  }) {
    return DiscoveryState(
      clinicFilters: clinicFilters ?? this.clinicFilters,
      clinics: clinics ?? this.clinics,
      clinicPagination: clearClinicPagination ? null : (clinicPagination ?? this.clinicPagination),
      nearbyClinics: nearbyClinics ?? this.nearbyClinics,
      selectedClinicDetail: clearSelectedClinicDetail
          ? null
          : (selectedClinicDetail ?? this.selectedClinicDetail),
      doctorFilters: doctorFilters ?? this.doctorFilters,
      doctors: doctors ?? this.doctors,
      doctorPagination: clearDoctorPagination ? null : (doctorPagination ?? this.doctorPagination),
      selectedDoctorDetail: clearSelectedDoctorDetail
          ? null
          : (selectedDoctorDetail ?? this.selectedDoctorDetail),
      doctorAvailability: doctorAvailability ?? this.doctorAvailability,
      isLoadingClinics: isLoadingClinics ?? this.isLoadingClinics,
      isLoadingMoreClinics: isLoadingMoreClinics ?? this.isLoadingMoreClinics,
      isLoadingNearbyClinics: isLoadingNearbyClinics ?? this.isLoadingNearbyClinics,
      isLoadingClinicDetail: isLoadingClinicDetail ?? this.isLoadingClinicDetail,
      isLoadingDoctors: isLoadingDoctors ?? this.isLoadingDoctors,
      isLoadingMoreDoctors: isLoadingMoreDoctors ?? this.isLoadingMoreDoctors,
      isLoadingDoctorDetail: isLoadingDoctorDetail ?? this.isLoadingDoctorDetail,
      isLoadingDoctorAvailability: isLoadingDoctorAvailability ?? this.isLoadingDoctorAvailability,
      clinicListError: clearClinicListError ? null : (clinicListError ?? this.clinicListError),
      nearbyError: clearNearbyError ? null : (nearbyError ?? this.nearbyError),
      clinicDetailError: clearClinicDetailError ? null : (clinicDetailError ?? this.clinicDetailError),
      doctorListError: clearDoctorListError ? null : (doctorListError ?? this.doctorListError),
      doctorDetailError: clearDoctorDetailError ? null : (doctorDetailError ?? this.doctorDetailError),
      doctorAvailabilityError: clearDoctorAvailabilityError
          ? null
          : (doctorAvailabilityError ?? this.doctorAvailabilityError),
    );
  }
}

class DiscoveryController extends StateNotifier<DiscoveryState> {
  DiscoveryController(this._api) : super(const DiscoveryState());

  final DiscoveryApi _api;

  int _clinicRequestId = 0;
  int _doctorRequestId = 0;
  ClinicFilters? _activeClinicRequest;
  DoctorFilters? _activeDoctorRequest;
  bool _disposed = false;

  void updateClinicFilters(ClinicFilters filters) {
    _set(state.copyWith(clinicFilters: filters.copyWith(page: 1)));
  }

  Future<bool> loadClinics({ClinicFilters? filters}) async {
    final nextFilters = (filters ?? state.clinicFilters).copyWith(page: filters?.page ?? state.clinicFilters.page);
    if (state.isLoadingClinics && nextFilters == _activeClinicRequest) return false;
    final requestId = ++_clinicRequestId;
    _activeClinicRequest = nextFilters;
    _set(
      state.copyWith(
        clinicFilters: nextFilters,
        isLoadingClinics: true,
        clearClinicListError: true,
      ),
    );
    try {
      final response = await _api.listClinics(
        region: nextFilters.region,
        service: nextFilters.service,
        insurance: nextFilters.insurance,
        search: nextFilters.search,
        type: nextFilters.type,
        page: nextFilters.page,
        limit: nextFilters.limit,
      );
      if (requestId != _clinicRequestId) return false;
      _set(
        state.copyWith(
          clinics: response.clinics,
          clinicPagination: response.pagination,
          isLoadingClinics: false,
        ),
      );
      return true;
    } catch (error) {
      if (requestId != _clinicRequestId) return false;
      _set(state.copyWith(isLoadingClinics: false, clinicListError: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadMoreClinics() async {
    if (state.isLoadingClinics || state.isLoadingMoreClinics || !state.canLoadMoreClinics) return false;
    final nextFilters = state.clinicFilters.copyWith(
      page: (state.clinicPagination?.page ?? state.clinicFilters.page) + 1,
      limit: state.clinicPagination?.limit ?? state.clinicFilters.limit,
    );
    _set(state.copyWith(isLoadingMoreClinics: true, clearClinicListError: true));
    try {
      final response = await _api.listClinics(
        region: nextFilters.region,
        service: nextFilters.service,
        insurance: nextFilters.insurance,
        search: nextFilters.search,
        type: nextFilters.type,
        page: nextFilters.page,
        limit: nextFilters.limit,
      );
      _set(
        state.copyWith(
          clinicFilters: nextFilters,
          clinics: [...state.clinics, ...response.clinics],
          clinicPagination: response.pagination,
          isLoadingMoreClinics: false,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isLoadingMoreClinics: false, clinicListError: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadNearbyClinics({
    required double lat,
    required double lng,
    double radius = 5,
    String? type,
  }) async {
    if (state.isLoadingNearbyClinics) return false;
    _set(state.copyWith(isLoadingNearbyClinics: true, clearNearbyError: true));
    try {
      final response = await _api.nearbyClinics(lat: lat, lng: lng, radius: radius, type: type);
      _set(
        state.copyWith(
          nearbyClinics: response.clinics,
          isLoadingNearbyClinics: false,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isLoadingNearbyClinics: false, nearbyError: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadClinicDetail(String id) async {
    if (state.isLoadingClinicDetail) return false;
    _set(state.copyWith(isLoadingClinicDetail: true, clearClinicDetailError: true));
    try {
      final detail = await _api.getClinic(id);
      _set(
        state.copyWith(
          selectedClinicDetail: detail,
          isLoadingClinicDetail: false,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isLoadingClinicDetail: false, clinicDetailError: _safeError(error)));
      return false;
    }
  }

  void updateDoctorFilters(DoctorFilters filters) {
    _set(state.copyWith(doctorFilters: filters.copyWith(page: 1)));
  }

  Future<bool> loadDoctors({DoctorFilters? filters}) async {
    final nextFilters = (filters ?? state.doctorFilters).copyWith(page: filters?.page ?? state.doctorFilters.page);
    if (state.isLoadingDoctors && nextFilters == _activeDoctorRequest) return false;
    final requestId = ++_doctorRequestId;
    _activeDoctorRequest = nextFilters;
    _set(
      state.copyWith(
        doctorFilters: nextFilters,
        isLoadingDoctors: true,
        clearDoctorListError: true,
      ),
    );
    try {
      final response = await _api.listDoctors(
        specialty: nextFilters.specialty,
        region: nextFilters.region,
        minRating: nextFilters.minRating,
        minFee: nextFilters.minFee,
        maxFee: nextFilters.maxFee,
        search: nextFilters.search,
        page: nextFilters.page,
        limit: nextFilters.limit,
      );
      if (requestId != _doctorRequestId) return false;
      _set(
        state.copyWith(
          doctors: response.doctors,
          doctorPagination: response.pagination,
          isLoadingDoctors: false,
        ),
      );
      return true;
    } catch (error) {
      if (requestId != _doctorRequestId) return false;
      _set(state.copyWith(isLoadingDoctors: false, doctorListError: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadMoreDoctors() async {
    if (state.isLoadingDoctors || state.isLoadingMoreDoctors || !state.canLoadMoreDoctors) return false;
    final nextFilters = state.doctorFilters.copyWith(
      page: (state.doctorPagination?.page ?? state.doctorFilters.page) + 1,
      limit: state.doctorPagination?.limit ?? state.doctorFilters.limit,
    );
    _set(state.copyWith(isLoadingMoreDoctors: true, clearDoctorListError: true));
    try {
      final response = await _api.listDoctors(
        specialty: nextFilters.specialty,
        region: nextFilters.region,
        minRating: nextFilters.minRating,
        minFee: nextFilters.minFee,
        maxFee: nextFilters.maxFee,
        search: nextFilters.search,
        page: nextFilters.page,
        limit: nextFilters.limit,
      );
      _set(
        state.copyWith(
          doctorFilters: nextFilters,
          doctors: [...state.doctors, ...response.doctors],
          doctorPagination: response.pagination,
          isLoadingMoreDoctors: false,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isLoadingMoreDoctors: false, doctorListError: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadDoctorDetail(String id) async {
    if (state.isLoadingDoctorDetail) return false;
    _set(state.copyWith(isLoadingDoctorDetail: true, clearDoctorDetailError: true));
    try {
      final detail = await _api.getDoctor(id);
      _set(
        state.copyWith(
          selectedDoctorDetail: detail,
          isLoadingDoctorDetail: false,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isLoadingDoctorDetail: false, doctorDetailError: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadDoctorAvailability(String id, {String? date}) async {
    if (state.isLoadingDoctorAvailability) return false;
    _set(state.copyWith(isLoadingDoctorAvailability: true, clearDoctorAvailabilityError: true));
    try {
      final response = await _api.getDoctorAvailability(id, date: date);
      _set(
        state.copyWith(
          doctorAvailability: response.slots,
          isLoadingDoctorAvailability: false,
        ),
      );
      return true;
    } catch (error) {
      _set(
        state.copyWith(
          isLoadingDoctorAvailability: false,
          doctorAvailabilityError: _safeError(error),
        ),
      );
      return false;
    }
  }

  void clearErrors() {
    _set(
      state.copyWith(
        clearClinicListError: true,
        clearNearbyError: true,
        clearClinicDetailError: true,
        clearDoctorListError: true,
        clearDoctorDetailError: true,
        clearDoctorAvailabilityError: true,
      ),
    );
  }

  DiscoveryError _safeError(Object error) {
    final api = ApiException.from(error);
    return DiscoveryError(
      message: api.message,
      code: api.code,
      statusCode: api.statusCode,
      retryable: true,
    );
  }

  void _set(DiscoveryState next) {
    if (!_disposed) state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final discoveryControllerProvider = StateNotifierProvider<DiscoveryController, DiscoveryState>(
  (ref) => DiscoveryController(ref.watch(discoveryApiProvider)),
);
