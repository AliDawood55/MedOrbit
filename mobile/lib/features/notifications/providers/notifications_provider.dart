import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/notifications_api.dart';
import '../models/notification_model.dart';

final notificationsApiProvider = Provider<NotificationsApi>(
  (ref) => NotificationsApi(ref.watch(dioProvider)),
);

class NotificationsState {
  const NotificationsState({
    this.notifications = const AsyncValue.loading(),
    this.unreadOnly = false,
    this.pendingIds = const {},
    this.isMarkingAllRead = false,
  });

  final AsyncValue<List<NotificationModel>> notifications;
  final bool unreadOnly;

  /// Ids currently mid mark-read/delete — blocks a duplicate tap on the same
  /// item while its request is in flight.
  final Set<String> pendingIds;
  final bool isMarkingAllRead;

  List<NotificationModel> get all => notifications.valueOrNull ?? const [];

  /// The list the screen should render — filtered client-side, matching the
  /// web app (the backend has no unread/all query param).
  List<NotificationModel> get visible =>
      unreadOnly ? all.where((n) => !n.isRead).toList() : all;

  int get unreadCount => all.where((n) => !n.isRead).length;

  NotificationsState copyWith({
    AsyncValue<List<NotificationModel>>? notifications,
    bool? unreadOnly,
    Set<String>? pendingIds,
    bool? isMarkingAllRead,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      pendingIds: pendingIds ?? this.pendingIds,
      isMarkingAllRead: isMarkingAllRead ?? this.isMarkingAllRead,
    );
  }
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._api) : super(const NotificationsState()) {
    load();
  }

  final NotificationsApi _api;
  bool _disposed = false;

  Future<void> load() async {
    state = state.copyWith(notifications: const AsyncValue.loading());
    final result = await AsyncValue.guard(() => _api.list());
    if (_disposed) return;
    state = state.copyWith(notifications: result);
  }

  Future<void> retry() => load();

  void setUnreadOnly(bool value) {
    state = state.copyWith(unreadOnly: value);
  }

  /// Optimistic: flips `isRead` locally, then confirms against the server.
  /// Rolls back to the pre-tap list on failure.
  Future<bool> markRead(String id) async {
    if (state.pendingIds.contains(id)) return false;
    final previous = state.all;
    final index = previous.indexWhere((n) => n.id == id);
    if (index == -1 || previous[index].isRead) return true;

    final optimistic = [
      for (final n in previous) if (n.id == id) n.copyWith(isRead: true, readAt: DateTime.now()) else n,
    ];
    state = state.copyWith(
      notifications: AsyncValue.data(optimistic),
      pendingIds: {...state.pendingIds, id},
    );

    try {
      final updated = await _api.markRead(id);
      if (_disposed) return true;
      final latest = state.all;
      state = state.copyWith(
        notifications: AsyncValue.data([for (final n in latest) if (n.id == id) updated else n]),
        pendingIds: {...state.pendingIds}..remove(id),
      );
      return true;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        notifications: AsyncValue.data(previous),
        pendingIds: {...state.pendingIds}..remove(id),
      );
      return false;
    }
  }

  /// Optimistic: flips every unread item locally, then confirms. Rolls back
  /// the whole list on failure.
  Future<bool> markAllRead() async {
    if (state.isMarkingAllRead) return false;
    final previous = state.all;
    if (previous.every((n) => n.isRead)) return true;

    final now = DateTime.now();
    final optimistic = [for (final n in previous) n.isRead ? n : n.copyWith(isRead: true, readAt: now)];
    state = state.copyWith(notifications: AsyncValue.data(optimistic), isMarkingAllRead: true);

    try {
      await _api.markAllRead();
      if (_disposed) return true;
      state = state.copyWith(isMarkingAllRead: false);
      return true;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(notifications: AsyncValue.data(previous), isMarkingAllRead: false);
      return false;
    }
  }

  /// Optimistic: removes the item locally, then confirms. Restores it (in
  /// its original position) on failure.
  Future<bool> delete(String id) async {
    if (state.pendingIds.contains(id)) return false;
    final previous = state.all;
    if (!previous.any((n) => n.id == id)) return false;

    final optimistic = [for (final n in previous) if (n.id != id) n];
    state = state.copyWith(
      notifications: AsyncValue.data(optimistic),
      pendingIds: {...state.pendingIds, id},
    );

    try {
      await _api.delete(id);
      if (_disposed) return true;
      state = state.copyWith(pendingIds: {...state.pendingIds}..remove(id));
      return true;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        notifications: AsyncValue.data(previous),
        pendingIds: {...state.pendingIds}..remove(id),
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

final notificationsControllerProvider =
    StateNotifierProvider.autoDispose<NotificationsController, NotificationsState>(
      (ref) => NotificationsController(ref.watch(notificationsApiProvider)),
    );
