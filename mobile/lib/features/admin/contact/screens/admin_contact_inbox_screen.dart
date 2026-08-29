import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_filter_chips.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_contact_message.dart';
import '../providers/admin_contact_provider.dart';
import '../widgets/admin_contact_detail_sheet.dart';

/// Mobile port of the web `admin-contact-messages.html` inbox.
///
/// Same server-ordered queue (`new` first, then `read`, then `resolved`,
/// newest first), the same status filter, and the same offset pagination —
/// expressed as one continuously growing list rather than prev/next buttons.
class AdminContactInboxScreen extends ConsumerWidget {
  const AdminContactInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminContactTitle,
      child: const _AdminContactInboxView(),
    );
  }
}

class _AdminContactInboxView extends ConsumerWidget {
  const _AdminContactInboxView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(adminContactInboxControllerProvider);
    final controller = ref.read(adminContactInboxControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.adminContactTitle),
        actions: [
          IconButton(
            key: const ValueKey('admin-contact-refresh'),
            tooltip: strings.adminRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
          ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveContent(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
              child: AdminFilterChips<AdminContactStatus>(
                label: strings.adminFiltersTitle,
                selected: state.status,
                onSelected: controller.setStatus,
                options: [
                  AdminFilterOption(
                    value: null,
                    label: strings.adminFilterAll,
                    key: const ValueKey('admin-contact-all'),
                  ),
                  AdminFilterOption(
                    value: AdminContactStatus.isNew,
                    label: strings.adminContactStatusNew,
                    key: const ValueKey('admin-contact-new'),
                  ),
                  AdminFilterOption(
                    value: AdminContactStatus.read,
                    label: strings.adminContactStatusRead,
                    key: const ValueKey('admin-contact-read'),
                  ),
                  AdminFilterOption(
                    value: AdminContactStatus.resolved,
                    label: strings.adminContactStatusResolved,
                    key: const ValueKey('admin-contact-resolved'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _body(
                context: context,
                controller: controller,
                state: state,
                strings: strings,
                isArabic: isArabic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body({
    required BuildContext context,
    required AdminContactInboxController controller,
    required AdminContactInboxState state,
    required AppStrings strings,
    required bool isArabic,
  }) {
    if (!state.hasLoadedOnce && state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasLoadedOnce && state.errorCode != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorRetryState(
            title: strings.adminLoadErrorTitle,
            message: strings.adminError(state.errorCode),
            retryLabel: strings.retry,
            onRetry: controller.load,
            retryKey: const ValueKey('admin-contact-retry'),
          ),
        ],
      );
    }
    if (state.messages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            key: const ValueKey('admin-contact-empty'),
            icon: Icons.mark_email_read_outlined,
            title: strings.adminContactEmptyTitle,
            hint: strings.adminContactEmptyHint,
          ),
        ],
      );
    }

    final showFooter = state.hasMore || state.pageErrorCode != null;

    return ResponsiveContent(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.pageHorizontalPadding(
            MediaQuery.sizeOf(context).width,
          ),
          vertical: AppTheme.spaceSm,
        ),
        itemCount: state.messages.length + (showFooter ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          if (index == state.messages.length) {
            return _PaginationFooter(
              strings: strings,
              errorCode: state.pageErrorCode,
              isLoading: state.isLoadingMore,
              onLoadMore: controller.loadMore,
            );
          }
          return _ContactCard(
            message: state.messages[index],
            strings: strings,
            isArabic: isArabic,
            onOpen: () => showAdminContactMessage(
              context: context,
              messageId: state.messages[index].id,
            ),
          );
        },
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.message,
    required this.strings,
    required this.isArabic,
    required this.onOpen,
  });

  final AdminContactMessage message;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = adminContactStatusVisual(
      message,
      strings,
    );
    final received = adminFormatDateTime(message.createdAt, isArabic: isArabic);

    return Semantics(
      button: true,
      label: '${message.subject}. ${message.senderName}. $statusLabel.',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('admin-contact-${message.id}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.subject,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: message.isUnread
                          ? AppTheme.weightExtraBold
                          : AppTheme.weightBold,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space2xs),
                  Text(
                    message.senderName.isEmpty
                        ? message.senderEmail
                        : '${message.senderName} · ${message.senderEmail}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppTheme.space2xs),
                  Text(
                    adminIsolate(received),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StatusBadge(label: statusLabel, color: statusColor),
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

/// Loads the next page as soon as it scrolls into view, and degrades to an
/// explicit retry when that page fails — so a transient error never silently
/// stops the list from growing.
class _PaginationFooter extends StatefulWidget {
  const _PaginationFooter({
    required this.strings,
    required this.errorCode,
    required this.isLoading,
    required this.onLoadMore,
  });

  final AppStrings strings;
  final String? errorCode;
  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  State<_PaginationFooter> createState() => _PaginationFooterState();
}

class _PaginationFooterState extends State<_PaginationFooter> {
  @override
  void initState() {
    super.initState();
    if (widget.errorCode == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoadMore();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.errorCode != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineMessage(
            message: widget.strings.adminError(widget.errorCode),
            tone: InlineMessageTone.warning,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          OutlinedButton.icon(
            key: const ValueKey('admin-contact-load-more-retry'),
            onPressed: widget.onLoadMore,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(widget.strings.retry),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
      child: Semantics(
        liveRegion: true,
        label: widget.strings.adminLoadingMore,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
