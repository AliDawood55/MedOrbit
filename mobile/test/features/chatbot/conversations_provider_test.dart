import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/chatbot/data/chatbot_api.dart';
import 'package:mobile/features/chatbot/models/chatbot_models.dart';
import 'package:mobile/features/chatbot/providers/chatbot_provider.dart';
import 'package:mobile/features/chatbot/providers/conversations_provider.dart';

void main() {
  test('initial list and pagination then load more', () async {
    final fake = _FakeChatbotApi()
      ..listResults.add(
        Future.value(
          (
            conversations: [const ConversationSummary(id: 'conversation-1', title: 'First')],
            pagination: const ChatPagination(page: 1, limit: 1, total: 2, totalPages: 2, hasNext: true),
          ),
        ),
      )
      ..listResults.add(
        Future.value(
          (
            conversations: [const ConversationSummary(id: 'conversation-2', title: 'Second')],
            pagination: const ChatPagination(page: 2, limit: 1, total: 2, totalPages: 2, hasNext: false),
          ),
        ),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(conversationsControllerProvider.notifier).loadConversations(limit: 1);
    await container.read(conversationsControllerProvider.notifier).loadMore();

    final state = container.read(conversationsControllerProvider);
    expect(state.conversations.map((conversation) => conversation.id), ['conversation-1', 'conversation-2']);
    expect(state.pagination?.page, 2);
    expect(fake.listCalls.last.page, 2);
  });

  test('search requires two characters and ignores stale results', () async {
    final first = Completer<List<ConversationSummary>>();
    final second = Completer<List<ConversationSummary>>();
    final fake = _FakeChatbotApi()
      ..searchResults.add(first.future)
      ..searchResults.add(second.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    final tooShort = await container.read(conversationsControllerProvider.notifier).searchConversations('a');
    final firstSearch = container.read(conversationsControllerProvider.notifier).searchConversations('he');
    final secondSearch = container.read(conversationsControllerProvider.notifier).searchConversations('heart');

    expect(tooShort, isFalse);
    expect(fake.searchCalls, ['he', 'heart']);

    second.complete([const ConversationSummary(id: 'newer', title: 'Heart')]);
    expect(await secondSearch, isTrue);

    first.complete([const ConversationSummary(id: 'stale', title: 'Headache')]);
    expect(await firstSearch, isFalse);
    expect(container.read(conversationsControllerProvider).conversations.single.id, 'newer');
  });

  test('optimistic rename rolls back on failure', () async {
    final rename = Completer<ConversationSummary>();
    final fake = _FakeChatbotApi()
      ..listResults.add(
        Future.value(
          (
            conversations: [const ConversationSummary(id: 'conversation-1', title: 'Original')],
            pagination: null,
          ),
        ),
      )
      ..renameResults.add(rename.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(conversationsControllerProvider.notifier).loadConversations();

    final pending = container
        .read(conversationsControllerProvider.notifier)
        .renameConversation('conversation-1', title: 'Optimistic');

    expect(container.read(conversationsControllerProvider).conversations.single.title, 'Optimistic');

    rename.completeError(const ApiException(message: 'Rename failed', code: 'RENAME_FAILED'));
    expect(await pending, isFalse);
    expect(container.read(conversationsControllerProvider).conversations.single.title, 'Original');
    expect(container.read(conversationsControllerProvider).error?.code, 'RENAME_FAILED');
  });

  test('delete removes only after success and keeps state on failure', () async {
    final deleteFailure = Completer<void>();
    final fake = _FakeChatbotApi()
      ..listResults.add(
        Future.value(
          (
            conversations: [
              const ConversationSummary(id: 'conversation-1'),
              const ConversationSummary(id: 'conversation-2'),
            ],
            pagination: null,
          ),
        ),
      )
      ..deleteResults.add(Future<void>.value())
      ..deleteResults.add(deleteFailure.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(conversationsControllerProvider.notifier).loadConversations();

    expect(await container.read(conversationsControllerProvider.notifier).deleteConversation('conversation-1'), isTrue);
    expect(container.read(conversationsControllerProvider).conversations.map((item) => item.id), ['conversation-2']);

    final failedDelete = container.read(conversationsControllerProvider.notifier).deleteConversation('conversation-2');
    deleteFailure.completeError(const ApiException(message: 'Delete failed', code: 'DELETE_FAILED'));
    expect(await failedDelete, isFalse);
    expect(container.read(conversationsControllerProvider).conversations.map((item) => item.id), ['conversation-2']);
    expect(container.read(conversationsControllerProvider).error?.code, 'DELETE_FAILED');
  });

  test('create title and place methods update state', () async {
    final fake = _FakeChatbotApi()
      ..createResults.add(Future.value(const ConversationSummary(id: 'conversation-1', title: 'Created')))
      ..titleResults.add(Future.value(const ConversationSummary(id: 'conversation-1', title: 'Generated')))
      ..placeListResults.add(
        Future.value(const [ChatConversationPlace(id: 'place-1', nameEn: 'Saved Clinic')]),
      )
      ..savePlaceResults.add(
        Future.value(const ChatConversationPlace(id: 'place-2', nameEn: 'Saved Pharmacy')),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    final created = await container.read(conversationsControllerProvider.notifier).createConversation(language: 'en');
    final titled = await container.read(conversationsControllerProvider.notifier).generateConversationTitle('conversation-1');
    final places = await container.read(conversationsControllerProvider.notifier).loadConversationPlaces('conversation-1');
    final saved = await container.read(conversationsControllerProvider.notifier).saveConversationPlace(
      'conversation-1',
      placeName: 'Saved Pharmacy',
      placeType: 'pharmacy',
      latitude: 32.2,
      longitude: 35.2,
    );

    final state = container.read(conversationsControllerProvider);
    expect(created?.id, 'conversation-1');
    expect(titled, isTrue);
    expect(state.conversations.single.title, 'Generated');
    expect(places.single.id, 'place-1');
    expect(saved?.id, 'place-2');
    expect(state.placesByConversationId['conversation-1']?.map((place) => place.id), ['place-1', 'place-2']);
    expect(fake.createLanguageCalls.single, 'en');
    expect(fake.savePlaceCalls.single.placeName, 'Saved Pharmacy');
  });
}

ProviderContainer _container(_FakeChatbotApi fake) {
  return ProviderContainer(
    overrides: [
      chatbotApiProvider.overrideWithValue(fake),
    ],
  );
}

class _FakeChatbotApi extends ChatbotApi {
  _FakeChatbotApi() : super(Dio());

  final listResults = <Future<({List<ConversationSummary> conversations, ChatPagination? pagination})>>[];
  final searchResults = <Future<List<ConversationSummary>>>[];
  final renameResults = <Future<ConversationSummary>>[];
  final deleteResults = <Future<void>>[];
  final createResults = <Future<ConversationSummary>>[];
  final titleResults = <Future<ConversationSummary>>[];
  final placeListResults = <Future<List<ChatConversationPlace>>>[];
  final savePlaceResults = <Future<ChatConversationPlace>>[];
  final listCalls = <({int page, int limit, String? search})>[];
  final searchCalls = <String>[];
  final createLanguageCalls = <String?>[];
  final savePlaceCalls = <({String placeName, String placeType, double latitude, double longitude})>[];

  @override
  Future<({List<ConversationSummary> conversations, ChatPagination? pagination})> listConversations({
    int page = 1,
    int limit = 50,
    String? search,
  }) {
    listCalls.add((page: page, limit: limit, search: search));
    return listResults.removeAt(0);
  }

  @override
  Future<List<ConversationSummary>> searchConversations(String query) {
    searchCalls.add(query);
    return searchResults.removeAt(0);
  }

  @override
  Future<ConversationSummary> createConversation({String? language}) {
    createLanguageCalls.add(language);
    return createResults.removeAt(0);
  }

  @override
  Future<ConversationSummary> renameConversation(String id, {required String title}) {
    return renameResults.removeAt(0);
  }

  @override
  Future<void> deleteConversation(String id) {
    return deleteResults.removeAt(0);
  }

  @override
  Future<ConversationSummary> generateConversationTitle(String id) {
    return titleResults.removeAt(0);
  }

  @override
  Future<List<ChatConversationPlace>> listConversationPlaces(String id) {
    return placeListResults.removeAt(0);
  }

  @override
  Future<ChatConversationPlace> saveConversationPlace(
    String id, {
    required String placeName,
    required String placeType,
    required double latitude,
    required double longitude,
    String? address,
    String? phone,
    double? distanceKm,
    double? rating,
  }) {
    savePlaceCalls.add((placeName: placeName, placeType: placeType, latitude: latitude, longitude: longitude));
    return savePlaceResults.removeAt(0);
  }
}
