import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/doctor_models.dart';
import 'clinic_mini_map.dart';
import 'doctor_result_card.dart';

class DoctorDetailSections extends ConsumerWidget {
  const DoctorDetailSections({
    super.key,
    required this.doctor,
    required this.clinics,
    required this.reviews,
  });
  final Doctor doctor;
  final List<DoctorClinicSummary> clinics;
  final List<DoctorReview> reviews;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final direction = Directionality.of(context);
    final bio =
        doctor.professionalBio ??
        (direction == TextDirection.rtl
            ? doctor.professionalBioAr ?? doctor.professionalBioEn
            : doctor.professionalBioEn ?? doctor.professionalBioAr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatusBadge(
                  label: doctor.isAcceptingPatients == true
                      ? strings.doctorAcceptingPatients
                      : strings.doctorAvailabilityNotConfirmed,
                  color: doctor.isAcceptingPatients == true
                      ? AppTheme.success
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppTheme.spaceMd),
                Text(
                  doctorDisplayName(doctor, direction, strings),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (doctorDisplaySpecialty(doctor, direction) != null) ...[
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    doctorDisplaySpecialty(doctor, direction)!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                if (bio?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(bio!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _InfoSection(doctor: doctor, strings: strings),
        const SizedBox(height: AppTheme.spaceLg),
        _ListSection(
          title: strings.doctorSectionEducation,
          values: doctor.education,
          empty: strings.doctorSectionEducationEmpty,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _ListSection(
          title: strings.doctorSectionCertifications,
          values: doctor.certifications,
          empty: strings.doctorSectionCertificationsEmpty,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _ClinicsSection(clinics: clinics, strings: strings),
        const SizedBox(height: AppTheme.spaceLg),
        _ReviewsSection(reviews: reviews, strings: strings),
      ],
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.doctor, required this.strings});
  final Doctor doctor;
  final AppStrings strings;
  @override
  Widget build(BuildContext context) {
    final rows = <String>[
      if (doctor.yearsOfExperience != null) strings.doctorInfoExperience(doctor.yearsOfExperience!),
      if (doctor.consultationFee != null)
        strings.doctorInfoConsultationFee(doctor.consultationFee!.toStringAsFixed(0)),
      if (doctor.consultationDuration != null)
        strings.doctorInfoConsultationDuration(doctor.consultationDuration!),
      if (doctor.averageRating != null)
        doctor.totalRatings == null
            ? strings.doctorInfoRating(doctor.averageRating!.toStringAsFixed(1))
            : strings.doctorInfoRatingWithCount(doctor.averageRating!.toStringAsFixed(1), doctor.totalRatings!),
      if (doctor.medicalLicenseNumber?.trim().isNotEmpty == true)
        strings.doctorInfoMedicalLicense(doctor.medicalLicenseNumber!),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.doctorSectionProfessionalDetails),
            if (rows.isEmpty)
              Text(strings.doctorSectionProfessionalDetailsEmpty)
            else
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                  child: Text(row),
                ),
          ],
        ),
      ),
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({
    required this.title,
    required this.values,
    required this.empty,
  });
  final String title, empty;
  final List<String> values;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title),
          if (values.isEmpty)
            Text(empty)
          else
            for (final value in values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                child: Text(value),
              ),
        ],
      ),
    ),
  );
}

class _ClinicsSection extends StatelessWidget {
  const _ClinicsSection({required this.clinics, required this.strings});
  final List<DoctorClinicSummary> clinics;
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
            SectionHeader(title: strings.doctorSectionAssociatedClinics),
            if (clinics.isEmpty)
              Text(strings.doctorSectionAssociatedClinicsEmpty)
            else ...[
              for (final clinic in clinics)
                ListTile(
                  key: ValueKey('doctor-clinic-${clinic.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(clinicDisplayName(clinic, direction, strings)),
                  subtitle: Text(
                    [
                      if ((direction == TextDirection.rtl
                                  ? clinic.addressAr ?? clinic.addressEn
                                  : clinic.addressEn ?? clinic.addressAr)
                              ?.trim()
                              .isNotEmpty ==
                          true)
                        direction == TextDirection.rtl
                            ? clinic.addressAr ?? clinic.addressEn
                            : clinic.addressEn ?? clinic.addressAr,
                      if (clinic.city?.trim().isNotEmpty == true) clinic.city,
                      if (clinic.region?.trim().isNotEmpty == true)
                        clinic.region,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: Icon(AppTheme.directionalForwardIconOf(context)),
                  onTap: () =>
                      context.push(RoutePaths.clinicDetailPath(clinic.id)),
                ),
              const SizedBox(height: AppTheme.spaceSm),
              ClinicMiniMap(clinics: clinics),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.reviews, required this.strings});
  final List<DoctorReview> reviews;
  final AppStrings strings;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: strings.doctorSectionReviews),
          if (reviews.isEmpty)
            Text(strings.doctorSectionReviewsEmpty)
          else
            for (final review in reviews)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: review.rating == null
                    ? null
                    : Text(review.rating!.toStringAsFixed(1)),
                title: review.comment?.trim().isNotEmpty == true
                    ? Text(review.comment!)
                    : Text(strings.doctorReviewNoComment),
                subtitle: review.createdAt == null
                    ? null
                    : Text(
                        review.createdAt!.toLocal().toString().split(' ').first,
                      ),
              ),
        ],
      ),
    ),
  );
}
