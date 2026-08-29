import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_users_api.dart';
import '../models/admin_user.dart';

final adminUsersApiProvider = Provider<AdminUsersApi>(
  (ref) => AdminUsersApi(ref.watch(dioProvider)),
);

/// How long typing pauses before the filtered list is re-fetched. Matches the
/// web page's 400 ms search debounce.
const Duration adminUsersSearchDebounce = Duration(milliseconds: 400);

class AdminUsersState {
  const AdminUsersState({
    this.users = const [],
    this.search = '',
    this.role,
    this.active,
    this.isLoading = true,
    this.isRefreshing = false,
    this.hasLoadedOnce = false,
    this.errorCode,
    this.pendingUserIds = const {},
    this.actionErrorCode,
  });

  final List<AdminUser> users;
  final String search;
  final AdminUserRole? role;
  final bool? active;
  final bool isLoading;
  final bool isRefreshing;

  /// True once a load has succeeded. Keeps a later filter/refresh failure from
  /// replacing the whole screen with a first-load error state.
  final bool hasLoadedOnce;
  final String? errorCode;

  /// Users with an activation call in flight — the source of duplicate-tap
  /// protection and per-row button disabling.
  final Set<String> pendingUserIds;

  /// The most recent failed activation, kept apart from [errorCode] so a failed
  /// mutation never looks like a failed load.
  final String? actionErrorCode;

  bool get hasActiveFilters =>
      search.trim().isNotEmpty || role != null || active != null;

  AdminUsersState copyWith({
    List<AdminUser>? users,
    String? search,
    AdminUserRole? role,
    bool clearRole = false,
    bool? active,
    bool clearActive = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoadedOnce,
    String? errorCode,
    bool clearError = false,
    Set<String>? pendingUserIds,
    String? actionErrorCode,
    bool clearActionError = false,
  }) => AdminUsersState(
    users: users ?? this.users,
    search: search ?? this.search,
    role: clearRole ? null : (role ?? this.role),
    active: clearActive ? null : (active ?? this.active),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    pendingUserIds: pendingUserIds ?? this.pendingUserIds,
    actionErrorCode: clearActionError
        ? null
        : (actionErrorCode ?? this.actionErrorCode),
  );
}

class AdminUsersController extends StateNotifier<AdminUsersState> {
  AdminUsersController(this._api, {this.searchDebounce = adminUsersSearchDebounce})
    : super(const AdminUsersState()) {
    load();
  }

  final AdminUsersApi _api;
  final Duration searchDebounce;

  bool _disposed = false;
  int _loadGeneration = 0;
  Timer? _searchTimer;

  Future<void> load({bool refresh = false}) async {
    _searchTimer?.cancel();
    final generation = ++_loadGeneration;
    if (_disposed) return;
    state = state.copyWith(
      isLoading: !refresh && !state.hasLoadedOnce,
      isRefreshing: refresh || state.hasLoadedOnce,
      clearError: true,
    );

    try {
      final users = await _api.list(
        search: state.search,
        role: state.role,
        active: state.active,
      );
      // A slower earlier request must never overwrite a newer one's result.
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWith(
        users: users,
        isLoading: false,
        isRefreshing: false,
        hasLoadedOnce: true,
      );
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorCode: ApiException.from(error).code,
      );
    }
  }

  Future<void> refresh() => load(refresh: true);

  /// Records the typed query immediately (so the field stays responsive) and
  /// schedules one debounced fetch.
  void setSearch(String value) {
    if (_disposed) return;
    state = state.copyWith(search: value);
    _searchTimer?.cancel();
    _searchTimer = Timer(searchDebounce, () {
      if (!_disposed) load();
    });
  }

  void setRole(AdminUserRole? role) {
    if (_disposed) return;
    state = state.copyWith(role: role, clearRole: role == null);
    load();
  }

  void setActive(bool? active) {
    if (_disposed) return;
    state = state.copyWith(active: active, clearActive: active == null);
    load();
  }

  void clearFilters() {
    if (_disposed) return;
    state = state.copyWith(search: '', clearRole: true, clearActive: true);
    load();
  }

  void clearActionError() {
    if (_disposed || state.actionErrorCode == null) return;
    state = state.copyWith(clearActionError: true);
  }

  /// Deactivates or reactivates [user]. Returns true on success.
  ///
  /// A second tap while the first call is in flight is dropped rather than
  /// queued — the endpoint bumps `authorization_version` and revokes the
  /// target's sessions, so sending it twice is not harmless.
  Future<bool> setUserActive(AdminUser user, {required bool activate}) async {
    if (_disposed || state.pendingUserIds.contains(user.id)) return false;

    state = state.copyWith(
      pendingUserIds: {...state.pendingUserIds, user.id},
      clearActionError: true,
    );

    try {
      final update = activate
          ? await _api.reactivate(user.id)
          : await _api.deactivate(user.id);
      if (_disposed) return true;
      state = state.copyWith(
        users: [
          for (final row in state.users)
            if (row.id == update.id)
              row.copyWith(
                isActive: update.isActive,
                emailVerified: update.emailVerified,
              )
            else
              row,
        ],
        pendingUserIds: _without(user.id),
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        pendingUserIds: _without(user.id),
        actionErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  Set<String> _without(String id) =>
      {...state.pendingUserIds}..removeWhere((value) => value == id);

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }
}

final adminUsersControllerProvider =
    StateNotifierProvider.autoDispose<AdminUsersController, AdminUsersState>(
      (ref) => AdminUsersController(ref.watch(adminUsersApiProvider)),
    );
