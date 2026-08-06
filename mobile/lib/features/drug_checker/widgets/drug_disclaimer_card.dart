import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../shared/widgets/page_sections.dart';

/// The mandatory "this is not medical/pharmacist advice" notice, shown above
/// the input on every visit — never dismissible, never gated behind a result.
class DrugDisclaimerCard extends StatelessWidget {
  const DrugDisclaimerCard({super.key, required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return InlineMessage(
      message: strings.drugCheckerDisclaimer,
      tone: InlineMessageTone.warning,
    );
  }
}
