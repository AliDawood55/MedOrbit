import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/appointment_model.dart';

class BookingSuccessSheet extends StatelessWidget {
  const BookingSuccessSheet({
    super.key,
    required this.strings,
    required this.appointment,
    required this.onViewAppointments,
    required this.onBookAnother,
  });

  final AppStrings strings;
  final AppointmentModel appointment;
  final VoidCallback onViewAppointments;
  final VoidCallback onBookAnother;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: AppTheme.iconXl),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Text(
          strings.bookingSuccessTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: AppTheme.weightExtraBold),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Text(strings.bookingSuccessHint, textAlign: TextAlign.center),
        const SizedBox(height: AppTheme.spaceXs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            appointment.appointmentNumber,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightExtraBold, color: AppTheme.primary),
          ),
        ),
        const SizedBox(height: AppTheme.spaceXl),
        PrimaryButton(label: strings.viewMyAppointmentsAction, onPressed: onViewAppointments),
        const SizedBox(height: AppTheme.spaceSm),
        OutlinedButton(onPressed: onBookAnother, child: Text(strings.bookAnotherAppointmentAction)),
      ],
    );
  }
}
