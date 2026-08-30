import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/messaging/data/messaging_api.dart';
import 'package:mobile/features/messaging/data/messaging_realtime.dart';
import 'package:mobile/features/messaging/models/messaging_models.dart';
import 'package:mobile/features/messaging/providers/messaging_providers.dart';
import 'package:mobile/features/messaging/screens/message_thread_screen.dart';
import 'package:mobile/features/messaging/screens/messaging_inbox_screen.dart';
import 'package:mobile/features/messaging/screens/new_message_screen.dart';
import 'package:mobile/features/messaging/widgets/conversation_tile.dart';
import 'package:mobile/features/messaging/widgets/message_bubble.dart';
import 'package:mobile/routes/route_paths.dart';
import 'package:mobile/shared/widgets/status_badge.dart';

void main() {
  testWidgets('inbox has a useful empty state and new-message action', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_ScreenApi(), const MessagingInboxScreen()));
    await _settleLoad(tester);

    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.text('New message'), findsWidgets);
  });

  testWidgets(
    'patient controls doctor discovery through server-backed preference',
    (tester) async {
      final api = _ScreenApi(
        allowDoctorMessages: false,
        updatedAllowDoctorMessages: true,
      );
      await tester.pumpWidget(_app(api, const MessagingInboxScreen()));
      await _settleLoad(tester);

      expect(find.text('Allow doctor message requests'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.pump();

      expect(api.preferenceUpdateValues, [true]);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    },
  );

  testWidgets('inbox renders role, request state, preview, and unread badge', (
    tester,
  ) async {
    final api = _ScreenApi(
      conversations: [
        _conversation(
          name: 'Dr Lina',
          preview: 'Your results are ready',
          unread: 3,
        ),
        _conversation(
          id: _pendingConversationId,
          name: 'Dr Samir',
          requestStatus: 'pending',
        ),
      ],
    );
    await tester.pumpWidget(_app(api, const MessagingInboxScreen()));
    await _settleLoad(tester);

    expect(find.text('Dr Lina'), findsOneWidget);
    expect(find.text('Your results are ready'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Message request awaiting response'), findsOneWidget);
    expect(find.text('Doctor'), findsNWidgets(2));
  });

  testWidgets('tapping an inbox row opens the protected internal thread path', (
    tester,
  ) async {
    final api = _ScreenApi(conversations: [_conversation()]);
    await tester.pumpWidget(_inboxRouterApp(api));
    await _settleLoad(tester);

    await tester.tap(
      find.byKey(const ValueKey('conversation-$_conversationId')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Opened $_conversationId'), findsOneWidget);
  });

  testWidgets('patient can accept a pending text-only request before composing', (
    tester,
  ) async {
    final pending = _conversation(requestStatus: 'pending', canRespond: true);
    final api = _ScreenApi(
      conversations: [pending],
      acceptResult: pending.copyWith(requestStatus: 'accepted'),
    );
    await tester.pumpWidget(
      _app(api, const MessageThreadScreen(conversationId: _conversationId)),
    );
    await _settleLoad(tester);

    expect(
      find.text('Message request from an approved doctor'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Accepting opens text messaging only. It grants no clinical access or medical-record permission.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('message-composer')))
          .enabled,
      isFalse,
    );
    expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pump();
    expect(find.text('Decline this message request?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pump();
    await tester.pump();

    expect(api.acceptCalls, 1);
    expect(find.text('Message request from an approved doctor'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('message-composer')))
          .enabled,
      isTrue,
    );
  });

  testWidgets('composer double tap starts one REST send and keeps one bubble', (
    tester,
  ) async {
    final pendingSend = Completer<CareMessage>();
    final api = _ScreenApi(
      conversations: [_conversation()],
      messages: [_message('مرحبا Doctor', senderId: _otherUserId)],
      sendResult: pendingSend.future,
    );
    await tester.pumpWidget(
      _app(api, const MessageThreadScreen(conversationId: _conversationId)),
    );
    await _settleLoad(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('message-composer')))
          .maxLength,
      4000,
    );

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Follow up',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.tap(find.byTooltip('Send'), warnIfMissed: false);
    await tester.pump();

    expect(api.sendCalls, 1);
    expect(find.text('Follow up'), findsOneWidget);

    pendingSend.complete(
      _message(
        'Follow up',
        clientId: api.lastClientMessageId!,
        senderId: _currentUserId,
      ),
    );
    await tester.pump();
    expect(find.text('Follow up'), findsOneWidget);
  });

  testWidgets('older-message control prepends the server cursor page', (
    tester,
  ) async {
    final api = _ScreenApi(
      conversations: [_conversation()],
      messages: [_message('Newest')],
      olderMessages: [_message('Oldest')],
      nextCursor: 'opaque-older',
    );
    await tester.pumpWidget(
      _app(api, const MessageThreadScreen(conversationId: _conversationId)),
    );
    await _settleLoad(tester);

    expect(find.text('Load older messages'), findsOneWidget);
    await tester.tap(find.text('Load older messages'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Oldest'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(api.olderCursors, ['opaque-older']);
  });

  testWidgets('doctor recipient search shows opted-in patients and doctors', (
    tester,
  ) async {
    final api = _ScreenApi(
      doctorResults: [
        _recipient('Dr Noor', RecipientKind.doctor),
        _recipient('Self', RecipientKind.doctor, id: _currentUserId),
      ],
      patientResults: [_recipient('Mariam', RecipientKind.patient)],
      ownDoctorId: _currentUserId,
    );
    await tester.pumpWidget(
      _app(api, const NewMessageScreen(), role: 'doctor'),
    );
    await _settleLoad(tester);

    expect(find.text('Mariam'), findsOneWidget);
    expect(find.text('Dr Noor'), findsOneWidget);
    expect(find.text('Self'), findsNothing);
    expect(find.text('Patient open to message requests'), findsOneWidget);
    expect(find.text('Approved doctor'), findsOneWidget);
  });

  testWidgets('Arabic RTL narrow layout with 2x text remains overflow-free', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ScreenApi(
      conversations: [_conversation(name: 'الدكتورة ليلى الطويلة للاختبار')],
      messages: [_message('نتيجة التحليل جيدة — follow-up بعد أسبوع')],
    );
    await tester.pumpWidget(
      _app(
        api,
        const MessageThreadScreen(conversationId: _conversationId),
        isArabic: true,
        textScale: 2,
      ),
    );
    await _settleLoad(tester);

    expect(
      find.text('نتيجة التحليل جيدة — follow-up بعد أسبوع'),
      findsOneWidget,
    );
    final composer = find.byKey(const ValueKey('message-composer'));
    await tester.tap(composer);
    await tester.showKeyboard(composer);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed bubble exposes safe retry and dismiss actions', (
    tester,
  ) async {
    var retried = false;
    var dismissed = false;
    final failed =
        CareMessage.optimistic(
          conversationId: _conversationId,
          senderUserId: _currentUserId,
          clientMessageId: _clientId,
          body: 'Private body',
          createdAt: DateTime.utc(2026, 8, 29, 12),
        ).copyWith(
          deliveryState: MessageDeliveryState.failed,
          errorCode: 'SERVICE_UNAVAILABLE',
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MessageBubble(
            message: failed,
            isMine: true,
            isArabic: false,
            strings: const AppStrings(false),
            onRetry: () => retried = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Send failed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Dismiss'));
    expect(retried, isTrue);
    expect(dismissed, isTrue);
  });

  testWidgets('inbox shows a loading indicator before conversations resolve', (
    tester,
  ) async {
    final gate = Completer<List<CareConversation>>();
    await tester.pumpWidget(
      _app(_DeferredListApi(gate.future), const MessagingInboxScreen()),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No conversations yet'), findsNothing);

    gate.complete(const []);
    await _settleLoad(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('inbox distinguishes doctor and patient role badges by colour', (
    tester,
  ) async {
    final api = _ScreenApi(
      conversations: [
        _conversation(id: _conversationId, name: 'Dr Lina'),
        _conversation(
          id: _pendingConversationId,
          name: 'Mr Adam',
          otherRole: 'patient',
        ),
      ],
    );
    await tester.pumpWidget(_app(api, const MessagingInboxScreen()));
    await _settleLoad(tester);

    final badges = tester
        .widgetList<StatusBadge>(find.byType(StatusBadge))
        .toList();
    final doctorBadge = badges.firstWhere((badge) => badge.label == 'Doctor');
    final patientBadge = badges.firstWhere((badge) => badge.label == 'Patient');
    expect(doctorBadge.color, isNot(equals(patientBadge.color)));
  });

  testWidgets('inbox stays overflow-free in Arabic RTL at 320px with 2x text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ScreenApi(
      conversations: [
        _conversation(
          name: 'الدكتورة ليلى عبد الرحمن الطويلة جدًا للاختبار',
          preview:
              'رسالة معاينة طويلة جدًا تتضمن تفاصيل المتابعة والنتائج المخبرية '
              'بالإضافة إلى ملاحظات إضافية',
          unread: 128,
        ),
      ],
    );
    await tester.pumpWidget(
      _app(api, const MessagingInboxScreen(), isArabic: true, textScale: 2),
    );
    await _settleLoad(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ConversationTile), findsOneWidget);
  });

  testWidgets('thread keeps the composer reachable under a long history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ScreenApi(
      conversations: [_conversation()],
      messages: _manyMessages(60),
    );
    await tester.pumpWidget(
      _app(api, const MessageThreadScreen(conversationId: _conversationId)),
    );
    await _settleLoad(tester);

    expect(tester.takeException(), isNull);
    final composer = find.byKey(const ValueKey('message-composer'));
    expect(composer, findsOneWidget);
    expect(tester.getRect(composer).bottom, lessThanOrEqualTo(640));
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('thread composer stays editable while a send is in flight', (
    tester,
  ) async {
    final pending = Completer<CareMessage>();
    final api = _ScreenApi(
      conversations: [_conversation()],
      messages: [_message('Hello', senderId: _otherUserId)],
      sendResult: pending.future,
    );
    await tester.pumpWidget(
      _app(api, const MessageThreadScreen(conversationId: _conversationId)),
    );
    await _settleLoad(tester);

    final composer = find.byKey(const ValueKey('message-composer'));
    await tester.enterText(composer, 'First');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(tester.widget<TextField>(composer).enabled, isTrue);
    await tester.enterText(composer, 'Second while first sends');
    expect(tester.takeException(), isNull);

    pending.complete(
      _message(
        'First',
        clientId: api.lastClientMessageId!,
        senderId: _currentUserId,
      ),
    );
    await tester.pump();
  });

  testWidgets('message bubble wraps an unbroken long token at narrow width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final message = CareMessage(
      id: '923e4567-e89b-42d3-a456-426614174000',
      conversationId: _conversationId,
      senderUserId: _currentUserId,
      clientMessageId: '923e4567-e89b-42d3-a456-426614174001',
      body: 'https://example.test/${'x' * 400} مرحبا-${'ن' * 200}',
      createdAt: DateTime.utc(2026, 8, 29, 12),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MessageBubble(
              message: message,
              isMine: true,
              isArabic: false,
              strings: const AppStrings(false),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MessageBubble), findsOneWidget);
    expect(tester.getSize(find.byType(MessageBubble)).width, lessThanOrEqualTo(320));
  });
}

List<CareMessage> _manyMessages(int count) {
  return List<CareMessage>.generate(count, (index) {
    final n = index.toString().padLeft(2, '0');
    return CareMessage(
      id: '723e4567-e89b-42d3-a456-4266141740$n',
      conversationId: _conversationId,
      senderUserId: index.isEven ? _currentUserId : _otherUserId,
      clientMessageId: '823e4567-e89b-42d3-a456-4266141740$n',
      body: 'History message number $index with enough text to take a line',
      createdAt: DateTime.utc(2026, 8, 29, 8).add(Duration(minutes: index)),
    );
  });
}

Widget _inboxRouterApp(MessagingApi api) {
  final router = GoRouter(
    initialLocation: RoutePaths.messages,
    routes: [
      GoRoute(
        path: RoutePaths.messages,
        builder: (context, state) => const MessagingInboxScreen(),
      ),
      GoRoute(
        path: RoutePaths.messageThread,
        builder: (context, state) =>
            Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      messagingApiProvider.overrideWithValue(api),
      messagingRealtimeFactoryProvider.overrideWithValue(_ScreenRealtime.new),
      authControllerProvider.overrideWith((ref) => _FakeAuth('patient')),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
      activeOriginProvider.overrideWithValue('https://example.test'),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

Widget _app(
  MessagingApi api,
  Widget screen, {
  String role = 'patient',
  bool isArabic = false,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      messagingApiProvider.overrideWithValue(api),
      messagingRealtimeFactoryProvider.overrideWithValue(_ScreenRealtime.new),
      authControllerProvider.overrideWith((_) => _FakeAuth(role)),
      secureStorageProvider.overrideWithValue(
        _FakeSecureStorage(isArabic ? 'ar' : 'en'),
      ),
      activeOriginProvider.overrideWithValue('https://example.test'),
      messagingIdFactoryProvider.overrideWithValue(() => _clientId),
      messagingClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 29, 12),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: isArabic),
      locale: Locale(isArabic ? 'ar' : 'en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: screen,
        ),
      ),
    ),
  );
}

Future<void> _settleLoad(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

const _conversationId = '123e4567-e89b-42d3-a456-426614174000';
const _pendingConversationId = '123e4567-e89b-42d3-a456-426614174009';
const _currentUserId = '223e4567-e89b-42d3-a456-426614174001';
const _otherUserId = '323e4567-e89b-42d3-a456-426614174002';
const _clientId = '423e4567-e89b-42d3-a456-426614174003';

CareConversation _conversation({
  String id = _conversationId,
  String name = 'Dr Lina',
  String requestStatus = 'accepted',
  bool canRespond = false,
  String? preview,
  int unread = 0,
  String otherRole = 'doctor',
}) {
  return CareConversation(
    id: id,
    status: 'active',
    conversationType: 'patient_doctor',
    requestStatus: requestStatus,
    initiatedByUserId: _otherUserId,
    createdAt: DateTime.utc(2026, 8, 29, 10),
    otherRole: otherRole,
    otherDisplayName: name,
    lastMessagePreview: preview,
    lastMessageCreatedAt: DateTime.utc(2026, 8, 29, 11),
    canRespondToRequest: canRespond,
    unreadCount: unread,
  );
}

CareMessage _message(
  String body, {
  String senderId = _currentUserId,
  String? clientId,
}) {
  final suffix = body.codeUnits.fold<int>(0, (sum, value) => sum + value) % 10;
  return CareMessage(
    id: '623e4567-e89b-42d3-a456-42661417400$suffix',
    conversationId: _conversationId,
    senderUserId: senderId,
    clientMessageId: clientId ?? '523e4567-e89b-42d3-a456-42661417400$suffix',
    body: body,
    createdAt: DateTime.utc(2026, 8, 29, 12),
  );
}

MessagingRecipient _recipient(String name, RecipientKind kind, {String? id}) {
  return MessagingRecipient(
    id: id ?? '${kind.name}-recipient',
    kind: kind,
    firstNameEn: name,
  );
}

class _ScreenApi extends MessagingApi {
  _ScreenApi({
    this.conversations = const [],
    this.messages = const [],
    this.olderMessages = const [],
    this.nextCursor,
    this.acceptResult,
    this.sendResult,
    this.doctorResults = const [],
    this.patientResults = const [],
    this.ownDoctorId = '',
    this.allowDoctorMessages = false,
    this.updatedAllowDoctorMessages,
  }) : super(Dio());

  final List<CareConversation> conversations;
  final List<CareMessage> messages;
  final List<CareMessage> olderMessages;
  final String? nextCursor;
  final CareConversation? acceptResult;
  final Future<CareMessage>? sendResult;
  final List<MessagingRecipient> doctorResults;
  final List<MessagingRecipient> patientResults;
  final String ownDoctorId;
  final bool allowDoctorMessages;
  final bool? updatedAllowDoctorMessages;
  int acceptCalls = 0;
  int sendCalls = 0;
  String? lastClientMessageId;
  final olderCursors = <String>[];
  final preferenceUpdateValues = <bool>[];

  @override
  Future<ConversationPage> listConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    return ConversationPage(items: conversations, limit: limit, offset: offset);
  }

  @override
  Future<MessagePage> listMessages(
    String conversationId, {
    int limit = 50,
    String? cursor,
    String? after,
  }) async {
    if (cursor != null) {
      olderCursors.add(cursor);
      return MessagePage(items: olderMessages, latestCursor: 'latest');
    }
    return MessagePage(
      items: after == null ? messages : const [],
      nextCursor: after == null ? nextCursor : null,
      latestCursor: 'latest',
    );
  }

  @override
  Future<MessagingReadState> markRead(
    String conversationId, {
    String? messageId,
  }) async {
    return MessagingReadState(
      conversationId: conversationId,
      lastReadMessageId: messageId,
    );
  }

  @override
  Future<CareConversation> acceptRequest(String conversationId) async {
    acceptCalls++;
    return acceptResult!;
  }

  @override
  Future<CareMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) {
    sendCalls++;
    lastClientMessageId = clientMessageId;
    return sendResult!;
  }

  @override
  Future<List<MessagingRecipient>> searchDoctors(
    String search, {
    int limit = 20,
  }) async => doctorResults;

  @override
  Future<List<MessagingRecipient>> searchPatients(
    String search, {
    int limit = 20,
  }) async => patientResults;

  @override
  Future<String> getOwnDoctorId() async => ownDoctorId;

  @override
  Future<PatientMessagingPreference> getPatientMessagingPreference() async {
    return PatientMessagingPreference(allowDoctorMessages: allowDoctorMessages);
  }

  @override
  Future<PatientMessagingPreference> updatePatientMessagingPreference(
    bool allowDoctorMessages,
  ) async {
    preferenceUpdateValues.add(allowDoctorMessages);
    return PatientMessagingPreference(
      allowDoctorMessages: updatedAllowDoctorMessages ?? allowDoctorMessages,
    );
  }
}

class _DeferredListApi extends _ScreenApi {
  _DeferredListApi(this._pending);

  final Future<List<CareConversation>> _pending;

  @override
  Future<ConversationPage> listConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    final items = await _pending;
    return ConversationPage(items: items, limit: limit, offset: offset);
  }
}

class _ScreenRealtime implements MessagingRealtimeClient {
  final _statuses = StreamController<MessagingConnectionStatus>.broadcast();
  final _events = StreamController<MessagingRealtimeEvent>.broadcast();
  MessagingConnectionStatus _status = MessagingConnectionStatus.idle;

  @override
  Stream<MessagingRealtimeEvent> get events => _events.stream;

  @override
  MessagingConnectionStatus get status => _status;

  @override
  Stream<MessagingConnectionStatus> get statuses => _statuses.stream;

  @override
  Future<void> connect() async {
    _status = MessagingConnectionStatus.connected;
    _statuses.add(_status);
  }

  @override
  void disconnect() {
    _status = MessagingConnectionStatus.idle;
  }

  @override
  void dispose() {
    _statuses.close();
    _events.close();
  }

  @override
  Future<void> retry() => connect();

  @override
  Future<bool> subscribe(String conversationId) async => true;

  @override
  void unsubscribe(String conversationId) {}
}

class _FakeAuth extends AuthController {
  _FakeAuth(String role)
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService()),
        GoogleAuthService(),
        SecureStorageService(),
      ) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: UserModel(
        id: _currentUserId,
        email: 'care@example.test',
        role: role,
      ),
    );
  }
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this.languageCode);

  final String languageCode;

  @override
  Future<String?> getLanguageCode() async => languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}
