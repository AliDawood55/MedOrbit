import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';

final doctorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(doctorApiProvider).listDoctors();
});

class DoctorsScreen extends ConsumerWidget {
  const DoctorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final doctors = ref.watch(doctorsProvider);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navDoctors)),
      body: doctors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(l10n.errorGeneric)),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final d = list[index];
            final specialty = isArabic ? d['specialty_ar'] : d['specialty_en'];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.medical_services)),
              title: Text(d['full_name'] as String? ?? ''),
              subtitle: Text('${specialty ?? ''} · ★ ${d['avg_rating'] ?? '0'}'),
            );
          },
        ),
      ),
    );
  }
}
