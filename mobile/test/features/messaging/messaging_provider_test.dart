import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/auth_api.dart';
import 'package:mobile/features/auth/data/google_auth_service.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/auth/repositories/auth_repository.dart';
import 'package:mobile/features/messaging/data/messaging_api.dart';
import 'package:mobile/features/messaging/data/messaging_realtime.dart';
import 'package:mobile/features/messaging/models/messaging_models.dart';
import 'package:mobile/features/messaging/providers/messaging_providers.dart';

void main() {
  group('MessagingInboxController', () {
    test('initial load and refresh keep server ordering', () async {
      final api = _FakeApi()
        ..conversationResponses.add(Future.value(_conversationPage(['A', 'B'])))
        ..conversationResponses.add(
          Future.value(_conversationPage(['B', 'A'])),
        );
      final controller = MessagingInboxController(api);
      addTearDown(controller.dispose);
      await _flush();

      expect(controller.state.items.map((item) => item.otherDisplayName), [
        'A',
        'B',
      ]);
      await controller.refresh();
      expect(controller.state.items.map((item) => item.otherDisplayName), [
        'B',
        'A',
      ]);
      expect(api.listConversationCalls, 2);
    });

    test('stale earlier response cannot replace a newer load', () async {
      final old = Completer<ConversationPage>();
      final fresh = Completer<ConversationPage>();
      final api = _FakeApi()
        ..conversationResponses.addAll([old.future, fresh.future]);
      final controller = MessagingInboxController(api);
      addTearDown(controller.dispose);

      final latestLoad = controller.load();
      fresh.complete(_conversationPage(['Fresh']));
      await latestLoad;
      old.complete(_conversationPage(['Stale']));
      await _flush();

      expect(controller.state.items.single.otherDisplayName, 'Fresh');
    });

    test(
      'disposal ignores an in-flight response and cancels lifecycle work',
      () async {
        final pending = Completer<ConversationPage>();
        final api = _FakeApi()..conversationResponses.add(pending.future);
        final controller = MessagingInboxController(api);
        controller.dispose();
        pending.complete(_conversationPage(['Late']));
        await _flush();
        expect(api.listConversationCalls, 1);
      },
    );

    test(
      'account replacement rebuilds state without retaining the previous inbox',
      () async {
        final api = _FakeApi()
          ..conversationResponses.add(
            Future.value(_conversationPage(['Old account'])),
          )
          ..conversationResponses.add(
            Future.value(_conversationPage(['New account'])),
          );
        final auth = _MutableAuth('account-old');
        final container = ProviderContainer(
          overrides: [
            messagingApiProvider.overrideWithValue(api),
            authControllerProvider.overrideWith((ref) => auth),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen<MessagingInboxState>(
          messagingInboxProvider,
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _flush();
        expect(
          container.read(messagingInboxProvider).items.single.otherDisplayName,
          'Old account',
        );

        auth.replaceAccount('account-new');
        await _flush();

        expect(
          container.read(messagingInboxProvider).items.single.otherDisplayName,
          'New account',
        );
        expect(api.listConversationCalls, 2);
      },
    );
  });

  group('PatientMessagingPreferenceController', () {
    test(
      'loads backend state and changes only after authoritative save',
      () async {
        final update = Completer<PatientMessagingPreference>();
        final api = _FakeApi()
          ..preferenceResponses.add(
            Future.value(
              const PatientMessagingPreference(allowDoctorMessages: false),
            ),
          )
          ..preferenceUpdateResponses.add(update.future);
        final controller = PatientMessagingPreferenceController(
          api,
          isPatient: true,
        );
        addTearDown(controller.dispose);
        await _flush();
        expect(controller.state.allowDoctorMessages, isFalse);

        final first = controller.update(true);
        expect(await controller.update(true), isFalse);
        expect(controller.state.allowDoctorMessages, isFalse);
        expect(controller.state.isSaving, isTrue);
        update.complete(
          const PatientMessagingPreference(allowDoctorMessages: true),
        );
        expect(await first, isTrue);

        expect(controller.state.allowDoctorMessages, isTrue);
        expect(api.preferenceUpdateValues, [true]);
      },
    );

    test('non-patient roles never call patient profile endpoints', () async {
      final api = _FakeApi();
      final controller = PatientMessagingPreferenceController(
        api,
        isPatient: false,
      );
      addTearDown(controller.dispose);
      await _flush();

      expect(controller.state.isApplicable, isFalse);
      expect(await controller.update(true), isFalse);
      expect(api.preferenceLoadCalls, 0);
      expect(api.preferenceUpdateValues, isEmpty);
    });

    test(
      'failed save retains the last server value and exposes only its code',
      () async {
        final failedUpdate = Completer<PatientMessagingPreference>();
        final api = _FakeApi()
          ..preferenceResponses.add(
            Future.value(
              const PatientMessagingPreference(allowDoctorMessages: true),
            ),
          )
          ..preferenceUpdateResponses.add(failedUpdate.future);
        final controller = PatientMessagingPreferenceController(
          api,
          isPatient: true,
        );
        addTearDown(controller.dispose);
        await _flush();

        final save = controller.update(false);
        failedUpdate.completeError(
          const ApiException(
            message: 'raw private server text',
            code: 'VALIDATION_ERROR',
          ),
        );
        expect(await save, isFalse);
        expect(controller.state.allowDoctorMessages, isTrue);
        expect(controller.state.errorCode, 'VALIDATION_ERROR');
      },
    );
  });

  group('ConversationThreadController', () {
    test(
      'loads server history, marks latest read, and subscribes accepted thread',
      () async {
        final api = _threadApi(
          messages: [_message('one'), _message('two', minute: 1)],
        );
        final realtime = _FakeRealtime();
        final controller = _controller(api, realtime);
        addTearDown(controller.dispose);
        await _flush();

        expect(controller.state.messages.map((message) => message.body), [
          'one',
          'two',
        ]);
        expect(api.markReadIds, [_messageId('two')]);
        expect(realtime.connectCalls, 1);
        expect(realtime.subscriptions, [_conversationId]);
      },
    );

    test(
      'double send produces one optimistic bubble and one HTTP call',
      () async {
        final send = Completer<CareMessage>();
        final api = _threadApi()..sendResponses.add(send.future);
        final controller = _controller(api, _FakeRealtime());
        addTearDown(controller.dispose);
        await _flush();

        final first = controller.send(' hello ');
        final second = await controller.send('hello');
        expect(second, isFalse);
        expect(api.sentClientIds, [_clientId]);
        expect(
          controller.state.messages.where((message) => message.body == 'hello'),
          hasLength(1),
        );

        send.complete(_message('hello', clientId: _clientId));
        expect(await first, isTrue);
        expect(
          controller.state.messages.where((message) => message.body == 'hello'),
          hasLength(1),
        );
      },
    );

    test(
      'retry reuses the same client_message_id after a safe failure',
      () async {
        final failedSend = Completer<CareMessage>();
        final api = _threadApi()
          ..sendResponses.add(failedSend.future)
          ..sendResponses.add(
            Future.value(_message('retry', clientId: _clientId)),
          );
        final controller = _controller(api, _FakeRealtime());
        addTearDown(controller.dispose);
        await _flush();

        final first = controller.send('retry');
        failedSend.completeError(
          const ApiException(message: 'raw', code: 'SERVICE_UNAVAILABLE'),
        );
        expect(await first, isFalse);
        expect(
          controller.state.messages.single.deliveryState,
          MessageDeliveryState.failed,
        );
        expect(await controller.retry(_clientId), isTrue);

        expect(api.sentClientIds, [_clientId, _clientId]);
        expect(controller.state.messages.single.isAuthoritative, isTrue);
      },
    );

    test(
      'socket echo reconciles before a delayed HTTP response without duplicates',
      () async {
        final send = Completer<CareMessage>();
        final api = _threadApi()..sendResponses.add(send.future);
        final realtime = _FakeRealtime();
        final controller = _controller(api, realtime);
        addTearDown(controller.dispose);
        await _flush();

        final future = controller.send('echo');
        final authoritative = _message('echo', clientId: _clientId);
        realtime.emit(RealtimeMessageCreated(authoritative));
        await _flush();
        expect(
          controller.state.messages.where((message) => message.body == 'echo'),
          hasLength(1),
        );
        expect(controller.state.messages.single.isAuthoritative, isTrue);

        send.complete(authoritative);
        expect(await future, isTrue);
        expect(
          controller.state.messages.where((message) => message.body == 'echo'),
          hasLength(1),
        );
      },
    );

    test(
      'older pagination prepends uniquely and advances the opaque cursor',
      () async {
        final api =
            _threadApi(
                messages: [_message('new', minute: 2)],
                nextCursor: 'older-1',
              )
              ..messageResponses.add(
                Future.value(
                  const MessagePage(items: [], latestCursor: 'latest-1'),
                ),
              )
              ..messageResponses.add(
                Future.value(
                  MessagePage(
                    items: [_message('old')],
                    nextCursor: null,
                    latestCursor: 'old-latest',
                  ),
                ),
              );
        final controller = _controller(api, _FakeRealtime());
        addTearDown(controller.dispose);
        await _flush();

        await controller.loadOlder();
        expect(controller.state.messages.map((message) => message.body), [
          'old',
          'new',
        ]);
        expect(controller.state.nextCursor, isNull);
        expect(api.messageQueries.last.cursor, 'older-1');
      },
    );

    test(
      'missed REST and socket delivery reconcile to the same authoritative message',
      () async {
        final incoming = _message(
          'incoming',
          senderId: _otherUserId,
          minute: 3,
        );
        final api = _threadApi()
          ..messageResponses.add(
            Future.value(
              MessagePage(items: [incoming], latestCursor: 'latest-2'),
            ),
          );
        final realtime = _FakeRealtime();
        final controller = _controller(api, realtime);
        addTearDown(controller.dispose);
        await _flush();

        realtime.emit(RealtimeMessageCreated(incoming));
        await controller.syncMissed();
        expect(
          controller.state.messages.where(
            (message) => message.body == 'incoming',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'pending patient request accepts once and unlocks only after backend success',
      () async {
        final pending = _conversation(
          requestStatus: 'pending',
          canRespond: true,
        );
        final accepted = _conversation(requestStatus: 'accepted');
        final api = _threadApi(conversation: pending)
          ..acceptResponses.add(Future.value(accepted));
        final realtime = _FakeRealtime();
        final controller = _controller(api, realtime);
        addTearDown(controller.dispose);
        await _flush();

        expect(controller.state.canSend, isFalse);
        expect(await controller.acceptRequest(), isTrue);
        expect(controller.state.canSend, isTrue);
        expect(api.acceptCalls, 1);
        expect(realtime.connectCalls, 1);
      },
    );

    test(
      'pending patient request decline is single-flight and closes locally after authority',
      () async {
        final pending = _conversation(
          requestStatus: 'pending',
          canRespond: true,
        );
        final decision = Completer<RequestDecision>();
        final api = _threadApi(conversation: pending)
          ..declineResponses.add(decision.future);
        final controller = _controller(api, _FakeRealtime());
        addTearDown(controller.dispose);
        await _flush();

        final first = controller.declineRequest();
        expect(await controller.declineRequest(), isFalse);
        decision.complete(
          const RequestDecision(
            id: _conversationId,
            status: 'closed',
            requestStatus: 'declined',
          ),
        );
        expect(await first, isTrue);
        expect(controller.state.closed, isTrue);
        expect(api.declineCalls, 1);
      },
    );

    test(
      'lifecycle pause disconnects and resume performs missed sync',
      () async {
        final api = _threadApi()
          ..messageResponses.add(
            Future.value(const MessagePage(items: [], latestCursor: 'latest')),
          );
        final realtime = _FakeRealtime();
        final controller = _controller(api, realtime);
        addTearDown(controller.dispose);
        await _flush();

        controller.setActive(false);
        expect(realtime.disconnectCalls, 1);
        controller.setActive(true);
        await _flush();
        expect(realtime.connectCalls, greaterThanOrEqualTo(2));
        expect(api.messageQueries.any((query) => query.after != null), isTrue);
      },
    );

    testWidgets(
      'unavailable realtime falls back to REST polling only while active',
      (tester) async {
        final api = _threadApi()
          ..messageResponses.add(
            Future.value(
              const MessagePage(items: [], latestCursor: 'latest-2'),
            ),
          );
        final realtime = _FakeRealtime(
          connectStatus: MessagingConnectionStatus.unavailable,
        );
        final controller = _controller(api, realtime);
        addTearDown(controller.dispose);
        await tester.pump();
        await tester.pump();
        expect(
          controller.state.connectionStatus,
          MessagingConnectionStatus.unavailable,
        );

        await tester.pump(const Duration(seconds: 8));
        await tester.pump();
        expect(
          api.messageQueries.any((query) => query.after == 'latest-1'),
          isTrue,
        );

        controller.setActive(false);
        final callsWhenPaused = api.messageQueries.length;
        await tester.pump(const Duration(seconds: 16));
        expect(api.messageQueries, hasLength(callsWhenPaused));
      },
    );
  });

  group('RecipientSearchController', () {
    test(
      'doctor search merges opted-in patients, removes self, and protects stale results',
      () async {
        final stale = Completer<List<MessagingRecipient>>();
        final api = _FakeApi()
          ..ownDoctorId = _otherUserId
          ..doctorSearchResponses.addAll([
            stale.future,
            Future.value([_recipient('new-doctor')]),
          ])
          ..patientSearchResponses.addAll([
            Future.value([_recipient('old-patient', patient: true)]),
            Future.value([_recipient('new-patient', patient: true)]),
          ]);
        final controller = RecipientSearchController(api, 'doctor');
        addTearDown(controller.dispose);

        final first = controller.search('old');
        final second = controller.search('new');
        await second;
        stale.complete([
          _recipient('stale'),
          _recipient('self', id: _otherUserId),
        ]);
        await first;

        expect(controller.state.items.map((item) => item.firstNameEn), [
          'new-patient',
          'new-doctor',
        ]);
        expect(
          controller.state.items.any((item) => item.id == _otherUserId),
          isFalse,
        );
      },
    );

    test('duplicate start tap creates one backend conversation', () async {
      final pending = Completer<CareConversation>();
      final api = _FakeApi()..createResponses.add(pending.future);
      final controller = RecipientSearchController(api, 'patient');
      addTearDown(controller.dispose);

      final first = controller.startConversation(_otherUserId);
      expect(await controller.startConversation(_otherUserId), isNull);
      pending.complete(_conversation());
      expect((await first)?.id, _conversationId);
      expect(api.createCalls, 1);
    });
  });
}

const _conversationId = '123e4567-e89b-42d3-a456-426614174000';
const _currentUserId = '223e4567-e89b-42d3-a456-426614174001';
const _otherUserId = '323e4567-e89b-42d3-a456-426614174002';
const _clientId = '423e4567-e89b-42d3-a456-426614174003';

ConversationThreadController _controller(
  _FakeApi api,
  _FakeRealtime realtime,
) => ConversationThreadController(
  _conversationId,
  _currentUserId,
  api,
  realtime,
  () => _clientId,
  () => DateTime.utc(2026, 8, 29, 12),
  () {},
);

_FakeApi _threadApi({
  CareConversation? conversation,
  List<CareMessage> messages = const [],
  String? nextCursor,
}) => _FakeApi()
  ..conversationResponses.add(
    Future.value(
      ConversationPage(
        items: [conversation ?? _conversation()],
        limit: 50,
        offset: 0,
      ),
    ),
  )
  ..messageResponses.add(
    Future.value(
      MessagePage(
        items: messages,
        nextCursor: nextCursor,
        latestCursor: 'latest-1',
      ),
    ),
  );

ConversationPage _conversationPage(List<String> names) => ConversationPage(
  items: [
    for (var index = 0; index < names.length; index++)
      _conversation(name: names[index], idSuffix: index),
  ],
  limit: 50,
  offset: 0,
);

CareConversation _conversation({
  String name = 'Dr Lina',
  String requestStatus = 'accepted',
  bool canRespond = false,
  int idSuffix = 0,
}) => CareConversation(
  id: idSuffix == 0
      ? _conversationId
      : '123e4567-e89b-42d3-a456-42661417400$idSuffix',
  status: 'active',
  conversationType: 'patient_doctor',
  requestStatus: requestStatus,
  initiatedByUserId: _otherUserId,
  createdAt: DateTime.utc(2026, 8, 29),
  otherRole: 'doctor',
  otherDisplayName: name,
  canRespondToRequest: canRespond,
  unreadCount: 1,
);

String _messageId(String body) {
  final suffix = body.codeUnits.fold<int>(0, (sum, value) => sum + value) % 10;
  return '523e4567-e89b-42d3-a456-42661417400$suffix';
}

CareMessage _message(
  String body, {
  String? clientId,
  String senderId = _currentUserId,
  int minute = 0,
}) => CareMessage(
  id: _messageId(body),
  conversationId: _conversationId,
  senderUserId: senderId,
  clientMessageId:
      clientId ??
      '623e4567-e89b-42d3-a456-42661417400${body.codeUnits.fold<int>(0, (sum, value) => sum + value) % 10}',
  body: body,
  createdAt: DateTime.utc(2026, 8, 29, 12, minute),
);

MessagingRecipient _recipient(
  String name, {
  bool patient = false,
  String? id,
}) => MessagingRecipient(
  id: id ?? '723e4567-e89b-42d3-a456-426614174007',
  kind: patient ? RecipientKind.patient : RecipientKind.doctor,
  firstNameEn: name,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _MessageQuery {
  const _MessageQuery({this.cursor, this.after});
  final String? cursor;
  final String? after;
}

class _FakeApi extends MessagingApi {
  _FakeApi() : super(Dio());

  final conversationResponses = <Future<ConversationPage>>[];
  final messageResponses = <Future<MessagePage>>[];
  final sendResponses = <Future<CareMessage>>[];
  final acceptResponses = <Future<CareConversation>>[];
  final declineResponses = <Future<RequestDecision>>[];
  final createResponses = <Future<CareConversation>>[];
  final doctorSearchResponses = <Future<List<MessagingRecipient>>>[];
  final patientSearchResponses = <Future<List<MessagingRecipient>>>[];
  final preferenceResponses = <Future<PatientMessagingPreference>>[];
  final preferenceUpdateResponses = <Future<PatientMessagingPreference>>[];
  final messageQueries = <_MessageQuery>[];
  final sentClientIds = <String>[];
  final markReadIds = <String?>[];
  int listConversationCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;
  int createCalls = 0;
  int preferenceLoadCalls = 0;
  final preferenceUpdateValues = <bool>[];
  String ownDoctorId = _otherUserId;

  @override
  Future<ConversationPage> listConversations({int limit = 50, int offset = 0}) {
    listConversationCalls++;
    return conversationResponses.removeAt(0);
  }

  @override
  Future<MessagePage> listMessages(
    String conversationId, {
    int limit = 50,
    String? cursor,
    String? after,
  }) {
    messageQueries.add(_MessageQuery(cursor: cursor, after: after));
    return messageResponses.removeAt(0);
  }

  @override
  Future<CareMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) {
    sentClientIds.add(clientMessageId);
    return sendResponses.removeAt(0);
  }

  @override
  Future<MessagingReadState> markRead(
    String conversationId, {
    String? messageId,
  }) async {
    markReadIds.add(messageId);
    return MessagingReadState(
      conversationId: conversationId,
      lastReadMessageId: messageId,
    );
  }

  @override
  Future<CareConversation> acceptRequest(String conversationId) {
    acceptCalls++;
    return acceptResponses.removeAt(0);
  }

  @override
  Future<RequestDecision> declineRequest(String conversationId) {
    declineCalls++;
    return declineResponses.removeAt(0);
  }

  @override
  Future<CareConversation> createConversation(String counterpartId) {
    createCalls++;
    return createResponses.removeAt(0);
  }

  @override
  Future<List<MessagingRecipient>> searchDoctors(
    String search, {
    int limit = 20,
  }) => doctorSearchResponses.removeAt(0);

  @override
  Future<List<MessagingRecipient>> searchPatients(
    String search, {
    int limit = 20,
  }) => patientSearchResponses.removeAt(0);

  @override
  Future<String> getOwnDoctorId() async => ownDoctorId;

  @override
  Future<PatientMessagingPreference> getPatientMessagingPreference() {
    preferenceLoadCalls++;
    return preferenceResponses.removeAt(0);
  }

  @override
  Future<PatientMessagingPreference> updatePatientMessagingPreference(
    bool allowDoctorMessages,
  ) {
    preferenceUpdateValues.add(allowDoctorMessages);
    return preferenceUpdateResponses.removeAt(0);
  }
}

class _FakeRealtime implements MessagingRealtimeClient {
  _FakeRealtime({this.connectStatus = MessagingConnectionStatus.connected});

  final MessagingConnectionStatus connectStatus;
  final _statuses = StreamController<MessagingConnectionStatus>.broadcast();
  final _events = StreamController<MessagingRealtimeEvent>.broadcast();
  MessagingConnectionStatus _status = MessagingConnectionStatus.idle;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int retryCalls = 0;
  final subscriptions = <String>[];

  @override
  Stream<MessagingRealtimeEvent> get events => _events.stream;
  @override
  Stream<MessagingConnectionStatus> get statuses => _statuses.stream;
  @override
  MessagingConnectionStatus get status => _status;

  @override
  Future<void> connect() async {
    connectCalls++;
    _status = connectStatus;
    _statuses.add(_status);
  }

  @override
  Future<bool> subscribe(String conversationId) async {
    subscriptions.add(conversationId);
    return true;
  }

  void emit(MessagingRealtimeEvent event) => _events.add(event);

  @override
  void unsubscribe(String conversationId) {}

  @override
  Future<void> retry() async {
    retryCalls++;
    await connect();
  }

  @override
  void disconnect() {
    disconnectCalls++;
    _status = MessagingConnectionStatus.idle;
  }

  @override
  void dispose() {
    _statuses.close();
    _events.close();
  }
}

class _MutableAuth extends AuthController {
  _MutableAuth(String userId)
    : super(
        AuthRepository(AuthApi(Dio()), SecureStorageService()),
        GoogleAuthService(),
        SecureStorageService(),
      ) {
    replaceAccount(userId);
  }

  void replaceAccount(String userId) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: UserModel(
        id: userId,
        email: '$userId@example.test',
        role: 'patient',
      ),
    );
  }
}
