import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_audit_api.dart';
import '../models/admin_audit_log.dart';

final adminAuditApiProvider = Provider<AdminAuditApi>(
  (ref) => AdminAuditApi(ref.watch(dioProvider)),
);

/// How many rows the screen renders. The endpoint sends every row inside the
/// window with no server-side limit, so the list is capped here to keep a busy
/// window from building thousands of widgets; the cap is surfaced to the
/// reader rather than hidden.
const int adminAuditRenderLimit = 200;

class AdminAuditState {
  const AdminAuditState({
    this.entries = const [],
    this.range = AdminAuditRange.week,
    this.entityType,
    this.isLoading = true,
    this.isRefreshing = false,
    this.hasLoadedOnce = false,
    this.truncated = false,
    this.errorCode,
  });

  final List<AdminAuditLog> entries;
  final AdminAuditRange range;
  final String? entityType;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasLoadedOnce;

  /// True when the window returned more rows than [adminAuditRenderLimit].
  final bool truncated;
  final String? errorCode;

  AdminAuditState copyWith({
    List<AdminAuditLog>? entries,
    AdminAuditRange? range,
    String? entityType,
    bool clearEntityType = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoadedOnce,
    bool? truncated,
    String? errorCode,
    bool clearError = false,
  }) => AdminAuditState(
    entries: entries ?? this.entries,
    range: range ?? this.range,
    entityType: clearEntityType ? null : (entityType ?? this.entityType),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
    truncated: truncated ?? this.truncated,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
  );
}

class AdminAuditController extends StateNotifier<AdminAuditState> {
  AdminAuditController(this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const AdminAuditState()) {
    load();
  }

  final AdminAuditApi _api;
  final DateTime Function() _clock;
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
      final entries = await _api.list(
        from: _clock().subtract(adminAuditRangeDuration(state.range)),
        entityType: state.entityType,
      );
      if (_disposed || generation != _generation) return;
      final truncated = entries.length > adminAuditRenderLimit;
      state = state.copyWith(
        entries: truncated
            ? entries.sublist(0, adminAuditRenderLimit)
            : entries,
        truncated: truncated,
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

  void setRange(AdminAuditRange range) {
    if (_disposed || range == state.range) return;
    state = state.copyWith(range: range);
    load();
  }

  void setEntityType(String? entityType) {
    if (_disposed) return;
    state = state.copyWith(
      entityType: entityType,
      clearEntityType: entityType == null,
    );
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final adminAuditControllerProvider =
    StateNotifierProvider.autoDispose<AdminAuditController, AdminAuditState>(
      (ref) => AdminAuditController(ref.watch(adminAuditApiProvider)),
    );
