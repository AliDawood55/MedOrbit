import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/drug_check_result.dart';

/// Renders one completed interaction check. A drug is never called "safe":
/// the no-interactions state says only that none were *found*, and every
/// interaction card shows the server's own severity and description as-is,
/// never invented or upgraded/downgraded.
class DrugResultCard extends StatelessWidget {
  const DrugResultCard({
    super.key,
    required this.result,
    required this.strings,
    required this.isArabic,
    required this.onCheckAnother,
  });

  final DrugCheckResult result;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onCheckAnother;

  @override
  Widget build(BuildContext context) {
    final interactions = result.interactions;
    final hasSevere = interactions.any((i) => i.severity == DrugSeverity.severe);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!result.hasInteractions || interactions.isEmpty)
              InlineMessage(
                message: strings.drugNoInteractionsTitle,
                tone: InlineMessageTone.success,
              )
            else ...[
              if (hasSevere) ...[
                InlineMessage(
                  message: strings.drugSevereWarning,
                  tone: InlineMessageTone.error,
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              Text(
                _severitySummaryText(strings, result.severitySummary),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              for (final interaction in interactions) ...[
                InlineMessage(
                  message: _interactionMessage(strings, isArabic, interaction),
                  tone: _severityTone(interaction.severity),
                ),
                const SizedBox(height: AppTheme.spaceSm),
              ],
            ],
            const SizedBox(height: AppTheme.spaceMd),
            OutlinedButton(
              onPressed: onCheckAnother,
              child: Text(strings.drugCheckAnotherAction),
            ),
          ],
        ),
      ),
    );
  }
}

InlineMessageTone _severityTone(DrugSeverity severity) => switch (severity) {
  DrugSeverity.severe => InlineMessageTone.error,
  DrugSeverity.moderate => InlineMessageTone.warning,
  DrugSeverity.mild => InlineMessageTone.info,
  DrugSeverity.unknown => InlineMessageTone.info,
};

String _severityLabel(AppStrings strings, DrugSeverity severity) => switch (severity) {
  DrugSeverity.severe => strings.drugSeveritySevere,
  DrugSeverity.moderate => strings.drugSeverityModerate,
  DrugSeverity.mild => strings.drugSeverityMild,
  DrugSeverity.unknown => strings.drugSeverityUnknown,
};

String _interactionMessage(
  AppStrings strings,
  bool isArabic,
  DrugInteraction interaction,
) {
  final drug1 = isArabic
      ? (interaction.drug1NameAr ?? interaction.drug1NameEn)
      : (interaction.drug1NameEn ?? interaction.drug1NameAr);
  final drug2 = isArabic
      ? (interaction.drug2NameAr ?? interaction.drug2NameEn)
      : (interaction.drug2NameEn ?? interaction.drug2NameAr);
  final severityLabel = _severityLabel(strings, interaction.severity);
  return '$drug1 + $drug2 — $severityLabel\n${interaction.description}';
}

String _severitySummaryText(AppStrings strings, Map<String, int> summary) {
  final parts = <String>[];
  for (final entry in [
    ('severe', strings.drugSeveritySevere),
    ('moderate', strings.drugSeverityModerate),
    ('mild', strings.drugSeverityMild),
    ('unknown', strings.drugSeverityUnknown),
  ]) {
    final count = summary[entry.$1] ?? 0;
    if (count > 0) parts.add('$count ${entry.$2}');
  }
  return parts.join(', ');
}
