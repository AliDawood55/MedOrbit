import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/models/prescription_item_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/prescription_model.dart';

(String, Color) prescriptionStatusVisual(
  String status,
  AppStrings strings,
) {
  switch (status) {
    case 'active':
      return (strings.statusActive, AppTheme.success);
    case 'completed':
      return (strings.statusCompleted, AppTheme.success);
    case 'expired':
      return (strings.statusExpired, AppTheme.danger);
    case 'cancelled':
      return (strings.statusCancelled, AppTheme.danger);
    default:
      return (status, AppTheme.info);
  }
}

String prescriptionDisplayTitle(
  PrescriptionModel prescription,
  bool isArabic,
  AppStrings strings,
) {
  if (prescription.items.isNotEmpty) {
    final item = prescription.items.first;
    final name = isArabic
        ? item.medicationNameAr ?? item.medicationNameEn
        : item.medicationNameEn ?? item.medicationNameAr;
    if (name != null && name.trim().isNotEmpty) return name.trim();
  }
  if (prescription.diagnosis?.trim().isNotEmpty == true) {
    return prescription.diagnosis!.trim();
  }
  return prescription.prescriptionNumber.isNotEmpty
      ? prescription.prescriptionNumber
      : strings.prescriptionFallbackTitle;
}

void showPrescriptionDetailSheet(
  BuildContext context,
  PrescriptionModel prescription,
  AppStrings strings,
  bool isArabic,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return AnimatedPadding(
        duration: AppTheme.motionDuration(
          sheetContext,
          AppTheme.motionFast,
        ),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTheme.maxPhoneContentWidth,
            ),
            child: Material(
              color: Theme.of(sheetContext).colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusXl),
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.82,
                minChildSize: 0.42,
                maxChildSize: 0.96,
                expand: false,
                builder: (context, scrollController) {
                  return _PrescriptionDetailContent(
                    prescription: prescription,
                    strings: strings,
                    isArabic: isArabic,
                    scrollController: scrollController,
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PrescriptionDetailContent extends StatelessWidget {
  const _PrescriptionDetailContent({
    required this.prescription,
    required this.strings,
    required this.isArabic,
    required this.scrollController,
  });

  final PrescriptionModel prescription;
  final AppStrings strings;
  final bool isArabic;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final localeCode = isArabic ? 'ar' : 'en';
    final title = prescriptionDisplayTitle(
      prescription,
      isArabic,
      strings,
    );
    final issuedDate = formatDate(
      parseDateOnly(prescription.prescriptionDate),
      localeCode: localeCode,
    );
    final validUntil = prescription.validUntil == null
        ? null
        : formatDate(
            parseDateOnly(prescription.validUntil!),
            localeCode: localeCode,
          );
    final (statusLabel, statusColor) =
        prescriptionStatusVisual(prescription.status, strings);

    return CustomScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.spaceSm),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppTheme.spaceLg,
                  AppTheme.spaceLg,
                  AppTheme.spaceSm,
                  AppTheme.spaceLg,
                ),
                child: _DetailHeader(
                  title: title,
                  prescriptionNumber: prescription.prescriptionNumber,
                  issuedDate: issuedDate,
                  statusLabel: statusLabel,
                  statusColor: statusColor,
                  strings: strings,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
              const Divider(),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppTheme.spaceLg,
            AppTheme.spaceMd,
            AppTheme.spaceLg,
            AppTheme.space2xl,
          ),
          sliver: SliverList.list(
            children: [
              _DetailSection(
                title: strings.prescriptionDetailsTitle,
                icon: Icons.info_outline_rounded,
                child: _DetailFieldGrid(
                  fields: [
                    _DetailFieldData(
                      label: strings.issuedDateLabel,
                      value: issuedDate,
                      icon: Icons.calendar_today_outlined,
                      textDirection: TextDirection.ltr,
                    ),
                    if (validUntil != null)
                      _DetailFieldData(
                        label: strings.detailValidUntil,
                        value: validUntil,
                        icon: Icons.event_available_outlined,
                        textDirection: TextDirection.ltr,
                      ),
                    _DetailFieldData(
                      label: strings.prescriptionStatusFilterLabel,
                      value: statusLabel,
                      icon: Icons.verified_outlined,
                    ),
                    _DetailFieldData(
                      label: strings.detailMedications,
                      value: strings.medicationCount(
                        prescription.items.length,
                      ),
                      icon: Icons.medication_outlined,
                    ),
                  ],
                ),
              ),
              if (prescription.diagnosis?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailDiagnosis,
                  icon: Icons.medical_information_outlined,
                  child: _DetailTextCard(
                    value: prescription.diagnosis!.trim(),
                  ),
                ),
              ],
              if (prescription.instructions?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailInstructions,
                  icon: Icons.list_alt_outlined,
                  child: _DetailTextCard(
                    value: prescription.instructions!.trim(),
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.spaceLg),
              _DetailSection(
                title: strings.detailMedications,
                icon: Icons.medication_liquid_outlined,
                child: prescription.items.isEmpty
                    ? EmptyState(
                        icon: Icons.medication_outlined,
                        title: strings.noMedicationItemsTitle,
                        hint: strings.noMedicationItemsHint,
                        variant: EmptyStateVariant.compact,
                      )
                    : Column(
                        children: [
                          for (
                            var index = 0;
                            index < prescription.items.length;
                            index++
                          ) ...[
                            _MedicationCard(
                              item: prescription.items[index],
                              index: index,
                              strings: strings,
                              isArabic: isArabic,
                            ),
                            if (index != prescription.items.length - 1)
                              const SizedBox(height: AppTheme.spaceMd),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.prescriptionNumber,
    required this.issuedDate,
    required this.statusLabel,
    required this.statusColor,
    required this.strings,
    required this.onClose,
  });

  final String title;
  final String prescriptionNumber;
  final String issuedDate;
  final String statusLabel;
  final Color statusColor;
  final AppStrings strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: const Icon(
        Icons.medication_outlined,
        color: Colors.white,
        size: AppTheme.iconLg,
      ),
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppTheme.weightExtraBold,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            prescriptionNumber,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            issuedDate,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        StatusBadge(label: statusLabel, color: statusColor),
      ],
    );

    return Semantics(
      container: true,
      label: strings.prescriptionNumberValue(prescriptionNumber),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < AppTheme.compactBreakpoint ||
              AppTheme.usesLargeText(context);
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const Spacer(),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceMd),
                heading,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(child: heading),
              IconButton(
                tooltip: strings.close,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: AppTheme.iconMd, color: AppTheme.primary),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: AppTheme.weightBold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        child,
      ],
    );
  }
}

class _DetailFieldGrid extends StatelessWidget {
  const _DetailFieldGrid({required this.fields});

  final List<_DetailFieldData> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = AppTheme.usesLargeText(context);
        final columns = constraints.maxWidth >= AppTheme.wideBreakpoint &&
                !largeText
            ? 2
            : 1;
        final gap = AppTheme.spaceMd;
        final width =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: fields
              .map(
                (field) => SizedBox(
                  width: width,
                  child: _DetailField(field: field),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DetailFieldData {
  const _DetailFieldData({
    required this.label,
    required this.value,
    required this.icon,
    this.textDirection,
  });

  final String label;
  final String value;
  final IconData icon;
  final TextDirection? textDirection;
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.field});

  final _DetailFieldData field;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: AppTheme.mutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(field.icon, size: AppTheme.iconSm, color: AppTheme.primary),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Directionality(
                  textDirection:
                      field.textDirection ?? Directionality.of(context),
                  child: Text(
                    field.value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTextCard extends StatelessWidget {
  const _DetailTextCard({required this.value, this.label});

  final String value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: AppTheme.mutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppTheme.spaceXs),
          ],
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.item,
    required this.index,
    required this.strings,
    required this.isArabic,
  });

  final PrescriptionItemModel item;
  final int index;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final name = isArabic
        ? item.medicationNameAr ?? item.medicationNameEn
        : item.medicationNameEn ?? item.medicationNameAr;
    final displayName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : strings.medicationFallbackName(index + 1);
    final fields = [
      if (item.dosage?.trim().isNotEmpty == true)
        _DetailFieldData(
          label: strings.medicationDosage,
          value: item.dosage!.trim(),
          icon: Icons.science_outlined,
          textDirection: TextDirection.ltr,
        ),
      if (item.frequency?.trim().isNotEmpty == true)
        _DetailFieldData(
          label: strings.medicationFrequency,
          value: item.frequency!.trim(),
          icon: Icons.repeat_rounded,
        ),
      if (item.duration?.trim().isNotEmpty == true)
        _DetailFieldData(
          label: strings.medicationDuration,
          value: item.duration!.trim(),
          icon: Icons.timelapse_outlined,
        ),
      if (item.quantity?.trim().isNotEmpty == true)
        _DetailFieldData(
          label: strings.medicationQuantity,
          value: item.quantity!.trim(),
          icon: Icons.numbers_rounded,
          textDirection: TextDirection.ltr,
        ),
    ];

    return Semantics(
      container: true,
      label: displayName,
      child: Card(
        color: AppTheme.mutedSurfaceOf(context),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: const Icon(
                      Icons.medication_rounded,
                      color: AppTheme.primary,
                      size: AppTheme.iconMd,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: AppTheme.weightBold,
                          ),
                    ),
                  ),
                ],
              ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _DetailFieldGrid(fields: fields),
              ],
              if (item.instructions?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _DetailTextCard(
                  label: strings.medicationInstructions,
                  value: item.instructions!.trim(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
