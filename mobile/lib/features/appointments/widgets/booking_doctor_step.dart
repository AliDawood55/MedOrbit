import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../discovery/models/doctor_models.dart';
import '../../discovery/widgets/doctor_result_card.dart';

/// The doctor picker: shows the initial browse list immediately and narrows
/// it as the patient types, debounced the same way as
/// `doctor_directory_screen.dart` and the web wizard's 300ms search.
class BookingDoctorStep extends StatefulWidget {
  const BookingDoctorStep({
    super.key,
    required this.strings,
    required this.query,
    required this.results,
    required this.isLoading,
    required this.hasError,
    required this.onSearch,
    required this.onSelect,
    required this.onRetry,
  });

  final AppStrings strings;
  final String query;
  final List<Doctor> results;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<String> onSearch;
  final ValueChanged<Doctor> onSelect;
  final VoidCallback onRetry;

  @override
  State<BookingDoctorStep> createState() => _BookingDoctorStepState();
}

class _BookingDoctorStepState extends State<BookingDoctorStep> {
  late final TextEditingController _controller = TextEditingController(text: widget.query);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => widget.onSearch(value));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: strings.searchDoctorsHint,
          controller: _controller,
          prefixIcon: const Icon(Icons.search_rounded),
          onChanged: _onChanged,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        if (widget.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.space2xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.hasError)
          ErrorRetryState(
            title: strings.couldNotLoadDoctors,
            message: strings.errorGeneric,
            retryLabel: strings.retry,
            onRetry: widget.onRetry,
            variant: ErrorRetryVariant.compact,
          )
        else if (widget.results.isEmpty)
          EmptyState(icon: Icons.person_search_outlined, title: strings.noDoctorsFound, variant: EmptyStateVariant.compact)
        else
          for (final doctor in widget.results) ...[
            DoctorResultCard(key: ValueKey('booking-doctor-${doctor.id}'), doctor: doctor, onTap: () => widget.onSelect(doctor)),
            const SizedBox(height: AppTheme.spaceSm),
          ],
      ],
    );
  }
}
