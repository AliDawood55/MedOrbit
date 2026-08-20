import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/my_report_item.dart';
import '../providers/my_reports_provider.dart';
import '../widgets/my_report_card.dart';

class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final reportsAsync = ref.watch(myReportsControllerProvider);
    final reload = ref.read(myReportsControllerProvider.notifier).load;

    return AppScaffold(
      appBar: AppBar(title: Text(strings.myReportsTitle)),
      useSafeArea: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spaceLg),
            child: ResponsiveContent(
              child: PageIntro(
                title: strings.myReportsTitle,
                subtitle: strings.myReportsSubtitle,
                icon: Icons.folder_shared_outlined,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          Expanded(
            child: reportsAsync.when(
              data: (reports) => _MyReportsList(
                reports: reports,
                strings: strings,
                isArabic: isArabic,
                onRefresh: reload,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceLg),
                  child: Card(
                    child: ErrorRetryState(
                      title: strings.myReportsLoadError,
                      message: strings.errorGeneric,
                      retryLabel: strings.retry,
                      onRetry: reload,
                      variant: ErrorRetryVariant.compact,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyReportsList extends StatelessWidget {
  const _MyReportsList({
    required this.reports,
    required this.strings,
    required this.isArabic,
    required this.onRefresh,
  });

  final List<MyReportItem> reports;
  final AppStrings strings;
  final bool isArabic;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
          children: [
            const SizedBox(height: AppTheme.spaceXl),
            Card(
              child: EmptyState(
                icon: Icons.folder_off_outlined,
                title: strings.myReportsEmptyTitle,
                hint: strings.myReportsEmptyMessage,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spaceLg,
          0,
          AppTheme.spaceLg,
          AppTheme.spaceXl,
        ),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spaceMd),
        itemBuilder: (context, index) => MyReportCard(
          report: reports[index],
          strings: strings,
          isArabic: isArabic,
        ),
      ),
    );
  }
}
