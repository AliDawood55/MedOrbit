import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/chatbot_api.dart';
import '../models/chatbot_models.dart';
import 'chatbot_provider.dart';

class ConversationsError {
  const ConversationsError({required this.message, required this.code, this.statusCode, this.retryable = true});

  final String message;
  final String code;
  final int? statusCode;
  final bool retryable;
}

class ConversationsState {
  const ConversationsState({
    this.conversations = const [],
    this.pagination,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSearching = false,
    this.searchQuery = '',
    this.error,
    this.selectedConversationId,
    this.placesByConversationId = const {},
  });

  final List<ConversationSummary> conversations;
  final ChatPagination? pagination;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSearching;
  final String searchQuery;
  final ConversationsError? error;
  final String? selectedConversationId;
  final Map<String, List<ChatConversationPlace>> placesByConversationId;

  bool get isEmpty => !isLoading && !isSearching && conversations.isEmpty;
  bool get canLoadMore {
    final value = pagination;
    if (value == null) return false;
    if (value.hasNext != null) return value.hasNext!;
    if (value.page != null && value.totalPages != null) return value.page! < value.totalPages!;
    return false;
  }

  ConversationsState copyWith({
    List<ConversationSummary>? conversations,
    ChatPagination? pagination,
    bool clearPagination = false,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSearching,
    String? searchQuery,
    ConversationsError? error,
    bool clearError = false,
    String? selectedConversationId,
    bool clearSelectedConversationId = false,
    Map<String, List<ChatConversationPlace>>? placesByConversationId,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      pagination: clearPagination ? null : (pagination ?? this.pagination),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      error: clearError ? null : (error ?? this.error),
      selectedConversationId: clearSelectedConversationId
          ? null
          : (selectedConversationId ?? this.selectedConversationId),
      placesByConversationId: placesByConversationId ?? this.placesByConversationId,
    );
  }
}

class ConversationsController extends StateNotifier<ConversationsState> {
  ConversationsController(this._api) : super(const ConversationsState());

  final ChatbotApi _api;

  int _searchRequestId = 0;
  int _listRequestId = 0;
  bool _disposed = false;

  Future<bool> loadConversations({int page = 1, int limit = 50}) async {
    if (state.isLoading || state.isSearching || state.isLoadingMore) return false;
    final requestId = ++_listRequestId;
    _set(
      state.copyWith(
        isLoading: true,
        searchQuery: '',
        clearError: true,
      ),
    );
    try {
      final result = await _api.listConversations(page: page, limit: limit);
      if (requestId != _listRequestId) return false;
      _set(
        state.copyWith(
          conversations: result.conversations,
          pagination: result.pagination,
          isLoading: false,
          clearError: true,
        ),
      );
      return true;
    } catch (error) {
      if (requestId != _listRequestId) return false;
      _set(state.copyWith(isLoading: false, error: _safeError(error)));
      return false;
    }
  }

  Future<bool> loadMore({int limit = 50}) async {
    if (state.isLoading || state.isLoadingMore || state.isSearching || !state.canLoadMore) return false;
    final nextPage = (state.pagination?.page ?? 1) + 1;
    _set(state.copyWith(isLoadingMore: true, clearError: true));
    try {
      final result = await _api.listConversations(
        page: nextPage,
        limit: state.pagination?.limit ?? limit,
        search: state.searchQuery.isEmpty ? null : state.searchQuery,
      );
      _set(
        state.copyWith(
          conversations: [...state.conversations, ...result.conversations],
          pagination: result.pagination,
          isLoadingMore: false,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isLoadingMore: false, error: _safeError(error)));
      return false;
    }
  }

  Future<bool> searchConversations(String query) async {
    final trimmed = query.trim();
    if (state.isSearching && trimmed == state.searchQuery) return false;
    final requestId = ++_searchRequestId;
    _set(state.copyWith(searchQuery: trimmed, clearError: true));
    if (trimmed.length < 2) {
      _set(state.copyWith(isSearching: false));
      return false;
    }

    _set(state.copyWith(isSearching: true));
    try {
      final conversations = await _api.searchConversations(trimmed);
      if (requestId != _searchRequestId) return false;
      _set(
        state.copyWith(
          conversations: conversations,
          isSearching: false,
          clearPagination: true,
        ),
      );
      return true;
    } catch (error) {
      if (requestId != _searchRequestId) return false;
      _set(state.copyWith(isSearching: false, error: _safeError(error)));
      return false;
    }
  }

  Future<ConversationSummary?> createConversation({String? language}) async {
    try {
      final conversation = await _api.createConversation(language: language);
      _set(
        state.copyWith(
          conversations: [conversation, ...state.conversations],
          selectedConversationId: conversation.id,
          clearError: true,
        ),
      );
      return conversation;
    } catch (error) {
      _set(state.copyWith(error: _safeError(error)));
      return null;
    }
  }

  Future<bool> renameConversation(String id, {required String title}) async {
    final before = state.conversations;
    final optimistic = before.map((conversation) {
      return conversation.id == id ? _copyConversation(conversation, title: title) : conversation;
    }).toList();
    _set(state.copyWith(conversations: optimistic, clearError: true));
    try {
      final updated = await _api.renameConversation(id, title: title);
      _set(
        state.copyWith(
          conversations: [
            for (final conversation in state.conversations)
              if (conversation.id == id) _mergeConversation(conversation, updated) else conversation,
          ],
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(conversations: before, error: _safeError(error)));
      return false;
    }
  }

  Future<bool> deleteConversation(String id) async {
    try {
      await _api.deleteConversation(id);
      final places = Map<String, List<ChatConversationPlace>>.from(state.placesByConversationId)..remove(id);
      _set(
        state.copyWith(
          conversations: state.conversations.where((conversation) => conversation.id != id).toList(),
          selectedConversationId: state.selectedConversationId == id ? null : state.selectedConversationId,
          clearSelectedConversationId: state.selectedConversationId == id,
          placesByConversationId: places,
          clearError: true,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(error: _safeError(error)));
      return false;
    }
  }

  Future<bool> generateConversationTitle(String id) async {
    try {
      final updated = await _api.generateConversationTitle(id);
      _set(
        state.copyWith(
          conversations: [
            for (final conversation in state.conversations)
              if (conversation.id == id) _mergeConversation(conversation, updated) else conversation,
          ],
          clearError: true,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(error: _safeError(error)));
      return false;
    }
  }

  Future<List<ChatConversationPlace>> loadConversationPlaces(String id) async {
    try {
      final places = await _api.listConversationPlaces(id);
      _set(
        state.copyWith(
          placesByConversationId: {
            ...state.placesByConversationId,
            id: places,
          },
          clearError: true,
        ),
      );
      return places;
    } catch (error) {
      _set(state.copyWith(error: _safeError(error)));
      return const [];
    }
  }

  Future<ChatConversationPlace?> saveConversationPlace(
    String id, {
    required String placeName,
    required String placeType,
    required double latitude,
    required double longitude,
    String? address,
    String? phone,
    double? distanceKm,
    double? rating,
  }) async {
    try {
      final place = await _api.saveConversationPlace(
        id,
        placeName: placeName,
        placeType: placeType,
        latitude: latitude,
        longitude: longitude,
        address: address,
        phone: phone,
        distanceKm: distanceKm,
        rating: rating,
      );
      final current = state.placesByConversationId[id] ?? const <ChatConversationPlace>[];
      _set(
        state.copyWith(
          placesByConversationId: {
            ...state.placesByConversationId,
            id: [...current, place],
          },
          clearError: true,
        ),
      );
      return place;
    } catch (error) {
      _set(state.copyWith(error: _safeError(error)));
      return null;
    }
  }

  void selectConversation(String? id) {
    _set(state.copyWith(selectedConversationId: id, clearSelectedConversationId: id == null));
  }

  void clearError() => _set(state.copyWith(clearError: true));

  ConversationSummary _copyConversation(ConversationSummary source, {String? title}) {
    return ConversationSummary(
      id: source.id,
      title: title ?? source.title,
      isAutoGenerated: source.isAutoGenerated,
      messageCount: source.messageCount,
      lastIntent: source.lastIntent,
      hasLocation: source.hasLocation,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      extra: source.extra,
    );
  }

  ConversationSummary _mergeConversation(ConversationSummary current, ConversationSummary update) {
    return ConversationSummary(
      id: update.id.isEmpty ? current.id : update.id,
      title: update.title ?? current.title,
      isAutoGenerated: update.isAutoGenerated ?? current.isAutoGenerated,
      messageCount: update.messageCount ?? current.messageCount,
      lastIntent: update.lastIntent ?? current.lastIntent,
      hasLocation: update.hasLocation ?? current.hasLocation,
      createdAt: update.createdAt ?? current.createdAt,
      updatedAt: update.updatedAt ?? current.updatedAt,
      extra: {...current.extra, ...update.extra},
    );
  }

  ConversationsError _safeError(Object error) {
    final api = ApiException.from(error);
    return ConversationsError(
      message: api.message,
      code: api.code,
      statusCode: api.statusCode,
      retryable: true,
    );
  }

  void _set(ConversationsState next) {
    if (!_disposed) state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final conversationsControllerProvider = StateNotifierProvider<ConversationsController, ConversationsState>(
  (ref) => ConversationsController(ref.watch(chatbotApiProvider)),
);
