import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/clinic_models.dart';

String clinicDisplayName(Clinic clinic, TextDirection direction) {
  final rtl = direction == TextDirection.rtl;
  final primary = rtl ? clinic.nameAr : clinic.nameEn;
  final fallback = rtl ? clinic.nameEn : clinic.nameAr;
  return _clean(primary) ?? _clean(fallback) ?? 'Healthcare facility';
}

String? clinicDisplayAddress(Clinic clinic, TextDirection direction) {
  final rtl = direction == TextDirection.rtl;
  return _clean(rtl ? clinic.addressAr : clinic.addressEn) ??
      _clean(rtl ? clinic.addressEn : clinic.addressAr);
}

String clinicTypeLabel(String? type) {
  return switch ((type ?? '').trim().toLowerCase()) {
    'clinic' => 'Clinic',
    'pharmacy' => 'Pharmacy',
    'hospital' => 'Hospital',
    'laboratory' => 'Laboratory',
    'dental' => 'Dental',
    'radiology' => 'Radiology',
    'emergency' => 'Emergency',
    _ => 'Facility',
  };
}

(String, Color) clinicVerificationVisual(Clinic clinic) {
  return switch (clinic.verificationStatus) {
    ClinicVerificationStatus.verified => ('Verified', AppTheme.success),
    ClinicVerificationStatus.pending => ('Pending verification', AppTheme.warning),
    ClinicVerificationStatus.rejected ||
    ClinicVerificationStatus.suspended ||
    ClinicVerificationStatus.unknown =>
      ('Unverified / unknown', AppTheme.info),
  };
}

class ClinicResultCard extends StatelessWidget {
  const ClinicResultCard({
    super.key,
    required this.clinic,
    this.nearbyMode = false,
    this.onTap,
  });

  final Clinic clinic;
  final bool nearbyMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final name = clinicDisplayName(clinic, direction);
    final address = clinicDisplayAddress(clinic, direction);
    final location = [
      _clean(address),
      _clean(clinic.city),
      _clean(clinic.region),
    ].whereType<String>().join(' · ');
    final phone = _clean(clinic.phone);
    final rating = clinic.averageRating ?? clinic.rating;
    final distanceKm = clinic.distanceKm;
    final (verificationLabel, verificationColor) = clinicVerificationVisual(clinic);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('clinic-card-${clinic.id}'),
        onTap: onTap ?? () => context.push(RoutePaths.clinicDetailPath(clinic.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(label: clinicTypeLabel(clinic.type), color: theme.colorScheme.primary),
                  StatusBadge(label: verificationLabel, color: verificationColor),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightExtraBold),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spaceXs),
                _IconText(icon: Icons.place_outlined, text: location),
              ],
              if (phone != null) ...[
                const SizedBox(height: AppTheme.spaceXs),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: _IconText(icon: Icons.phone_outlined, text: phone),
                ),
              ],
              if (rating != null || (nearbyMode && distanceKm != null)) ...[
                const SizedBox(height: AppTheme.spaceSm),
                Wrap(
                  spacing: AppTheme.spaceMd,
                  runSpacing: AppTheme.spaceXs,
                  children: [
                    if (rating != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: _IconText(icon: Icons.star_rounded, text: rating.toStringAsFixed(1)),
                      ),
                    if (nearbyMode && distanceKm != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: _IconText(icon: Icons.near_me_outlined, text: '${distanceKm.toStringAsFixed(1)} km'),
                      ),
                  ],
                ),
              ],
              if (clinic.services.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _PreviewChips(values: clinic.services, maxItems: 3),
              ],
              if (clinic.insuranceAccepted.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spaceSm),
                _PreviewChips(values: clinic.insuranceAccepted, maxItems: 2, icon: Icons.verified_user_outlined),
              ],
              const SizedBox(height: AppTheme.spaceSm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onTap ?? () => context.push(RoutePaths.clinicDetailPath(clinic.id)),
                  iconAlignment: IconAlignment.end,
                  icon: Icon(AppTheme.directionalForwardIconOf(context), size: AppTheme.iconSm),
                  label: const Text('Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppTheme.iconSm, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: AppTheme.spaceXs),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _PreviewChips extends StatelessWidget {
  const _PreviewChips({
    required this.values,
    required this.maxItems,
    this.icon = Icons.medical_services_outlined,
  });

  final List<String> values;
  final int maxItems;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final shown = values.take(maxItems).toList();
    final remaining = values.length - shown.length;
    return Wrap(
      spacing: AppTheme.spaceXs,
      runSpacing: AppTheme.spaceXs,
      children: [
        for (final value in shown)
          Chip(
            avatar: Icon(icon, size: AppTheme.iconSm),
            label: Text(value),
            visualDensity: VisualDensity.compact,
          ),
        if (remaining > 0)
          Chip(
            label: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('+$remaining'),
            ),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
