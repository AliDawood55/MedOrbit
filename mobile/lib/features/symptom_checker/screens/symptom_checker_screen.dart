import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../providers/symptom_checker_provider.dart';
import '../widgets/symptom_disclaimer_card.dart';
import '../widgets/symptom_input_section.dart';
import '../widgets/symptom_result_card.dart';

class SymptomCheckerScreen extends ConsumerWidget {
  const SymptomCheckerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(symptomCheckerControllerProvider);
    final notifier = ref.read(symptomCheckerControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.symptomCheckerTitle)),
      useSafeArea: true,
      keyboardAware: true,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageIntro(
                  title: strings.symptomCheckerTitle,
                  subtitle: strings.symptomCheckerSubtitle,
                  icon: Icons.health_and_safety_outlined,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                SymptomDisclaimerCard(strings: strings),
                const SizedBox(height: AppTheme.spaceLg),
                if (state.error != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: ErrorRetryState(
                        title: strings.symptomCheckerLoadError,
                        message: _errorMessage(strings, state.error!),
                        retryLabel: strings.retry,
                        onRetry: notifier.retry,
                        variant: ErrorRetryVariant.compact,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                ],
                if (state.result != null)
                  SymptomResultCard(
                    result: state.result!,
                    strings: strings,
                    isArabic: isArabic,
                    onCheckAnother: notifier.reset,
                  )
                else
                  SymptomInputSection(
                    initialValue: state.symptomsInput,
                    strings: strings,
                    isSubmitting: state.isSubmitting,
                    showValidationError: state.showValidationError,
                    onChanged: notifier.updateInput,
                    onSubmit: notifier.submit,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _errorMessage(AppStrings strings, SymptomCheckErrorKind kind) {
  return switch (kind) {
    SymptomCheckErrorKind.timeout => strings.symptomCheckerTimeoutError,
    SymptomCheckErrorKind.serviceUnavailable =>
      strings.symptomCheckerServiceUnavailableError,
    SymptomCheckErrorKind.generic => strings.symptomCheckerGenericError,
  };
}
