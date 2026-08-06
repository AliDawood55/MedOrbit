import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/chatbot/data/chatbot_api.dart';
import 'package:mobile/features/chatbot/models/chatbot_models.dart';
import 'package:mobile/features/chatbot/providers/chatbot_provider.dart';

void main() {
  group('per-request timeout budget', () {
    test('/chat/message gets an AI-safe receive budget above the backend ceiling', () async {
      final server = _FakeServer()..enqueue(_ok());
      final api = ChatbotApi(server.dio);

      await api.sendMessage(const ChatMessageRequest(message: 'hello'));

      final request = server.requests.single;
      expect(request.path, '/chat/message');
      expect(request.receiveTimeout, AppConfig.chatAiReceiveTimeout);
      expect(request.sendTimeout, AppConfig.chatAiSendTimeout);
      // Connect is untouched: reaching the server is not the slow part.
      expect(request.connectTimeout, AppConfig.connectTimeout);
      // The whole point — the shared 15s budget aborted valid slow answers.
      expect(request.receiveTimeout!.inSeconds, greaterThan(60));
    });

    test('the widened budget is not applied globally', () async {
      final server = _FakeServer()
        ..enqueue(_ok({'conversations': [], 'pagination': null}))
        ..enqueue(_ok({'conversations': []}));
      final api = ChatbotApi(server.dio);

      await api.listConversations();
      await api.searchConversations('clinic');

      for (final request in server.requests) {
        expect(request.receiveTimeout, AppConfig.receiveTimeout);
        expect(request.receiveTimeout, isNot(AppConfig.chatAiReceiveTimeout));
      }
    });

    test('a slow answer inside the new budget still succeeds', () async {
      final server = _FakeServer(delay: const Duration(milliseconds: 120))..enqueue(_ok());
      final api = ChatbotApi(server.dio);

      final response = await api.sendMessage(const ChatMessageRequest(message: 'hello'));

      expect(response.reply, 'A reply.');
    });

    test('is tagged for the redacting log interceptor', () async {
      final server = _FakeServer()..enqueue(_ok());
      final api = ChatbotApi(server.dio);

      await api.sendMessage(const ChatMessageRequest(message: 'hello'));

      expect(server.requests.single.extra['network.requestName'], 'chat.message');
    });
  });

  group('failure categorisation', () {
    test('a receive timeout is a timeout, not an unreachable service', () async {
      final container = _container(_FakeChatbotApi()..failWith(DioExceptionType.receiveTimeout));
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have a headache');

      final error = container.read(chatbotControllerProvider).error!;
      expect(error.kind, ChatFailureKind.receiveTimeout);
      expect(error.isTimeout, isTrue);
      expect(error.code, ApiException.codeReceiveTimeout);
    });

    test('a connect timeout is reported separately from a receive timeout', () async {
      final container = _container(_FakeChatbotApi()..failWith(DioExceptionType.connectionTimeout));
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have a headache');

      final error = container.read(chatbotControllerProvider).error!;
      expect(error.kind, ChatFailureKind.connectTimeout);
      expect(error.code, ApiException.codeConnectTimeout);
    });

    test('a connection error is service-unavailable, and is not a timeout', () async {
      // Must never be described as "took longer than expected" — the message
      // never arrived at all.
      final container = _container(_FakeChatbotApi()..failWith(DioExceptionType.connectionError));
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have a headache');

      final error = container.read(chatbotControllerProvider).error!;
      expect(error.kind, ChatFailureKind.unavailable);
      expect(error.isTimeout, isFalse);
    });

    test('a malformed envelope is an invalid response, not a network fault', () async {
      final container = _container(
        _FakeChatbotApi()
          ..failWithException(
            const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE'),
          ),
      );
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have a headache');

      expect(container.read(chatbotControllerProvider).error!.kind, ChatFailureKind.invalidResponse);
    });

    test('a backend HTTP failure is categorised as backend', () async {
      final container = _container(
        _FakeChatbotApi()
          ..failWithException(
            const ApiException(message: 'Request failed.', code: 'BACKEND_FAILURE', statusCode: 500),
          ),
      );
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have a headache');

      expect(container.read(chatbotControllerProvider).error!.kind, ChatFailureKind.backend);
    });

    test('every failure stays retryable so the patient can try again', () async {
      final container = _container(_FakeChatbotApi()..failWith(DioExceptionType.receiveTimeout));
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have a headache');

      expect(container.read(chatbotControllerProvider).error!.retryable, isTrue);
    });
  });

  group('retry behaviour', () {
    test('the message stays visible after a failure', () async {
      final container = _container(_FakeChatbotApi()..failWith(DioExceptionType.receiveTimeout));
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have chest pain');

      final state = container.read(chatbotControllerProvider);
      expect(state.messages, hasLength(1));
      expect(state.messages.single.messageType, 'user');
      expect(state.messages.single.messageText, 'I have chest pain');
    });

    test('retrying does not duplicate the user message', () async {
      final fake = _FakeChatbotApi()..failWith(DioExceptionType.receiveTimeout);
      final container = _container(fake);
      addTearDown(container.dispose);
      final controller = container.read(chatbotControllerProvider.notifier);

      await controller.sendMessage('I have chest pain');
      fake.succeedNext();
      await controller.retryLastMessage();

      final state = container.read(chatbotControllerProvider);
      expect(state.messages.where((m) => m.messageType == 'user'), hasLength(1));
      expect(fake.sendRequests, hasLength(2));
      expect(state.error, isNull);
    });

    test('nothing is retried automatically', () async {
      // A medical question must never be resent without the patient asking.
      final fake = _FakeChatbotApi()..failWith(DioExceptionType.receiveTimeout);
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have chest pain');

      expect(fake.sendRequests, hasLength(1));
    });

    test('a send already in flight is not duplicated', () async {
      final fake = _FakeChatbotApi();
      final pending = Completer<ChatMessageResponse>();
      fake.sendResults.add(pending.future);
      final container = _container(fake);
      addTearDown(container.dispose);
      final controller = container.read(chatbotControllerProvider.notifier);

      final first = controller.sendMessage('Find a doctor');
      final second = await controller.sendMessage('Find a doctor');

      expect(second, isFalse);
      expect(fake.sendRequests, hasLength(1));
      pending.complete(const ChatMessageResponse(conversationId: 'c1', reply: 'Done.'));
      expect(await first, isTrue);
    });
  });

  group('privacy', () {
    test('a failed send logs nothing at all', () async {
      final printed = <String>[];
      final container = _container(_FakeChatbotApi()..failWith(DioExceptionType.receiveTimeout));
      addTearDown(container.dispose);

      await runZoned(
        () => container
            .read(chatbotControllerProvider.notifier)
            .sendMessage('I have severe chest pain', latitude: 32.2211, longitude: 35.2544),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );

      expect(printed, isEmpty);
    });

    test('the surfaced error carries no raw exception text', () async {
      final container = _container(_FakeChatbotApi()..failWithRaw(_LeakyError()));
      addTearDown(container.dispose);

      await container.read(chatbotControllerProvider.notifier).sendMessage('I have chest pain');

      final error = container.read(chatbotControllerProvider).error!;
      expect(error.message, isNot(contains('patient-record')));
      expect(error.message, isNot(contains(r'C:\')));
      expect(error.kind, ChatFailureKind.unknown);
    });
  });
}

ProviderContainer _container(_FakeChatbotApi fake) {
  return ProviderContainer(overrides: [chatbotApiProvider.overrideWithValue(fake)]);
}

Map<String, dynamic> _ok([Map<String, dynamic>? data]) {
  return {
    'success': true,
    'data': data ?? {'conversationId': 'c1', 'reply': 'A reply.'},
  };
}

/// Transport-level fake, so the real `Options` the API attaches are observable.
class _FakeServer implements HttpClientAdapter {
  _FakeServer({this.delay}) {
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api',
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.sendTimeout,
      ),
    )..httpClientAdapter = this;
  }

  final Duration? delay;
  late final Dio dio;
  final List<_Reply> _replies = [];
  final List<RequestOptions> requests = [];

  void enqueue(Map<String, dynamic> body) => _replies.add(_Reply(200, body));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (delay != null) await Future<void>.delayed(delay!);
    final reply = _replies.isEmpty ? _Reply(500, const {'success': false}) : _replies.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  const _Reply(this.statusCode, this.body);
  final int statusCode;
  final Map<String, dynamic> body;
}

/// Controller-level fake, following the pattern in `chatbot_provider_test.dart`.
class _FakeChatbotApi extends ChatbotApi {
  _FakeChatbotApi() : super(Dio());

  final List<Future<ChatMessageResponse>> sendResults = [];
  final List<ChatMessageRequest> sendRequests = [];

  void failWith(DioExceptionType type) {
    sendResults.add(
      Future<ChatMessageResponse>.error(
        DioException(requestOptions: RequestOptions(path: '/chat/message'), type: type),
      ),
    );
  }

  void failWithException(ApiException exception) {
    sendResults.add(Future<ChatMessageResponse>.error(exception));
  }

  void failWithRaw(Object error) {
    sendResults.add(Future<ChatMessageResponse>.error(error));
  }

  void succeedNext() {
    sendResults.add(
      Future<ChatMessageResponse>.value(
        const ChatMessageResponse(conversationId: 'c1', reply: 'A reply.'),
      ),
    );
  }

  @override
  Future<ChatMessageResponse> sendMessage(ChatMessageRequest request) {
    sendRequests.add(request);
    return sendResults.removeAt(0);
  }
}

/// Stands in for a plugin/platform throwable whose `toString()` carries data
/// that must never reach the screen.
class _LeakyError {
  @override
  String toString() => r'FileSystemException: C:\patients\patient-record-4821.pdf';
}
