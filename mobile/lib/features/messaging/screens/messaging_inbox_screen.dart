import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../providers/messaging_providers.dart';
import '../widgets/conversation_tile.dart';

class MessagingInboxScreen extends ConsumerStatefulWidget {
  const MessagingInboxScreen({super.key});

  @override
  ConsumerState<MessagingInboxScreen> createState() =>
      _MessagingInboxScreenState();
}

class _MessagingInboxScreenState extends ConsumerState<MessagingInboxScreen>
    with WidgetsBindingObserver {
  // Guards against the go_router Navigator's
  // "'!keyReservation.contains(key)'" assertion, which fires when the same
  // route is pushed twice before the first push's page has finished
  // registering — a fast double-tap on any of the "New message" buttons or
  // a conversation tile was enough to trigger it.
  bool _isNavigating = false;

  void _navigate(String path) {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    context.push(path).whenComplete(() {
      if (mounted) setState(() => _isNavigating = false);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(messagingInboxProvider.notifier).setActive(true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(messagingInboxProvider.notifier)
        .setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(messagingInboxProvider);
    final controller = ref.read(messagingInboxProvider.notifier);
    final preference = ref.watch(patientMessagingPreferenceProvider);
    final preferenceController = ref.read(
      patientMessagingPreferenceProvider.notifier,
    );
    final assetOrigin = ref.watch(activeOriginProvider);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.messagesTitle),
        actions: [
          IconButton(
            tooltip: strings.messagesNew,
            onPressed: () => _navigate(RoutePaths.messagesNew),
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          key: const PageStorageKey<String>('care-messages-inbox'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(
                    title: strings.messagesTitle,
                    subtitle: strings.messagesSubtitle,
                    icon: Icons.forum_outlined,
                    trailing: FilledButton.icon(
                      onPressed: () => _navigate(RoutePaths.messagesNew),
                      icon: const Icon(Icons.add_comment_outlined),
                      label: Text(strings.messagesNew),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  if (state.isLoading && state.items.isEmpty)
                    _InboxLoading(label: strings.loading)
                  else if (state.errorCode != null && state.items.isEmpty)
                    Card(
                      child: ErrorRetryState(
                        title: strings.messagesInboxLoadError,
                        message: strings.messagingError(state.errorCode),
                        retryLabel: strings.retry,
                        onRetry: controller.refresh,
                        variant: ErrorRetryVariant.compact,
                      ),
                    )
                  else if (state.items.isEmpty)
                    Card(
                      child: EmptyState(
                        icon: Icons.mark_chat_unread_outlined,
                        title: strings.messagesInboxEmptyTitle,
                        hint: strings.messagesInboxEmptyHint,
                        action: FilledButton.icon(
                          onPressed: () => _navigate(RoutePaths.messagesNew),
                          icon: const Icon(Icons.add_comment_outlined),
                          label: Text(strings.messagesNew),
                        ),
                        variant: EmptyStateVariant.compact,
                      ),
                    )
                  else ...[
                    if (state.errorCode != null) ...[
                      InlineMessage(
                        message: strings.messagingError(state.errorCode),
                        tone: InlineMessageTone.warning,
                      ),
                      const SizedBox(height: AppTheme.spaceMd),
                    ],
                    for (final conversation in state.items) ...[
                      ConversationTile(
                        key: ValueKey('conversation-${conversation.id}'),
                        conversation: conversation,
                        strings: strings,
                        isArabic: isArabic,
                        assetOrigin: assetOrigin,
                        onTap: () => _navigate(
                          RoutePaths.messageThreadPath(conversation.id),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceSm),
                    ],
                  ],
                  if (state.isRefreshing) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    Semantics(
                      liveRegion: true,
                      label: strings.loading,
                      child: const LinearProgressIndicator(),
                    ),
                  ],
                  if (preference.isApplicable) ...[
                    const SizedBox(height: AppTheme.spaceLg),
                    _PatientMessagingPreferenceCard(
                      state: preference,
                      strings: strings,
                      onRetry: preferenceController.load,
                      onChanged: preferenceController.update,
                    ),
                  ],
                  const SizedBox(height: AppTheme.spaceLg),
                  Text(
                    strings.messagesTextOnlyNotice,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientMessagingPreferenceCard extends StatelessWidget {
  const _PatientMessagingPreferenceCard({
    required this.state,
    required this.strings,
    required this.onRetry,
    required this.onChanged,
  });

  final PatientMessagingPreferenceState state;
  final AppStrings strings;
  final VoidCallback onRetry;
  final Future<bool> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isLoading)
              Semantics(
                liveRegion: true,
                label: strings.loading,
                child: const LinearProgressIndicator(),
              )
            else if (state.allowDoctorMessages != null)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.manage_search_outlined),
                title: Text(strings.messagesPrivacyTitle),
                subtitle: Text(strings.messagesPrivacyHelp),
                value: state.allowDoctorMessages!,
                onChanged: state.isSaving ? null : onChanged,
              ),
            if (state.isSaving) const LinearProgressIndicator(),
            if (state.errorCode != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              InlineMessage(
                message: strings.messagingError(state.errorCode),
                tone: InlineMessageTone.warning,
              ),
              if (state.allowDoctorMessages == null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: onRetry,
                    child: Text(strings.retry),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InboxLoading extends StatelessWidget {
  const _InboxLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: const Padding(
        padding: EdgeInsets.all(AppTheme.spaceXl),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
