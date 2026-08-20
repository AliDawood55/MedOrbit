import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/notifications/data/notifications_api.dart';
import 'package:mobile/features/notifications/models/notification_model.dart';
import 'package:mobile/features/notifications/providers/notifications_provider.dart';

NotificationModel _notification({required String id, bool isRead = false, String type = 'appointment'}) {
  return NotificationModel(
    id: id,
    notificationType: type,
    titleAr: 'عنوان $id',
    titleEn: 'Title $id',
    messageAr: 'رسالة $id',
    messageEn: 'Message $id',
    isRead: isRead,
    createdAt: DateTime.parse('2026-08-05T09:00:00.000Z'),
    readAt: isRead ? DateTime.parse('2026-08-05T09:30:00.000Z') : null,
  );
}

void main() {
  test('initial load succeeds and populates the list', () async {
    final api = _FakeNotificationsApi()..listResults.add([_notification(id: 'n1'), _notification(id: 'n2', isRead: true)]);
    final container = _container(api);
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(notificationsControllerProvider);
    expect(state.notifications.hasValue, isTrue);
    expect(state.all, hasLength(2));
    expect(state.unreadOnly, isFalse);
  });

  test('an empty list is a valid loaded state, not an error', () async {
    final api = _FakeNotificationsApi()..listResults.add(const <NotificationModel>[]);
    final container = _container(api);
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(notificationsControllerProvider);
    expect(state.notifications.hasError, isFalse);
    expect(state.all, isEmpty);
    expect(state.visible, isEmpty);
    expect(state.unreadCount, 0);
  });

  test('a load failure surfaces as an error state, and retry recovers', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add(const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable))
      ..listResults.add([_notification(id: 'n1')]);
    final container = _container(api);
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(notificationsControllerProvider).notifications.hasError, isTrue);

    await container.read(notificationsControllerProvider.notifier).retry();

    final state = container.read(notificationsControllerProvider);
    expect(state.notifications.hasError, isFalse);
    expect(state.all, hasLength(1));
    expect(api.listCallCount, 2);
  });

  test('unreadOnly filters the visible list client-side without refetching', () async {
    final api = _FakeNotificationsApi()..listResults.add([_notification(id: 'n1'), _notification(id: 'n2', isRead: true)]);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    notifier.setUnreadOnly(true);

    final state = container.read(notificationsControllerProvider);
    expect(state.visible, hasLength(1));
    expect(state.visible.single.id, 'n1');
    expect(api.listCallCount, 1, reason: 'filtering must not trigger a refetch');
  });

  test('markRead flips isRead optimistically, then reconciles with the server response', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..markReadResults.add(_notification(id: 'n1', isRead: true));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final future = notifier.markRead('n1');
    // The optimistic flip happens synchronously, before the network await.
    expect(container.read(notificationsControllerProvider).all.single.isRead, isTrue);

    final ok = await future;

    expect(ok, isTrue);
    expect(container.read(notificationsControllerProvider).all.single.isRead, isTrue);
    expect(container.read(notificationsControllerProvider).pendingIds, isEmpty);
    expect(api.markReadCalls, ['n1']);
  });

  test('markRead rolls back to unread on failure', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..markReadResults.add(const ApiException(message: 'Notification not found', code: 'NOT_FOUND'));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.markRead('n1');

    expect(ok, isFalse);
    expect(container.read(notificationsControllerProvider).all.single.isRead, isFalse);
    expect(container.read(notificationsControllerProvider).pendingIds, isEmpty);
  });

  test('markAllRead flips every unread item optimistically and confirms', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2')])
      ..markAllReadResults.add(2);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.markAllRead();

    expect(ok, isTrue);
    expect(container.read(notificationsControllerProvider).all.every((n) => n.isRead), isTrue);
    expect(container.read(notificationsControllerProvider).isMarkingAllRead, isFalse);
    expect(api.markAllReadCallCount, 1);
  });

  test('markAllRead rolls back the whole list on failure', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2')])
      ..markAllReadResults.add(const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.markAllRead();

    expect(ok, isFalse);
    expect(container.read(notificationsControllerProvider).all.every((n) => !n.isRead), isTrue);
  });

  test('delete removes the item optimistically and confirms', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2')])
      ..deleteResults.add(null);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final future = notifier.delete('n1');
    expect(
      container.read(notificationsControllerProvider).all.map((n) => n.id),
      ['n2'],
      reason: 'removed optimistically, before the network await',
    );

    final ok = await future;

    expect(ok, isTrue);
    expect(container.read(notificationsControllerProvider).all.map((n) => n.id), ['n2']);
    expect(api.deleteCalls, ['n1']);
  });

  test('delete restores the item, in its original position, on failure', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2')])
      ..deleteResults.add(const ApiException(message: 'Notification not found', code: 'NOT_FOUND'));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.delete('n1');

    expect(ok, isFalse);
    expect(container.read(notificationsControllerProvider).all.map((n) => n.id), ['n1', 'n2']);
  });

  test('a second markRead on the same id while the first is in flight is ignored', () async {
    final completer = Completer<NotificationModel>();
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..markReadResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final first = notifier.markRead('n1');
    final second = await notifier.markRead('n1');

    expect(second, isFalse, reason: 'blocked while a request for the same id is already pending');
    completer.complete(_notification(id: 'n1', isRead: true));
    await first;
    expect(api.markReadCalls, ['n1'], reason: 'only one network call was actually made');
  });

  test('a second delete on the same id while the first is in flight is ignored', () async {
    final completer = Completer<void>();
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..deleteResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final first = notifier.delete('n1');
    final second = await notifier.delete('n1');

    expect(second, isFalse);
    completer.complete();
    await first;
    expect(api.deleteCalls, ['n1']);
  });

  test('a second markAllRead while the first is in flight is ignored', () async {
    final completer = Completer<int>();
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..markAllReadResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final first = notifier.markAllRead();
    final second = await notifier.markAllRead();

    expect(second, isFalse);
    completer.complete(1);
    await first;
    expect(api.markAllReadCallCount, 1);
  });

  test('unreadCount reflects only unread items regardless of the active filter', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2', isRead: true), _notification(id: 'n3')]);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(notificationsControllerProvider).unreadCount, 2);
    notifier.setUnreadOnly(true);
    expect(container.read(notificationsControllerProvider).unreadCount, 2);
  });

  test('notification title/message text is never printed during load or mutation', () async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..markReadResults.add(_notification(id: 'n1', isRead: true));
    final printed = <String>[];

    await runZoned(
      () async {
        final container = _container(api);
        addTearDown(container.dispose);
        final notifier = container.read(notificationsControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);
        await notifier.markRead('n1');
      },
      zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
    );

    expect(printed, isEmpty);
  });
}

ProviderContainer _container(NotificationsApi api) {
  final container = ProviderContainer(overrides: [notificationsApiProvider.overrideWithValue(api)]);
  // `notificationsControllerProvider` is `autoDispose`. `container.read()`
  // alone doesn't keep it alive across `await` boundaries — Riverpod
  // schedules disposal the instant nothing is watching, which fires between
  // awaited statements in these tests. In the real app `NotificationsScreen`
  // holds it alive via `ref.watch` for as long as it's mounted; mirror that
  // with a real listener (same fix used in booking_provider_test.dart).
  container.listen(notificationsControllerProvider, (previous, next) {});
  return container;
}

class _FakeNotificationsApi extends NotificationsApi {
  _FakeNotificationsApi() : super(Dio());

  /// Each entry is a `List<NotificationModel>` (success), an error object, or
  /// a `Future<List<NotificationModel>>` (for tests that need to control
  /// exactly when the call resolves, e.g. concurrency guards).
  final listResults = <Object>[];
  final markReadResults = <Object>[];
  final markAllReadResults = <Object>[];

  /// `null` = success, otherwise an error object or a `Future<void>`.
  final deleteResults = <Object?>[];

  final markReadCalls = <String>[];
  final deleteCalls = <String>[];
  int markAllReadCallCount = 0;
  int listCallCount = 0;

  @override
  Future<List<NotificationModel>> list() {
    listCallCount++;
    final next = listResults.removeAt(0);
    if (next is Future<List<NotificationModel>>) return next;
    if (next is List<NotificationModel>) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<NotificationModel> markRead(String id) {
    markReadCalls.add(id);
    final next = markReadResults.removeAt(0);
    if (next is Future<NotificationModel>) return next;
    if (next is NotificationModel) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<int> markAllRead() {
    markAllReadCallCount++;
    final next = markAllReadResults.removeAt(0);
    if (next is Future<int>) return next;
    if (next is int) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<void> delete(String id) {
    deleteCalls.add(id);
    final next = deleteResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }
}
