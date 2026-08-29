import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/contact/data/admin_contact_api.dart';
import 'package:mobile/features/admin/contact/models/admin_contact_message.dart';
import 'package:mobile/features/admin/contact/providers/admin_contact_provider.dart';

AdminContactMessage _message(String id, {String status = 'new'}) =>
    AdminContactMessage.fromJson({
      'id': id,
      'authenticated': true,
      'sender_name': 'Lina',
      'sender_email': 'lina@example.test',
      'subject': 'Subject $id',
      'message': 'Body $id',
      'status': status,
      'created_at': '2026-02-01T09:00:00Z',
    });

AdminContactStatusUpdate _update(String id, String status) =>
    AdminContactStatusUpdate.fromJson({
      'id': id,
      'status': status,
      'read_at': '2026-02-02T08:00:00Z',
      'resolved_at': status == 'resolved' ? '2026-02-02T09:00:00Z' : null,
    });

void main() {
  group('inbox pagination', () {
    test('requests one row past the page size to detect a next page', () async {
      final api = _FakeApi()
        ..pages = [
          List.generate(
            adminContactPageSize + 1,
            (index) => _message('m$index'),
          ),
        ];
      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(api.limits.single, adminContactPageSize + 1);
      expect(api.offsets.single, 0);
      // The look-ahead row proves a next page exists but is not rendered.
      expect(controller.state.messages.length, adminContactPageSize);
      expect(controller.state.hasMore, isTrue);
    });

    test('a short page means there is nothing more to load', () async {
      final api = _FakeApi()
        ..pages = [
          [_message('m0')],
        ];
      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(controller.state.hasMore, isFalse);
      expect(controller.state.messages.length, 1);
    });

    test('loadMore appends from the current offset and de-duplicates', () async {
      final first = List.generate(
        adminContactPageSize + 1,
        (index) => _message('m$index'),
      );
      // The second page repeats one row, as an offset query can when a message
      // changes status underneath it.
      final second = [_message('m${adminContactPageSize - 1}'), _message('x1')];

      final api = _FakeApi()..pages = [first, second];
      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      await controller.loadMore();
      expect(api.offsets, [0, adminContactPageSize]);
      expect(controller.state.messages.length, adminContactPageSize + 1);
      expect(
        controller.state.messages.map((m) => m.id).toSet().length,
        controller.state.messages.length,
      );
      expect(controller.state.hasMore, isFalse);
    });

    test('loadMore is ignored when there is no next page or one is running', () async {
      final api = _FakeApi()
        ..pages = [
          [_message('m0')],
        ];
      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      await controller.loadMore();
      expect(api.listCalls, 1);
    });

    test('a page failure keeps the loaded rows and offers a retry code', () async {
      final api = _FakeApi()
        ..pages = [
          List.generate(
            adminContactPageSize + 1,
            (index) => _message('m$index'),
          ),
        ];

      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      // Only the *next* page fails; the first one already landed.
      api.listError = const ApiException(
        message: 'raw backend detail',
        code: 'INTERNAL_ERROR',
      );
      await controller.loadMore();
      expect(controller.state.pageErrorCode, 'INTERNAL_ERROR');
      expect(controller.state.errorCode, isNull);
      expect(controller.state.messages.length, adminContactPageSize);
    });

    test('changing the status filter resets the list and reloads from zero', () async {
      final api = _FakeApi()
        ..pages = [
          [_message('m0')],
          [_message('r0', status: 'resolved')],
        ];
      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.setStatus(AdminContactStatus.resolved);
      await pumpEventQueue();

      expect(api.statuses, [null, AdminContactStatus.resolved]);
      expect(api.offsets, [0, 0]);
      expect(controller.state.messages.single.id, 'r0');
    });

    test('a page that lands after a filter change is discarded', () async {
      final api = _FakeApi()
        ..pages = [
          List.generate(
            adminContactPageSize + 1,
            (index) => _message('m$index'),
          ),
        ];
      final controller = AdminContactInboxController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final gate = Completer<List<AdminContactMessage>>();
      api.gate = gate;
      final pending = controller.loadMore();
      await pumpEventQueue();

      api.gate = null;
      api.fixedPage = [_message('fresh')];
      controller.setStatus(AdminContactStatus.read);
      await pumpEventQueue();
      expect(controller.state.messages.single.id, 'fresh');

      gate.complete([_message('stale')]);
      await pending;
      // The in-flight page belonged to the previous filter and is dropped.
      expect(controller.state.messages.single.id, 'fresh');
    });
  });

  group('detail', () {
    test('opening a new message marks it read once and notifies the inbox', () async {
      final api = _FakeApi()..message = _message('m1');
      final updates = <AdminContactStatusUpdate>[];
      final controller = AdminContactDetailController(api, 'm1', updates.add);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(api.markReadCalls, 1);
      expect(controller.state.message!.status, AdminContactStatus.read);
      expect(updates.single.status, AdminContactStatus.read);

      await controller.load();
      // Already attempted for this screen; a second open would retry, a
      // second load of the same screen must not.
      expect(api.markReadCalls, 1);
    });

    test('an already-read message is never marked read again', () async {
      final api = _FakeApi()..message = _message('m1', status: 'read');
      final controller = AdminContactDetailController(api, 'm1', (_) {});
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(api.markReadCalls, 0);
    });

    test('a failed auto mark-read is silent and leaves the message readable', () async {
      final api = _FakeApi()
        ..message = _message('m1')
        ..markReadError = const ApiException(
          message: 'raw',
          code: 'INTERNAL_ERROR',
        );
      final controller = AdminContactDetailController(api, 'm1', (_) {});
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(controller.state.message!.status, AdminContactStatus.isNew);
      expect(controller.state.errorCode, isNull);
      expect(controller.state.actionErrorCode, isNull);
    });

    test('resolve updates the message and notifies the inbox', () async {
      final api = _FakeApi()..message = _message('m1', status: 'read');
      final updates = <AdminContactStatusUpdate>[];
      final controller = AdminContactDetailController(api, 'm1', updates.add);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(await controller.resolve(), isTrue);
      expect(controller.state.message!.isResolved, isTrue);
      expect(updates.single.status, AdminContactStatus.resolved);
    });

    test('a second resolve while one is in flight is dropped', () async {
      final api = _FakeApi()
        ..message = _message('m1', status: 'read')
        ..resolveGate = Completer<AdminContactStatusUpdate>();
      final controller = AdminContactDetailController(api, 'm1', (_) {});
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final first = controller.resolve();
      await pumpEventQueue();
      expect(await controller.resolve(), isFalse);
      expect(api.resolveCalls, 1);

      api.resolveGate!.complete(_update('m1', 'resolved'));
      expect(await first, isTrue);
    });

    test('a failed resolve records the code only', () async {
      final api = _FakeApi()
        ..message = _message('m1', status: 'read')
        ..resolveError = const ApiException(
          message: 'Contact message not found for lina@example.test',
          code: 'NOT_FOUND',
        );
      final controller = AdminContactDetailController(api, 'm1', (_) {});
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(await controller.resolve(), isFalse);
      expect(controller.state.actionErrorCode, 'NOT_FOUND');
      expect(controller.state.message!.isResolved, isFalse);
    });

    test('resolving after disposal does not throw', () async {
      final gate = Completer<AdminContactStatusUpdate>();
      final api = _FakeApi()
        ..message = _message('m1', status: 'read')
        ..resolveGate = gate;
      final controller = AdminContactDetailController(api, 'm1', (_) {});
      await pumpEventQueue();

      final pending = controller.resolve();
      controller.dispose();
      gate.complete(_update('m1', 'resolved'));
      await expectLater(pending, completion(isTrue));
    });
  });

  test('applyStatusUpdate rewrites only the matching cached row', () async {
    final api = _FakeApi()
      ..pages = [
        [_message('m0'), _message('m1')],
      ];
    final controller = AdminContactInboxController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    controller.applyStatusUpdate(_update('m1', 'resolved'));

    expect(controller.state.messages.first.status, AdminContactStatus.isNew);
    expect(controller.state.messages[1].isResolved, isTrue);
    expect(controller.state.messages[1].subject, 'Subject m1');
  });
}

class _FakeApi extends AdminContactApi {
  _FakeApi() : super(Dio());

  List<List<AdminContactMessage>> pages = const [];

  /// When set, every subsequent call answers with this page regardless of how
  /// many requests have already been made.
  List<AdminContactMessage>? fixedPage;
  Object? listError;
  Completer<List<AdminContactMessage>>? gate;

  AdminContactMessage? message;
  Object? markReadError;
  Object? resolveError;
  Completer<AdminContactStatusUpdate>? resolveGate;

  int listCalls = 0;
  int markReadCalls = 0;
  int resolveCalls = 0;
  final limits = <int>[];
  final offsets = <int>[];
  final statuses = <AdminContactStatus?>[];

  @override
  Future<AdminContactPage> list({
    AdminContactStatus? status,
    required int limit,
    required int offset,
  }) async {
    final index = listCalls;
    listCalls++;
    limits.add(limit);
    offsets.add(offset);
    statuses.add(status);

    if (gate != null) {
      final items = await gate!.future;
      return AdminContactPage(items: items, limit: limit, offset: offset);
    }
    if (listError != null) {
      final error = listError!;
      listError = null;
      throw error;
    }
    final items =
        fixedPage ??
        (index < pages.length ? pages[index] : const <AdminContactMessage>[]);
    return AdminContactPage(items: items, limit: limit, offset: offset);
  }

  @override
  Future<AdminContactMessage> get(String messageId) async => message!;

  @override
  Future<AdminContactStatusUpdate> markRead(String messageId) {
    markReadCalls++;
    if (markReadError != null) return Future.error(markReadError!);
    return Future.value(_update(messageId, 'read'));
  }

  @override
  Future<AdminContactStatusUpdate> resolve(String messageId) {
    resolveCalls++;
    if (resolveGate != null) return resolveGate!.future;
    if (resolveError != null) return Future.error(resolveError!);
    return Future.value(_update(messageId, 'resolved'));
  }
}
