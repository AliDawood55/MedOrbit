import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/doctor_portal_api.dart';

class DoctorPatientDetailScreen extends ConsumerStatefulWidget {
  const DoctorPatientDetailScreen({super.key, required this.patientId});
  final String patientId;

  @override
  ConsumerState<DoctorPatientDetailScreen> createState() => _DoctorPatientDetailScreenState();
}

class _DoctorPatientDetailScreenState extends ConsumerState<DoctorPatientDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  DoctorPortalApi get _api => DoctorPortalApi(ref.read(dioProvider));

  @override
  void initState() {
    super.initState();
    _future = _api.patientDetail(widget.patientId);
  }

  void _reload() => setState(() => _future = _api.patientDetail(widget.patientId));

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    if (ref.watch(authControllerProvider).user?.role != 'doctor') {
      return const AppScaffold(body: Center(child: EmptyState(icon: Icons.lock_outline, title: 'Doctor access required', hint: 'This workspace is available to approved doctor accounts only.')));
    }
    return AppScaffold(
      appBar: AppBar(
        title: Text(ar ? 'ملف المريض' : 'Patient file'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: context.pop),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) {
            return ErrorRetryState(title: ar ? 'تعذر تحميل ملف المريض' : 'Could not load patient file', message: ar ? 'يظهر الملف فقط للمرضى المرتبطين برعايتك.' : 'This file is only available for patients linked to your care.', retryLabel: ar ? 'إعادة المحاولة' : 'Retry', onRetry: _reload);
          }
          final data = snapshot.data!;
          final patient = _map(data['patient']);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              children: [
                PageIntro(title: _patientName(patient, ar), subtitle: patient['email']?.toString() ?? '', icon: Icons.person_outline, color: AppTheme.primary),
                if ((patient['user_id']?.toString() ?? '').isNotEmpty)
                  FilledButton.icon(onPressed: () => _messagePatient(patient['user_id'].toString(), ar), icon: const Icon(Icons.message_outlined), label: Text(ar ? 'مراسلة المريض' : 'Message patient')),
                if ((patient['phone']?.toString() ?? '').isNotEmpty)
                  Card(child: ListTile(leading: const Icon(Icons.phone_outlined), title: Text(patient['phone'].toString()))),
                const SizedBox(height: AppTheme.spaceXl),
                _ClinicalSection(title: ar ? 'سجل المواعيد' : 'Appointment history', values: _maps(data['appointments']), emptyLabel: ar ? 'لا توجد مواعيد بعد.' : 'No appointments yet.', label: (item) => '${item['scheduled_date'] ?? ''} · ${item['start_time'] ?? ''} · ${item['status'] ?? ''}'),
                _ClinicalSection(title: ar ? 'السجلات الطبية' : 'Medical records', values: _maps(data['notes']), emptyLabel: ar ? 'لا توجد سجلات بعد.' : 'No records yet.', label: (item) => _first(item, const ['diagnosis', 'chief_complaint', 'record_number'])),
                _ClinicalSection(title: ar ? 'الوصفات الطبية' : 'Prescriptions', values: _maps(data['prescriptions']), emptyLabel: ar ? 'لا توجد وصفات بعد.' : 'No prescriptions yet.', label: (item) => '${item['prescription_number'] ?? ''}${item['diagnosis'] == null ? '' : ' · ${item['diagnosis']}'}'),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _messagePatient(String userId, bool ar) async {
    try {
      await _api.startConversation(userId);
      if (mounted) context.push(RoutePaths.doctorMessages);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ar ? 'تعذر بدء المحادثة.' : 'Could not start the conversation.')));
    }
  }
}

class _ClinicalSection extends StatelessWidget {
  const _ClinicalSection({required this.title, required this.values, required this.emptyLabel, required this.label});
  final String title;
  final List<Map<String, dynamic>> values;
  final String emptyLabel;
  final String Function(Map<String, dynamic>) label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spaceSm),
          if (values.isEmpty) Text(emptyLabel) else ...values.map((value) => Card(child: ListTile(leading: const Icon(Icons.description_outlined), title: Text(label(value).isEmpty ? '—' : label(value))))),
        ],
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : const {};
List<Map<String, dynamic>> _maps(dynamic value) => value is List ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : const [];
String _first(Map<String, dynamic> value, List<String> keys) => keys.map((key) => value[key]?.toString().trim() ?? '').firstWhere((item) => item.isNotEmpty, orElse: () => '');
String _patientName(Map<String, dynamic> value, bool ar) {
  final keys = ar ? ['first_name_ar', 'last_name_ar', 'first_name_en', 'last_name_en'] : ['first_name_en', 'last_name_en', 'first_name_ar', 'last_name_ar'];
  final parts = keys.map((key) => value[key]?.toString().trim() ?? '').where((part) => part.isNotEmpty).take(2);
  return parts.isEmpty ? (ar ? 'مريض' : 'Patient') : parts.join(' ');
}
