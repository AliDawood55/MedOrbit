import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/doctor_models.dart';
import 'clinic_mini_map.dart';
import 'doctor_result_card.dart';

class DoctorDetailSections extends StatelessWidget {
  const DoctorDetailSections({super.key, required this.doctor, required this.clinics, required this.reviews});
  final Doctor doctor; final List<DoctorClinicSummary> clinics; final List<DoctorReview> reviews;
  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final bio = direction == TextDirection.rtl ? doctor.professionalBioAr ?? doctor.professionalBioEn : doctor.professionalBioEn ?? doctor.professionalBioAr;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StatusBadge(label: doctor.isAcceptingPatients == true ? 'Accepting patients' : 'Availability not confirmed', color: doctor.isAcceptingPatients == true ? AppTheme.success : Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: AppTheme.spaceMd), Text(doctorDisplayName(doctor, direction), style: Theme.of(context).textTheme.headlineSmall),
        if (doctorDisplaySpecialty(doctor, direction) != null) ...[const SizedBox(height: AppTheme.spaceXs), Text(doctorDisplaySpecialty(doctor, direction)!, style: Theme.of(context).textTheme.titleMedium)],
        if (bio?.trim().isNotEmpty == true) ...[const SizedBox(height: AppTheme.spaceMd), Text(bio!)],
      ]))),
      const SizedBox(height: AppTheme.spaceLg),
      _InfoSection(doctor: doctor), const SizedBox(height: AppTheme.spaceLg),
      _ListSection(title: 'Education', values: doctor.education, empty: 'No education details are listed.'), const SizedBox(height: AppTheme.spaceLg),
      _ListSection(title: 'Certifications', values: doctor.certifications, empty: 'No certifications are listed.'), const SizedBox(height: AppTheme.spaceLg),
      _ClinicsSection(clinics: clinics), const SizedBox(height: AppTheme.spaceLg),
      _ReviewsSection(reviews: reviews),
    ]);
  }
}

class _InfoSection extends StatelessWidget { const _InfoSection({required this.doctor}); final Doctor doctor;
  @override Widget build(BuildContext context) { final rows = <String>[
    if (doctor.yearsOfExperience != null) 'Experience: ${doctor.yearsOfExperience} years',
    if (doctor.consultationFee != null) 'Consultation fee: ${doctor.consultationFee!.toStringAsFixed(0)} ILS',
    if (doctor.consultationDuration != null) 'Consultation duration: ${doctor.consultationDuration} min',
    if (doctor.averageRating != null) 'Rating: ${doctor.averageRating!.toStringAsFixed(1)}${doctor.totalRatings == null ? '' : ' (${doctor.totalRatings} ratings)'}',
    if (doctor.medicalLicenseNumber?.trim().isNotEmpty == true) 'Medical license: ${doctor.medicalLicenseNumber}',
    if (doctor.email?.trim().isNotEmpty == true) 'Email: ${doctor.email}',
  ]; return Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader(title: 'Professional details'), if (rows.isEmpty) const Text('No additional professional details are listed.') else for (final row in rows) Padding(padding: const EdgeInsets.only(bottom: AppTheme.spaceSm), child: Text(row))]))); }
}
class _ListSection extends StatelessWidget { const _ListSection({required this.title, required this.values, required this.empty}); final String title, empty; final List<String> values;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SectionHeader(title: title), if (values.isEmpty) Text(empty) else for (final value in values) Padding(padding: const EdgeInsets.only(bottom: AppTheme.spaceSm), child: Text(value))]))); }
class _ClinicsSection extends StatelessWidget { const _ClinicsSection({required this.clinics}); final List<DoctorClinicSummary> clinics;
  @override Widget build(BuildContext context) { final direction = Directionality.of(context); return Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader(title: 'Associated clinics'), if (clinics.isEmpty) const Text('No associated clinics are listed.') else ...[for (final clinic in clinics) ListTile(key: ValueKey('doctor-clinic-${clinic.id}'), contentPadding: EdgeInsets.zero, title: Text(clinicDisplayName(clinic, direction)), subtitle: Text([if ((direction == TextDirection.rtl ? clinic.addressAr ?? clinic.addressEn : clinic.addressEn ?? clinic.addressAr)?.trim().isNotEmpty == true) direction == TextDirection.rtl ? clinic.addressAr ?? clinic.addressEn : clinic.addressEn ?? clinic.addressAr, if (clinic.city?.trim().isNotEmpty == true) clinic.city, if (clinic.region?.trim().isNotEmpty == true) clinic.region].whereType<String>().join(' · ')), trailing: Icon(AppTheme.directionalForwardIconOf(context)), onTap: () => context.push(RoutePaths.clinicDetailPath(clinic.id))), const SizedBox(height: AppTheme.spaceSm), ClinicMiniMap(clinics: clinics)] ]))); }
}
class _ReviewsSection extends StatelessWidget { const _ReviewsSection({required this.reviews}); final List<DoctorReview> reviews;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader(title: 'Reviews'), if (reviews.isEmpty) const Text('No reviews are listed.') else for (final review in reviews) ListTile(contentPadding: EdgeInsets.zero, leading: review.rating == null ? null : Text(review.rating!.toStringAsFixed(1)), title: review.comment?.trim().isNotEmpty == true ? Text(review.comment!) : const Text('No written comment'), subtitle: review.createdAt == null ? null : Text(review.createdAt!.toLocal().toString().split(' ').first))]))); }
