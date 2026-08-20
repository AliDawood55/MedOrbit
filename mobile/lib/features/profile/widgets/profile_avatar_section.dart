import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../home/models/user_profile_model.dart';
import '../providers/profile_provider.dart';

class ProfileAvatarSection extends StatelessWidget {
  const ProfileAvatarSection({
    super.key,
    required this.profile,
    required this.isArabic,
    required this.strings,
    required this.avatarOrigin,
    required this.isUploading,
    required this.avatarError,
    required this.onChangePhoto,
  });

  final UserProfileModel profile;
  final bool isArabic;
  final AppStrings strings;

  /// Prepended to `avatar_url`, which the backend returns as a relative path
  /// (e.g. `/uploads/avatars/169...jpg`).
  final String avatarOrigin;
  final bool isUploading;
  final AvatarErrorKind? avatarError;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final name = profile.displayName(isArabic);
    final avatarUrl = profile.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final localeCode = isArabic ? 'ar' : 'en';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppTheme.primaryTint,
                      backgroundImage: hasAvatar
                          ? NetworkImage('$avatarOrigin$avatarUrl')
                          : null,
                      child: hasAvatar
                          ? null
                          : Text(
                              profile.initial,
                              style: const TextStyle(
                                fontSize: 28,
                                color: AppTheme.primary,
                                fontWeight: AppTheme.weightExtraBold,
                              ),
                            ),
                    ),
                    PositionedDirectional(
                      end: -6,
                      bottom: -6,
                      child: Material(
                        color: AppTheme.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: const ValueKey('profile-change-photo'),
                          customBorder: const CircleBorder(),
                          onTap: isUploading ? null : onChangePhoto,
                          child: SizedBox(
                            width: AppTheme.minTouchTarget,
                            height: AppTheme.minTouchTarget,
                            child: isUploading
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Semantics(
                                    button: true,
                                    label: strings.changePhotoAction,
                                    child: const Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.white,
                                      size: AppTheme.iconSm,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppTheme.spaceLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: AppTheme.weightExtraBold),
                      ),
                      Text(
                        profile.email,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (profile.createdAt != null) ...[
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          strings.profileMemberSince(
                            formatDate(
                              profile.createdAt!,
                              localeCode: localeCode,
                            ),
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              strings.avatarHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (avatarError != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              InlineMessage(
                message: _avatarErrorMessage(strings, avatarError!),
                tone: InlineMessageTone.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _avatarErrorMessage(AppStrings strings, AvatarErrorKind kind) {
  return switch (kind) {
    AvatarErrorKind.invalidType => strings.avatarErrorInvalidType,
    AvatarErrorKind.tooLarge => strings.avatarErrorTooLarge,
    AvatarErrorKind.timeout ||
    AvatarErrorKind.serviceUnavailable ||
    AvatarErrorKind.generic => strings.avatarErrorGeneric,
  };
}
