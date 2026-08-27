import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/doctor_models.dart';

class DoctorResultCard extends ConsumerWidget {
  const DoctorResultCard({super.key, required this.doctor, this.onTap});

  final Doctor doctor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final direction = Directionality.of(context);
    final name = doctorDisplayName(doctor, direction, strings);
    final specialty = doctorDisplaySpecialty(doctor, direction);
    final clinic = doctor.clinics.isEmpty ? null : doctor.clinics.first;
    final values = <Widget>[
      if (specialty != null) _Fact(icon: Icons.medical_services_outlined, value: specialty),
      if (doctor.yearsOfExperience != null)
        Directionality(textDirection: TextDirection.ltr, child: _Fact(icon: Icons.work_outline_rounded, value: strings.yearsExperienceValue(doctor.yearsOfExperience!))),
      if (doctor.averageRating != null)
        Directionality(textDirection: TextDirection.ltr, child: _Fact(icon: Icons.star_rounded, value: '${doctor.averageRating!.toStringAsFixed(1)}${doctor.totalRatings == null ? '' : ' (${doctor.totalRatings})'}')),
      if (doctor.consultationFee != null)
        Directionality(textDirection: TextDirection.ltr, child: _Fact(icon: Icons.payments_outlined, value: strings.consultationFeeValue(doctor.consultationFee!.toStringAsFixed(0)))),
      if (doctor.consultationDuration != null)
        Directionality(textDirection: TextDirection.ltr, child: _Fact(icon: Icons.schedule_outlined, value: strings.consultationDurationValue(doctor.consultationDuration!))),
    ];
    final tap = onTap ?? () => context.push(RoutePaths.doctorDetailPath(doctor.id));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('doctor-card-${doctor.id}'),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                children: [
                  StatusBadge(
                    label: doctor.isAcceptingPatients == true ? strings.doctorAcceptingPatients : strings.doctorAvailabilityNotConfirmed,
                    color: doctor.isAcceptingPatients == true ? AppTheme.success : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightExtraBold)),
              if (values.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spaceSm),
                Wrap(spacing: AppTheme.spaceMd, runSpacing: AppTheme.spaceXs, children: values),
              ],
              if (clinic != null) ...[
                const SizedBox(height: AppTheme.spaceSm),
                _Fact(icon: Icons.local_hospital_outlined, value: clinicDisplayName(clinic, direction, strings)),
              ],
              const SizedBox(height: AppTheme.spaceSm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: tap,
                  icon: Icon(AppTheme.directionalForwardIconOf(context), size: AppTheme.iconSm),
                  iconAlignment: IconAlignment.end,
                  label: Text(strings.discoveryDetailsAction),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value});
  final IconData icon;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: AppTheme.iconSm), const SizedBox(width: AppTheme.spaceXs), Flexible(child: Text(value))],
      );
}

/// [strings] is optional so existing call sites outside `discovery/` (e.g.
/// the appointments booking wizard, frozen for this slice) keep compiling
/// and keep their original English fallback text unchanged. Discovery call
/// sites pass [strings] explicitly to get a localized fallback.
String doctorDisplayName(Doctor doctor, TextDirection direction, [AppStrings? strings]) {
  final rtl = direction == TextDirection.rtl;
  final first = rtl ? doctor.firstNameAr ?? doctor.firstNameEn : doctor.firstNameEn ?? doctor.firstNameAr;
  final last = rtl ? doctor.lastNameAr ?? doctor.lastNameEn : doctor.lastNameEn ?? doctor.lastNameAr;
  final name = [first, last].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ').trim();
  return name.isEmpty ? (strings?.doctorFallbackName ?? 'Doctor') : name;
}

String? doctorDisplaySpecialty(Doctor doctor, TextDirection direction) {
  final rtl = direction == TextDirection.rtl;
  final value = rtl
      ? doctor.specialtyNameAr ?? doctor.specialtyAr ?? doctor.specialtyNameEn ?? doctor.specialtyEn
      : doctor.specialtyNameEn ?? doctor.specialtyEn ?? doctor.specialtyNameAr ?? doctor.specialtyAr;
  return value?.trim().isEmpty == true ? null : value;
}

String clinicDisplayName(DoctorClinicSummary clinic, TextDirection direction, [AppStrings? strings]) {
  final value = direction == TextDirection.rtl ? clinic.nameAr ?? clinic.nameEn : clinic.nameEn ?? clinic.nameAr;
  return value?.trim().isNotEmpty == true ? value!.trim() : (strings?.clinicFallbackName ?? 'Clinic');
}
