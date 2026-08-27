import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/clinic_models.dart';
import 'clinic_result_card.dart';

class ClinicDetailSections extends ConsumerWidget {
  const ClinicDetailSections({
    super.key,
    required this.clinic,
    required this.doctors,
  });

  final Clinic clinic;
  final List<ClinicDoctorSummary> doctors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final direction = Directionality.of(context);
    final (verificationLabel, verificationColor) = clinicVerificationVisual(clinic, strings);
    final needsDisclaimer = clinic.verificationStatus != ClinicVerificationStatus.verified;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppTheme.spaceSm,
                  runSpacing: AppTheme.spaceSm,
                  children: [
                    StatusBadge(label: clinicTypeLabel(clinic.type, strings), color: Theme.of(context).colorScheme.primary),
                    StatusBadge(label: verificationLabel, color: verificationColor),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceMd),
                Text(
                  clinicDisplayName(clinic, direction, strings),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (needsDisclaimer) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  InlineMessage(
                    message: strings.clinicVerificationDisclaimer,
                    tone: InlineMessageTone.warning,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _ContactSection(clinic: clinic, strings: strings),
        const SizedBox(height: AppTheme.spaceLg),
        _ServicesSection(title: strings.clinicServicesTitle, values: clinic.services, strings: strings),
        const SizedBox(height: AppTheme.spaceLg),
        _ServicesSection(title: strings.clinicInsuranceTitle, values: clinic.insuranceAccepted, strings: strings),
        const SizedBox(height: AppTheme.spaceLg),
        _HoursSection(hours: clinic.operatingHours, strings: strings),
        const SizedBox(height: AppTheme.spaceLg),
        _DoctorsSection(doctors: doctors, strings: strings),
      ],
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.clinic, required this.strings});

  final Clinic clinic;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final address = clinicDisplayAddress(clinic, direction);
    final city = _clean(clinic.city);
    final region = _clean(clinic.region);
    final phone = _clean(clinic.phone);
    final email = _clean(clinic.email);
    final website = _clean(clinic.website);
    final rows = [
      if (address != null) _DetailRow(Icons.place_outlined, strings.addressLabel, address),
      if (city != null) _DetailRow(Icons.location_city_outlined, strings.cityLabel, city),
      if (region != null) _DetailRow(Icons.map_outlined, strings.clinicRegionLabel, region),
      if (phone != null) _DetailRow(Icons.phone_outlined, strings.clinicPhoneLabel, phone, ltr: true),
      if (email != null) _DetailRow(Icons.email_outlined, strings.emailLabel, email, ltr: true),
      if (website != null) _DetailRow(Icons.language_outlined, strings.clinicWebsiteLabel, website, ltr: true),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.clinicContactSectionTitle),
            if (rows.isEmpty)
              Text(
                strings.clinicNoContactDetails,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...rows,
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              strings.clinicActionsDisabledNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({required this.title, required this.values, required this.strings});

  final String title;
  final List<String> values;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: title),
            if (values.isEmpty)
              Text(strings.clinicNoneListed, style: Theme.of(context).textTheme.bodyMedium)
            else
              Wrap(
                spacing: AppTheme.spaceXs,
                runSpacing: AppTheme.spaceXs,
                children: values.map((value) => Chip(label: Text(value))).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _HoursSection extends StatelessWidget {
  const _HoursSection({required this.hours, required this.strings});

  final ClinicOperatingHours? hours;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final days = hours?.days.entries.toList() ?? const <MapEntry<String, ClinicDayHours>>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.clinicHoursTitle,
              subtitle: strings.clinicHoursSubtitle,
            ),
            if (days.isEmpty)
              Text(strings.clinicNoHoursListed, style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final entry in days)
                _DetailRow(
                  Icons.schedule_outlined,
                  strings.weekdayLabel(entry.key),
                  entry.value.isClosed == true
                      ? strings.clinicHoursClosed
                      : [entry.value.open, entry.value.close].whereType<String>().join('–'),
                  ltr: true,
                ),
          ],
        ),
      ),
    );
  }
}

class _DoctorsSection extends StatelessWidget {
  const _DoctorsSection({required this.doctors, required this.strings});

  final List<ClinicDoctorSummary> doctors;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.clinicDoctorsSectionTitle),
            if (doctors.isEmpty)
              Text(strings.clinicNoDoctorsListed, style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final doctor in doctors) ...[
                _DoctorTile(doctor: doctor, direction: direction, strings: strings),
                if (doctor != doctors.last) const Divider(),
              ],
          ],
        ),
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({required this.doctor, required this.direction, required this.strings});

  final ClinicDoctorSummary doctor;
  final TextDirection direction;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final rtl = direction == TextDirection.rtl;
    final accepting = doctor.isAcceptingPatients;
    final rating = doctor.averageRating;
    final name = [
      rtl ? doctor.firstNameAr ?? doctor.firstNameEn : doctor.firstNameEn ?? doctor.firstNameAr,
      rtl ? doctor.lastNameAr ?? doctor.lastNameEn : doctor.lastNameEn ?? doctor.lastNameAr,
    ].whereType<String>().join(' ').trim();
    final specialty = rtl ? doctor.specialtyAr ?? doctor.specialtyEn : doctor.specialtyEn ?? doctor.specialtyAr;
    return ListTile(
      key: ValueKey('clinic-detail-doctor-${doctor.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
      title: Text(name.isEmpty ? strings.doctorFallbackName : name),
      subtitle: Text([
        if (_clean(specialty) != null) specialty,
        if (rating != null) strings.clinicDoctorRatingLabel(rating.toStringAsFixed(1)),
        if (accepting != null) accepting ? strings.doctorAcceptingPatients : strings.doctorNotAcceptingPatients,
      ].whereType<String>().join(' · ')),
      trailing: Icon(AppTheme.directionalForwardIconOf(context)),
      onTap: doctor.id.isEmpty ? null : () => context.push(RoutePaths.doctorDetailPath(doctor.id)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value, {this.ltr = false});

  final IconData icon;
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.iconMd, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Directionality(
                  textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
                  child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
