import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../discovery/models/doctor_models.dart';
import '../models/availability_slot_model.dart';
import '../providers/booking_provider.dart';
import 'booking_summary_card.dart';

class BookingConfirmStep extends StatefulWidget {
  const BookingConfirmStep({
    super.key,
    required this.strings,
    required this.doctor,
    required this.clinic,
    required this.date,
    required this.slot,
    required this.reason,
    required this.notes,
    required this.isSubmitting,
    required this.submitError,
    required this.onReasonChanged,
    required this.onNotesChanged,
    required this.onSubmit,
    required this.onBack,
  });

  final AppStrings strings;
  final Doctor doctor;
  final DoctorClinicSummary clinic;
  final DateTime date;
  final GeneratedSlot slot;
  final String reason;
  final String notes;
  final bool isSubmitting;
  final BookingSubmitError? submitError;
  final ValueChanged<String> onReasonChanged;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  State<BookingConfirmStep> createState() => _BookingConfirmStepState();
}

class _BookingConfirmStepState extends State<BookingConfirmStep> {
  // Owned locally and seeded once: the wizard state updates on every
  // keystroke, and rebuilding these from `widget.reason`/`widget.notes` each
  // time would fight the user's cursor position mid-sentence.
  late final TextEditingController _reasonController = TextEditingController(
    text: widget.reason,
  );
  late final TextEditingController _notesController = TextEditingController(
    text: widget.notes,
  );

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.submitError != null) ...[
          InlineMessage(
            message: _submitErrorMessage(strings, widget.submitError!.kind),
            tone: InlineMessageTone.error,
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
        BookingSummaryCard(
          doctor: widget.doctor,
          clinic: widget.clinic,
          date: widget.date,
          slot: widget.slot,
          strings: strings,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        AppTextField(
          label: strings.visitReasonLabel,
          controller: _reasonController,
          minLines: 2,
          maxLines: 4,
          onChanged: widget.onReasonChanged,
        ),
        const SizedBox(height: AppTheme.spaceMd),
        AppTextField(
          label: strings.additionalNotesLabel,
          controller: _notesController,
          minLines: 2,
          maxLines: 4,
          onChanged: widget.onNotesChanged,
        ),
        const SizedBox(height: AppTheme.spaceXl),
        PrimaryButton(
          label: strings.confirmAndBookAction,
          isLoading: widget.isSubmitting,
          onPressed: widget.isSubmitting ? null : widget.onSubmit,
        ),
        const SizedBox(height: AppTheme.spaceSm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.isSubmitting ? null : widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(strings.backAction),
          ),
        ),
      ],
    );
  }
}

String _submitErrorMessage(AppStrings strings, BookingSubmitErrorKind kind) {
  return switch (kind) {
    BookingSubmitErrorKind.slotBusy => strings.slotBusyMessage,
    BookingSubmitErrorKind.patientNotFound => strings.patientNotFoundMessage,
    BookingSubmitErrorKind.timeout => strings.bookingTimeoutMessage,
    BookingSubmitErrorKind.serviceUnavailable =>
      strings.bookingServiceUnavailableMessage,
    BookingSubmitErrorKind.validation => strings.couldNotCreateAppointment,
    BookingSubmitErrorKind.generic => strings.couldNotCreateAppointment,
  };
}
