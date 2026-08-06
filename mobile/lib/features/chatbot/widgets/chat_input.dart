import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
class ChatInput extends StatelessWidget {
  const ChatInput({super.key, required this.controller, required this.enabled, required this.onSend});
  final TextEditingController controller; final bool enabled; final VoidCallback onSend;
  @override Widget build(BuildContext context) => SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(AppTheme.spaceMd), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(key: const ValueKey('chat-input'), controller: controller, enabled: enabled, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: const InputDecoration(labelText: 'Message', hintText: 'Describe how you feel'))), const SizedBox(width: AppTheme.spaceSm), IconButton(key: const ValueKey('chat-send'), tooltip: 'Send message', onPressed: enabled ? onSend : null, icon: const Icon(Icons.send_rounded))])));
}
