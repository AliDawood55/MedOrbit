import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/report_summary_result.dart';

/// Extracted-text preview is truncated here purely for on-screen length —
/// the full text already came back from the server and isn't fetched again,
/// this just avoids dumping an entire document onto one card.
const int _extractedTextPreviewLimit = 320;

/// Renders one completed summary: both language summaries (each forced to
/// its own text direction regardless of app locale, since `summary_ar` is
/// always Arabic and `summary_en` is always English), a truncated extracted
/// text preview, and the model/processing-time/source-type metadata.
class ReportSummaryResultCard extends StatelessWidget {
  const ReportSummaryResultCard({
    super.key,
    required this.result,
    required this.strings,
    required this.onSummarizeAnother,
  });

  final ReportSummaryResult result;
  final AppStrings strings;
  final VoidCallback onSummarizeAnother;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final preview = result.extractedText.length > _extractedTextPreviewLimit
        ? '${result.extractedText.substring(0, _extractedTextPreviewLimit)}…'
        : result.extractedText;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.reportSummaryResult),
            if (result.summaryAr.isNotEmpty) ...[
              Text(strings.arabicSummary, style: textTheme.labelLarge),
              const SizedBox(height: AppTheme.spaceXs),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(result.summaryAr, style: textTheme.bodyMedium),
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            if (result.summaryEn.isNotEmpty) ...[
              Text(strings.englishSummary, style: textTheme.labelLarge),
              const SizedBox(height: AppTheme.spaceXs),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(result.summaryEn, style: textTheme.bodyMedium),
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            if (preview.isNotEmpty) ...[
              Text(strings.extractedTextPreview, style: textTheme.labelLarge),
              const SizedBox(height: AppTheme.spaceXs),
              Text(
                preview,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            Wrap(
              spacing: AppTheme.spaceLg,
              runSpacing: AppTheme.spaceXs,
              children: [
                if (result.modelUsed.isNotEmpty)
                  _MetaItem(label: strings.modelUsed, value: result.modelUsed),
                if (result.processingTimeMs > 0)
                  _MetaItem(
                    label: strings.processingTime,
                    value: '${(result.processingTimeMs / 1000).toStringAsFixed(1)}s',
                  ),
                if (result.sourceFileType.isNotEmpty)
                  _MetaItem(label: strings.sourceFileType, value: result.sourceFileType),
              ],
            ),
            const SizedBox(height: AppTheme.spaceLg),
            OutlinedButton(
              onPressed: onSummarizeAnother,
              child: Text(strings.reportSummarizeAnotherAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: textTheme.bodyMedium),
      ],
    );
  }
}
