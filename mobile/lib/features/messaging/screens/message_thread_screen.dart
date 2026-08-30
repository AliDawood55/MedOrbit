import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../data/messaging_realtime.dart';
import '../models/messaging_models.dart';
import '../providers/messaging_providers.dart';
import '../widgets/message_bubble.dart';

class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<MessageThreadScreen> createState() =>
      _MessageThreadScreenState();
}

class _MessageThreadScreenState extends ConsumerState<MessageThreadScreen>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showJumpToLatest = false;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(conversationThreadProvider(widget.conversationId).notifier)
        .setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        120;
  }

  void _handleScroll() {
    if (_showJumpToLatest && _nearBottom) {
      setState(() => _showJumpToLatest = false);
    }
  }

  void _scrollToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: AppTheme.motionDuration(context, AppTheme.motionBase),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
      if (_showJumpToLatest) setState(() => _showJumpToLatest = false);
    });
  }

  Future<void> _loadOlder() async {
    if (!_scrollController.hasClients) return;
    final beforeExtent = _scrollController.position.maxScrollExtent;
    final beforeOffset = _scrollController.offset;
    await ref
        .read(conversationThreadProvider(widget.conversationId).notifier)
        .loadOlder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final addedExtent =
          _scrollController.position.maxScrollExtent - beforeExtent;
      _scrollController.jumpTo(
        (beforeOffset + addedExtent).clamp(
          0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    final state = ref.read(conversationThreadProvider(widget.conversationId));
    if (body.isEmpty ||
        body.length > 4000 ||
        !state.canSend ||
        state.isSending) {
      return;
    }
    final future = ref
        .read(conversationThreadProvider(widget.conversationId).notifier)
        .send(body);
    _messageController.clear();
    _scrollToLatest();
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final provider = conversationThreadProvider(widget.conversationId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final conversation = state.conversation;

    ref.listen<ConversationThreadState>(provider, (previous, next) {
      final oldLength = previous?.messages.length ?? 0;
      if (next.messages.length <= oldLength) return;
      final newest = next.messages.last;
      if (!_didInitialScroll ||
          newest.senderUserId == controller.currentUserId ||
          _nearBottom) {
        _didInitialScroll = true;
        _scrollToLatest(animate: oldLength > 0);
      } else if (mounted && !_showJumpToLatest) {
        setState(() => _showJumpToLatest = true);
      }
    });

    final hasSubtitle = conversation != null;
    // Grow the toolbar with the user's real text scale instead of clamping it,
    // so accessibility settings are honoured and the two-line title still fits.
    // Capped so an extreme setting cannot produce an oversized bar.
    final toolbarHeight = MediaQuery.textScalerOf(context)
        .scale(hasSubtitle ? kToolbarHeight + 10 : kToolbarHeight)
        .clamp(kToolbarHeight, hasSubtitle ? 132.0 : 112.0)
        .toDouble();

    return AppScaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              conversation?.otherDisplayName ?? strings.messagesThreadTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (conversation != null)
              Text(
                conversation.otherRole == 'doctor'
                    ? strings.messagesRoleDoctor
                    : strings.messagesRolePatient,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: strings.retry,
            onPressed: state.isLoading ? null : controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.isLoading
            ? Semantics(
                liveRegion: true,
                label: strings.loading,
                child: const Center(child: CircularProgressIndicator()),
              )
            : state.errorCode != null && conversation == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceLg),
                  child: Card(
                    child: ErrorRetryState(
                      title: strings.messagesThreadLoadError,
                      message: strings.messagingError(state.errorCode),
                      retryLabel: strings.retry,
                      onRetry: controller.load,
                      variant: ErrorRetryVariant.compact,
                    ),
                  ),
                ),
              )
            : Column(
                children: [
                  _ConnectionBanner(
                    status: state.connectionStatus,
                    strings: strings,
                    onRetry: controller.retryRealtime,
                  ),
                  if (conversation?.isPending == true)
                    _RequestBanner(
                      canRespond: conversation!.canRespondToRequest,
                      isBusy: state.isResponding,
                      errorCode: state.requestErrorCode,
                      strings: strings,
                      onAccept: () async {
                        final ok = await controller.acceptRequest();
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.messagesRequestAccepted),
                            ),
                          );
                        }
                      },
                      onDecline: () =>
                          _confirmDecline(context, controller, strings),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        _History(
                          state: state,
                          currentUserId: controller.currentUserId,
                          strings: strings,
                          scrollController: _scrollController,
                          onLoadOlder: _loadOlder,
                          onRetryMessage: controller.retry,
                          onDismissMessage: controller.dismissFailed,
                        ),
                        if (_showJumpToLatest)
                          PositionedDirectional(
                            end: AppTheme.spaceLg,
                            bottom: AppTheme.spaceLg,
                            child: Semantics(
                              button: true,
                              label: strings.messagesJumpToLatest,
                              child: FloatingActionButton.small(
                                heroTag: 'messages-jump-latest',
                                tooltip: strings.messagesJumpToLatest,
                                onPressed: _scrollToLatest,
                                child: const Icon(Icons.arrow_downward_rounded),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Composer(
                    controller: _messageController,
                    strings: strings,
                    canType: state.canSend,
                    canSend: state.canSend && !state.isSending,
                    isSending: state.isSending,
                    onSend: _send,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmDecline(
    BuildContext context,
    ConversationThreadController controller,
    AppStrings strings,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.messagesDeclineTitle),
        content: Text(strings.messagesDeclineBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.messagesDecline),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await controller.declineRequest();
    if (ok && context.mounted) Navigator.of(context).pop();
  }
}

class _History extends StatelessWidget {
  const _History({
    required this.state,
    required this.currentUserId,
    required this.strings,
    required this.scrollController,
    required this.onLoadOlder,
    required this.onRetryMessage,
    required this.onDismissMessage,
  });

  final ConversationThreadState state;
  final String currentUserId;
  final AppStrings strings;
  final ScrollController scrollController;
  final VoidCallback onLoadOlder;
  final Future<bool> Function(String) onRetryMessage;
  final void Function(String) onDismissMessage;

  @override
  Widget build(BuildContext context) {
    if (state.messages.isEmpty) {
      return ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        children: [
          EmptyState(
            icon: state.conversation?.isPending == true
                ? Icons.hourglass_top_rounded
                : Icons.chat_bubble_outline_rounded,
            title: state.conversation?.isPending == true
                ? strings.messagesPendingEmptyTitle
                : strings.messagesThreadEmptyTitle,
            hint: state.conversation?.isPending == true
                ? strings.messagesPendingComposerDisabled
                : strings.messagesThreadEmptyHint,
            variant: EmptyStateVariant.compact,
          ),
        ],
      );
    }

    return Semantics(
      liveRegion: true,
      label: strings.messagesHistoryLabel,
      child: ListView.builder(
        key: const PageStorageKey<String>('care-message-history'),
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        itemCount: state.messages.length + (state.nextCursor != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (state.nextCursor != null && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
              child: Center(
                child: TextButton.icon(
                  onPressed: state.isLoadingOlder ? null : onLoadOlder,
                  icon: state.isLoadingOlder
                      ? const SizedBox.square(
                          dimension: AppTheme.iconSm,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.history_rounded),
                  label: Text(strings.messagesLoadOlder),
                ),
              ),
            );
          }
          final messageIndex = index - (state.nextCursor != null ? 1 : 0);
          final message = state.messages[messageIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
            child: MessageBubble(
              key: ValueKey('message-${message.stableKey}'),
              message: message,
              isMine: message.senderUserId == currentUserId,
              isArabic: strings.isArabic,
              strings: strings,
              onRetry: message.deliveryState == MessageDeliveryState.failed
                  ? () => onRetryMessage(message.clientMessageId)
                  : null,
              onDismiss: message.deliveryState == MessageDeliveryState.failed
                  ? () => onDismissMessage(message.clientMessageId)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.strings,
    required this.canType,
    required this.canSend,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final AppStrings strings;

  /// The counterpart accepts messages: the field stays editable even while a
  /// previous message is still in flight so a fast typer is never locked out.
  final bool canType;

  /// A new send may start right now (accepted conversation, nothing sending).
  final bool canSend;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: AppTheme.elevation1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceSm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('message-composer'),
                  controller: controller,
                  enabled: canType,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: canType
                        ? strings.messagesComposerHint
                        : strings.messagesPendingComposerDisabled,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              Semantics(
                button: true,
                enabled: canSend,
                label: strings.messagesSend,
                child: IconButton.filled(
                  tooltip: strings.messagesSend,
                  onPressed: canSend ? onSend : null,
                  icon: isSending
                      ? const SizedBox.square(
                          dimension: AppTheme.iconMd,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestBanner extends StatelessWidget {
  const _RequestBanner({
    required this.canRespond,
    required this.isBusy,
    required this.errorCode,
    required this.strings,
    required this.onAccept,
    required this.onDecline,
  });

  final bool canRespond;
  final bool isBusy;
  final String? errorCode;
  final AppStrings strings;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: canRespond
          ? '${strings.messagesIncomingRequestTitle}. '
                '${strings.messagesRequestTextOnlyWarning}'
          : '${strings.messagesOutgoingRequestTitle}. '
                '${strings.messagesOutgoingRequestHint}',
      child: Material(
        color: AppTheme.warning.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                canRespond
                    ? strings.messagesIncomingRequestTitle
                    : strings.messagesOutgoingRequestTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: AppTheme.weightExtraBold,
                ),
              ),
              const SizedBox(height: AppTheme.spaceXs),
              Text(
                canRespond
                    ? strings.messagesRequestTextOnlyWarning
                    : strings.messagesOutgoingRequestHint,
              ),
              if (errorCode != null) ...[
                const SizedBox(height: AppTheme.spaceSm),
                Text(
                  strings.messagingError(errorCode),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (canRespond) ...[
                const SizedBox(height: AppTheme.spaceMd),
                Wrap(
                  spacing: AppTheme.spaceSm,
                  runSpacing: AppTheme.spaceSm,
                  children: [
                    FilledButton.icon(
                      onPressed: isBusy ? null : onAccept,
                      icon: isBusy
                          ? const SizedBox.square(
                              dimension: AppTheme.iconSm,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(strings.messagesAccept),
                    ),
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : onDecline,
                      icon: const Icon(Icons.close_rounded),
                      label: Text(strings.messagesDecline),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.status,
    required this.strings,
    required this.onRetry,
  });

  final MessagingConnectionStatus status;
  final AppStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == MessagingConnectionStatus.idle ||
        status == MessagingConnectionStatus.connected) {
      return const SizedBox.shrink();
    }
    final label = switch (status) {
      MessagingConnectionStatus.connecting => strings.messagesConnecting,
      MessagingConnectionStatus.reconnecting => strings.messagesReconnecting,
      MessagingConnectionStatus.unavailable => strings.messagesLiveUnavailable,
      _ => strings.messagesConnected,
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppTheme.spaceMd,
            vertical: AppTheme.spaceXs,
          ),
          child: Row(
            children: [
              if (status == MessagingConnectionStatus.unavailable)
                const Icon(Icons.cloud_off_outlined, size: AppTheme.iconSm)
              else
                const SizedBox.square(
                  dimension: AppTheme.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(child: Text(label)),
              if (status == MessagingConnectionStatus.unavailable)
                TextButton(onPressed: onRetry, child: Text(strings.retry)),
            ],
          ),
        ),
      ),
    );
  }
}
