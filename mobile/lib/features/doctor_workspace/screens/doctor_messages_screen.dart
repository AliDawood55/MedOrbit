import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/doctor_portal_api.dart';

class DoctorMessagesScreen extends ConsumerStatefulWidget {
  const DoctorMessagesScreen({super.key});
  @override
  ConsumerState<DoctorMessagesScreen> createState() => _DoctorMessagesScreenState();
}

class _DoctorMessagesScreenState extends ConsumerState<DoctorMessagesScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  DoctorPortalApi get _api => DoctorPortalApi(ref.read(dioProvider));

  @override
  void initState() {
    super.initState();
    _future = _api.conversations();
  }

  void _reload() => setState(() => _future = _api.conversations());

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    return AppScaffold(
      appBar: AppBar(
        title: Text(ar ? 'الرسائل' : 'Messages'),
        leading: IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go(RoutePaths.home)),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return ErrorRetryState(title: ar ? 'تعذر تحميل الرسائل' : 'Could not load messages', message: ar ? 'حاول مرة أخرى.' : 'Please try again.', retryLabel: ar ? 'إعادة المحاولة' : 'Retry', onRetry: _reload);
          final values = snapshot.data!;
          if (values.isEmpty) return EmptyState(icon: Icons.forum_outlined, title: ar ? 'لا توجد محادثات بعد' : 'No conversations yet', hint: ar ? 'ابدأ من زر مراسلة المريض في ملف المريض.' : 'Start from Message patient in a patient file.');
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              itemCount: values.length,
              itemBuilder: (context, index) {
                final conversation = values[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(conversation['other_display_name']?.toString() ?? (ar ? 'محادثة' : 'Conversation')),
                    subtitle: Text(conversation['last_message_preview']?.toString() ?? (ar ? 'لا توجد رسائل بعد' : 'No messages yet'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DoctorMessageThreadScreen(conversation: conversation))),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class DoctorMessageThreadScreen extends ConsumerStatefulWidget {
  const DoctorMessageThreadScreen({super.key, required this.conversation});
  final Map<String, dynamic> conversation;
  @override
  ConsumerState<DoctorMessageThreadScreen> createState() => _DoctorMessageThreadScreenState();
}

class _DoctorMessageThreadScreenState extends ConsumerState<DoctorMessageThreadScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final _input = TextEditingController();
  bool _sending = false;
  String get _id => widget.conversation['id'].toString();
  DoctorPortalApi get _api => DoctorPortalApi(ref.read(dioProvider));

  @override
  void initState() { super.initState(); _future = _api.messages(_id); }
  @override
  void dispose() { _input.dispose(); super.dispose(); }
  void _reload() => setState(() => _future = _api.messages(_id));

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final currentUserId = ref.watch(authControllerProvider).user?.id ?? '';
    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.conversation['other_display_name']?.toString() ?? (ar ? 'رسالة' : 'Message')),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return ErrorRetryState(title: ar ? 'تعذر تحميل المحادثة' : 'Could not load conversation', message: ar ? 'حاول مرة أخرى.' : 'Please try again.', retryLabel: ar ? 'إعادة المحاولة' : 'Retry', onRetry: _reload, variant: ErrorRetryVariant.compact);
                final messages = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  children: [
                    if (messages.isEmpty) Padding(padding: const EdgeInsets.only(top: AppTheme.spaceLg), child: Text(ar ? 'ابدأ المحادثة برسالة.' : 'Start the conversation with a message.')),
                    ...messages.map((message) => _MessageBubble(message: message, mine: message['sender_user_id']?.toString() == currentUserId)),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: TextField(controller: _input, enabled: !_sending, minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: ar ? 'اكتب رسالة' : 'Write a message'))),
                  const SizedBox(width: AppTheme.spaceSm),
                  IconButton.filled(onPressed: _sending ? null : () => _send(ar), icon: _sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(bool ar) async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.sendMessage(_id, body, '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}');
      _input.clear();
      _reload();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ar ? 'تعذر إرسال الرسالة.' : 'Could not send message.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final Map<String, dynamic> message;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spaceSm),
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(color: mine ? AppTheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        child: Text(message['body']?.toString() ?? '', style: TextStyle(color: mine ? Colors.white : null)),
      ),
    );
  }
}
