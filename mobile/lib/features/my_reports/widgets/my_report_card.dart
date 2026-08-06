import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../models/my_report_item.dart';

/// One report in the list. Collapsed by default, showing only enough to
/// scan (type, date, source, a short preview); "View details" reveals the
/// full summaries — never the full extracted text, which the backend
/// truncates before it ever reaches this model.
class MyReportCard extends StatefulWidget {
  const MyReportCard({super.key, required this.report, required this.strings, required this.isArabic});

  final MyReportItem report;
  final AppStrings strings;
  final bool isArabic;

  @override
  State<MyReportCard> createState() => _MyReportCardState();
}

class _MyReportCardState extends State<MyReportCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final strings = widget.strings;
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final dateFormat = DateFormat('MMM d, y', widget.isArabic ? 'ar' : 'en');
    final preview = widget.isArabic
        ? (report.summaryAr?.isNotEmpty ?? false ? report.summaryAr : report.summaryEn)
        : (report.summaryEn?.isNotEmpty ?? false ? report.summaryEn : report.summaryAr);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_typeIcon(report.type), color: AppTheme.primary),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Text(_typeLabel(strings, report.type), style: textTheme.titleMedium),
                ),
                Text(dateFormat.format(report.createdAt), style: mutedStyle),
              ],
            ),
            if (report.sourceFileType != null && report.sourceFileType!.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceXs),
              Text('${strings.myReportSourceLabel}: ${report.sourceFileType}', style: mutedStyle),
            ],
            if (preview != null && preview.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                preview,
                style: textTheme.bodyMedium,
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ],
            if (_expanded) ..._expandedDetails(context, report, strings, textTheme, mutedStyle),
            const SizedBox(height: AppTheme.spaceMd),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? strings.myReportHideDetails : strings.myReportViewDetails),
                ),
                const Spacer(),
                if (report.downloadUrl != null)
                  OutlinedButton.icon(
                    onPressed: () {}, // populated once a source type with a real artifact is wired up
                    icon: const Icon(Icons.download_outlined),
                    label: Text(strings.myReportDownloadAction),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _expandedDetails(
    BuildContext context,
    MyReportItem report,
    AppStrings strings,
    TextTheme textTheme,
    TextStyle? mutedStyle,
  ) {
    return [
      const SizedBox(height: AppTheme.spaceMd),
      const Divider(height: 1),
      if (report.summaryAr != null && report.summaryAr!.isNotEmpty) ...[
        const SizedBox(height: AppTheme.spaceMd),
        Text(strings.arabicSummary, style: textTheme.labelLarge),
        const SizedBox(height: AppTheme.spaceXs),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(report.summaryAr!, style: textTheme.bodyMedium),
        ),
      ],
      if (report.summaryEn != null && report.summaryEn!.isNotEmpty) ...[
        const SizedBox(height: AppTheme.spaceMd),
        Text(strings.englishSummary, style: textTheme.labelLarge),
        const SizedBox(height: AppTheme.spaceXs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(report.summaryEn!, style: textTheme.bodyMedium),
        ),
      ],
      if (report.extractedTextPreview != null && report.extractedTextPreview!.isNotEmpty) ...[
        const SizedBox(height: AppTheme.spaceMd),
        Text(strings.extractedTextPreview, style: textTheme.labelLarge),
        const SizedBox(height: AppTheme.spaceXs),
        Text(report.extractedTextPreview!, style: mutedStyle),
      ],
    ];
  }
}

IconData _typeIcon(MyReportType type) => switch (type) {
  MyReportType.reportSummary => Icons.summarize_outlined,
  MyReportType.generatedReport => Icons.description_outlined,
  MyReportType.virtualDoctor => Icons.graphic_eq_rounded,
};

String _typeLabel(AppStrings strings, MyReportType type) => switch (type) {
  MyReportType.reportSummary => strings.myReportTypeSummary,
  MyReportType.generatedReport => strings.myReportTypeGenerated,
  MyReportType.virtualDoctor => strings.myReportTypeVirtualDoctor,
};
