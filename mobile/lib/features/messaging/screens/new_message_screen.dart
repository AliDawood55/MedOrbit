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
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/messaging_models.dart';
import '../providers/messaging_providers.dart';

class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key, this.initialCounterpartId});

  final String? initialCounterpartId;

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  final _searchController = TextEditingController();
  bool _startedInitialCounterpart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final counterpartId = widget.initialCounterpartId;
      if (counterpartId != null && counterpartId.isNotEmpty) {
        _start(counterpartId, automatic: true);
      } else {
        ref.read(recipientSearchProvider.notifier).search('');
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _start(String counterpartId, {bool automatic = false}) async {
    if (automatic && _startedInitialCounterpart) return;
    if (automatic) _startedInitialCounterpart = true;
    final conversation = await ref
        .read(recipientSearchProvider.notifier)
        .startConversation(counterpartId);
    if (!mounted || conversation == null) return;
    ref.invalidate(messagingInboxProvider);
    if (conversation.isPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(appStringsProvider).messagesRequestSent),
        ),
      );
    }
    context.pushReplacement(RoutePaths.messageThreadPath(conversation.id));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final role = ref.watch(authControllerProvider).user?.role.toLowerCase();
    final state = ref.watch(recipientSearchProvider);
    final controller = ref.read(recipientSearchProvider.notifier);
    final origin = ref.watch(activeOriginProvider);
    final automaticStart = widget.initialCounterpartId != null;

    return AppScaffold(
      appBar: AppBar(title: Text(strings.messagesNew)),
      useSafeArea: true,
      safeAreaTop: false,
      keyboardAware: false,
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageIntro(
                  title: strings.messagesNewTitle,
                  subtitle: role == 'doctor'
                      ? strings.messagesDoctorRecipientHint
                      : strings.messagesPatientRecipientHint,
                  icon: Icons.person_search_outlined,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                if (automaticStart && state.startingIds.isNotEmpty)
                  Semantics(
                    liveRegion: true,
                    label: strings.messagesStartingConversation,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.spaceXl),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: AppTheme.spaceMd),
                            Text(strings.messagesStartingConversation),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    key: const ValueKey('recipient-search'),
                    controller: _searchController,
                    maxLength: 80,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: strings.messagesRecipientSearchLabel,
                      hintText: strings.messagesRecipientSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: strings.messagesSearch,
                        onPressed: state.isSearching
                            ? null
                            : () => controller.search(_searchController.text),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                    onSubmitted: state.isSearching ? null : controller.search,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  if (state.startErrorCode != null) ...[
                    InlineMessage(
                      message: strings.messagingError(state.startErrorCode),
                      tone: InlineMessageTone.error,
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                  ],
                  if (state.isSearching)
                    Semantics(
                      liveRegion: true,
                      label: strings.messagesSearching,
                      child: const Padding(
                        padding: EdgeInsets.all(AppTheme.spaceXl),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (state.errorCode != null)
                    Card(
                      child: ErrorRetryState(
                        title: strings.messagesSearchError,
                        message: strings.messagingError(state.errorCode),
                        retryLabel: strings.retry,
                        onRetry: () => controller.search(state.query),
                        variant: ErrorRetryVariant.compact,
                      ),
                    )
                  else if (state.items.isEmpty)
                    Card(
                      child: EmptyState(
                        icon: Icons.person_search_outlined,
                        title: strings.messagesNoEligibleRecipients,
                        hint: strings.messagesNoEligibleRecipientsHint,
                        variant: EmptyStateVariant.compact,
                      ),
                    )
                  else
                    for (final recipient in state.items) ...[
                      _RecipientCard(
                        recipient: recipient,
                        isArabic: isArabic,
                        strings: strings,
                        origin: origin,
                        isStarting: state.startingIds.contains(recipient.id),
                        onTap: () => _start(recipient.id),
                      ),
                      const SizedBox(height: AppTheme.spaceSm),
                    ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({
    required this.recipient,
    required this.isArabic,
    required this.strings,
    required this.origin,
    required this.isStarting,
    required this.onTap,
  });

  final MessagingRecipient recipient;
  final bool isArabic;
  final AppStrings strings;
  final String origin;
  final bool isStarting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = recipient.displayName(isArabic);
    final displayName = name.isEmpty ? strings.messagesUnknownUser : name;
    final role = recipient.kind == RecipientKind.doctor
        ? strings.messagesVerifiedDoctor
        : strings.messagesPatientOpenToRequests;
    final details = [
      recipient.specialty(isArabic),
      recipient.city,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final image = _assetUrl(origin, recipient.avatarUrl);

    return Semantics(
      button: true,
      enabled: !isStarting,
      label: '$displayName, $role${details.isEmpty ? '' : ', $details'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isStarting ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    foregroundImage: image == null ? null : NetworkImage(image),
                    child: Text(displayName.characters.first.toUpperCase()),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: AppTheme.weightBold),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        StatusBadge(label: role, color: AppTheme.primary),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.spaceXs),
                          Text(
                            details,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  if (isStarting)
                    const SizedBox.square(
                      dimension: AppTheme.iconMd,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const ExcludeSemantics(
                      child: Icon(Icons.chevron_right_rounded),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _assetUrl(String origin, String? value) {
  final source = value?.trim() ?? '';
  if (source.isEmpty) return null;
  final uri = Uri.tryParse(source);
  if (uri?.hasScheme == true) return source;
  if (origin.isEmpty) return null;
  return '$origin/${source.replaceFirst(RegExp(r'^/+'), '')}';
}
