import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/models/prescription_item_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/record_entry_model.dart';

class RecordEntryVisual {
  const RecordEntryVisual({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

String recordEntryTypeLabel(String type, AppStrings strings) {
  return switch (type) {
    'appointment' => strings.typeAppointment,
    'prescription' => strings.typePrescription,
    'record' => strings.typeRecord,
    _ => type,
  };
}

RecordEntryVisual recordEntryVisual(
  RecordEntryModel entry,
  AppStrings strings,
) {
  if (entry.entryType == 'appointment') {
    return RecordEntryVisual(
      label: strings.typeAppointment,
      icon: Icons.calendar_month_outlined,
      color: AppTheme.primary,
    );
  }
  if (entry.entryType == 'prescription') {
    return RecordEntryVisual(
      label: strings.typePrescription,
      icon: Icons.medication_outlined,
      color: AppTheme.accent,
    );
  }

  return switch (entry.recordType?.toLowerCase()) {
    'consultation' => RecordEntryVisual(
        label: strings.recordSubtypeConsultation,
        icon: Icons.person_search_outlined,
        color: AppTheme.secondary,
      ),
    'lab_result' => RecordEntryVisual(
        label: strings.recordSubtypeLabResult,
        icon: Icons.science_outlined,
        color: AppTheme.info,
      ),
    'diagnosis' => RecordEntryVisual(
        label: strings.recordSubtypeDiagnosis,
        icon: Icons.medical_information_outlined,
        color: AppTheme.primary,
      ),
    'imaging' => RecordEntryVisual(
        label: strings.recordSubtypeImaging,
        icon: Icons.image_search_outlined,
        color: AppTheme.violet,
      ),
    'procedure' => RecordEntryVisual(
        label: strings.recordSubtypeProcedure,
        icon: Icons.medical_services_outlined,
        color: AppTheme.warning,
      ),
    _ => RecordEntryVisual(
        label: strings.typeRecord,
        icon: Icons.description_outlined,
        color: AppTheme.secondary,
      ),
  };
}

String? recordEntryDate(RecordEntryModel entry) {
  return entry.entryDate ??
      switch (entry.entryType) {
        'appointment' => entry.scheduledDate,
        'prescription' => entry.prescriptionDate,
        _ => entry.createdAt,
      };
}

String? recordEntryIdentifier(RecordEntryModel entry) {
  final value = switch (entry.entryType) {
    'appointment' => entry.appointmentNumber,
    'prescription' => entry.prescriptionNumber,
    'record' => entry.recordNumber,
    _ => null,
  };
  return value?.trim().isNotEmpty == true ? value!.trim() : null;
}

String recordEntryTitle(
  RecordEntryModel entry,
  AppStrings strings,
  bool isArabic,
) {
  if (entry.entryType == 'appointment') {
    return _firstValue([
          entry.reasonForVisit,
          entry.specialty(isArabic),
        ]) ??
        strings.medicalAppointmentFallback;
  }
  if (entry.entryType == 'prescription') {
    final medicine = entry.items.isEmpty
        ? null
        : _medicationName(entry.items.first, isArabic);
    return _firstValue([
          medicine,
          entry.diagnosis,
          entry.prescriptionNumber,
        ]) ??
        strings.typePrescription;
  }
  return _firstValue([
        entry.diagnosis,
        entry.chiefComplaint,
      ]) ??
      recordEntryVisual(entry, strings).label;
}

String? recordEntryNotePreview(RecordEntryModel entry) {
  return switch (entry.entryType) {
    'appointment' => _trimmed(entry.reasonForVisit),
    'prescription' => _trimmed(entry.instructions),
    _ => _firstValue([entry.treatmentPlan, entry.chiefComplaint]),
  };
}

(String, Color)? recordStatusVisual(
  String? status,
  AppStrings strings, {
  String? entryType,
}) {
  if (status == null || status.trim().isEmpty) return null;
  return switch (status.toLowerCase()) {
    'scheduled' => (strings.statusScheduled, AppTheme.warning),
    'confirmed' => (strings.statusConfirmed, AppTheme.primary),
    'in_progress' => (strings.statusInProgress, AppTheme.info),
    'completed' => (
        entryType == 'appointment'
            ? strings.statusAppointmentCompleted
            : strings.statusCompleted,
        AppTheme.success,
      ),
    'cancelled' => (
        entryType == 'appointment'
            ? strings.statusAppointmentCancelled
            : strings.statusCancelled,
        AppTheme.danger,
      ),
    'no_show' => (strings.statusNoShow, AppTheme.danger),
    'active' => (strings.statusActive, AppTheme.success),
    'expired' => (strings.statusExpired, AppTheme.danger),
    _ => (status, AppTheme.info),
  };
}

void showRecordDetailSheet(
  BuildContext context,
  RecordEntryModel entry,
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
      return AnimatedPadding(
        duration: AppTheme.motionDuration(sheetContext, AppTheme.motionFast),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
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
                  return _RecordDetailContent(
                    entry: entry,
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

class _RecordDetailContent extends StatelessWidget {
  const _RecordDetailContent({
    required this.entry,
    required this.strings,
    required this.isArabic,
    required this.scrollController,
  });

  final RecordEntryModel entry;
  final AppStrings strings;
  final bool isArabic;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final visual = recordEntryVisual(entry, strings);
    final title = recordEntryTitle(entry, strings, isArabic);
    final identifier = recordEntryIdentifier(entry);
    final status = recordStatusVisual(
      entry.status,
      strings,
      entryType: entry.entryType,
    );
    final date = _formattedDate(recordEntryDate(entry), isArabic);
    final overviewFields = _overviewFields(date, status?.$1);
    final doctor = entry.doctorFullName(isArabic);
    final specialty = entry.specialty(isArabic);
    final vitals = entry.vitals?.entries
            .where((item) => _hasValue(item.value))
            .toList() ??
        const <MapEntry<String, dynamic>>[];

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
                  visual: visual,
                  title: title,
                  identifier: identifier,
                  date: date,
                  status: status,
                  closeLabel: strings.close,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
              const Divider(height: 1),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppTheme.spaceLg,
            AppTheme.spaceLg,
            AppTheme.spaceLg,
            AppTheme.space2xl,
          ),
          sliver: SliverList.list(
            children: [
              _DetailSection(
                title: strings.recordOverviewTitle,
                icon: Icons.info_outline_rounded,
                child: _DetailFieldGrid(fields: overviewFields),
              ),
              if (doctor != null || specialty != null) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailDoctor,
                  icon: Icons.medical_information_outlined,
                  child: _DetailFieldGrid(
                    fields: [
                      if (doctor != null)
                        _DetailFieldData(
                          label: strings.detailDoctor,
                          value: doctor,
                          icon: Icons.person_outline_rounded,
                        ),
                      if (specialty != null)
                        _DetailFieldData(
                          label: strings.detailSpecialty,
                          value: specialty,
                          icon: Icons.local_hospital_outlined,
                        ),
                    ],
                  ),
                ),
              ],
              if (_trimmed(entry.diagnosis) case final value?) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailDiagnosis,
                  icon: Icons.medical_information_outlined,
                  child: _DetailTextCard(value: value),
                ),
              ],
              if (_trimmed(entry.chiefComplaint) case final value?) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailChiefComplaint,
                  icon: Icons.healing_outlined,
                  child: _DetailTextCard(value: value),
                ),
              ],
              if (_trimmed(entry.reasonForVisit) case final value?) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailReason,
                  icon: Icons.notes_outlined,
                  child: _DetailTextCard(value: value),
                ),
              ],
              if (_trimmed(entry.treatmentPlan) case final value?) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailTreatmentPlan,
                  icon: Icons.fact_check_outlined,
                  child: _DetailTextCard(value: value),
                ),
              ],
              if (_trimmed(entry.instructions) case final value?) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailInstructions,
                  icon: Icons.list_alt_outlined,
                  child: _DetailTextCard(value: value),
                ),
              ],
              if (vitals.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.recordVitalsTitle,
                  icon: Icons.monitor_heart_outlined,
                  child: _DetailFieldGrid(
                    fields: [
                      for (final vital in vitals)
                        _DetailFieldData(
                          label: _humanizeKey(vital.key),
                          value: _displayValue(vital.value),
                          icon: Icons.favorite_border_rounded,
                          textDirection: TextDirection.ltr,
                        ),
                    ],
                  ),
                ),
              ],
              if (entry.entryType == 'prescription') ...[
                const SizedBox(height: AppTheme.spaceLg),
                _DetailSection(
                  title: strings.detailMedications,
                  icon: Icons.medication_liquid_outlined,
                  child: entry.items.isEmpty
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
                              index < entry.items.length;
                              index++
                            ) ...[
                              _MedicationCard(
                                item: entry.items[index],
                                index: index,
                                strings: strings,
                                isArabic: isArabic,
                              ),
                              if (index != entry.items.length - 1)
                                const SizedBox(height: AppTheme.spaceMd),
                            ],
                          ],
                        ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<_DetailFieldData> _overviewFields(String? date, String? statusLabel) {
    final identifier = recordEntryIdentifier(entry);
    final fields = <_DetailFieldData>[
      if (identifier != null)
        _DetailFieldData(
          label: switch (entry.entryType) {
            'appointment' => strings.appointmentNumberLabel,
            'prescription' => strings.detailPrescriptionNumber,
            _ => strings.recordNumberLabel,
          },
          value: identifier,
          icon: Icons.tag_rounded,
          textDirection: TextDirection.ltr,
        ),
      if (date != null)
        _DetailFieldData(
          label: strings.recordEntryDateLabel,
          value: date,
          icon: Icons.calendar_today_outlined,
          textDirection: TextDirection.ltr,
        ),
      _DetailFieldData(
        label: strings.detailType,
        value: recordEntryVisual(entry, strings).label,
        icon: Icons.category_outlined,
      ),
      if (statusLabel != null)
        _DetailFieldData(
          label: strings.recordStatusLabel,
          value: statusLabel,
          icon: Icons.verified_outlined,
        ),
      if (_trimmed(entry.startTime) case final value?)
        _DetailFieldData(
          label: strings.detailTime,
          value: formatTime(value),
          icon: Icons.schedule_outlined,
          textDirection: TextDirection.ltr,
        ),
      if (_trimmed(entry.appointmentType) case final value?)
        _DetailFieldData(
          label: strings.detailType,
          value: switch (value.toLowerCase()) {
            'telemedicine' => strings.appointmentTypeTelemedicine,
            'in_person' => strings.appointmentTypeInPerson,
            _ => value,
          },
          icon: Icons.health_and_safety_outlined,
        ),
      if (_trimmed(entry.validUntil) case final value?)
        _DetailFieldData(
          label: strings.detailValidUntil,
          value: _formattedDate(value, isArabic) ?? value,
          icon: Icons.event_available_outlined,
          textDirection: TextDirection.ltr,
        ),
      if (entry.entryType == 'prescription')
        _DetailFieldData(
          label: strings.detailMedications,
          value: strings.medicationCount(entry.items.length),
          icon: Icons.medication_outlined,
        ),
    ];
    return fields;
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.visual,
    required this.title,
    required this.identifier,
    required this.date,
    required this.status,
    required this.closeLabel,
    required this.onClose,
  });

  final RecordEntryVisual visual;
  final String title;
  final String? identifier;
  final String? date;
  final (String, Color)? status;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualIcon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Icon(visual.icon, color: visual.color, size: AppTheme.iconLg),
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          visual.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: visual.color,
            fontWeight: AppTheme.weightBold,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppTheme.weightExtraBold,
          ),
        ),
        if (identifier != null) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              identifier!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (date != null) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              date!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (status != null) ...[
          const SizedBox(height: AppTheme.spaceSm),
          StatusBadge(label: status!.$1, color: status!.$2),
        ],
      ],
    );

    return Semantics(
      container: true,
      label: [visual.label, title, ?identifier, ?date, ?status?.$1].join('. '),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < AppTheme.compactBreakpoint ||
              AppTheme.usesLargeText(context);
          final close = IconButton(
            tooltip: closeLabel,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [visualIcon, const Spacer(), close]),
                const SizedBox(height: AppTheme.spaceMd),
                heading,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              visualIcon,
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(child: heading),
              close,
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
        final width = (constraints.maxWidth -
                (AppTheme.spaceMd * (columns - 1))) /
            columns;
        return Wrap(
          spacing: AppTheme.spaceMd,
          runSpacing: AppTheme.spaceMd,
          children: [
            for (final field in fields)
              SizedBox(width: width, child: _DetailField(field: field)),
          ],
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final name = _medicationName(item, isArabic) ??
        strings.medicationFallbackName(index + 1);
    final fields = <_DetailFieldData>[
      if (_trimmed(item.dosage) case final value?)
        _DetailFieldData(
          label: strings.medicationDosage,
          value: value,
          icon: Icons.science_outlined,
          textDirection: TextDirection.ltr,
        ),
      if (_trimmed(item.frequency) case final value?)
        _DetailFieldData(
          label: strings.medicationFrequency,
          value: value,
          icon: Icons.repeat_rounded,
        ),
      if (_trimmed(item.duration) case final value?)
        _DetailFieldData(
          label: strings.medicationDuration,
          value: value,
          icon: Icons.timelapse_outlined,
        ),
      if (_trimmed(item.quantity) case final value?)
        _DetailFieldData(
          label: strings.medicationQuantity,
          value: value,
          icon: Icons.numbers_rounded,
          textDirection: TextDirection.ltr,
        ),
    ];

    return Semantics(
      container: true,
      label: name,
      child: Card(
        color: AppTheme.mutedSurfaceOf(context),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    color: AppTheme.accent,
                    size: AppTheme.iconMd,
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: Text(
                      name,
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
              if (_trimmed(item.instructions) case final value?) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _DetailTextCard(
                  label: strings.medicationInstructions,
                  value: value,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String? _formattedDate(String? value, bool isArabic) {
  final date = _trimmed(value);
  if (date == null) return null;
  try {
    return formatDate(
      parseDateOnly(date),
      localeCode: isArabic ? 'ar' : 'en',
    );
  } on FormatException {
    return date;
  }
}

String? _medicationName(PrescriptionItemModel item, bool isArabic) {
  return _firstValue(
    isArabic
        ? [item.medicationNameAr, item.medicationNameEn]
        : [item.medicationNameEn, item.medicationNameAr],
  );
}

String? _firstValue(Iterable<String?> values) {
  for (final value in values) {
    final result = _trimmed(value);
    if (result != null) return result;
  }
  return null;
}

String? _trimmed(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}

bool _hasValue(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

String _displayValue(Object? value) {
  if (value is Iterable) return value.join(', ');
  if (value is Map) {
    return value.entries.map((item) => '${item.key}: ${item.value}').join(', ');
  }
  return value.toString();
}

String _humanizeKey(String value) {
  if (value.isEmpty) return value;
  final words = value.replaceAll('_', ' ').trim();
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
