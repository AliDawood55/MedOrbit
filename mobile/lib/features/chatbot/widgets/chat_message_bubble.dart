import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/chatbot_models.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({super.key, required this.message});
  final ChatMessage message;
  @override Widget build(BuildContext context) {
    final user = message.messageType.toLowerCase() == 'user';
    final warning = message.lastIntent?.toLowerCase().contains('emergency') == true || message.metadata.values['intent']?.toString().toLowerCase().contains('emergency') == true;
    final color = user ? Theme.of(context).colorScheme.primary : warning ? AppTheme.warning : Theme.of(context).colorScheme.surfaceContainerHighest;
    final foreground = user ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      container: true,
      label: user ? 'Your message' : warning ? 'Emergency guidance' : 'Assistant message',
      liveRegion: !user,
      child: Align(
        alignment: user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          margin: const EdgeInsets.only(bottom: AppTheme.spaceSm),
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
          child: SelectableText(message.messageText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground)),
        ),
      ),
    );
  }
}
