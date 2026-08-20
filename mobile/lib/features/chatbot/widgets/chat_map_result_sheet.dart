import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routes/route_paths.dart';
import '../../../shared/widgets/primary_button.dart';
import 'chat_results_map.dart';

class ChatMapResultSheet extends StatelessWidget {
  const ChatMapResultSheet({super.key, required this.result, required this.onClose});

  final ChatMapResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Expanded(child: Text(result.label, style: Theme.of(context).textTheme.titleMedium)), IconButton(tooltip: 'Close map result', onPressed: onClose, icon: const Icon(Icons.close_rounded))]),
            if (result.subtitle != null) Text(result.subtitle!),
            if (result.clinicId?.isNotEmpty == true) ...[const SizedBox(height: 8), PrimaryButton(label: 'Clinic details', onPressed: () => context.push(RoutePaths.clinicDetailPath(result.clinicId!)))],
            if (result.doctorId?.isNotEmpty == true) ...[const SizedBox(height: 8), PrimaryButton(label: 'Doctor details', onPressed: () => context.push(RoutePaths.doctorDetailPath(result.doctorId!)))],
          ],
        ),
      ),
    );
  }
}
