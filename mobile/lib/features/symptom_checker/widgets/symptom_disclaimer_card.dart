import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../shared/widgets/page_sections.dart';

/// The mandatory "this is not a diagnosis" notice, shown above the input on
/// every visit — never dismissible, never gated behind a result.
class SymptomDisclaimerCard extends StatelessWidget {
  const SymptomDisclaimerCard({super.key, required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return InlineMessage(
      message: strings.symptomCheckerDisclaimer,
      tone: InlineMessageTone.warning,
    );
  }
}
