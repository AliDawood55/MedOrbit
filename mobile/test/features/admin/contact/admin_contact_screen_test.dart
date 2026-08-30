import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/contact/data/admin_contact_api.dart';
import 'package:mobile/features/admin/contact/models/admin_contact_message.dart';
import 'package:mobile/features/admin/contact/providers/admin_contact_provider.dart';
import 'package:mobile/features/admin/contact/screens/admin_contact_inbox_screen.dart';

import '../admin_test_support.dart';

AdminContactMessage _message(
  String id, {
  String status = 'new',
  String? body,
}) => AdminContactMessage.fromJson({
  'id': id,
  'authenticated': true,
  'sender_name': 'Lina Haddad',
  'sender_email': 'lina@example.test',
  'subject': 'Cannot book $id',
  'message': body,
  'status': status,
  'created_at': '2026-02-01T09:00:00Z',
});

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 1600),
}) => pumpAdminScreen(
  tester,
  screen: const AdminContactInboxScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminContactApiProvider.overrideWithValue(api)],
);

void main() {
  testWidgets('a patient is refused and no inbox is fetched', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(api.listCalls, 0);
  });

  testWidgets('shows a loading state before the first page', (tester) async {
    await _pump(tester, api: _FakeApi()..gate = Completer<AdminContactPage>());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('an empty inbox shows the empty state', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(find.byKey(const ValueKey('admin-contact-empty')), findsOneWidget);
    expect(find.text(en.adminContactEmptyTitle), findsOneWidget);
  });

  testWidgets('a load failure shows safe copy and Retry reloads', (
    tester,
  ) async {
    final api = _FakeApi()
      ..listError = const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      );
    await _pump(tester, api: api);

    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    api.listError = null;
    api.items = [_message('m1')];
    await tapByKey(tester, const ValueKey('admin-contact-retry'));
    await tester.pump();
    await tester.pump();

    expect(api.listCalls, 2);
    expect(find.text('Cannot book m1'), findsOneWidget);
  });

  testWidgets('renders the queue with its status badge', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()
        ..items = [_message('m1'), _message('m2', status: 'resolved')],
    );

    expect(find.text('Cannot book m1'), findsOneWidget);
    // The same words label a filter chip, so the badge is matched inside the
    // card it belongs to.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-contact-m1')),
        matching: find.text(en.adminContactStatusNew),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-contact-m2')),
        matching: find.text(en.adminContactStatusResolved),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the status filter refetches with the exact wire value', (
    tester,
  ) async {
    final api = _FakeApi()..items = [_message('m1')];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-contact-resolved'));
    await tester.pump();
    await tester.pump();

    expect(api.lastStatus, AdminContactStatus.resolved);
    expect(api.listCalls, 2);
  });

  testWidgets('opening a new message marks it read and shows its body', (
    tester,
  ) async {
    final api = _FakeApi()
      ..items = [_message('m1')]
      ..detail = _message('m1', body: 'The calendar is empty.');
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-contact-m1'));
    await tester.pumpAndSettle();

    expect(find.text('The calendar is empty.'), findsOneWidget);
    // Rendered by both the queue card behind the sheet and the sheet itself.
    expect(find.text('Lina Haddad · lina@example.test'), findsWidgets);
    expect(api.markReadCalls, 1);
    expect(find.byKey(const ValueKey('admin-contact-resolve')), findsOneWidget);
  });

  testWidgets('resolving is confirmed, then applied to the sheet', (
    tester,
  ) async {
    final api = _FakeApi()
      ..items = [_message('m1', status: 'read')]
      ..detail = _message('m1', status: 'read', body: 'Body');
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-contact-m1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-contact-resolve')));
    await tester.pumpAndSettle();
    expect(find.text(en.adminContactResolveTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, en.cancel));
    await tester.pumpAndSettle();
    expect(api.resolveCalls, 0);

    await tester.tap(find.byKey(const ValueKey('admin-contact-resolve')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-contact-resolve-confirm')),
    );
    await tester.pumpAndSettle();

    expect(api.resolveCalls, 1);
    expect(find.text(en.adminContactResolvedSuccess), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-contact-resolve')), findsNothing);
  });

  testWidgets('a failed resolve shows mapped copy, never the raw message', (
    tester,
  ) async {
    final api = _FakeApi()
      ..items = [_message('m1', status: 'read')]
      ..detail = _message('m1', status: 'read', body: 'Body')
      ..resolveError = const ApiException(
        message: 'Contact message not found for lina@example.test',
        code: 'NOT_FOUND',
      );
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-contact-m1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-contact-resolve')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-contact-resolve-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text(en.adminError('NOT_FOUND')), findsOneWidget);
    expect(find.textContaining('lina@example.test'), findsWidgets);
    expect(
      find.textContaining('Contact message not found'),
      findsNothing,
    );
  });

  testWidgets('reaching the end of a full page loads the next one', (
    tester,
  ) async {
    final api = _FakeApi()
      ..items = List.generate(
        adminContactPageSize + 1,
        (index) => _message('m$index'),
      )
      ..nextItems = [_message('x1')];
    await _pump(tester, api: api, size: const Size(420, 4000));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin-contact-m29')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(api.listCalls, greaterThanOrEqualTo(2));
    expect(api.offsets.last, adminContactPageSize);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..items = [_message('m1')],
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 2000),
    );

    // Once as the filter chip, once as the card's badge.
    expect(find.text(ar.adminContactStatusNew), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminContactApi {
  _FakeApi() : super(Dio());

  List<AdminContactMessage> items = const [];
  List<AdminContactMessage> nextItems = const [];
  AdminContactMessage? detail;
  Object? listError;
  Object? resolveError;
  Completer<AdminContactPage>? gate;

  int listCalls = 0;
  int markReadCalls = 0;
  int resolveCalls = 0;
  AdminContactStatus? lastStatus;
  final offsets = <int>[];

  @override
  Future<AdminContactPage> list({
    AdminContactStatus? status,
    required int limit,
    required int offset,
  }) {
    listCalls++;
    lastStatus = status;
    offsets.add(offset);
    if (gate != null) return gate!.future;
    if (listError != null) return Future.error(listError!);
    return Future.value(
      AdminContactPage(
        items: offset == 0 ? items : nextItems,
        limit: limit,
        offset: offset,
      ),
    );
  }

  @override
  Future<AdminContactMessage> get(String messageId) async =>
      detail ?? _message(messageId, body: 'Body');

  @override
  Future<AdminContactStatusUpdate> markRead(String messageId) async {
    markReadCalls++;
    return AdminContactStatusUpdate.fromJson({
      'id': messageId,
      'status': 'read',
      'read_at': '2026-02-02T08:00:00Z',
    });
  }

  @override
  Future<AdminContactStatusUpdate> resolve(String messageId) {
    resolveCalls++;
    if (resolveError != null) return Future.error(resolveError!);
    return Future.value(
      AdminContactStatusUpdate.fromJson({
        'id': messageId,
        'status': 'resolved',
        'read_at': '2026-02-02T08:00:00Z',
        'resolved_at': '2026-02-02T09:00:00Z',
      }),
    );
  }
}
