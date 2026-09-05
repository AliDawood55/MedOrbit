import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/profile_provider.dart';

/// Account-owned public contact links. The backend remains authoritative, but
/// local validation keeps malformed values from making a network round-trip.
class SocialLinksSection extends StatefulWidget {
  const SocialLinksSection({
    super.key,
    required this.initialLinks,
    required this.strings,
    required this.isSaving,
    required this.error,
    required this.onSave,
  });

  final Map<String, String> initialLinks;
  final AppStrings strings;
  final bool isSaving;
  final ProfileErrorKind? error;
  final ValueChanged<Map<String, String>> onSave;

  @override
  State<SocialLinksSection> createState() => _SocialLinksSectionState();
}

class _SocialLinksSectionState extends State<SocialLinksSection> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final key in _urlKeys)
      key: TextEditingController(text: widget.initialLinks[key] ?? ''),
    'whatsapp': TextEditingController(
      text: widget.initialLinks['whatsapp'] ?? '',
    ),
  };

  static const _urlKeys = [
    'website',
    'instagram',
    'facebook',
    'tiktok',
    'linkedin',
    'x',
    'youtube',
  ];

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _urlValidator(String? value) {
    final link = value?.trim() ?? '';
    if (link.isEmpty) return null;
    final uri = Uri.tryParse(link);
    return uri == null ||
            uri.scheme.toLowerCase() != 'https' ||
            !uri.hasAuthority
        ? widget.strings.socialLinksInvalidUrl
        : null;
  }

  String? _whatsAppValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final number = raw
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^00'), '');
    return number.length < 8 || number.length > 15
        ? widget.strings.socialLinksInvalidWhatsApp
        : null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final links = <String, String>{};
    for (final entry in _controllers.entries) {
      var value = entry.value.text.trim();
      if (value.isEmpty) continue;
      if (entry.key == 'whatsapp') {
        value = value
            .replaceAll(RegExp(r'[^0-9]'), '')
            .replaceFirst(RegExp(r'^00'), '');
      }
      links[entry.key] = value;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSave(links);
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppTheme.secondaryGradient,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: const Icon(Icons.link_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: SectionHeader(
                      title: strings.socialLinksTitle,
                      subtitle: strings.socialLinksSubtitle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceLg),
              AppTextField(
                label: strings.socialLinksWhatsApp,
                hintText: strings.socialLinksWhatsAppHint,
                controller: _controllers['whatsapp'],
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\- ]')),
                ],
                validator: _whatsAppValidator,
                prefixIcon: const Icon(Icons.chat_outlined),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.socialLinksWebsite,
                hintText: 'https://example.com',
                controller: _controllers['website'],
                keyboardType: TextInputType.url,
                validator: _urlValidator,
                prefixIcon: const Icon(Icons.language_rounded),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              for (final key in _urlKeys.where((key) => key != 'website')) ...[
                AppTextField(
                  label: strings.socialLinksPlatform(key),
                  hintText: 'https://',
                  controller: _controllers[key],
                  keyboardType: TextInputType.url,
                  validator: _urlValidator,
                  prefixIcon: Icon(_iconFor(key)),
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              if (widget.error != null) ...[
                Text(
                  _errorText(strings, widget.error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              PrimaryButton(
                label: strings.socialLinksSave,
                icon: Icons.save_outlined,
                isLoading: widget.isSaving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String key) => switch (key) {
    'instagram' => Icons.camera_alt_outlined,
    'facebook' => Icons.thumb_up_alt_outlined,
    'tiktok' => Icons.music_note_outlined,
    'linkedin' => Icons.business_center_outlined,
    'x' => Icons.alternate_email_rounded,
    'youtube' => Icons.play_circle_outline_rounded,
    _ => Icons.link_outlined,
  };

  String _errorText(AppStrings strings, ProfileErrorKind error) =>
      switch (error) {
        ProfileErrorKind.timeout => strings.profileSaveTimeout,
        ProfileErrorKind.serviceUnavailable =>
          strings.profileSaveServiceUnavailable,
        ProfileErrorKind.generic => strings.profileSaveError,
      };
}
