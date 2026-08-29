import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/storage/secure_storage_service.dart';
import '../models/messaging_models.dart';

enum MessagingConnectionStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  unavailable,
}

sealed class MessagingRealtimeEvent {
  const MessagingRealtimeEvent();
}

class RealtimeMessageCreated extends MessagingRealtimeEvent {
  const RealtimeMessageCreated(this.message);
  final CareMessage message;
}

class RealtimeConversationRead extends MessagingRealtimeEvent {
  const RealtimeConversationRead({
    required this.conversationId,
    required this.userId,
    this.lastReadMessageId,
  });

  final String conversationId;
  final String userId;
  final String? lastReadMessageId;
}

abstract class MessagingRealtimeClient {
  Stream<MessagingConnectionStatus> get statuses;
  Stream<MessagingRealtimeEvent> get events;
  MessagingConnectionStatus get status;

  Future<void> connect();
  Future<bool> subscribe(String conversationId);
  void unsubscribe(String conversationId);
  Future<void> retry();
  void disconnect();
  void dispose();
}

class SocketIoMessagingRealtime implements MessagingRealtimeClient {
  SocketIoMessagingRealtime(this._origin, this._storage);

  final String _origin;
  final SecureStorageService _storage;
  final _statusController =
      StreamController<MessagingConnectionStatus>.broadcast();
  final _eventController = StreamController<MessagingRealtimeEvent>.broadcast();

  io.Socket? _socket;
  bool _disposed = false;
  String? _subscribedConversationId;
  MessagingConnectionStatus _status = MessagingConnectionStatus.idle;

  @override
  Stream<MessagingConnectionStatus> get statuses => _statusController.stream;

  @override
  Stream<MessagingRealtimeEvent> get events => _eventController.stream;

  @override
  MessagingConnectionStatus get status => _status;

  void _setStatus(MessagingConnectionStatus next) {
    if (_disposed || _status == next) return;
    _status = next;
    _statusController.add(next);
  }

  @override
  Future<void> connect() async {
    if (_disposed || _socket?.connected == true) return;
    _setStatus(MessagingConnectionStatus.connecting);
    final token = await _storage.getAccessToken();
    if (_disposed) return;
    if (token == null || token.isEmpty || _origin.isEmpty) {
      _setStatus(MessagingConnectionStatus.unavailable);
      return;
    }

    _disposeSocket();
    final socket = io.io(
      _origin,
      io.OptionBuilder()
          // socket_io_client's Dart VM transport is WebSocket-only. REST
          // cursor polling in the provider is the supported degradation path.
          .setTransports(['websocket'])
          .setAuth({'token': token})
          // Managers are cached by host even after dispose. A fresh manager is
          // required so an account change can never reuse the previous token.
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(8)
          .setReconnectionDelay(800)
          .setReconnectionDelayMax(8000)
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _setStatus(MessagingConnectionStatus.connected);
    });
    socket.onDisconnect((_) {
      if (!_disposed) _setStatus(MessagingConnectionStatus.reconnecting);
    });
    socket.onConnectError((_) {
      if (!_disposed) _setStatus(MessagingConnectionStatus.reconnecting);
    });
    socket.onError((_) {
      if (!_disposed && _status != MessagingConnectionStatus.connected) {
        _setStatus(MessagingConnectionStatus.reconnecting);
      }
    });
    socket.io.on('reconnect_attempt', (_) {
      _setStatus(MessagingConnectionStatus.reconnecting);
    });
    socket.io.on('reconnect_failed', (_) {
      _setStatus(MessagingConnectionStatus.unavailable);
    });
    socket.on('message.created', _handleMessageCreated);
    socket.on('conversation.read', _handleConversationRead);
    socket.connect();
  }

  void _handleMessageCreated(Object? payload) {
    if (_disposed || payload is! Map) return;
    try {
      final message = CareMessage.fromJson(Map<String, dynamic>.from(payload));
      _eventController.add(RealtimeMessageCreated(message));
    } on FormatException {
      // A malformed realtime frame is ignored; REST synchronization remains
      // authoritative and will either recover the message or expose an error.
    }
  }

  void _handleConversationRead(Object? payload) {
    if (_disposed || payload is! Map) return;
    final data = Map<String, dynamic>.from(payload);
    final conversationId = data['conversation_id'];
    final userId = data['user_id'];
    if (conversationId is! String ||
        conversationId.isEmpty ||
        userId is! String ||
        userId.isEmpty) {
      return;
    }
    _eventController.add(
      RealtimeConversationRead(
        conversationId: conversationId,
        userId: userId,
        lastReadMessageId: data['last_read_message_id'] is String
            ? data['last_read_message_id'] as String
            : null,
      ),
    );
  }

  @override
  Future<bool> subscribe(String conversationId) async {
    _subscribedConversationId = conversationId;
    final socket = _socket;
    if (_disposed || socket == null || !socket.connected) return false;
    final completer = Completer<bool>();
    socket.emitWithAck(
      'conversation.subscribe',
      {'conversation_id': conversationId},
      ack: (dynamic response) {
        if (!completer.isCompleted) {
          completer.complete(response is Map && response['ok'] == true);
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
  }

  @override
  void unsubscribe(String conversationId) {
    if (_subscribedConversationId == conversationId) {
      _subscribedConversationId = null;
    }
    final socket = _socket;
    if (socket?.connected == true) {
      socket!.emit('conversation.unsubscribe', {
        'conversation_id': conversationId,
      });
    }
  }

  @override
  Future<void> retry() async {
    if (_disposed) return;
    _disposeSocket();
    await connect();
  }

  @override
  void disconnect() {
    final conversationId = _subscribedConversationId;
    if (conversationId != null) unsubscribe(conversationId);
    _disposeSocket();
    _setStatus(MessagingConnectionStatus.idle);
  }

  void _disposeSocket() {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    socket.off('message.created');
    socket.off('conversation.read');
    socket.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    _statusController.close();
    _eventController.close();
  }
}
