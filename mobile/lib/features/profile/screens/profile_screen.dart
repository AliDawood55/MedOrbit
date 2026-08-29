import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/profile_edit_model.dart';
import '../providers/profile_provider.dart';
import '../widgets/change_password_sheet.dart';
import '../widgets/preferences_section.dart';
import '../widgets/profile_avatar_section.dart';
import '../widgets/profile_form_section.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(profileControllerProvider);
    final notifier = ref.read(profileControllerProvider.notifier);
    final avatarOrigin = ref.watch(activeOriginProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final role = ref.watch(authControllerProvider).user?.role.toLowerCase();
    final canUseCareMessages = role == 'patient' || role == 'doctor';

    return AppScaffold(
      appBar: AppBar(title: Text(strings.profileTitle)),
      useSafeArea: true,
      keyboardAware: true,
      body: state.profile.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppTheme.spaceMd),
              Text(strings.loading),
            ],
          ),
        ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Card(
              child: ErrorRetryState(
                title: strings.profileLoadError,
                message: strings.errorGeneric,
                retryLabel: strings.retry,
                onRetry: notifier.retry,
                variant: ErrorRetryVariant.compact,
              ),
            ),
          ),
        ),
        data: (profile) => RefreshIndicator(
          onRefresh: notifier.retry,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: strings.profileTitle,
                      subtitle: strings.profileSubtitle,
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    ProfileAvatarSection(
                      profile: profile,
                      isArabic: isArabic,
                      strings: strings,
                      avatarOrigin: avatarOrigin,
                      isUploading: state.isUploadingAvatar,
                      avatarError: state.avatarError,
                      onChangePhoto: () => _pickAvatar(context, ref),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    ProfileFormSection(
                      key: ValueKey('profile-form-${profile.id}'),
                      initialDraft: ProfileEditModel.fromProfile(profile),
                      strings: strings,
                      isSaving: state.isSaving,
                      saveError: state.saveError,
                      onSave: (draft) =>
                          _handleSave(context, notifier, draft, strings),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    PreferencesSection(
                      strings: strings,
                      languageCode: isArabic ? 'ar' : 'en',
                      isSyncingLanguage: state.isSyncingLanguage,
                      languageSyncFailed: state.languageSyncFailed,
                      onLanguageChanged: notifier.setLanguage,
                      themeMode: themeMode,
                      onThemeChanged: (mode) => ref
                          .read(themeControllerProvider.notifier)
                          .setThemeMode(mode),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    FeatureCard(
                      title: strings.billingTitle,
                      subtitle: strings.billingProfileDescription,
                      icon: Icons.workspace_premium_outlined,
                      color: AppTheme.violet,
                      trailing: Icon(
                        AppTheme.directionalForwardIconOf(context),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => context.push(RoutePaths.billing),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    if (canUseCareMessages) ...[
                      FeatureCard(
                        title: strings.messagesTitle,
                        subtitle: strings.messagesSubtitle,
                        icon: Icons.forum_outlined,
                        onTap: () => context.push(RoutePaths.messages),
                        semanticLabel: strings.messagesOpenConversation,
                      ),
                      const SizedBox(height: AppTheme.spaceLg),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.spaceLg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SectionHeader(
                              title: strings.profileSectionPassword,
                              subtitle: strings.profilePasswordDesc,
                            ),
                            PrimaryButton(
                              label: strings.changePasswordAction,
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) =>
                                    const _ChangePasswordSheetHost(),
                              ),
                            ),
                          ],
                        ),
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
}

Future<void> _handleSave(
  BuildContext context,
  ProfileController notifier,
  ProfileEditModel draft,
  AppStrings strings,
) async {
  final ok = await notifier.save(draft);
  if (ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.profileSaveSuccess)));
  }
}

/// Picks a gallery image and uploads it. Cancelling the picker (a null
/// result) is silent — that's the user changing their mind, not a failure.
Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
  final strings = ref.read(appStringsProvider);
  XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
  } catch (_) {
    return;
  }
  if (file == null) return;

  final sizeBytes = await file.length();
  final notifier = ref.read(profileControllerProvider.notifier);
  final ok = await notifier.uploadAvatar(
    filePath: file.path,
    fileName: file.name,
    fileSizeBytes: sizeBytes,
  );
  if (ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.profileSaveSuccess)));
  }
}

/// Bridges the modal sheet (outside the page's own widget subtree) to the
/// controller, so it can show live submit/error state and, on success, pop
/// itself and hand off to a forced re-login — the backend revokes every
/// session on a password change.
class _ChangePasswordSheetHost extends ConsumerWidget {
  const _ChangePasswordSheetHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(profileControllerProvider);

    return ChangePasswordSheet(
      strings: strings,
      isSubmitting: state.isChangingPassword,
      error: state.passwordError,
      onSubmit: (current, next) => _submit(context, ref, current, next),
    );
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    String current,
    String next,
  ) async {
    final strings = ref.read(appStringsProvider);
    final notifier = ref.read(profileControllerProvider.notifier);
    final ok = await notifier.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    if (!ok || !context.mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.passwordChangedMessage)));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (context.mounted) context.go(RoutePaths.login);
  }
}
