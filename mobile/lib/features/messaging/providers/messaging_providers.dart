import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/messaging_api.dart';
import '../data/messaging_realtime.dart';
import '../models/messaging_models.dart';

final messagingApiProvider = Provider<MessagingApi>(
  (ref) => MessagingApi(ref.watch(dioProvider)),
);

final messagingIdFactoryProvider = Provider<String Function()>(
  (_) => _secureUuidV4,
);

final messagingClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final messagingRealtimeFactoryProvider =
    Provider<MessagingRealtimeClient Function()>((ref) {
      // Rebuild the factory on identity changes even though authorization is
      // supplied by the secure token. This prevents an old account's socket
      // from surviving an in-process account replacement.
      ref.watch(authControllerProvider.select((state) => state.user?.id));
      final origin = ref.watch(activeOriginProvider);
      final storage = ref.watch(secureStorageProvider);
      return () => SocketIoMessagingRealtime(origin, storage);
    });

class MessagingInboxState {
  const MessagingInboxState({
    this.items = const [],
    this.isLoading = true,
    this.isRefreshing = false,
    this.errorCode,
  });

  final List<CareConversation> items;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorCode;

  int get unreadCount => items.fold(0, (sum, item) => sum + item.unreadCount);

  MessagingInboxState copyWith({
    List<CareConversation>? items,
    bool? isLoading,
    bool? isRefreshing,
    String? errorCode,
    bool clearError = false,
  }) {
    return MessagingInboxState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

class MessagingInboxController extends StateNotifier<MessagingInboxState> {
  MessagingInboxController(this._api) : super(const MessagingInboxState()) {
    load();
    _schedulePoll();
  }

  final MessagingApi _api;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _active = true;
  int _generation = 0;
  bool _requestInFlight = false;

  Future<void> load({bool refresh = false}) async {
    if (_requestInFlight && refresh) return;
    final generation = ++_generation;
    _requestInFlight = true;
    state = state.copyWith(
      isLoading: !refresh && state.items.isEmpty,
      isRefreshing: refresh,
      clearError: true,
    );
    try {
      final page = await _api.listConversations();
      if (_disposed || generation != _generation) return;
      state = MessagingInboxState(items: page.items, isLoading: false);
    } catch (error) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorCode: ApiException.from(error).code,
      );
    } finally {
      if (!_disposed && generation == _generation) _requestInFlight = false;
    }
  }

  Future<void> refresh() => load(refresh: true);

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (active) {
      refresh();
      _schedulePoll();
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!_active || _disposed) return;
    _pollTimer = Timer(const Duration(seconds: 20), () async {
      await refresh();
      _schedulePoll();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pollTimer?.cancel();
    super.dispose();
  }
}

final messagingInboxProvider =
    StateNotifierProvider.autoDispose<
      MessagingInboxController,
      MessagingInboxState
    >((ref) {
      ref.watch(
        authControllerProvider.select(
          (state) => (state.status, state.user?.id, state.user?.role),
        ),
      );
      return MessagingInboxController(ref.watch(messagingApiProvider));
    });

class PatientMessagingPreferenceState {
  const PatientMessagingPreferenceState({
    required this.isApplicable,
    this.allowDoctorMessages,
    this.isLoading = false,
    this.isSaving = false,
    this.errorCode,
  });

  final bool isApplicable;
  final bool? allowDoctorMessages;
  final bool isLoading;
  final bool isSaving;
  final String? errorCode;

  PatientMessagingPreferenceState copyWith({
    bool? allowDoctorMessages,
    bool? isLoading,
    bool? isSaving,
    String? errorCode,
    bool clearError = false,
  }) {
    return PatientMessagingPreferenceState(
      isApplicable: isApplicable,
      allowDoctorMessages: allowDoctorMessages ?? this.allowDoctorMessages,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

class PatientMessagingPreferenceController
    extends StateNotifier<PatientMessagingPreferenceState> {
  PatientMessagingPreferenceController(this._api, {required bool isPatient})
    : super(
        PatientMessagingPreferenceState(
          isApplicable: isPatient,
          isLoading: isPatient,
        ),
      ) {
    if (isPatient) load();
  }

  final MessagingApi _api;
  bool _disposed = false;
  int _generation = 0;

  Future<void> load() async {
    if (_disposed || !state.isApplicable) return;
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final preference = await _api.getPatientMessagingPreference();
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        allowDoctorMessages: preference.allowDoctorMessages,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorCode: ApiException.from(error).code,
      );
    }
  }

  Future<bool> update(bool allowDoctorMessages) async {
    if (_disposed ||
        !state.isApplicable ||
        state.isLoading ||
        state.isSaving ||
        state.allowDoctorMessages == null) {
      return false;
    }
    final generation = _generation;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final preference = await _api.updatePatientMessagingPreference(
        allowDoctorMessages,
      );
      if (_disposed || generation != _generation) return true;
      state = state.copyWith(
        allowDoctorMessages: preference.allowDoctorMessages,
        isSaving: false,
        clearError: true,
      );
      return true;
    } catch (error) {
      if (_disposed || generation != _generation) return false;
      state = state.copyWith(
        isSaving: false,
        errorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

final patientMessagingPreferenceProvider =
    StateNotifierProvider.autoDispose<
      PatientMessagingPreferenceController,
      PatientMessagingPreferenceState
    >((ref) {
      final auth = ref.watch(authControllerProvider);
      return PatientMessagingPreferenceController(
        ref.watch(messagingApiProvider),
        isPatient:
            auth.status == AuthStatus.authenticated &&
            auth.user?.role.toLowerCase() == 'patient',
      );
    });

class ConversationThreadState {
  const ConversationThreadState({
    this.conversation,
    this.messages = const [],
    this.isLoading = true,
    this.isLoadingOlder = false,
    this.isSending = false,
    this.isResponding = false,
    this.connectionStatus = MessagingConnectionStatus.idle,
    this.nextCursor,
    this.latestCursor,
    this.errorCode,
    this.requestErrorCode,
    this.closed = false,
  });

  final CareConversation? conversation;
  final List<CareMessage> messages;
  final bool isLoading;
  final bool isLoadingOlder;
  final bool isSending;
  final bool isResponding;
  final MessagingConnectionStatus connectionStatus;
  final String? nextCursor;
  final String? latestCursor;
  final String? errorCode;
  final String? requestErrorCode;
  final bool closed;

  bool get canSend => conversation?.isAccepted == true && !closed;

  ConversationThreadState copyWith({
    CareConversation? conversation,
    List<CareMessage>? messages,
    bool? isLoading,
    bool? isLoadingOlder,
    bool? isSending,
    bool? isResponding,
    MessagingConnectionStatus? connectionStatus,
    String? nextCursor,
    String? latestCursor,
    String? errorCode,
    String? requestErrorCode,
    bool? closed,
    bool clearError = false,
    bool clearRequestError = false,
    bool clearNextCursor = false,
    bool clearLatestCursor = false,
  }) {
    return ConversationThreadState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      isSending: isSending ?? this.isSending,
      isResponding: isResponding ?? this.isResponding,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      latestCursor: clearLatestCursor
          ? null
          : (latestCursor ?? this.latestCursor),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      requestErrorCode: clearRequestError
          ? null
          : (requestErrorCode ?? this.requestErrorCode),
      closed: closed ?? this.closed,
    );
  }
}

class ConversationThreadController
    extends StateNotifier<ConversationThreadState> {
  ConversationThreadController(
    this.conversationId,
    this.currentUserId,
    this._api,
    this._realtime,
    this._idFactory,
    this._clock,
    this._onInboxChanged,
  ) : super(const ConversationThreadState()) {
    _statusSubscription = _realtime.statuses.listen(_onConnectionStatus);
    _eventSubscription = _realtime.events.listen(_onRealtimeEvent);
    load();
  }

  final String conversationId;
  final String currentUserId;
  final MessagingApi _api;
  final MessagingRealtimeClient _realtime;
  final String Function() _idFactory;
  final DateTime Function() _clock;
  final void Function() _onInboxChanged;
  late final StreamSubscription<MessagingConnectionStatus> _statusSubscription;
  late final StreamSubscription<MessagingRealtimeEvent> _eventSubscription;

  Timer? _syncTimer;
  bool _disposed = false;
  bool _active = true;
  bool _syncing = false;
  bool _loadingOlder = false;
  bool _subscribed = false;
  bool _subscriptionInFlight = false;
  int _loadGeneration = 0;
  String? _lastMarkedReadId;
  final Set<String> _sendingClientIds = {};

  Future<void> load() async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final conversations = await _api.listConversations();
      final conversation = conversations.items
          .where((item) => item.id == conversationId)
          .firstOrNull;
      if (conversation == null) {
        throw const ApiException(
          message: 'Conversation not found.',
          code: 'NOT_FOUND',
        );
      }
      final page = await _api.listMessages(conversationId);
      if (_disposed || generation != _loadGeneration) return;
      state = ConversationThreadState(
        conversation: conversation,
        messages: _mergeMessages(const [], page.items),
        isLoading: false,
        nextCursor: page.nextCursor,
        latestCursor: page.latestCursor,
      );
      await _markLatestRead();
      if (_disposed || generation != _loadGeneration) return;
      if (conversation.isAccepted && _active) {
        await _realtime.connect();
        if (!_disposed) await _ensureSubscribed();
      }
      _scheduleSync();
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorCode: ApiException.from(error).code,
      );
      _scheduleSync();
    }
  }

  Future<void> loadOlder() async {
    final cursor = state.nextCursor;
    if (_disposed || _loadingOlder || cursor == null) return;
    _loadingOlder = true;
    state = state.copyWith(isLoadingOlder: true, clearError: true);
    try {
      final page = await _api.listMessages(conversationId, cursor: cursor);
      if (_disposed) return;
      state = state.copyWith(
        messages: _mergeMessages(page.items, state.messages),
        isLoadingOlder: false,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
      );
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isLoadingOlder: false,
        errorCode: ApiException.from(error).code,
      );
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> syncMissed() async {
    if (_disposed || _syncing || state.conversation?.isAccepted != true) return;
    _syncing = true;
    try {
      final page = await _api.listMessages(
        conversationId,
        after: state.latestCursor,
      );
      if (_disposed) return;
      if (page.items.isNotEmpty) {
        state = state.copyWith(
          messages: _mergeMessages(state.messages, page.items),
          latestCursor: page.latestCursor,
          clearError: true,
        );
        await _markLatestRead();
        _onInboxChanged();
      }
    } catch (_) {
      // Realtime degradation is intentionally low noise. The next lifecycle
      // resume, poll, or manual refresh retries from the same server cursor.
    } finally {
      _syncing = false;
    }
  }

  Future<bool> send(String rawBody) async {
    final body = rawBody.trim();
    if (_disposed ||
        state.isSending ||
        !state.canSend ||
        body.isEmpty ||
        body.length > 4000) {
      return false;
    }
    final clientMessageId = _idFactory();
    final optimistic = CareMessage.optimistic(
      conversationId: conversationId,
      senderUserId: currentUserId,
      clientMessageId: clientMessageId,
      body: body,
      createdAt: _clock(),
    );
    state = state.copyWith(
      messages: [...state.messages, optimistic],
      isSending: true,
      clearError: true,
    );
    return _performSend(optimistic);
  }

  Future<bool> retry(String clientMessageId) async {
    if (_disposed ||
        state.isSending ||
        _sendingClientIds.contains(clientMessageId)) {
      return false;
    }
    final index = state.messages.indexWhere(
      (message) =>
          message.clientMessageId == clientMessageId &&
          message.deliveryState == MessageDeliveryState.failed,
    );
    if (index == -1 || !state.canSend) return false;
    final pending = state.messages[index].copyWith(
      deliveryState: MessageDeliveryState.sending,
      clearError: true,
    );
    final updated = [...state.messages]..[index] = pending;
    state = state.copyWith(messages: updated, isSending: true);
    return _performSend(pending);
  }

  Future<bool> _performSend(CareMessage optimistic) async {
    final clientId = optimistic.clientMessageId;
    if (!_sendingClientIds.add(clientId)) return false;
    try {
      final authoritative = await _api.sendMessage(
        conversationId: conversationId,
        body: optimistic.body,
        clientMessageId: clientId,
      );
      if (_disposed) return true;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, [authoritative]),
        isSending: false,
      );
      _onInboxChanged();
      return true;
    } catch (error) {
      if (_disposed) return false;
      final alreadyAccepted = state.messages.any(
        (message) =>
            message.clientMessageId == clientId && message.isAuthoritative,
      );
      if (!alreadyAccepted) {
        final failure = ApiException.from(error);
        state = state.copyWith(
          messages: [
            for (final message in state.messages)
              if (message.clientMessageId == clientId &&
                  !message.isAuthoritative)
                message.copyWith(
                  deliveryState: MessageDeliveryState.failed,
                  errorCode: failure.code,
                )
              else
                message,
          ],
          isSending: false,
        );
      } else {
        state = state.copyWith(isSending: false);
      }
      return alreadyAccepted;
    } finally {
      _sendingClientIds.remove(clientId);
    }
  }

  void dismissFailed(String clientMessageId) {
    state = state.copyWith(
      messages: state.messages
          .where(
            (message) =>
                message.clientMessageId != clientMessageId ||
                message.deliveryState != MessageDeliveryState.failed,
          )
          .toList(growable: false),
    );
  }

  Future<bool> acceptRequest() async {
    final conversation = state.conversation;
    if (_disposed ||
        state.isResponding ||
        conversation?.canRespondToRequest != true ||
        !conversation!.isPending) {
      return false;
    }
    state = state.copyWith(isResponding: true, clearRequestError: true);
    try {
      final updated = await _api.acceptRequest(conversationId);
      if (_disposed) return true;
      state = state.copyWith(
        conversation: updated,
        isResponding: false,
        clearRequestError: true,
      );
      _onInboxChanged();
      if (_active) {
        await _realtime.connect();
        if (!_disposed) await _ensureSubscribed();
      }
      _scheduleSync();
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isResponding: false,
        requestErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  Future<bool> declineRequest() async {
    final conversation = state.conversation;
    if (_disposed ||
        state.isResponding ||
        conversation?.canRespondToRequest != true ||
        !conversation!.isPending) {
      return false;
    }
    state = state.copyWith(isResponding: true, clearRequestError: true);
    try {
      await _api.declineRequest(conversationId);
      if (_disposed) return true;
      _realtime.disconnect();
      state = state.copyWith(
        isResponding: false,
        closed: true,
        clearRequestError: true,
      );
      _onInboxChanged();
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isResponding: false,
        requestErrorCode: ApiException.from(error).code,
      );
      return false;
    }
  }

  Future<void> _markLatestRead() async {
    final last = state.messages
        .where((message) => message.id != null)
        .lastOrNull;
    if (last?.id == null || last!.id == _lastMarkedReadId) return;
    try {
      await _api.markRead(conversationId, messageId: last.id);
      if (_disposed) return;
      _lastMarkedReadId = last.id;
      final conversation = state.conversation;
      if (conversation != null && conversation.unreadCount != 0) {
        state = state.copyWith(
          conversation: conversation.copyWith(unreadCount: 0),
        );
        _onInboxChanged();
      }
    } catch (_) {
      // Reading history remains available even if the best-effort read pointer
      // update fails. A future sync retries the newest authoritative message.
    }
  }

  void _onConnectionStatus(MessagingConnectionStatus status) {
    if (_disposed) return;
    state = state.copyWith(connectionStatus: status);
    if (status == MessagingConnectionStatus.connected) {
      _ensureSubscribed();
      syncMissed();
    } else {
      _subscribed = false;
    }
    _scheduleSync();
  }

  void _onRealtimeEvent(MessagingRealtimeEvent event) {
    if (_disposed) return;
    if (event is RealtimeMessageCreated &&
        event.message.conversationId == conversationId) {
      state = state.copyWith(
        messages: _mergeMessages(state.messages, [event.message]),
      );
      _markLatestRead();
      _onInboxChanged();
    }
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _syncTimer?.cancel();
    _syncTimer = null;
    if (!active) {
      _subscribed = false;
      _realtime.disconnect();
      return;
    }
    syncMissed();
    if (state.conversation?.isAccepted == true) {
      _realtime.connect();
    }
    _scheduleSync();
  }

  Future<void> retryRealtime() async {
    _subscribed = false;
    await _realtime.retry();
    if (!_disposed && state.conversation?.isAccepted == true) {
      await _ensureSubscribed();
      await syncMissed();
    }
  }

  Future<void> _ensureSubscribed() async {
    if (_disposed ||
        _subscribed ||
        _subscriptionInFlight ||
        state.conversation?.isAccepted != true) {
      return;
    }
    _subscriptionInFlight = true;
    try {
      final subscribed = await _realtime.subscribe(conversationId);
      _subscribed =
          subscribed && _realtime.status == MessagingConnectionStatus.connected;
    } finally {
      _subscriptionInFlight = false;
    }
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    if (_disposed || !_active || state.conversation?.isAccepted != true) return;
    final delay = state.connectionStatus == MessagingConnectionStatus.connected
        ? const Duration(seconds: 30)
        : const Duration(seconds: 8);
    _syncTimer = Timer(delay, () async {
      await syncMissed();
      _scheduleSync();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _syncTimer?.cancel();
    _statusSubscription.cancel();
    _eventSubscription.cancel();
    _realtime.dispose();
    super.dispose();
  }
}

final conversationThreadProvider = StateNotifierProvider.autoDispose
    .family<ConversationThreadController, ConversationThreadState, String>((
      ref,
      conversationId,
    ) {
      final auth = ref.watch(authControllerProvider);
      final userId = auth.user?.id ?? '';
      final realtime = ref.watch(messagingRealtimeFactoryProvider)();
      return ConversationThreadController(
        conversationId,
        userId,
        ref.watch(messagingApiProvider),
        realtime,
        ref.watch(messagingIdFactoryProvider),
        ref.watch(messagingClockProvider),
        () => ref.invalidate(messagingInboxProvider),
      );
    });

class RecipientSearchState {
  const RecipientSearchState({
    this.query = '',
    this.items = const [],
    this.isSearching = false,
    this.startingIds = const {},
    this.errorCode,
    this.startErrorCode,
  });

  final String query;
  final List<MessagingRecipient> items;
  final bool isSearching;
  final Set<String> startingIds;
  final String? errorCode;
  final String? startErrorCode;

  RecipientSearchState copyWith({
    String? query,
    List<MessagingRecipient>? items,
    bool? isSearching,
    Set<String>? startingIds,
    String? errorCode,
    String? startErrorCode,
    bool clearError = false,
    bool clearStartError = false,
  }) {
    return RecipientSearchState(
      query: query ?? this.query,
      items: items ?? this.items,
      isSearching: isSearching ?? this.isSearching,
      startingIds: startingIds ?? this.startingIds,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      startErrorCode: clearStartError
          ? null
          : (startErrorCode ?? this.startErrorCode),
    );
  }
}

class RecipientSearchController extends StateNotifier<RecipientSearchState> {
  RecipientSearchController(this._api, String role)
    : _role = role.toLowerCase(),
      super(const RecipientSearchState());

  final MessagingApi _api;
  final String _role;
  bool _disposed = false;
  int _generation = 0;
  String? _ownDoctorId;

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length > 80) return;
    final generation = ++_generation;
    state = state.copyWith(query: query, isSearching: true, clearError: true);
    try {
      final doctorsFuture = _api.searchDoctors(query);
      var patients = const <MessagingRecipient>[];
      if (_role == 'doctor') {
        _ownDoctorId ??= await _api.getOwnDoctorId();
        patients = await _api.searchPatients(query);
      }
      final doctors = await doctorsFuture;
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        items: [
          ...patients,
          ...doctors.where((doctor) => doctor.id != _ownDoctorId),
        ],
        isSearching: false,
        clearError: true,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        isSearching: false,
        errorCode: ApiException.from(error).code,
      );
    }
  }

  Future<CareConversation?> startConversation(String counterpartId) async {
    if (_disposed || state.startingIds.contains(counterpartId)) return null;
    state = state.copyWith(
      startingIds: {...state.startingIds, counterpartId},
      clearStartError: true,
    );
    try {
      final conversation = await _api.createConversation(counterpartId);
      if (_disposed) return conversation;
      state = state.copyWith(
        startingIds: {...state.startingIds}..remove(counterpartId),
        clearStartError: true,
      );
      return conversation;
    } catch (error) {
      if (_disposed) return null;
      state = state.copyWith(
        startingIds: {...state.startingIds}..remove(counterpartId),
        startErrorCode: ApiException.from(error).code,
      );
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

final recipientSearchProvider =
    StateNotifierProvider.autoDispose<
      RecipientSearchController,
      RecipientSearchState
    >((ref) {
      final auth = ref.watch(authControllerProvider);
      return RecipientSearchController(
        ref.watch(messagingApiProvider),
        auth.user?.role ?? '',
      );
    });

List<CareMessage> _mergeMessages(
  List<CareMessage> current,
  List<CareMessage> incoming,
) {
  final merged = <CareMessage>[...current];
  for (final message in incoming) {
    final idIndex = message.id == null
        ? -1
        : merged.indexWhere((existing) => existing.id == message.id);
    if (idIndex >= 0) {
      if (message.isAuthoritative || !merged[idIndex].isAuthoritative) {
        merged[idIndex] = message;
      }
      continue;
    }
    final clientIndex = merged.indexWhere(
      (existing) =>
          existing.clientMessageId == message.clientMessageId &&
          existing.senderUserId == message.senderUserId,
    );
    if (clientIndex >= 0) {
      if (message.isAuthoritative || !merged[clientIndex].isAuthoritative) {
        merged[clientIndex] = message;
      }
    } else {
      merged.add(message);
    }
  }
  merged.sort((left, right) {
    final time = left.createdAt.compareTo(right.createdAt);
    if (time != 0) return time;
    return left.stableKey.compareTo(right.stableKey);
  });
  return List<CareMessage>.unmodifiable(merged);
}

String _secureUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final value = bytes.map(hex).join();
  return '${value.substring(0, 8)}-'
      '${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-'
      '${value.substring(16, 20)}-'
      '${value.substring(20)}';
}
