import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/billing/models/billing_models.dart';
import 'package:mobile/features/chatbot/data/chatbot_api.dart';
import 'package:mobile/features/chatbot/models/chatbot_models.dart';
import 'package:mobile/features/chatbot/providers/chatbot_provider.dart';

void main() {
  test(
    'successful first message sets conversation ID and inserts user and bot once',
    () async {
      final fake = _FakeChatbotApi()
        ..sendResults.add(
          Future.value(
            const ChatMessageResponse(
              conversationId: 'conversation-1',
              reply: 'Here are nearby options.',
              intent: 'find_clinic',
              confidence: 0.91,
              places: [ChatPlaceResult(id: 'place-1', nameEn: 'Nablus Clinic')],
              doctors: [
                ChatDoctorResult(id: 'doctor-1', firstNameEn: 'Mariam'),
              ],
              route: ChatRouteResult(distanceKm: 1.4),
              suggestions: [ChatSuggestion(text: 'Show clinic details')],
            ),
          ),
        );
      final container = _container(fake);
      addTearDown(container.dispose);

      final ok = await container
          .read(chatbotControllerProvider.notifier)
          .sendMessage('Find a clinic');
      final state = container.read(chatbotControllerProvider);

      expect(ok, isTrue);
      expect(state.currentConversationId, 'conversation-1');
      expect(
        state.messages.where((message) => message.messageType == 'user'),
        hasLength(1),
      );
      expect(
        state.messages.where((message) => message.messageType == 'assistant'),
        hasLength(1),
      );
      expect(state.places.single.id, 'place-1');
      expect(state.doctors.single.id, 'doctor-1');
      expect(state.route?.distanceKm, 1.4);
      expect(state.suggestions.single.text, 'Show clinic details');
      expect(state.lastIntent, 'find_clinic');
      expect(state.lastConfidence, 0.91);
    },
  );

  test('duplicate concurrent send is prevented', () async {
    final completer = Completer<ChatMessageResponse>();
    final fake = _FakeChatbotApi()..sendResults.add(completer.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    final first = container
        .read(chatbotControllerProvider.notifier)
        .sendMessage('Find a doctor');
    final second = await container
        .read(chatbotControllerProvider.notifier)
        .sendMessage('Find a doctor');

    expect(second, isFalse);
    expect(fake.sendRequests, hasLength(1));

    completer.complete(
      const ChatMessageResponse(
        conversationId: 'conversation-1',
        reply: 'Done.',
      ),
    );
    expect(await first, isTrue);
  });

  test(
    'failure keeps user message exposes retry and retry does not duplicate user message',
    () async {
      final failure = Completer<ChatMessageResponse>();
      final fake = _FakeChatbotApi()
        ..sendResults.add(failure.future)
        ..sendResults.add(
          Future.value(
            const ChatMessageResponse(
              conversationId: 'conversation-1',
              reply: 'Recovered reply.',
            ),
          ),
        );
      final container = _container(fake);
      addTearDown(container.dispose);

      final pending = container
          .read(chatbotControllerProvider.notifier)
          .sendMessage('I need help');
      failure.completeError(
        const ApiException(message: 'Could not send message.', code: 'NETWORK'),
      );
      final first = await pending;
      final failedState = container.read(chatbotControllerProvider);

      expect(first, isFalse);
      expect(failedState.messages, hasLength(1));
      expect(failedState.messages.single.messageType, 'user');
      expect(failedState.error?.retryable, isTrue);

      final retry = await container
          .read(chatbotControllerProvider.notifier)
          .retryLastMessage();
      final retriedState = container.read(chatbotControllerProvider);

      expect(retry, isTrue);
      expect(fake.sendRequests, hasLength(2));
      expect(
        retriedState.messages.where((message) => message.messageType == 'user'),
        hasLength(1),
      );
      expect(
        retriedState.messages.where(
          (message) => message.messageType == 'assistant',
        ),
        hasLength(1),
      );
      expect(retriedState.error, isNull);
    },
  );

  test(
    'retry reuses one client request ID for one logical charged message',
    () async {
      final first = Completer<ChatMessageResponse>();
      final fake = _FakeChatbotApi()
        ..sendResults.add(first.future)
        ..sendResults.add(
          Future.value(
            const ChatMessageResponse(
              conversationId: 'conversation-1',
              reply: 'Idempotent replay.',
            ),
          ),
        );
      var idCalls = 0;
      final controller = ChatbotController(
        fake,
        requestIdFactory: () {
          idCalls += 1;
          return 'stable-request-$idCalls';
        },
      );
      addTearDown(controller.dispose);

      final pending = controller.sendMessage('Please answer once');
      first.completeError(
        const ApiException(message: 'Network interrupted', code: 'NETWORK'),
      );
      expect(await pending, isFalse);
      expect(await controller.retryLastMessage(), isTrue);

      expect(idCalls, 1);
      expect(fake.sendRequests, hasLength(2));
      expect(fake.sendRequests[0].clientMessageId, 'stable-request-1');
      expect(fake.sendRequests[1].clientMessageId, 'stable-request-1');
      expect(
        controller.state.messages.where((m) => m.messageType == 'user'),
        hasLength(1),
      );
    },
  );

  test(
    'accepted response quota is applied to local and shared snapshots',
    () async {
      const quota = ChatEntitlement(
        allowed: true,
        unlimited: false,
        used: 3,
        limit: 7,
        remaining: 4,
      );
      final received = <ChatEntitlement>[];
      final fake = _FakeChatbotApi()
        ..sendResults.add(
          Future.value(
            const ChatMessageResponse(
              conversationId: 'conversation-1',
              reply: 'Accepted.',
              quota: quota,
            ),
          ),
        );
      final controller = ChatbotController(fake, onQuota: received.add);
      addTearDown(controller.dispose);

      expect(await controller.sendMessage('Hello'), isTrue);
      expect(controller.state.quota?.remaining, 4);
      expect(received.single.remaining, 4);
    },
  );

  test(
    'quota denial details become the authoritative exhausted snapshot',
    () async {
      final fake = _FakeChatbotApi()
        ..sendResults.add(
          Future.error(
            const ApiException(
              message: 'raw backend prose',
              code: ApiException.codeFreeQuotaExhausted,
              details: {
                'used': 7,
                'limit': 7,
                'remaining': 0,
                'resets_at': '2026-08-30T10:00:00Z',
              },
            ),
          ),
        );
      final controller = ChatbotController(fake);
      addTearDown(controller.dispose);

      expect(await controller.sendMessage('One too many'), isFalse);
      expect(controller.state.quota?.remaining, 0);
      expect(controller.state.quota?.allowed, isFalse);
      expect(
        controller.state.quota?.resetsAt,
        DateTime.parse('2026-08-30T10:00:00Z'),
      );
    },
  );

  test(
    'RATE_LIMITED is a retryable fair-use error distinct from free quota',
    () async {
      final fake = _FakeChatbotApi()
        ..sendResults.add(
          Future.error(
            const ApiException(
              message: 'raw backend prose',
              code: ApiException.codeRateLimited,
              statusCode: 429,
            ),
          ),
        );
      final controller = ChatbotController(fake);
      addTearDown(controller.dispose);

      await controller.sendMessage('Slow down');

      expect(controller.state.error?.kind, ChatFailureKind.rateLimited);
      expect(controller.state.error?.retryable, isTrue);
    },
  );

  test('loadConversation restores messages and metadata', () async {
    final fake = _FakeChatbotApi()
      ..detailResults.add(
        Future.value(
          ConversationDetail(
            conversation: const ConversationSummary(
              id: 'conversation-1',
              title: 'Saved',
            ),
            messages: [
              ChatMessage(
                id: 'message-1',
                messageText: 'Headache',
                messageType: 'user',
                metadata: const ChatMetadata({'severity': 'mild'}),
                createdAt: DateTime.parse('2026-08-04T10:00:00Z'),
              ),
            ],
            places: const [
              ChatConversationPlace(id: 'place-1', nameEn: 'Saved Clinic'),
            ],
            messageCount: 1,
          ),
        ),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    final ok = await container
        .read(chatbotControllerProvider.notifier)
        .loadConversation('conversation-1');
    final state = container.read(chatbotControllerProvider);

    expect(ok, isTrue);
    expect(state.currentConversationId, 'conversation-1');
    expect(state.messages.single.metadata.values['severity'], 'mild');
    expect(state.messages.single.createdAt, isNotNull);
    expect(state.places.single.id, 'place-1');
  });

  test('startNewConversation clears state without API call', () async {
    final fake = _FakeChatbotApi()
      ..sendResults.add(
        Future.value(
          const ChatMessageResponse(
            conversationId: 'conversation-1',
            reply: 'Hello',
          ),
        ),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    await container
        .read(chatbotControllerProvider.notifier)
        .sendMessage('Hello');
    container.read(chatbotControllerProvider.notifier).startNewConversation();

    expect(container.read(chatbotControllerProvider).hasMessages, isFalse);
    expect(
      container.read(chatbotControllerProvider).currentConversationId,
      isNull,
    );
    expect(fake.createConversationCalls, 0);
  });

  group('entitlement failures', () {
    test(
      'FREE_QUOTA_EXHAUSTED classifies as freeQuotaExhausted and is not retryable',
      () async {
        final fake = _FakeChatbotApi()
          ..sendResults.add(
            Future.error(
              const ApiException(
                message: 'Your free messages are used for this period.',
                code: ApiException.codeFreeQuotaExhausted,
                statusCode: 429,
                details: {
                  'used': 20,
                  'limit': 20,
                  'remaining': 0,
                  'resets_at': '2026-08-23T00:00:00Z',
                },
              ),
            ),
          );
        final container = _container(fake);
        addTearDown(container.dispose);

        await container
            .read(chatbotControllerProvider.notifier)
            .sendMessage('Hello');
        final error = container.read(chatbotControllerProvider).error;

        expect(error, isNotNull);
        expect(error!.kind, ChatFailureKind.freeQuotaExhausted);
        expect(error.retryable, isFalse);
        expect(error.code, ApiException.codeFreeQuotaExhausted);
      },
    );

    test(
      'DUPLICATE_IN_FLIGHT classifies as duplicateInFlight and stays retryable',
      () async {
        final fake = _FakeChatbotApi()
          ..sendResults.add(
            Future.error(
              const ApiException(
                message: 'This message is already being processed.',
                code: ApiException.codeDuplicateInFlight,
                statusCode: 409,
                details: {'retry_after_seconds': 2},
              ),
            ),
          );
        final container = _container(fake);
        addTearDown(container.dispose);

        await container
            .read(chatbotControllerProvider.notifier)
            .sendMessage('Hello');
        final error = container.read(chatbotControllerProvider).error;

        expect(error!.kind, ChatFailureKind.duplicateInFlight);
        expect(error.retryable, isTrue);
      },
    );

    test(
      'ENTITLEMENT_UNAVAILABLE classifies distinctly from quota exhaustion and stays retryable',
      () async {
        final fake = _FakeChatbotApi()
          ..sendResults.add(
            Future.error(
              const ApiException(
                message:
                    'Entitlement could not be determined. Please try again.',
                code: ApiException.codeEntitlementUnavailable,
                statusCode: 403,
              ),
            ),
          );
        final container = _container(fake);
        addTearDown(container.dispose);

        await container
            .read(chatbotControllerProvider.notifier)
            .sendMessage('Hello');
        final error = container.read(chatbotControllerProvider).error;

        expect(error!.kind, ChatFailureKind.entitlementUnavailable);
        expect(error.kind, isNot(ChatFailureKind.freeQuotaExhausted));
        expect(error.retryable, isTrue);
      },
    );

    test(
      'SUBSCRIPTION_REQUIRED and SUBSCRIPTION_INACTIVE are handled defensively and are not retryable',
      () async {
        for (final code in [
          ApiException.codeSubscriptionRequired,
          ApiException.codeSubscriptionInactive,
        ]) {
          final fake = _FakeChatbotApi()
            ..sendResults.add(
              Future.error(
                ApiException(
                  message: 'Subscription issue.',
                  code: code,
                  statusCode: 403,
                ),
              ),
            );
          final container = _container(fake);
          addTearDown(container.dispose);

          await container
              .read(chatbotControllerProvider.notifier)
              .sendMessage('Hello');
          final error = container.read(chatbotControllerProvider).error;

          expect(error, isNotNull, reason: code);
          expect(error!.retryable, isFalse, reason: code);
        }
      },
    );

    test(
      'an entitlement failure never crashes and carries no raw server message dependency',
      () async {
        final fake = _FakeChatbotApi()
          ..sendResults.add(
            Future.error(
              const ApiException(
                message:
                    'some arbitrary backend copy that could change at any time',
                code: ApiException.codeFreeQuotaExhausted,
                statusCode: 429,
              ),
            ),
          );
        final container = _container(fake);
        addTearDown(container.dispose);

        final ok = await container
            .read(chatbotControllerProvider.notifier)
            .sendMessage('Hello');

        expect(ok, isFalse);
        // The controller classifies by `code`, a machine-readable constant — the
        // screen renders text from AppStrings keyed on `error.kind`, never
        // `error.message`, so a copy change on the backend cannot break display.
        expect(
          container.read(chatbotControllerProvider).error?.kind,
          ChatFailureKind.freeQuotaExhausted,
        );
      },
    );
  });

  test('no manual sensitive logging', () async {
    final fake = _FakeChatbotApi()
      ..sendResults.add(
        Future.value(
          const ChatMessageResponse(
            conversationId: 'conversation-1',
            reply: 'Private reply',
          ),
        ),
      );
    final container = _container(fake);
    addTearDown(container.dispose);
    final printed = <String>[];

    await runZoned(
      () => container
          .read(chatbotControllerProvider.notifier)
          .sendMessage('Private medical message'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

ProviderContainer _container(_FakeChatbotApi fake) {
  return ProviderContainer(
    overrides: [chatbotApiProvider.overrideWithValue(fake)],
  );
}

class _FakeChatbotApi extends ChatbotApi {
  _FakeChatbotApi() : super(Dio());

  final sendResults = <Future<ChatMessageResponse>>[];
  final detailResults = <Future<ConversationDetail>>[];
  final sendRequests = <ChatMessageRequest>[];
  int createConversationCalls = 0;

  @override
  Future<ChatMessageResponse> sendMessage(ChatMessageRequest request) {
    sendRequests.add(request);
    return sendResults.removeAt(0);
  }

  @override
  Future<ConversationDetail> getConversation(
    String id, {
    int limit = 50,
    int offset = 0,
  }) {
    return detailResults.removeAt(0);
  }

  @override
  Future<ConversationSummary> createConversation({String? language}) {
    createConversationCalls += 1;
    return Future.value(
      ConversationSummary(id: 'created-$createConversationCalls'),
    );
  }
}
