import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/doctor_models.dart';
import '../providers/doctor_workspace_providers.dart';
import '../widgets/doctor_workspace_gate.dart';

class DoctorProfileScreen extends ConsumerStatefulWidget {
  const DoctorProfileScreen({super.key});
  @override
  ConsumerState<DoctorProfileScreen> createState() =>
      _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends ConsumerState<DoctorProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _headline = TextEditingController(),
      _bio = TextEditingController(),
      _sub = TextEditingController(),
      _experience = TextEditingController(),
      _expertise = TextEditingController(),
      _interests = TextEditingController(),
      _education = TextEditingController(),
      _certifications = TextEditingController(),
      _languages = TextEditingController(),
      _city = TextEditingController(),
      _fee = TextEditingController();
  String? _loadedId;
  int _duration = 30;
  bool _accepting = false, _saving = false;

  void _populate(DoctorProfile p) {
    if (_loadedId == p.id) return;
    _loadedId = p.id;
    _headline.text = p.headline ?? '';
    _bio.text = p.bio ?? '';
    _sub.text = p.subSpecialty ?? '';
    _experience.text = p.yearsOfExperience?.toString() ?? '';
    _expertise.text = p.expertise.join(', ');
    _interests.text = p.interests.join(', ');
    _education.text = p.education.join('\n');
    _certifications.text = p.certifications.join('\n');
    _languages.text = p.languages.join(', ');
    _city.text = p.city ?? '';
    _fee.text = p.consultationFee?.toStringAsFixed(2) ?? '';
    _duration = const [15, 20, 30, 45, 60].contains(p.consultationDuration)
        ? p.consultationDuration!
        : 30;
    _accepting = p.isAcceptingPatients;
  }

  List<String> _comma(TextEditingController c) => c.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  List<String> _lines(TextEditingController c) => c.text
      .split('\n')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  String? _limit(
    String? value,
    int max,
    AppStrings s, {
    bool required = false,
  }) {
    final v = value?.trim() ?? '';
    if (required && v.isEmpty) return s.doctorRequiredField;
    if (v.length > max) return s.invalidValue;
    return null;
  }

  Future<void> _save(AppStrings s) async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final expertise = _comma(_expertise),
        interests = _comma(_interests),
        languages = _comma(_languages),
        education = _lines(_education),
        certs = _lines(_certifications);
    if (expertise.length > 12 ||
        interests.length > 10 ||
        languages.length > 10 ||
        education.length > 20 ||
        certs.length > 20 ||
        [...expertise, ...interests, ...languages].any((v) => v.length > 80) ||
        [...education, ...certs].any((v) => v.length > 160)) {
      showDoctorError(
        context,
        s,
        const ApiException(message: '', code: 'VALIDATION_ERROR'),
      );
      return;
    }
    setState(() => _saving = true);
    final result = await ref
        .read(doctorProfileProvider.notifier)
        .save(
          headline: _headline.text,
          bio: _bio.text,
          subSpecialty: _sub.text,
          yearsOfExperience: int.tryParse(_experience.text),
          expertise: expertise,
          interests: interests,
          education: education,
          certifications: certs,
          languages: languages,
          city: _city.text,
          consultationFee: double.tryParse(_fee.text),
          consultationDuration: _duration,
          isAcceptingPatients: _accepting,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.error != null) {
      showDoctorError(context, s, result.error);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.operationSucceeded)));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _headline,
      _bio,
      _sub,
      _experience,
      _expertise,
      _interests,
      _education,
      _certifications,
      _languages,
      _city,
      _fee,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final profile = ref.watch(doctorProfileProvider).valueOrNull;
    if (profile != null) _populate(profile);
    return AppScaffold(
      appBar: AppBar(title: Text(s.professionalProfile)),
      body: DoctorWorkspaceGate(
        child: profile == null
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spaceLg,
                  ),
                  children: [
                    ResponsiveContent(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PageIntro(
                            title: s.professionalProfile,
                            subtitle: s.doctorStatus(profile.approvalStatus),
                            icon: Icons.badge_outlined,
                          ),
                          const SizedBox(height: AppTheme.spaceLg),
                          _readOnly(context, s, profile),
                          TextFormField(
                            controller: _headline,
                            maxLength: 160,
                            decoration: InputDecoration(
                              labelText: s.professionalHeadline,
                            ),
                            validator: (v) => _limit(v, 160, s),
                          ),
                          TextFormField(
                            controller: _bio,
                            maxLength: 3000,
                            minLines: 4,
                            maxLines: 8,
                            decoration: InputDecoration(
                              labelText: s.professionalBiography,
                            ),
                            validator: (v) => _limit(v, 3000, s),
                          ),
                          TextFormField(
                            controller: _sub,
                            maxLength: 160,
                            decoration: InputDecoration(
                              labelText: s.subSpecialty,
                            ),
                            validator: (v) => _limit(v, 160, s),
                          ),
                          Wrap(
                            spacing: AppTheme.spaceMd,
                            runSpacing: AppTheme.spaceSm,
                            children: [
                              SizedBox(
                                width: 210,
                                child: TextFormField(
                                  controller: _experience,
                                  decoration: InputDecoration(
                                    labelText: s.yearsOfExperience,
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return null;
                                    final n = int.tryParse(v);
                                    return n == null || n < 0 || n > 80
                                        ? s.invalidValue
                                        : null;
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 210,
                                child: TextFormField(
                                  controller: _fee,
                                  decoration: InputDecoration(
                                    labelText: s.consultationFee,
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return null;
                                    final n = double.tryParse(v);
                                    return n == null || n < 0 || n > 100000
                                        ? s.invalidValue
                                        : null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          DropdownButtonFormField<int>(
                            initialValue: _duration,
                            decoration: InputDecoration(
                              labelText: s.slotDuration,
                            ),
                            items: const [15, 20, 30, 45, 60]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(s.minutesValue(v)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _duration = v ?? 30),
                          ),
                          TextFormField(
                            controller: _city,
                            maxLength: 80,
                            decoration: InputDecoration(labelText: s.city),
                            validator: (v) => _limit(v, 80, s),
                          ),
                          TextFormField(
                            controller: _expertise,
                            decoration: InputDecoration(
                              labelText: s.areasOfExpertise,
                            ),
                          ),
                          TextFormField(
                            controller: _interests,
                            decoration: InputDecoration(
                              labelText: s.professionalInterests,
                            ),
                          ),
                          TextFormField(
                            controller: _languages,
                            decoration: InputDecoration(labelText: s.languages),
                          ),
                          TextFormField(
                            controller: _education,
                            minLines: 2,
                            maxLines: 5,
                            decoration: InputDecoration(
                              labelText: s.educationLines,
                            ),
                          ),
                          TextFormField(
                            controller: _certifications,
                            minLines: 2,
                            maxLines: 5,
                            decoration: InputDecoration(
                              labelText: s.certificationLines,
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.acceptingPatients),
                            value: _accepting,
                            onChanged: (v) => setState(() => _accepting = v),
                          ),
                          const SizedBox(height: AppTheme.spaceLg),
                          FilledButton.icon(
                            onPressed: _saving ? null : () => _save(s),
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(s.save),
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

  Widget _readOnly(BuildContext context, AppStrings s, DoctorProfile p) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.specialtyEn ?? p.specialtyAr ?? '—',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(p.licenseNumber ?? '—'),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            s.verifiedCredentialsReadOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
