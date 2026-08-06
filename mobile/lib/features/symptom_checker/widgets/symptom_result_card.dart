import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/symptom_check_result.dart';

/// Renders one completed triage result. Framed throughout as a suggestion,
/// never a diagnosis: "suggested specialty", not "your diagnosis"; a
/// confidence percentage taken as-is from the server, never invented or
/// rounded to sound more certain than it is.
class SymptomResultCard extends StatelessWidget {
  const SymptomResultCard({
    super.key,
    required this.result,
    required this.strings,
    required this.isArabic,
    required this.onCheckAnother,
  });

  final SymptomCheckResult result;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onCheckAnother;

  @override
  Widget build(BuildContext context) {
    final (tone, title) = switch (result.triageLevel) {
      TriageLevel.emergency => (InlineMessageTone.error, strings.symptomEmergencyTitle),
      TriageLevel.urgent => (InlineMessageTone.warning, strings.symptomUrgentTitle),
      TriageLevel.routine => (InlineMessageTone.success, strings.symptomRoutineTitle),
    };
    final specialty = isArabic
        ? (result.recommendedSpecialtyNameAr ?? result.recommendedSpecialtyNameEn)
        : (result.recommendedSpecialtyNameEn ?? result.recommendedSpecialtyNameAr);
    final confidencePercent = (result.confidenceScore.clamp(0.0, 1.0) * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InlineMessage(message: title, tone: tone),
            if (result.triageLevel == TriageLevel.emergency) ...[
              const SizedBox(height: AppTheme.spaceSm),
              InlineMessage(
                message: strings.symptomEmergencyMessage,
                tone: InlineMessageTone.error,
              ),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            if (specialty != null) ...[
              SectionHeader(title: strings.symptomRecommendedSpecialty),
              Text(specialty, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            SectionHeader(title: strings.symptomConfidenceLabel),
            Text(
              '$confidencePercent%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.spaceMd),
            SectionHeader(title: strings.symptomRecommendationsLabel),
            Text(
              result.recommendations,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            OutlinedButton(
              onPressed: onCheckAnother,
              child: Text(strings.symptomCheckAnotherAction),
            ),
          ],
        ),
      ),
    );
  }
}
