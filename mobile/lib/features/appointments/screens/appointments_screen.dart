import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/enriched_appointment.dart';
import '../providers/appointments_provider.dart';
import '../utils/appointment_filters.dart';
import '../widgets/appointment_card.dart';

enum _AppointmentTab { upcoming, past, cancelled }

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() =>
      _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _cancellingAppointmentId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<EnrichedAppointment> _classify(
    List<EnrichedAppointment> all,
    _AppointmentTab tab,
  ) {
    final filtered = all.where((entry) {
      final status = entry.appointment.status;
      switch (tab) {
        case _AppointmentTab.cancelled:
          return status == 'cancelled';
        case _AppointmentTab.past:
          return status != 'cancelled' && isPastAppointment(entry);
        case _AppointmentTab.upcoming:
          return isUpcomingAppointment(entry);
      }
    }).toList();

    int compare(EnrichedAppointment a, EnrichedAppointment b) {
      final dateA = parseDateOnly(a.appointment.scheduledDate);
      final dateB = parseDateOnly(b.appointment.scheduledDate);
      final byDate = dateA.compareTo(dateB);
      if (byDate != 0) return byDate;
      return a.appointment.startTime.compareTo(b.appointment.startTime);
    }

    filtered.sort(
      tab == _AppointmentTab.upcoming
          ? compare
          : (a, b) => compare(b, a),
    );
    return filtered;
  }

  Future<void> _confirmCancel(
    EnrichedAppointment entry,
    AppStrings strings,
  ) async {
    if (_cancellingAppointmentId != null) return;

    final reasonController = TextEditingController();
    final request = await showDialog<_CancellationRequest>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceLg,
          vertical: AppTheme.spaceXl,
        ),
        icon: const Icon(
          Icons.event_busy_outlined,
          color: AppTheme.danger,
          size: AppTheme.iconXl,
        ),
        title: Text(
          strings.cancelDialogTitle,
          textAlign: TextAlign.center,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.maxAuthContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.cancelDialogBody,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              AppTextField(
                label: strings.cancelReasonHint,
                hintText: strings.cancelReasonPlaceholder,
                controller: reasonController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                semanticLabel: strings.cancelReasonHint,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(
              _CancellationRequest(reasonController.text),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.close_rounded),
            label: Text(strings.cancelConfirm),
          ),
        ],
      ),
    );
    reasonController.dispose();

    if (request == null || !mounted) return;

    setState(() => _cancellingAppointmentId = entry.appointment.id);
    final success = await ref
        .read(appointmentsControllerProvider.notifier)
        .cancel(entry.appointment.id, reason: request.reason);

    if (!mounted) return;
    setState(() => _cancellingAppointmentId = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            success
                ? strings.cancelSuccessMessage
                : strings.cancelErrorMessage,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic =
        ref.watch(localeControllerProvider).languageCode == 'ar';
    final appointmentsAsync = ref.watch(appointmentsControllerProvider);
    final reload =
        ref.read(appointmentsControllerProvider.notifier).load;

    return AppScaffold(
      appBar: AppBar(title: Text(strings.appName)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.appointmentBooking),
        icon: const Icon(Icons.add_rounded),
        label: Text(strings.bookNewAppointment),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceLg),
              child: ResponsiveContent(
                child: PageIntro(
                  title: strings.appointmentsTitle,
                  subtitle: strings.appointmentsSubtitle,
                  icon: Icons.event_available_outlined,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            Expanded(
              child: appointmentsAsync.when(
                data: (all) => _AppointmentsContent(
                  tabController: _tabController,
                  upcoming: _classify(all, _AppointmentTab.upcoming),
                  past: _classify(all, _AppointmentTab.past),
                  cancelled: _classify(all, _AppointmentTab.cancelled),
                  strings: strings,
                  isArabic: isArabic,
                  cancellingAppointmentId: _cancellingAppointmentId,
                  onCancel: (entry) => _confirmCancel(entry, strings),
                  onRefresh: reload,
                ),
                loading: () => _AppointmentsLoading(
                  label: strings.loadingAppointments,
                  onRefresh: reload,
                ),
                error: (error, stackTrace) => _AppointmentsError(
                  strings: strings,
                  onRetry: reload,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancellationRequest {
  const _CancellationRequest(this.reason);

  final String reason;
}

class _AppointmentsContent extends StatelessWidget {
  const _AppointmentsContent({
    required this.tabController,
    required this.upcoming,
    required this.past,
    required this.cancelled,
    required this.strings,
    required this.isArabic,
    required this.cancellingAppointmentId,
    required this.onCancel,
    required this.onRefresh,
  });

  final TabController tabController;
  final List<EnrichedAppointment> upcoming;
  final List<EnrichedAppointment> past;
  final List<EnrichedAppointment> cancelled;
  final AppStrings strings;
  final bool isArabic;
  final String? cancellingAppointmentId;
  final ValueChanged<EnrichedAppointment> onCancel;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ResponsiveContent(
          child: _AppointmentTabs(
            controller: tabController,
            upcomingCount: upcoming.length,
            pastCount: past.length,
            cancelledCount: cancelled.length,
            strings: strings,
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.maxPhoneContentWidth,
              ),
              child: TabBarView(
                controller: tabController,
                children: [
                  _AppointmentList(
                    storageKey: 'appointments-upcoming',
                    entries: upcoming,
                    strings: strings,
                    isArabic: isArabic,
                    emptyLabel: strings.emptyUpcoming,
                    emptyHint: strings.emptyUpcomingHint,
                    allowCancel: true,
                    cancellingAppointmentId: cancellingAppointmentId,
                    onCancel: onCancel,
                    onRefresh: onRefresh,
                  ),
                  _AppointmentList(
                    storageKey: 'appointments-past',
                    entries: past,
                    strings: strings,
                    isArabic: isArabic,
                    emptyLabel: strings.emptyPast,
                    emptyHint: strings.emptyPastHint,
                    allowCancel: false,
                    cancellingAppointmentId: cancellingAppointmentId,
                    onRefresh: onRefresh,
                  ),
                  _AppointmentList(
                    storageKey: 'appointments-cancelled',
                    entries: cancelled,
                    strings: strings,
                    isArabic: isArabic,
                    emptyLabel: strings.emptyCancelledTab,
                    emptyHint: strings.emptyCancelledHint,
                    allowCancel: false,
                    cancellingAppointmentId: cancellingAppointmentId,
                    onRefresh: onRefresh,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppointmentTabs extends StatelessWidget {
  const _AppointmentTabs({
    required this.controller,
    required this.upcomingCount,
    required this.pastCount,
    required this.cancelledCount,
    required this.strings,
  });

  final TabController controller;
  final int upcomingCount;
  final int pastCount;
  final int cancelledCount;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = AppTheme.usesLargeText(
            context,
            threshold: 1.2,
          );
          final scrollable =
              constraints.maxWidth < AppTheme.wideBreakpoint || largeText;
          return Semantics(
            container: true,
            label: strings.appointmentFiltersLabel,
            child: TabBar(
              controller: controller,
              isScrollable: scrollable,
              tabAlignment:
                  scrollable ? TabAlignment.start : TabAlignment.fill,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spaceXs,
              ),
              tabs: [
                Tab(
                  child: _TabLabel(
                    label: strings.tabUpcoming,
                    count: upcomingCount,
                  ),
                ),
                Tab(
                  child: _TabLabel(
                    label: strings.tabPast,
                    count: pastCount,
                  ),
                ),
                Tab(
                  child: _TabLabel(
                    label: strings.tabCancelled,
                    count: cancelledCount,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: AppTheme.spaceXs),
        Container(
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceXs),
          decoration: BoxDecoration(
            color: AppTheme.mutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
          alignment: Alignment.center,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    required this.storageKey,
    required this.entries,
    required this.strings,
    required this.isArabic,
    required this.emptyLabel,
    required this.emptyHint,
    required this.allowCancel,
    required this.cancellingAppointmentId,
    required this.onRefresh,
    this.onCancel,
  });

  final String storageKey;
  final List<EnrichedAppointment> entries;
  final AppStrings strings;
  final bool isArabic;
  final String emptyLabel;
  final String emptyHint;
  final bool allowCancel;
  final String? cancellingAppointmentId;
  final Future<void> Function() onRefresh;
  final ValueChanged<EnrichedAppointment>? onCancel;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppTheme.pageHorizontalPadding(
      MediaQuery.sizeOf(context).width,
    );
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          key: PageStorageKey<String>(storageKey),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.fromSTEB(
            horizontal,
            0,
            horizontal,
            AppTheme.spaceXl,
          ),
          children: [
            Card(
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                title: emptyLabel,
                hint: emptyHint,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        key: PageStorageKey<String>(storageKey),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsetsDirectional.fromSTEB(
          horizontal,
          0,
          horizontal,
          AppTheme.spaceXl,
        ),
        itemCount: entries.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final status = entry.appointment.status;
          final canCancel = allowCancel &&
              (status == 'scheduled' || status == 'confirmed');
          final isCancelling =
              cancellingAppointmentId == entry.appointment.id;
          return RepaintBoundary(
            child: AppointmentCard(
              entry: entry,
              strings: strings,
              isArabic: isArabic,
              onCancel: canCancel ? () => onCancel?.call(entry) : null,
              isCancelling: isCancelling,
              cancelEnabled: cancellingAppointmentId == null,
            ),
          );
        },
      ),
    );
  }
}

class _AppointmentsLoading extends StatelessWidget {
  const _AppointmentsLoading({required this.label, required this.onRefresh});

  final String label;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
        children: [
          ResponsiveContent(
            child: Semantics(
              liveRegion: true,
              label: label,
              child: Column(
                children: [
                  const _FilterSkeleton(),
                  const SizedBox(height: AppTheme.spaceMd),
                  for (var index = 0; index < 3; index++) ...[
                    const _AppointmentSkeletonCard(),
                    if (index != 2)
                      const SizedBox(height: AppTheme.spaceMd),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSkeleton extends StatelessWidget {
  const _FilterSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              Expanded(child: _SkeletonLine(widthFactor: 0.7)),
              if (index != 2)
                const SizedBox(width: AppTheme.spaceMd),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppointmentSkeletonCard extends StatelessWidget {
  const _AppointmentSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final placeholder = AppTheme.mutedSurfaceOf(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: placeholder,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
            ),
            const SizedBox(width: AppTheme.spaceLg),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(widthFactor: 0.45),
                  SizedBox(height: AppTheme.spaceSm),
                  _SkeletonLine(widthFactor: 0.7),
                  SizedBox(height: AppTheme.spaceMd),
                  _SkeletonLine(widthFactor: 1),
                  SizedBox(height: AppTheme.spaceSm),
                  _SkeletonLine(widthFactor: 0.8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: AppTheme.mutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
      ),
    );
  }
}

class _AppointmentsError extends StatelessWidget {
  const _AppointmentsError({required this.strings, required this.onRetry});

  final AppStrings strings;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
        children: [
          ResponsiveContent(
            child: Card(
              child: ErrorRetryState(
                title: strings.appointmentsLoadErrorTitle,
                message: strings.appointmentsLoadErrorMessage,
                retryLabel: strings.retry,
                onRetry: onRetry,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
