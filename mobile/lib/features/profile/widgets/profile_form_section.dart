import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/profile_edit_model.dart';
import '../providers/profile_provider.dart';

class ProfileFormSection extends StatefulWidget {
  const ProfileFormSection({
    super.key,
    required this.initialDraft,
    required this.strings,
    required this.isSaving,
    required this.saveError,
    required this.onSave,
  });

  final ProfileEditModel initialDraft;
  final AppStrings strings;
  final bool isSaving;
  final ProfileErrorKind? saveError;
  final ValueChanged<ProfileEditModel> onSave;

  @override
  State<ProfileFormSection> createState() => _ProfileFormSectionState();
}

class _ProfileFormSectionState extends State<ProfileFormSection> {
  final _formKey = GlobalKey<FormState>();

  // Owned locally and seeded once — the draft passed in from the provider
  // only changes after a save round-trip, and rebuilding these from
  // `widget.initialDraft` on every rebuild would fight the user's typing.
  late final TextEditingController _firstNameAr = TextEditingController(
    text: widget.initialDraft.firstNameAr,
  );
  late final TextEditingController _lastNameAr = TextEditingController(
    text: widget.initialDraft.lastNameAr,
  );
  late final TextEditingController _firstNameEn = TextEditingController(
    text: widget.initialDraft.firstNameEn,
  );
  late final TextEditingController _lastNameEn = TextEditingController(
    text: widget.initialDraft.lastNameEn,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.initialDraft.phone,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.initialDraft.address,
  );
  late final TextEditingController _city = TextEditingController(
    text: widget.initialDraft.city,
  );
  String? _gender;

  @override
  void initState() {
    super.initState();
    _gender = widget.initialDraft.gender;
  }

  @override
  void dispose() {
    _firstNameAr.dispose();
    _lastNameAr.dispose();
    _firstNameEn.dispose();
    _lastNameEn.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    super.dispose();
  }

  void _resetToInitial() {
    setState(() {
      _firstNameAr.text = widget.initialDraft.firstNameAr;
      _lastNameAr.text = widget.initialDraft.lastNameAr;
      _firstNameEn.text = widget.initialDraft.firstNameEn;
      _lastNameEn.text = widget.initialDraft.lastNameEn;
      _phone.text = widget.initialDraft.phone;
      _address.text = widget.initialDraft.address;
      _city.text = widget.initialDraft.city;
      _gender = widget.initialDraft.gender;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(
      ProfileEditModel(
        firstNameAr: _firstNameAr.text,
        lastNameAr: _lastNameAr.text,
        firstNameEn: _firstNameEn.text,
        lastNameEn: _lastNameEn.text,
        phone: _phone.text,
        gender: _gender,
        address: _address.text,
        city: _city.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: strings.profileSectionInfo),
              AppTextField(
                label: strings.firstNameArLabel,
                controller: _firstNameAr,
                textDirection: TextDirection.rtl,
                validator: (value) => Validators.required(
                  value,
                  fieldName: strings.firstNameArLabel,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.lastNameArLabel,
                controller: _lastNameAr,
                textDirection: TextDirection.rtl,
                validator: (value) => Validators.required(
                  value,
                  fieldName: strings.lastNameArLabel,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.firstNameEnLabel,
                controller: _firstNameEn,
                textDirection: TextDirection.ltr,
                validator: (value) => Validators.required(
                  value,
                  fieldName: strings.firstNameEnLabel,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.lastNameEnLabel,
                controller: _lastNameEn,
                textDirection: TextDirection.ltr,
                validator: (value) => Validators.required(
                  value,
                  fieldName: strings.lastNameEnLabel,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.phoneOptionalLabel,
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                strings.genderLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                children: [
                  ChoiceChip(
                    label: Text(strings.maleLabel),
                    selected: _gender == 'male',
                    onSelected: (_) => setState(() => _gender = 'male'),
                  ),
                  ChoiceChip(
                    label: Text(strings.femaleLabel),
                    selected: _gender == 'female',
                    onSelected: (_) => setState(() => _gender = 'female'),
                  ),
                  ChoiceChip(
                    label: Text(strings.genderOtherLabel),
                    selected: _gender == 'other',
                    onSelected: (_) => setState(() => _gender = 'other'),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.addressLabel,
                hintText: strings.addressPlaceholder,
                controller: _address,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.cityLabel,
                hintText: strings.cityPlaceholder,
                controller: _city,
              ),
              if (widget.saveError != null) ...[
                const SizedBox(height: AppTheme.spaceMd),
                InlineMessage(
                  message: _saveErrorMessage(strings, widget.saveError!),
                  tone: InlineMessageTone.error,
                ),
              ],
              const SizedBox(height: AppTheme.spaceLg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.isSaving ? null : _resetToInitial,
                      child: Text(strings.cancelChangesAction),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: PrimaryButton(
                      label: strings.saveChangesAction,
                      isLoading: widget.isSaving,
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _saveErrorMessage(AppStrings strings, ProfileErrorKind kind) {
  return switch (kind) {
    ProfileErrorKind.timeout => strings.profileSaveTimeout,
    ProfileErrorKind.serviceUnavailable =>
      strings.profileSaveServiceUnavailable,
    ProfileErrorKind.generic => strings.profileSaveError,
  };
}
