import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../providers/drug_checker_provider.dart';
import '../widgets/drug_disclaimer_card.dart';
import '../widgets/drug_input_section.dart';
import '../widgets/drug_result_card.dart';

class DrugCheckerScreen extends ConsumerWidget {
  const DrugCheckerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(drugCheckerControllerProvider);
    final notifier = ref.read(drugCheckerControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.drugCheckerTitle)),
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
                  title: strings.drugCheckerTitle,
                  subtitle: strings.drugCheckerSubtitle,
                  icon: Icons.medication_liquid_outlined,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                DrugDisclaimerCard(strings: strings),
                const SizedBox(height: AppTheme.spaceLg),
                if (state.error != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: ErrorRetryState(
                        title: strings.drugCheckerLoadError,
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
                  DrugResultCard(
                    result: state.result!,
                    strings: strings,
                    isArabic: isArabic,
                    onCheckAnother: notifier.reset,
                  )
                else
                  DrugInputSection(
                    initialValue: state.medicationsInput,
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

String _errorMessage(AppStrings strings, DrugCheckErrorKind kind) {
  return switch (kind) {
    DrugCheckErrorKind.timeout => strings.drugCheckerTimeoutError,
    DrugCheckErrorKind.serviceUnavailable =>
      strings.drugCheckerServiceUnavailableError,
    DrugCheckErrorKind.generic => strings.drugCheckerGenericError,
  };
}
