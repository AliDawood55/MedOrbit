import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notifications/data/notifications_api.dart';
import 'package:mobile/features/notifications/models/notification_model.dart';
import 'package:mobile/features/notifications/providers/notifications_provider.dart';
import 'package:mobile/features/notifications/screens/notifications_screen.dart';
import 'package:mobile/routes/route_paths.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

NotificationModel _notification({
  required String id,
  bool isRead = false,
  String type = 'appointment',
  String? referenceId,
  String? referenceType,
}) {
  return NotificationModel(
    id: id,
    notificationType: type,
    titleAr: 'عنوان $id',
    titleEn: 'Title $id',
    messageAr: 'رسالة $id',
    messageEn: 'Message $id',
    isRead: isRead,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    readAt: isRead ? DateTime.now() : null,
    referenceId: referenceId,
    referenceType: referenceType,
  );
}

void main() {
  testWidgets('shows a loading state while the initial list is in flight', (tester) async {
    final completer = Completer<List<NotificationModel>>();
    final api = _FakeNotificationsApi()..listResults.add(completer.future);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete([_notification(id: 'n1')]);
  });

  testWidgets('loads and renders the notification list', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2', isRead: true)]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text('Title n1'), findsOneWidget);
    expect(find.text('Title n2'), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-n2')), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no notifications', (tester) async {
    final api = _FakeNotificationsApi()..listResults.add(const <NotificationModel>[]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.notificationsEmptyTitle), findsOneWidget);
  });

  testWidgets('shows a safe error with retry, and retry reloads the list', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add(const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable))
      ..listResults.add([_notification(id: 'n1')]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.notificationsErrorLoad), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry));
    await tester.pump();

    expect(find.text('Title n1'), findsOneWidget);
    expect(api.listCallCount, 2);
  });

  testWidgets('the unread filter hides read notifications, and All brings them back', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2', isRead: true)]);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.text(_strings.notificationsFilterUnread));
    await tester.pump();

    expect(find.text('Title n1'), findsOneWidget);
    expect(find.text('Title n2'), findsNothing);

    await tester.tap(find.text(_strings.notificationsFilterAll));
    await tester.pump();

    expect(find.text('Title n2'), findsOneWidget);
  });

  testWidgets('marking a notification read hides its mark-read action once confirmed', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..markReadResults.add(_notification(id: 'n1', isRead: true));
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    final tile = find.byKey(const ValueKey('notification-n1'));
    final markReadButton = find.descendant(of: tile, matching: find.byIcon(Icons.done_rounded));
    expect(markReadButton, findsOneWidget);

    await tester.tap(markReadButton);
    await tester.pump();
    await tester.pump();

    expect(find.descendant(of: tile, matching: find.byIcon(Icons.done_rounded)), findsNothing);
    expect(api.markReadCalls, ['n1']);
  });

  testWidgets('mark-all-read is only shown while unread items exist, and clears them all', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2')])
      ..markAllReadResults.add(2);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    final markAllButton = find.widgetWithText(TextButton, _strings.notificationsMarkAllRead);
    expect(markAllButton, findsOneWidget);

    await tester.tap(markAllButton);
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextButton, _strings.notificationsMarkAllRead), findsNothing);
    expect(api.markAllReadCallCount, 1);
  });

  testWidgets('deleting requires confirmation — cancel keeps it, confirm removes it', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1')])
      ..deleteResults.add(null);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    final tile = find.byKey(const ValueKey('notification-n1'));
    final deleteButton = find.descendant(of: tile, matching: find.byIcon(Icons.delete_outline_rounded));

    await tester.tap(deleteButton);
    await tester.pump();
    expect(find.text(_strings.notificationsDeleteDialogTitle), findsOneWidget);

    // Cancel: dialog closes, item stays, no network call.
    await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
    await tester.pump();
    expect(find.byKey(const ValueKey('notification-n1')), findsOneWidget);
    expect(api.deleteCalls, isEmpty);

    // Confirm: item is removed and the API is called.
    await tester.tap(deleteButton);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, _strings.notificationsDeleteOne));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('notification-n1')), findsNothing);
    expect(api.deleteCalls, ['n1']);
  });

  testWidgets('an allow-listed direct message marks read then opens its internal thread', (tester) async {
    const conversationId = '123e4567-e89b-42d3-a456-426614174000';
    final api = _FakeNotificationsApi()
      ..listResults.add([
        _notification(
          id: 'n-message',
          type: 'NEW_DIRECT_MESSAGE',
          referenceId: conversationId,
          referenceType: 'DIRECT_CONVERSATION',
        ),
      ])
      ..markReadResults.add(
        _notification(
          id: 'n-message',
          isRead: true,
          type: 'NEW_DIRECT_MESSAGE',
          referenceId: conversationId,
          referenceType: 'DIRECT_CONVERSATION',
        ),
      );
    await tester.pumpWidget(_routerApp(api));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('notification-n-message')));
    await tester.pump();
    await tester.pump();

    expect(api.markReadCalls, ['n-message']);
    expect(find.text('Opened $conversationId'), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (tester) async {
    final api = _FakeNotificationsApi()
      ..listResults.add([_notification(id: 'n1'), _notification(id: 'n2', isRead: true)]);
    await tester.pumpWidget(_app(api: api, isArabic: true, direction: TextDirection.rtl, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Widget _routerApp(NotificationsApi api) {
  final router = GoRouter(
    initialLocation: '/notifications-test',
    routes: [
      GoRoute(
        path: '/notifications-test',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.messageThread,
        builder: (_, state) => Scaffold(
          body: Text('Opened ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      notificationsApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
    ),
  );
}

Widget _app({
  required NotificationsApi api,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      notificationsApiProvider.overrideWithValue(api),
      // The real secure storage plugin has no backing implementation under
      // `flutter_test` and would throw MissingPluginException the moment
      // `localeControllerProvider` reads a persisted language on startup.
      secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: isArabic),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: const NotificationsScreen()),
      ),
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;
}

class _FakeNotificationsApi extends NotificationsApi {
  _FakeNotificationsApi() : super(Dio());

  final listResults = <Object>[];
  final markReadResults = <Object>[];
  final markAllReadResults = <Object>[];
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
