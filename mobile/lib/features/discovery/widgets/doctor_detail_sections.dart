import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/core_providers.dart';
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
    final isArabic = direction == TextDirection.rtl;
    final bio =
        doctor.professionalBio ??
        (isArabic
            ? doctor.professionalBioAr ?? doctor.professionalBioEn
            : doctor.professionalBioEn ?? doctor.professionalBioAr);
    final specialty = doctorDisplaySpecialty(doctor, direction);
    final imageUrl = _absoluteImageUrl(ref, doctor.profileImageUrl);
    final name = doctorDisplayName(doctor, direction, strings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Text conveys the accepting-patients state on its own; colour
                // is only a reinforcement. `false` and `unknown` stay distinct.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusBadge(
                    label: switch (doctor.isAcceptingPatients) {
                      true => strings.doctorAcceptingPatients,
                      false => strings.doctorNotAcceptingPatients,
                      null => strings.doctorAvailabilityNotConfirmed,
                    },
                    color: switch (doctor.isAcceptingPatients) {
                      true => AppTheme.success,
                      false => AppTheme.danger,
                      null => Theme.of(context).colorScheme.onSurfaceVariant,
                    },
                  ),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DoctorAvatar(name: name, imageUrl: imageUrl),
                    const SizedBox(width: AppTheme.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (specialty != null) ...[
                            const SizedBox(height: AppTheme.spaceXs),
                            Text(
                              [
                                specialty,
                                if (doctor.subSpecialty?.trim().isNotEmpty == true)
                                  doctor.subSpecialty!.trim(),
                              ].join(' · '),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                          if (doctor.professionalHeadline?.trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: AppTheme.spaceXs),
                            Text(
                              doctor.professionalHeadline!.trim(),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (bio?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  Text(bio!.trim()),
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
        _ReviewsSection(reviews: reviews, strings: strings, isArabic: isArabic),
      ],
    );
  }
}

String? _absoluteImageUrl(WidgetRef ref, String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  return '${ref.watch(activeOriginProvider)}$value';
}

/// Doctor photo with an initials fallback. Mirrors the web profile's
/// `onerror` swap to initials — a broken or missing image never surfaces a
/// broken-image glyph or a network error.
class _DoctorAvatar extends StatelessWidget {
  const _DoctorAvatar({required this.name, this.imageUrl});
  final String name;
  final String? imageUrl;
  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.primaryGradient,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: AppTheme.weightExtraBold,
            ),
      ),
    );
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
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
      if (doctor.yearsOfExperience != null)
        strings.doctorInfoExperience(doctor.yearsOfExperience!),
      if (doctor.consultationFee != null)
        strings.doctorInfoConsultationFee(doctor.consultationFee!.toStringAsFixed(0)),
      if (doctor.consultationDuration != null)
        strings.doctorInfoConsultationDuration(doctor.consultationDuration!),
      if (doctor.averageRating != null)
        doctor.totalRatings == null
            ? strings.doctorInfoRating(doctor.averageRating!.toStringAsFixed(1))
            : strings.doctorInfoRatingWithCount(
                doctor.averageRating!.toStringAsFixed(1), doctor.totalRatings!),
      if (doctor.medicalLicenseNumber?.trim().isNotEmpty == true)
        strings.doctorInfoMedicalLicense(doctor.medicalLicenseNumber!),
    ];
    final chipGroups = <(String, List<String>)>[
      (strings.doctorInfoExpertise, doctor.areasOfExpertise),
      (strings.doctorInfoInterests, doctor.professionalInterests),
      (strings.doctorInfoLanguages, doctor.languagesSpoken),
    ].where((group) => group.$2.isNotEmpty).toList();
    final empty = rows.isEmpty && chipGroups.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: strings.doctorSectionProfessionalDetails),
            if (empty)
              Text(strings.doctorSectionProfessionalDetailsEmpty)
            else ...[
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                  child: Text(row),
                ),
              for (final group in chipGroups) ...[
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  group.$1,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Wrap(
                  spacing: AppTheme.spaceSm,
                  runSpacing: AppTheme.spaceXs,
                  children: [
                    for (final value in group.$2) Chip(label: Text(value)),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceSm),
              ],
            ],
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
  const _ReviewsSection({
    required this.reviews,
    required this.strings,
    required this.isArabic,
  });
  final List<DoctorReview> reviews;
  final AppStrings strings;
  final bool isArabic;
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
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
                child: _ReviewTile(
                  review: review,
                  strings: strings,
                  isArabic: isArabic,
                ),
              ),
        ],
      ),
    ),
  );
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.strings,
    required this.isArabic,
  });
  final DoctorReview review;
  final AppStrings strings;
  final bool isArabic;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = review.localizedText(isArabic: isArabic);
    final reviewer = review.reviewerName(isArabic: isArabic) ??
        strings.doctorReviewAnonymous;
    final date = review.createdAt?.toLocal().toString().split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                reviewer,
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (review.rating != null)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: AppTheme.iconSm),
                    const SizedBox(width: AppTheme.spaceXs),
                    Text(review.rating!.toStringAsFixed(1)),
                  ],
                ),
              ),
          ],
        ),
        if (date != null) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            date,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spaceXs),
        Text(body ?? strings.doctorReviewNoComment),
      ],
    );
  }
}
