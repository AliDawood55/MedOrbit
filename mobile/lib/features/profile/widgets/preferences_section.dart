import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_sections.dart';

/// Language (synced to the account) and theme (device-only) selectors.
class PreferencesSection extends StatelessWidget {
  const PreferencesSection({
    super.key,
    required this.strings,
    required this.languageCode,
    required this.isSyncingLanguage,
    required this.languageSyncFailed,
    required this.onLanguageChanged,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final AppStrings strings;

  /// `'ar' | 'en'`.
  final String languageCode;
  final bool isSyncingLanguage;
  final bool languageSyncFailed;
  final ValueChanged<String> onLanguageChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.profileSectionLanguage,
              subtitle: strings.profileLanguageDesc,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppTheme.minTouchTarget,
              ),
              child: SegmentedButton<String>(
                key: const ValueKey('profile-language-selector'),
                segments: [
                  ButtonSegment<String>(
                    value: 'ar',
                    label: Text(strings.profileLanguageArOption),
                  ),
                  ButtonSegment<String>(
                    value: 'en',
                    label: Text(strings.profileLanguageEnOption),
                  ),
                ],
                selected: {languageCode},
                onSelectionChanged: isSyncingLanguage
                    ? null
                    : (selection) => onLanguageChanged(selection.first),
              ),
            ),
            if (languageSyncFailed) ...[
              const SizedBox(height: AppTheme.spaceSm),
              InlineMessage(
                message: strings.profileLanguageSyncError,
                tone: InlineMessageTone.warning,
              ),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            SectionHeader(
              title: strings.profileSectionTheme,
              subtitle: strings.profileThemeDesc,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppTheme.minTouchTarget,
              ),
              child: SegmentedButton<ThemeMode>(
                key: const ValueKey('profile-theme-selector'),
                segments: [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text(strings.themeSystemOption),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text(strings.themeLightOption),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text(strings.themeDarkOption),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) =>
                    onThemeChanged(selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
