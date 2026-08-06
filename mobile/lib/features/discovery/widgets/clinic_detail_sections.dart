import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/clinic_models.dart';
import 'clinic_result_card.dart';

class ClinicDetailSections extends StatelessWidget {
  const ClinicDetailSections({
    super.key,
    required this.clinic,
    required this.doctors,
  });

  final Clinic clinic;
  final List<ClinicDoctorSummary> doctors;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final (verificationLabel, verificationColor) = clinicVerificationVisual(clinic);
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
                    StatusBadge(label: clinicTypeLabel(clinic.type), color: Theme.of(context).colorScheme.primary),
                    StatusBadge(label: verificationLabel, color: verificationColor),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceMd),
                Text(
                  clinicDisplayName(clinic, direction),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (needsDisclaimer) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  const InlineMessage(
                    message: 'Hours and facility details may not be verified. Contact the facility before visiting.',
                    tone: InlineMessageTone.warning,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _ContactSection(clinic: clinic),
        const SizedBox(height: AppTheme.spaceLg),
        _ServicesSection(title: 'Services', values: clinic.services),
        const SizedBox(height: AppTheme.spaceLg),
        _ServicesSection(title: 'Insurance accepted', values: clinic.insuranceAccepted),
        const SizedBox(height: AppTheme.spaceLg),
        _HoursSection(hours: clinic.operatingHours),
        const SizedBox(height: AppTheme.spaceLg),
        _DoctorsSection(doctors: doctors),
      ],
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.clinic});

  final Clinic clinic;

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
      if (address != null) _DetailRow(Icons.place_outlined, 'Address', address),
      if (city != null) _DetailRow(Icons.location_city_outlined, 'City', city),
      if (region != null) _DetailRow(Icons.map_outlined, 'Region', region),
      if (phone != null) _DetailRow(Icons.phone_outlined, 'Phone', phone, ltr: true),
      if (email != null) _DetailRow(Icons.email_outlined, 'Email', email, ltr: true),
      if (website != null) _DetailRow(Icons.language_outlined, 'Website', website, ltr: true),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Contact and location'),
            if (rows.isEmpty)
              Text(
                'No contact details are listed.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...rows,
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              'Phone and website actions are not enabled in this phase.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({required this.title, required this.values});

  final String title;
  final List<String> values;

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
              Text('None listed.', style: Theme.of(context).textTheme.bodyMedium)
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
  const _HoursSection({required this.hours});

  final ClinicOperatingHours? hours;

  @override
  Widget build(BuildContext context) {
    final days = hours?.days.entries.toList() ?? const <MapEntry<String, ClinicDayHours>>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Listed hours',
              subtitle: 'These are backend-listed hours. Open-now status is not calculated.',
            ),
            if (days.isEmpty)
              Text('No operating hours are listed.', style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final entry in days)
                _DetailRow(
                  Icons.schedule_outlined,
                  entry.key,
                  entry.value.isClosed == true
                      ? 'Closed'
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
  const _DoctorsSection({required this.doctors});

  final List<ClinicDoctorSummary> doctors;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Doctors at this facility'),
            if (doctors.isEmpty)
              Text('No doctors are listed for this facility.', style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final doctor in doctors) ...[
                _DoctorTile(doctor: doctor, direction: direction),
                if (doctor != doctors.last) const Divider(),
              ],
          ],
        ),
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({required this.doctor, required this.direction});

  final ClinicDoctorSummary doctor;
  final TextDirection direction;

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
      title: Text(name.isEmpty ? 'Doctor' : name),
      subtitle: Text([
        if (_clean(specialty) != null) specialty,
        if (rating != null) 'Rating ${rating.toStringAsFixed(1)}',
        if (accepting != null) accepting ? 'Accepting patients' : 'Not accepting patients',
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
