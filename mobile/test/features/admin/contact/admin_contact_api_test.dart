import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/contact/data/admin_contact_api.dart';
import 'package:mobile/features/admin/contact/models/admin_contact_message.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _row({
  String id = 'msg-1',
  String status = 'new',
  bool authenticated = true,
}) => {
  'id': id,
  'authenticated': authenticated,
  'sender_name': 'Lina Haddad',
  'sender_email': 'lina@example.test',
  'subject': 'Cannot book an appointment',
  'status': status,
  'created_at': '2026-02-01T09:00:00Z',
  'updated_at': '2026-02-01T09:00:00Z',
  'read_at': null,
  'resolved_at': null,
};

void main() {
  test('list sends status, limit and offset — the only supported filters', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {'items': <dynamic>[], 'limit': 31, 'offset': 0},
      })
      ..enqueue({
        'success': true,
        'data': {'items': <dynamic>[], 'limit': 31, 'offset': 30},
      });

    final api = AdminContactApi(dio.dio);
    await api.list(limit: 31, offset: 0);
    await api.list(status: AdminContactStatus.resolved, limit: 31, offset: 30);

    expect(dio.paths, [
      '/admin/contact-messages',
      '/admin/contact-messages',
    ]);
    expect(dio.queries.first, {'limit': 31, 'offset': 0});
    expect(dio.queries[1], {'status': 'resolved', 'limit': 31, 'offset': 30});
  });

  test('every status maps to its exact wire value', () {
    expect(adminContactStatusWireValue(AdminContactStatus.isNew), 'new');
    expect(adminContactStatusWireValue(AdminContactStatus.read), 'read');
    expect(
      adminContactStatusWireValue(AdminContactStatus.resolved),
      'resolved',
    );
    expect(adminContactStatusWireValue(null), isNull);
    expect(adminContactStatusWireValue(AdminContactStatus.unknown), isNull);
  });

  test('parses a page, including the authenticated-sender flag', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          'items': [_row(), _row(id: 'msg-2', authenticated: false)],
          'limit': 31,
          'offset': 0,
        },
      });

    final page = await AdminContactApi(dio.dio).list(limit: 31, offset: 0);

    expect(page.items.length, 2);
    expect(page.limit, 31);
    expect(page.offset, 0);
    expect(page.items.first.status, AdminContactStatus.isNew);
    expect(page.items.first.isUnread, isTrue);
    expect(page.items.first.authenticated, isTrue);
    expect(page.items[1].authenticated, isFalse);
    // The list projection omits `message`; it must read as absent, not empty.
    expect(page.items.first.body, isNull);
  });

  test('the detail projection carries the message body', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {..._row(status: 'read'), 'message': 'The calendar is empty.'},
      });

    final message = await AdminContactApi(dio.dio).get('msg-1');

    expect(dio.paths.single, '/admin/contact-messages/msg-1');
    expect(message.body, 'The calendar is empty.');
    expect(message.status, AdminContactStatus.read);
  });

  test('read and resolve POST empty bodies to the exact paths', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          'id': 'msg-1',
          'status': 'read',
          'read_at': '2026-02-02T08:00:00Z',
          'resolved_at': null,
        },
      })
      ..enqueue({
        'success': true,
        'data': {
          'id': 'msg-1',
          'status': 'resolved',
          'read_at': '2026-02-02T08:00:00Z',
          'resolved_at': '2026-02-02T09:00:00Z',
        },
      });

    final api = AdminContactApi(dio.dio);
    final read = await api.markRead('msg-1');
    final resolved = await api.resolve('msg-1');

    expect(dio.paths, [
      '/admin/contact-messages/msg-1/read',
      '/admin/contact-messages/msg-1/resolve',
    ]);
    expect(dio.methods, ['POST', 'POST']);
    expect(dio.bodies, [<String, dynamic>{}, <String, dynamic>{}]);
    expect(read.status, AdminContactStatus.read);
    expect(resolved.status, AdminContactStatus.resolved);
    expect(resolved.resolvedAt, isNotNull);
  });

  test('a status update merges into the cached row without losing the body', () {
    final message = AdminContactMessage.fromJson({
      ..._row(),
      'message': 'The calendar is empty.',
    });
    final merged = message.copyWithStatus(
      AdminContactStatusUpdate.fromJson({
        'id': 'msg-1',
        'status': 'resolved',
        'read_at': '2026-02-02T08:00:00Z',
        'resolved_at': '2026-02-02T09:00:00Z',
      }),
    );

    expect(merged.status, AdminContactStatus.resolved);
    expect(merged.isResolved, isTrue);
    expect(merged.body, 'The calendar is empty.');
    expect(merged.subject, 'Cannot book an appointment');
  });

  test('an unknown status keeps its raw value', () {
    final message = AdminContactMessage.fromJson(_row(status: 'archived'));
    expect(message.status, AdminContactStatus.unknown);
    expect(message.statusValue, 'archived');
  });

  test('a malformed page fails the read', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {'items': 'nope'},
      });

    await expectLater(
      AdminContactApi(dio.dio).list(limit: 31, offset: 0),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
      ),
    );
  });

  test('a rejected status filter surfaces VALIDATION_ERROR only', () async {
    final dio = RecordingDio()..enqueueFailure(400, 'VALIDATION_ERROR');

    try {
      await AdminContactApi(dio.dio).list(limit: 31, offset: 0);
      fail('expected a failure');
    } catch (error) {
      expect(ApiException.from(error).code, 'VALIDATION_ERROR');
    }
  });
}
