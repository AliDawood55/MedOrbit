import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';

/// Free-text medication entry. Owns its own [TextEditingController], seeded
/// once from [initialValue] — matching `SymptomInputSection`'s pattern — so
/// the provider's `medicationsInput` echo-back on every keystroke never
/// fights the cursor position.
class DrugInputSection extends StatefulWidget {
  const DrugInputSection({
    super.key,
    required this.initialValue,
    required this.strings,
    required this.isSubmitting,
    required this.showValidationError,
    required this.isArabic,
    required this.onChanged,
    required this.onSubmit,
  });

  final String initialValue;
  final AppStrings strings;
  final bool isSubmitting;
  final bool showValidationError;
  final bool isArabic;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<DrugInputSection> createState() => _DrugInputSectionState();
}

class _DrugInputSectionState extends State<DrugInputSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  static const _commonMedications = [
    (en: 'Paracetamol', ar: 'باراسيتامول'),
    (en: 'Aspirin', ar: 'أسبرين'),
    (en: 'Warfarin', ar: 'وارفارين'),
    (en: 'Metformin', ar: 'ميتفورمين'),
    (en: 'Omeprazole', ar: 'أوميبرازول'),
    (en: 'Amlodipine', ar: 'أملوديبين'),
    (en: 'Diclofenac', ar: 'ديكلوفيناك'),
    (en: 'Azithromycin', ar: 'أزيثرومايسين'),
  ];

  void _addSuggestion(String medication) {
    final existing = _controller.text
        .split(RegExp(r'[\n,]+'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (!existing.add(medication.toLowerCase())) return;

    final next = _controller.text.trim().isEmpty
        ? medication
        : '${_controller.text.trim()}\n$medication';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged(next);
  }

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
            SectionHeader(title: strings.drugInputLabel),
            AppTextField(
              label: strings.drugInputLabel,
              hintText: strings.drugInputHint,
              helperText: strings.drugInputHelper,
              controller: _controller,
              keyboardType: TextInputType.multiline,
              minLines: 5,
              maxLines: 8,
              onChanged: widget.onChanged,
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Text(
              strings.drugCommonMedications,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                for (final medication in _commonMedications)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(widget.isArabic ? medication.ar : medication.en),
                    onPressed: () => _addSuggestion(
                      widget.isArabic ? medication.ar : medication.en,
                    ),
                  ),
              ],
            ),
            if (widget.showValidationError) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message: strings.drugCheckerErrorMinMeds,
                tone: InlineMessageTone.error,
              ),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            PrimaryButton(
              label: strings.drugCheckerSubmit,
              isLoading: widget.isSubmitting,
              onPressed: widget.onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
