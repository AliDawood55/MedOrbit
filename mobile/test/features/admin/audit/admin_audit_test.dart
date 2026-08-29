import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/audit/data/admin_audit_api.dart';
import 'package:mobile/features/admin/audit/models/admin_audit_log.dart';
import 'package:mobile/features/admin/audit/providers/admin_audit_provider.dart';
import 'package:mobile/features/admin/audit/screens/admin_audit_log_screen.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _row({
  String id = 'log-1',
  String action = 'DOCTOR_APPLICATION_APPROVED',
  String? entityType = 'DOCTOR_APPLICATION',
  String? userRole = 'admin',
}) => {
  'id': id,
  'user_id': 'actor-1',
  'user_role': userRole,
  'action': action,
  'entity_type': entityType,
  'entity_id': 'app-1',
  'old_values': {'status': 'pending', 'bio': 'private professional detail'},
  'new_values': {'status': 'approved'},
  'ip_address': '10.0.0.4',
  'user_agent': 'MedOrbit/1.0',
  'created_at': '2026-02-20T09:00:00Z',
};

AdminAuditLog _entry({String id = 'log-1', String? userRole = 'admin'}) =>
    AdminAuditLog.fromJson(_row(id: id, userRole: userRole));

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 1600),
}) => pumpAdminScreen(
  tester,
  screen: const AdminAuditLogScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminAuditApiProvider.overrideWithValue(api)],
);

void main() {
  group('api', () {
    test('always bounds the query with a from instant, in UTC', () async {
      final dio = RecordingDio()..enqueue({'success': true, 'data': <dynamic>[]});

      await AdminAuditApi(dio.dio).list(
        from: DateTime.utc(2026, 2, 20, 9),
        entityType: 'USER',
      );

      expect(dio.paths.single, '/admin/audit-logs');
      expect(dio.methods.single, 'GET');
      expect(dio.queries.single, {
        'from': '2026-02-20T09:00:00.000Z',
        'entity_type': 'USER',
      });
    });

    test('omits filters that were not supplied', () async {
      final dio = RecordingDio()..enqueue({'success': true, 'data': <dynamic>[]});

      await AdminAuditApi(dio.dio).list(from: DateTime.utc(2026, 2, 20));

      expect(dio.queries.single.keys, ['from']);
    });

    test('parses metadata and never exposes the value snapshots', () async {
      final dio = RecordingDio()
        ..enqueue({
          'success': true,
          'data': [_row()],
        });

      final entry = (await AdminAuditApi(
        dio.dio,
      ).list(from: DateTime.utc(2026, 2, 20))).single;

      expect(entry.action, 'DOCTOR_APPLICATION_APPROVED');
      expect(entry.entityType, 'DOCTOR_APPLICATION');
      expect(entry.entityId, 'app-1');
      expect(entry.ipAddress, '10.0.0.4');
      expect(entry.userRole, 'admin');
      // old_values/new_values are deliberately not modelled: they can carry a
      // licence number or a professional bio.
      expect(entry.toString().contains('private professional detail'), isFalse);
    });

    test('an entry with no actor still parses', () async {
      final dio = RecordingDio()
        ..enqueue({
          'success': true,
          'data': [
            {
              'id': 'log-2',
              'action': 'CONTACT_MESSAGE_SUBMITTED',
              'created_at': '2026-02-20T09:00:00Z',
            },
          ],
        });

      final entry = (await AdminAuditApi(
        dio.dio,
      ).list(from: DateTime.utc(2026, 2, 20))).single;

      expect(entry.userRole, isNull);
      expect(entry.entityType, isNull);
    });

    test('a row without an action fails the read', () async {
      final dio = RecordingDio()
        ..enqueue({
          'success': true,
          'data': [
            {'id': 'log-3', 'created_at': '2026-02-20T09:00:00Z'},
          ],
        });

      await expectLater(
        AdminAuditApi(dio.dio).list(from: DateTime.utc(2026, 2, 20)),
        throwsA(isA<FormatException>()),
      );
    });

    test('a 403 surfaces the code only', () async {
      final dio = RecordingDio()..enqueueFailure(403, 'FORBIDDEN');

      try {
        await AdminAuditApi(dio.dio).list(from: DateTime.utc(2026, 2, 20));
        fail('expected a failure');
      } catch (error) {
        expect(ApiException.from(error).code, 'FORBIDDEN');
      }
    });
  });

  group('controller', () {
    test('defaults to a seven-day window and caps what it renders', () async {
      final api = _FakeApi()
        ..entries = List.generate(
          adminAuditRenderLimit + 5,
          (index) => _entry(id: 'log-$index'),
        );
      final controller = AdminAuditController(
        api,
        clock: () => DateTime.utc(2026, 2, 20, 12),
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(controller.state.range, AdminAuditRange.week);
      expect(api.lastFrom, DateTime.utc(2026, 2, 13, 12));
      expect(controller.state.entries.length, adminAuditRenderLimit);
      expect(controller.state.truncated, isTrue);
    });

    test('each range maps to its documented trailing window', () async {
      final api = _FakeApi();
      final controller = AdminAuditController(
        api,
        clock: () => DateTime.utc(2026, 2, 20, 12),
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.setRange(AdminAuditRange.day);
      await pumpEventQueue();
      expect(api.lastFrom, DateTime.utc(2026, 2, 19, 12));

      controller.setRange(AdminAuditRange.month);
      await pumpEventQueue();
      expect(api.lastFrom, DateTime.utc(2026, 1, 21, 12));
    });

    test('selecting the current range does not refetch', () async {
      final api = _FakeApi();
      final controller = AdminAuditController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.setRange(AdminAuditRange.week);
      await pumpEventQueue();
      expect(api.listCalls, 1);
    });

    test('the entity filter is sent and cleared exactly as selected', () async {
      final api = _FakeApi();
      final controller = AdminAuditController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.setEntityType('USER');
      await pumpEventQueue();
      expect(api.lastEntityType, 'USER');

      controller.setEntityType(null);
      await pumpEventQueue();
      expect(api.lastEntityType, isNull);
      expect(controller.state.entityType, isNull);
    });

    test('a slow earlier response never overwrites a newer one', () async {
      final api = _FakeApi();
      final gate = Completer<List<AdminAuditLog>>();
      api.gate = gate;
      final controller = AdminAuditController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      api.gate = null;
      api.entries = [_entry(id: 'fresh')];
      controller.setRange(AdminAuditRange.day);
      await pumpEventQueue();
      expect(controller.state.entries.single.id, 'fresh');

      gate.complete([_entry(id: 'stale')]);
      await pumpEventQueue();
      expect(controller.state.entries.single.id, 'fresh');
    });
  });

  group('screen', () {
    testWidgets('a patient is refused and nothing is fetched', (tester) async {
      final api = _FakeApi();
      await _pump(tester, api: api, role: 'patient');

      expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
      expect(api.listCalls, 0);
    });

    testWidgets('renders entries with actor, entity and no value dump', (
      tester,
    ) async {
      await _pump(tester, api: _FakeApi()..entries = [_entry()]);

      expect(find.text('DOCTOR_APPLICATION_APPROVED'), findsOneWidget);
      expect(find.text(en.roleAdmin), findsOneWidget);
      expect(find.text('10.0.0.4'), findsOneWidget);
      expect(find.text(en.adminAuditPayloadNote), findsOneWidget);
      expect(find.textContaining('private professional detail'), findsNothing);
    });

    testWidgets('an entry with no actor is attributed to the system', (
      tester,
    ) async {
      await _pump(
        tester,
        api: _FakeApi()..entries = [_entry(userRole: null)],
      );

      expect(find.text(en.adminAuditSystemActor), findsOneWidget);
    });

    testWidgets('an empty window shows the empty state', (tester) async {
      await _pump(tester, api: _FakeApi());

      expect(find.byKey(const ValueKey('admin-audit-empty')), findsOneWidget);
    });

    testWidgets('a load failure shows safe copy and Retry reloads', (
      tester,
    ) async {
      final api = _FakeApi()
        ..listError = const ApiException(
          message: 'raw backend detail',
          code: 'INTERNAL_ERROR',
        );
      await _pump(tester, api: api);

      expect(find.text(en.adminError('INTERNAL_ERROR')), findsOneWidget);
      expect(find.textContaining('raw backend detail'), findsNothing);

      api.listError = null;
      api.entries = [_entry()];
      await tapByKey(tester, const ValueKey('admin-audit-retry'));
      await tester.pump();
      await tester.pump();

      expect(api.listCalls, 2);
      expect(find.text('DOCTOR_APPLICATION_APPROVED'), findsOneWidget);
    });

    testWidgets('changing the range refetches with a new bound', (tester) async {
      final api = _FakeApi()..entries = [_entry()];
      await _pump(tester, api: api);
      final first = api.lastFrom!;

      await tapByKey(tester, const ValueKey('admin-audit-range-day'));
      await tester.pump();
      await tester.pump();

      expect(api.listCalls, 2);
      expect(api.lastFrom!.isAfter(first), isTrue);
    });

    testWidgets('the entity filter narrows the query', (tester) async {
      final api = _FakeApi()..entries = [_entry()];
      await _pump(tester, api: api);

      await tapByKey(tester, const ValueKey('admin-audit-entity-USER'));
      await tester.pump();
      await tester.pump();

      expect(api.lastEntityType, 'USER');
    });

    testWidgets('the render cap is disclosed above the entries', (
      tester,
    ) async {
      await _pump(
        tester,
        api: _FakeApi()
          ..entries = List.generate(
            adminAuditRenderLimit + 1,
            (index) => _entry(id: 'log-$index'),
          ),
      );

      expect(
        find.text(en.adminAuditTruncatedNote(adminAuditRenderLimit)),
        findsOneWidget,
      );
    });

    testWidgets('no truncation notice when the window fits', (tester) async {
      await _pump(tester, api: _FakeApi()..entries = [_entry()]);

      expect(
        find.text(en.adminAuditTruncatedNote(adminAuditRenderLimit)),
        findsNothing,
      );
    });

    testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
      tester,
    ) async {
      await _pump(
        tester,
        api: _FakeApi()..entries = [_entry()],
        isArabic: true,
        textScale: 1.5,
        size: const Size(320, 2400),
      );

      expect(find.text(ar.adminAuditTitle), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeApi extends AdminAuditApi {
  _FakeApi() : super(Dio());

  List<AdminAuditLog> entries = const [];
  Object? listError;
  Completer<List<AdminAuditLog>>? gate;

  int listCalls = 0;
  DateTime? lastFrom;
  String? lastEntityType;

  @override
  Future<List<AdminAuditLog>> list({
    required DateTime from,
    DateTime? to,
    String? entityType,
    String? userId,
  }) {
    listCalls++;
    lastFrom = from;
    lastEntityType = entityType;
    if (gate != null) return gate!.future;
    if (listError != null) return Future.error(listError!);
    return Future.value(entries);
  }
}
