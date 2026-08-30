import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../discovery/models/doctor_models.dart';

/// Required specialty picker for the doctor application form.
///
/// A [FormField] so `Form.validate()` and autovalidation work like every other
/// field. The value is the backend `specialty_id`; an empty string means "not
/// selected". Selection happens in a mobile-friendly bottom sheet that stays
/// readable with long Arabic/English names, RTL, and large text.
class SpecialtyField extends FormField<String> {
  SpecialtyField({
    super.key,
    required List<Specialty> specialties,
    required bool isArabic,
    required AppStrings strings,
    required ValueChanged<String?> onChanged,
    String? initialValue,
    bool enabled = true,
    super.autovalidateMode,
  }) : super(
          initialValue: initialValue ?? '',
          validator: (value) =>
              value == null || value.isEmpty ? strings.doctorApplicationSpecialtyRequired : null,
          builder: (state) {
            final theme = Theme.of(state.context);
            final selected = specialties
                .where((item) => item.id != null && item.id == state.value)
                .cast<Specialty?>()
                .firstWhere((item) => item != null, orElse: () => null);
            final hasError = state.hasError;

            Future<void> open() async {
              if (!enabled) return;
              FocusScope.of(state.context).unfocus();
              final picked = await showModalBottomSheet<String>(
                context: state.context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (sheetContext) => _SpecialtySheet(
                  specialties: specialties,
                  isArabic: isArabic,
                  strings: strings,
                  selectedId: state.value,
                ),
              );
              if (picked != null) {
                state.didChange(picked);
                onChanged(picked);
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  label: strings.doctorApplicationSpecialtyLabel,
                  value: selected?.label(isArabic) ?? strings.doctorApplicationSpecialtySelect,
                  child: InkWell(
                    key: const ValueKey('doctor-application-specialty-field'),
                    onTap: enabled ? open : null,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: InputDecorator(
                      isEmpty: selected == null,
                      decoration: InputDecoration(
                        labelText: strings.doctorApplicationSpecialtyLabel,
                        hintText: strings.doctorApplicationSpecialtySelect,
                        errorText: hasError ? state.errorText : null,
                        prefixIcon: const Icon(Icons.medical_services_outlined, size: AppTheme.iconMd),
                        suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                        constraints: const BoxConstraints(minHeight: AppTheme.minTouchTarget),
                        enabled: enabled,
                      ),
                      child: selected == null
                          ? null
                          : Text(
                              selected.label(isArabic),
                              style: theme.textTheme.bodyLarge,
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
}

class _SpecialtySheet extends StatelessWidget {
  const _SpecialtySheet({
    required this.specialties,
    required this.isArabic,
    required this.strings,
    required this.selectedId,
  });

  final List<Specialty> specialties;
  final bool isArabic;
  final AppStrings strings;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spaceLg,
                AppTheme.spaceXs,
                AppTheme.spaceLg,
                AppTheme.spaceSm,
              ),
              child: Text(
                strings.doctorApplicationSpecialtySelect,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppTheme.weightBold,
                ),
              ),
            ),
            if (specialties.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: Text(strings.doctorApplicationSpecialtyEmpty),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
                  itemCount: specialties.length,
                  itemBuilder: (context, index) {
                    final specialty = specialties[index];
                    final id = specialty.id!;
                    final isSelected = id == selectedId;
                    return ListTile(
                      key: ValueKey('specialty-option-$id'),
                      selected: isSelected,
                      title: Text(specialty.label(isArabic)),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                          : null,
                      onTap: () => Navigator.of(context).pop(id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
