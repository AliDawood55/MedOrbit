import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';

/// Free-text symptom entry. Owns its own [TextEditingController], seeded once
/// from [initialValue] — matching `ProfileFormSection`'s pattern — so the
/// provider's `symptomsInput` echo-back on every keystroke never fights the
/// cursor position.
class SymptomInputSection extends StatefulWidget {
  const SymptomInputSection({
    super.key,
    required this.initialValue,
    required this.strings,
    required this.isSubmitting,
    required this.showValidationError,
    required this.onChanged,
    required this.onSubmit,
  });

  final String initialValue;
  final AppStrings strings;
  final bool isSubmitting;
  final bool showValidationError;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<SymptomInputSection> createState() => _SymptomInputSectionState();
}

class _SymptomInputSectionState extends State<SymptomInputSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.symptomInputLabel),
            AppTextField(
              label: strings.symptomInputLabel,
              hintText: strings.symptomInputHint,
              helperText: strings.symptomInputHelper,
              controller: _controller,
              keyboardType: TextInputType.multiline,
              minLines: 5,
              maxLines: 8,
              onChanged: widget.onChanged,
            ),
            if (widget.showValidationError) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message: strings.symptomCheckerErrorMinSymptoms,
                tone: InlineMessageTone.error,
              ),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            PrimaryButton(
              label: strings.symptomCheckerSubmit,
              isLoading: widget.isSubmitting,
              onPressed: widget.onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
