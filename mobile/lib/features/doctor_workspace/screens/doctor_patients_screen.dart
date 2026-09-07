import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/doctor_models.dart';
import '../providers/doctor_workspace_providers.dart';
import '../widgets/doctor_workspace_gate.dart';

class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});
  @override
  ConsumerState<DoctorPatientsScreen> createState() =>
      _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends ConsumerState<DoctorPatientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  // Guards against the go_router Navigator's
  // "'!keyReservation.contains(key)'" assertion, which fires when the same
  // route is pushed twice before the first push's page has finished
  // registering — a fast double-tap on a patient row was enough to trigger
  // it.
  bool _isNavigating = false;

  void _openPatient(String path) {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    context.push(path).whenComplete(() {
      if (mounted) setState(() => _isNavigating = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => ref.read(doctorPatientsProvider.notifier).load(query: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final async = ref.watch(doctorPatientsProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(s.myPatients)),
      body: DoctorWorkspaceGate(
        child: RefreshIndicator(
          onRefresh: () => ref.read(doctorPatientsProvider.notifier).load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: _changed,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: s.searchPatients,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _search.clear();
                                  _changed('');
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    async.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, _) => ErrorRetryState(
                        title: s.myPatients,
                        message: doctorErrorMessage(s, e),
                        retryLabel: s.retry,
                        onRetry: () =>
                            ref.read(doctorPatientsProvider.notifier).load(),
                      ),
                      data: (patients) => patients.isEmpty
                          ? EmptyState(
                              icon: Icons.group_off_outlined,
                              title: s.noPatients,
                            )
                          : Column(
                              children: patients
                                  .map((p) => _card(context, s, p))
                                  .toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AppStrings s, DoctorPatient p) {
    final name =
        (s.isArabic
                ? [p.firstNameAr, p.lastNameAr]
                : [p.firstNameEn, p.lastNameEn])
            .whereType<String>()
            .join(' ')
            .trim();
    return Card(
      child: ListTile(
        minVerticalPadding: 12,
        leading: CircleAvatar(
          child: Text(name.isEmpty ? '?' : name.characters.first),
        ),
        title: Text(name.isEmpty ? p.email : name),
        subtitle: Text(
          [
            p.email,
            p.phone,
            p.nextAppointmentDate,
          ].whereType<String>().join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openPatient(RoutePaths.doctorPatientPath(p.id)),
      ),
    );
  }
}
