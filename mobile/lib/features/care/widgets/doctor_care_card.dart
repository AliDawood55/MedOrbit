import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../models/my_doctor_model.dart';
import 'doctor_avatar.dart';

/// A treating doctor with the presentation fields the My Doctor screen has:
/// avatar, name, specialty, rating, relationship start date, last/next
/// appointment date, and the two supported actions (view doctor / book
/// another appointment). No messaging action — that is Phase 8 scope.
class DoctorCareCard extends StatelessWidget {
  const DoctorCareCard({
    super.key,
    required this.doctor,
    required this.isArabic,
    required this.strings,
    required this.avatarOrigin,
    required this.onViewDoctor,
    required this.onBookAppointment,
  });

  final MyDoctorModel doctor;
  final bool isArabic;
  final AppStrings strings;

  /// Prepended to `profile_image_url`, which the backend returns as a
  /// relative path (matches `ProfileAvatarSection`'s `avatarOrigin`).
  final String avatarOrigin;
  final VoidCallback onViewDoctor;
  final VoidCallback onBookAppointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = doctor.displayName(isArabic);
    final specialty = doctor.displaySpecialty(isArabic);
    final avatarUrl = doctor.profileImageUrl;
    final localeCode = isArabic ? 'ar' : 'en';

    String? formatted(String? value) {
      if (value == null || value.isEmpty) return null;
      try {
        return formatDate(parseDateOnly(value), localeCode: localeCode);
      } catch (_) {
        return null;
      }
    }

    final since = formatted(doctor.relationshipStartedAt);
    final next = formatted(doctor.nextAppointmentDate);
    final last = formatted(doctor.lastAppointmentDate);

    return Card(
      key: ValueKey('my-doctor-card-${doctor.id}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DoctorAvatar(
                  name: name,
                  imageUrl: avatarUrl == null || avatarUrl.isEmpty ? null : '$avatarOrigin$avatarUrl',
                ),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightExtraBold),
                      ),
                      if (specialty != null) ...[
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          specialty,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                      if (doctor.averageRating != null) ...[
                        const SizedBox(height: AppTheme.spaceXs),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: AppTheme.iconSm, color: AppTheme.accent),
                              const SizedBox(width: AppTheme.spaceXs),
                              Text(doctor.averageRating!.toStringAsFixed(1), style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (since != null || next != null || last != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Wrap(
                spacing: AppTheme.spaceMd,
                runSpacing: AppTheme.spaceXs,
                children: [
                  if (since != null) _MetaFact(icon: Icons.favorite_border_rounded, label: strings.careSinceLabel(since)),
                  if (next != null) _MetaFact(icon: Icons.calendar_month_outlined, label: strings.nextVisitLabel(next)),
                  if (last != null) _MetaFact(icon: Icons.history_rounded, label: strings.lastVisitLabel(last)),
                ],
              ),
            ],
            const SizedBox(height: AppTheme.spaceMd),
            LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < AppTheme.compactBreakpoint;
                final viewButton = OutlinedButton.icon(
                  key: ValueKey('view-doctor-${doctor.id}'),
                  onPressed: onViewDoctor,
                  icon: const Icon(Icons.person_outline_rounded, size: AppTheme.iconSm),
                  label: Text(strings.viewDoctorAction),
                );
                final bookButton = FilledButton.icon(
                  key: ValueKey('book-with-doctor-${doctor.id}'),
                  onPressed: onBookAppointment,
                  icon: const Icon(Icons.event_outlined, size: AppTheme.iconSm),
                  label: Text(strings.bookAppointmentWithDoctorAction),
                );
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [bookButton, const SizedBox(height: AppTheme.spaceSm), viewButton],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: viewButton),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(child: bookButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaFact extends StatelessWidget {
  const _MetaFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppTheme.iconSm, color: color),
        const SizedBox(width: AppTheme.spaceXs),
        Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
      ],
    );
  }
}
