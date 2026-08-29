import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_contact_api.dart';
import '../models/admin_contact_message.dart';

final adminContactApiProvider = Provider<AdminContactApi>(
  (ref) => AdminContactApi(ref.watch(dioProvider)),
);

/// Rows per page. Matches the web inbox's `PAGE_SIZE`, and stays inside the
/// endpoint's 1–100 clamp once the +1 look-ahead row is added.
const int adminContactPageSize = 30;

class AdminContactInboxState {
  const AdminContactInboxState({
    this.messages = const [],
    this.status,
    this.isLoading = true,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasLoadedOnce = false,
    this.hasMore = false,
    this.errorCode,
    this.pageErrorCode,
  });

  final List<AdminContactMessage> messages;
  final AdminContactStatus? status;
  final bool isLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasLoadedOnce;

  /// True when the look-ahead row proved another page exists.
  final bool hasMore;
  final String? errorCode;

  /// A failure while appending the *next* page, kept apart from [errorCode]
  /// so the pages already on screen are not replaced by an error state.
  final String? pageErrorCode;

  AdminContactInboxState copyWith({
    List<AdminContactMessage>? messages,
    AdminContactStatus? status,
    bool clearStatus = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasLoadedOnce,
    bool? hasMore,
    String? errorCode,
    bool clearError = false,
    String? pageErrorCode,
    bool clearPageError = false,
  }) => AdminContactInboxState(
    messages: messages ?? this.messages,
    status: clearStatus ? null : (status ?? this.status),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
    hasMore: hasMore ?? this.hasMore,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    pageErrorCode: clearPageError
        ? null
        : (pageErrorCode ?? this.pageErrorCode),
  );
}

class AdminContactInboxController
    extends StateNotifier<AdminContactInboxState> {
  AdminContactInboxController(this._api)
    : super(const AdminContactInboxState()) {
    load();
  }

  final AdminContactApi _api;
  bool _disposed = false;
  int _generation = 0;

  Future<void> load({bool refresh = false}) async {
    final generation = ++_generation;
    if (_disposed) return;
    state = state.copyWith(
      isLoading: !refresh && !state.hasLoadedOnce,
      isRefreshing: refresh || state.hasLoadedOnce,
      clearError: true,
      clearPageError: true,
    );

    try {
      final page = await _api.list(
        status: state.status,
        // One row past the page size: its presence is how the endpoint's
        // offset pagination reveals that another page exists, since it
        // returns no total.
        limit: adminContactPageSize + 1,
        offset: 0,
      );
      if (_disposed || generation != _generation) return;
      final hasMore = page.items.length > adminContactPageSize;
      state = state.copyWith(
        messages: hasMore
            ? page.items.sublist(0, adminContactPageSize)
            : page.items,
        hasMore: hasMore,
        isLoading: false,
        isRefreshing: false,
        isLoadingMore: false,
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

  void setStatus(AdminContactStatus? status) {
    if (_disposed) return;
    state = state.copyWith(
      status: status,
      clearStatus: status == null,
      messages: const [],
      hasMore: false,
      hasLoadedOnce: false,
    );
    load();
  }

  Future<void> loadMore() async {
    if (_disposed || state.isLoadingMore || !state.hasMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearPageError: true);

    try {
      final page = await _api.list(
        status: state.status,
        limit: adminContactPageSize + 1,
        offset: state.messages.length,
      );
      // A filter change or refresh started while this page was in flight
      // makes the appended rows belong to a query that no longer applies.
      if (_disposed || generation != _generation) return;
      final hasMore = page.items.length > adminContactPageSize;
      final fetched = hasMore
          ? page.items.sublist(0, adminContactPageSize)
          : page.items;
      final known = state.messages.map((message) => message.id).toSet();
      state = state.copyWith(
        messages: [
          ...state.messages,
          // Rows can shift between pages when a message changes status
          // underneath an offset query; de-duplicating keeps the list keys
          // unique instead of rendering the same message twice.
          ...fetched.where((message) => !known.contains(message.id)),
        ],
        hasMore: hasMore,
        isLoadingMore: false,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        isLoadingMore: false,
        pageErrorCode: ApiException.from(error).code,
      );
    }
  }

  /// Applies a status transition made on the detail screen to the cached row,
  /// so returning to the inbox shows the new state without a round trip.
  void applyStatusUpdate(AdminContactStatusUpdate update) {
    if (_disposed) return;
    state = state.copyWith(
      messages: [
        for (final message in state.messages)
          if (message.id == update.id) message.copyWithStatus(update) else message,
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final adminContactInboxControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminContactInboxController,
      AdminContactInboxState
    >((ref) => AdminContactInboxController(ref.watch(adminContactApiProvider)));

// ── One message ──────────────────────────────────────────────────────────

class AdminContactDetailState {
  const AdminContactDetailState({
    this.message,
    this.isLoading = true,
    this.errorCode,
    this.isResolving = false,
    this.actionErrorCode,
  });

  final AdminContactMessage? message;
  final bool isLoading;
  final String? errorCode;
  final bool isResolving;
  final String? actionErrorCode;

  AdminContactDetailState copyWith({
    AdminContactMessage? message,
    bool? isLoading,
    String? errorCode,
    bool clearError = false,
    bool? isResolving,
    String? actionErrorCode,
    bool clearActionError = false,
  }) => AdminContactDetailState(
    message: message ?? this.message,
    isLoading: isLoading ?? this.isLoading,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    isResolving: isResolving ?? this.isResolving,
    actionErrorCode: clearActionError
        ? null
        : (actionErrorCode ?? this.actionErrorCode),
  );
}

class AdminContactDetailController
    extends StateNotifier<AdminContactDetailState> {
  AdminContactDetailController(this._api, this.messageId, this._onStatusChanged)
    : super(const AdminContactDetailState()) {
    load();
  }

  final AdminContactApi _api;
  final String messageId;
  final void Function(AdminContactStatusUpdate) _onStatusChanged;
  bool _disposed = false;
  bool _autoReadAttempted = false;

  Future<void> load() async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final message = await _api.get(messageId);
      if (_disposed) return;
      state = state.copyWith(message: message, isLoading: false);
      await _markReadIfNew(message);
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        errorCode: ApiException.from(error).code,
      );
    }
  }

  /// Opening a `new` message moves it to `read`, matching the web inbox.
  ///
  /// Attempted once per screen, and its failure is deliberately silent: the
  /// administrator is reading the message either way, and an error banner for
  /// a bookkeeping call they never asked for would be noise.
  Future<void> _markReadIfNew(AdminContactMessage message) async {
    if (_disposed || _autoReadAttempted || !message.isUnread) return;
    _autoReadAttempted = true;
    try {
      final update = await _api.markRead(messageId);
      if (_disposed) return;
      state = state.copyWith(message: message.copyWithStatus(update));
      _onStatusChanged(update);
    } catch (_) {
      // Left as `new`; the next open retries.
    }
  }

  Future<bool> resolve() async {
    final message = state.message;
    if (_disposed || message == null || state.isResolving) return false;
    state = state.copyWith(isResolving: true, clearActionError: true);
    try {
      final update = await _api.resolve(messageId);
      if (_disposed) return true;
      state = state.copyWith(
        message: message.copyWithStatus(update),
        isResolving: false,
      );
      _onStatusChanged(update);
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isResolving: false,
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

final adminContactDetailControllerProvider =
    StateNotifierProvider.autoDispose
        .family<
          AdminContactDetailController,
          AdminContactDetailState,
          String
        >(
          (ref, messageId) => AdminContactDetailController(
            ref.watch(adminContactApiProvider),
            messageId,
            (update) {
              // The inbox controller stays alive behind the pushed detail
              // screen; `read(... )` avoids creating it when it does not.
              ref
                  .read(adminContactInboxControllerProvider.notifier)
                  .applyStatusUpdate(update);
            },
          ),
        );
