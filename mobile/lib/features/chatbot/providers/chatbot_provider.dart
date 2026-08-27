import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../data/chatbot_api.dart';
import '../models/chatbot_models.dart';

final chatbotApiProvider = Provider<ChatbotApi>((ref) => ChatbotApi(ref.watch(dioProvider)));

/// Why a chat turn failed, at the granularity the patient needs.
///
/// The distinction matters clinically: a receive timeout means the question may
/// still be being answered, whereas [unavailable] means it never arrived. The
/// UI must not describe the second as "took longer than expected".
enum ChatFailureKind {
  /// Could not open a connection to the backend at all.
  connectTimeout,

  /// Connected, but no answer within the AI-safe budget.
  receiveTimeout,

  /// No route to the backend — offline, wrong host, or service down.
  unavailable,

  /// Answered, but the envelope was empty or the wrong shape.
  invalidResponse,

  /// The backend answered with an error (HTTP status or `success: false`).
  backend,

  /// The free-tier message quota for this window is used up
  /// (`FREE_QUOTA_EXHAUSTED`). Not a network fault — retrying immediately
  /// cannot succeed, since the backend enforces the same window server-side.
  freeQuotaExhausted,

  /// A prior identical message is still being processed
  /// (`DUPLICATE_IN_FLIGHT`). Genuinely temporary: the in-flight request will
  /// settle shortly, so a later retry can succeed.
  duplicateInFlight,

  /// Entitlement could not be determined right now (`ENTITLEMENT_UNAVAILABLE`).
  /// Distinct from [freeQuotaExhausted]: this is the billing subsystem being
  /// unavailable, not the user having used up their quota.
  entitlementUnavailable,

  /// This feature requires an active Pro subscription (`SUBSCRIPTION_REQUIRED`).
  /// Not currently returned by the chatbot route, but handled defensively
  /// since it is part of the shared billing error vocabulary.
  subscriptionRequired,

  /// The caller's subscription exists but is not active
  /// (`SUBSCRIPTION_INACTIVE`). Same defensive handling as
  /// [subscriptionRequired].
  subscriptionInactive,

  /// Anything not otherwise classified.
  unknown,
}

class ChatbotError {
  const ChatbotError({
    required this.message,
    required this.code,
    required this.kind,
    this.statusCode,
  });

  final String message;
  final String code;
  final ChatFailureKind kind;
  final int? statusCode;

  /// Whether another attempt could reasonably succeed.
  ///
  /// False for the entitlement failures the backend enforces server-side
  /// (quota window, subscription state) — an immediate retry hits the exact
  /// same denial and just spends another round trip. True for everything
  /// else, including [ChatFailureKind.duplicateInFlight] and
  /// [ChatFailureKind.entitlementUnavailable], which are genuinely transient.
  /// Retries are always user-initiated regardless — a medical question is
  /// never resent automatically.
  bool get retryable => switch (kind) {
    ChatFailureKind.freeQuotaExhausted ||
    ChatFailureKind.subscriptionRequired ||
    ChatFailureKind.subscriptionInactive => false,
    _ => true,
  };

  /// True only for a genuine timeout, so "took longer than expected" copy
  /// cannot leak onto an unreachable-service failure.
  bool get isTimeout =>
      kind == ChatFailureKind.connectTimeout || kind == ChatFailureKind.receiveTimeout;
}

class ChatbotState {
  const ChatbotState({
    this.currentConversationId,
    this.messages = const [],
    this.suggestions = const [],
    this.places = const [],
    this.clinics = const [],
    this.doctors = const [],
    this.route,
    this.isSending = false,
    this.isInitialLoading = false,
    this.isLocationAttachedToNextRequest = false,
    this.error,
    this.lastIntent,
    this.lastConfidence,
  });

  final String? currentConversationId;
  final List<ChatMessage> messages;
  final List<ChatSuggestion> suggestions;
  final List<ChatPlaceResult> places;
  final List<ChatPlaceResult> clinics;
  final List<ChatDoctorResult> doctors;
  final ChatRouteResult? route;
  final bool isSending;
  final bool isInitialLoading;
  final bool isLocationAttachedToNextRequest;
  final ChatbotError? error;
  final String? lastIntent;
  final double? lastConfidence;

  bool get hasMessages => messages.isNotEmpty;

  ChatbotState copyWith({
    String? currentConversationId,
    bool clearCurrentConversationId = false,
    List<ChatMessage>? messages,
    List<ChatSuggestion>? suggestions,
    List<ChatPlaceResult>? places,
    List<ChatPlaceResult>? clinics,
    List<ChatDoctorResult>? doctors,
    ChatRouteResult? route,
    bool clearRoute = false,
    bool? isSending,
    bool? isInitialLoading,
    bool? isLocationAttachedToNextRequest,
    ChatbotError? error,
    bool clearError = false,
    String? lastIntent,
    bool clearLastIntent = false,
    double? lastConfidence,
    bool clearLastConfidence = false,
  }) {
    return ChatbotState(
      currentConversationId: clearCurrentConversationId
          ? null
          : (currentConversationId ?? this.currentConversationId),
      messages: messages ?? this.messages,
      suggestions: suggestions ?? this.suggestions,
      places: places ?? this.places,
      clinics: clinics ?? this.clinics,
      doctors: doctors ?? this.doctors,
      route: clearRoute ? null : (route ?? this.route),
      isSending: isSending ?? this.isSending,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLocationAttachedToNextRequest: isLocationAttachedToNextRequest ?? this.isLocationAttachedToNextRequest,
      error: clearError ? null : (error ?? this.error),
      lastIntent: clearLastIntent ? null : (lastIntent ?? this.lastIntent),
      lastConfidence: clearLastConfidence ? null : (lastConfidence ?? this.lastConfidence),
    );
  }
}

class ChatbotController extends StateNotifier<ChatbotState> {
  ChatbotController(this._api) : super(const ChatbotState());

  final ChatbotApi _api;

  String? _lastRetryMessage;
  String? _lastRetryConversationId;
  int _localId = 0;
  bool _disposed = false;

  Future<bool> sendMessage(
    String message, {
    String? conversationId,
    double? latitude,
    double? longitude,
  }) {
    return _sendMessage(
      message,
      conversationId: conversationId,
      latitude: latitude,
      longitude: longitude,
      insertUserMessage: true,
    );
  }

  Future<bool> retryLastMessage() async {
    final message = _lastRetryMessage;
    if (message == null || state.isSending) return false;
    return _sendMessage(
      message,
      conversationId: _lastRetryConversationId ?? state.currentConversationId,
      insertUserMessage: false,
    );
  }

  Future<bool> _sendMessage(
    String message, {
    String? conversationId,
    double? latitude,
    double? longitude,
    required bool insertUserMessage,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || state.isSending) return false;

    final targetConversationId = conversationId ?? state.currentConversationId;
    _lastRetryMessage = trimmed;
    _lastRetryConversationId = targetConversationId;

    final nextMessages = insertUserMessage ? [...state.messages, _localMessage(trimmed, 'user')] : state.messages;
    _set(
      state.copyWith(
        messages: nextMessages,
        isSending: true,
        isLocationAttachedToNextRequest: latitude != null && longitude != null,
        clearError: true,
      ),
    );

    try {
      final response = await _api.sendMessage(
        ChatMessageRequest(
          message: trimmed,
          conversationId: targetConversationId,
          latitude: latitude,
          longitude: longitude,
        ),
      );
      _lastRetryMessage = null;
      _lastRetryConversationId = null;
      _set(
        state.copyWith(
          currentConversationId: response.conversationId.isEmpty ? targetConversationId : response.conversationId,
          messages: [...state.messages, _botMessage(response)],
          suggestions: response.suggestions,
          places: response.places,
          clinics: response.clinics,
          doctors: response.doctors,
          route: response.route,
          clearRoute: response.route == null,
          isSending: false,
          isLocationAttachedToNextRequest: false,
          lastIntent: response.intent,
          clearLastIntent: response.intent == null,
          lastConfidence: response.confidence,
          clearLastConfidence: response.confidence == null,
        ),
      );
      return true;
    } catch (error) {
      _set(
        state.copyWith(
          isSending: false,
          isLocationAttachedToNextRequest: false,
          error: _safeError(error),
        ),
      );
      return false;
    }
  }

  Future<bool> loadConversation(String id, {int limit = 50, int offset = 0}) async {
    if (state.isInitialLoading) return false;
    _set(state.copyWith(isInitialLoading: true, clearError: true));
    try {
      final detail = await _api.getConversation(id, limit: limit, offset: offset);
      _lastRetryMessage = null;
      _lastRetryConversationId = null;
      _set(
        state.copyWith(
          currentConversationId: detail.conversation?.id ?? id,
          messages: detail.messages,
          places: detail.places,
          clinics: const [],
          doctors: const [],
          suggestions: const [],
          clearRoute: true,
          isInitialLoading: false,
          clearLastIntent: true,
          clearLastConfidence: true,
        ),
      );
      return true;
    } catch (error) {
      _set(state.copyWith(isInitialLoading: false, error: _safeError(error)));
      return false;
    }
  }

  void startNewConversation() {
    _lastRetryMessage = null;
    _lastRetryConversationId = null;
    _set(const ChatbotState());
  }

  void clearError() => _set(state.copyWith(clearError: true));

  ChatMessage _localMessage(String text, String type) {
    _localId += 1;
    return ChatMessage(
      id: 'local-$_localId',
      messageText: text,
      messageType: type,
      createdAt: DateTime.now(),
    );
  }

  ChatMessage _botMessage(ChatMessageResponse response) {
    _localId += 1;
    return ChatMessage(
      id: 'local-$_localId',
      conversationId: response.conversationId,
      messageText: response.reply,
      messageType: 'assistant',
      confidenceScore: response.confidence,
      metadata: ChatMetadata({
        if (response.intent != null) 'intent': response.intent,
        if (response.confidence != null) 'confidence': response.confidence,
        ...response.extra,
      }),
      createdAt: DateTime.now(),
    );
  }

  ChatbotError _safeError(Object error) {
    final api = ApiException.from(error);
    return ChatbotError(
      message: api.message,
      code: api.code,
      statusCode: api.statusCode,
      kind: _kindOf(api),
    );
  }

  static ChatFailureKind _kindOf(ApiException api) {
    return switch (api.code) {
      // Billing/entitlement codes checked first: they carry an HTTP status
      // (429/403/409) that would otherwise fall into the generic `backend`
      // bucket below and lose their semantic meaning.
      ApiException.codeFreeQuotaExhausted => ChatFailureKind.freeQuotaExhausted,
      ApiException.codeDuplicateInFlight => ChatFailureKind.duplicateInFlight,
      ApiException.codeEntitlementUnavailable => ChatFailureKind.entitlementUnavailable,
      ApiException.codeSubscriptionRequired => ChatFailureKind.subscriptionRequired,
      ApiException.codeSubscriptionInactive => ChatFailureKind.subscriptionInactive,
      ApiException.codeConnectTimeout => ChatFailureKind.connectTimeout,
      ApiException.codeReceiveTimeout || ApiException.codeSendTimeout => ChatFailureKind.receiveTimeout,
      ApiException.codeServiceUnavailable => ChatFailureKind.unavailable,
      // Raised by `ChatbotApi._envelopeData` when the body is missing or the
      // wrong shape — the request succeeded, so this is not a network fault.
      'EMPTY_RESPONSE' || 'INVALID_RESPONSE' => ChatFailureKind.invalidResponse,
      'BACKEND_FAILURE' || ApiException.codeHttpError => ChatFailureKind.backend,
      // Anything else with an HTTP status came from the server; a
      // server-supplied error code lands here too.
      _ => api.statusCode != null ? ChatFailureKind.backend : ChatFailureKind.unknown,
    };
  }

  void _set(ChatbotState next) {
    if (!_disposed) state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final chatbotControllerProvider = StateNotifierProvider<ChatbotController, ChatbotState>(
  (ref) => ChatbotController(ref.watch(chatbotApiProvider)),
);
