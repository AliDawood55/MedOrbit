import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../shared/widgets/page_sections.dart';

/// Shown on the slot step right after a `SLOT_BUSY` conflict sends the
/// patient back from the confirm step — the slot grid beneath it has already
/// been refreshed and the taken slot deselected.
class SlotBusyState extends StatelessWidget {
  const SlotBusyState({super.key, required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return InlineMessage(message: strings.slotBusyMessage, tone: InlineMessageTone.warning);
  }
}
