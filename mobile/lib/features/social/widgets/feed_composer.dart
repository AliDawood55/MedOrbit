import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../localization/social_strings.dart';
import '../models/social_models.dart';
import '../providers/social_providers.dart';
import 'social_avatar.dart';

/// Doctor-only quick composer, pinned above the feed.
///
/// Web parity (`frontend/src/js/feed.js`): a category select, a body field,
/// a title derived from the first 140 characters of the body, and immediate
/// publication through the existing doctor-posts endpoint. Patients, admins
/// and super_admins never see this — the caller decides that via
/// `socialComposerAvailableForRole`, and the publish endpoint enforces it
/// again server-side.
class FeedComposer extends ConsumerStatefulWidget {
  const FeedComposer({super.key, required this.onPublished});

  /// Fired after a successful publish so the feed can reload and show the
  /// new post, exactly as the web composer calls `load(true)`.
  final Future<void> Function() onPublished;

  @override
  ConsumerState<FeedComposer> createState() => _FeedComposerState();
}

class _FeedComposerState extends ConsumerState<FeedComposer> {
  final TextEditingController _body = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Mirrors the web composer's `expanded` class: collapsed to a single
  /// line until it is focused or holds text, which matters far more on a
  /// phone than it does on desktop.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_syncExpansion);
    _body.addListener(_syncExpansion);
  }

  @override
  void dispose() {
    _focus.removeListener(_syncExpansion);
    _body.removeListener(_syncExpansion);
    _focus.dispose();
    _body.dispose();
    super.dispose();
  }

  void _syncExpansion() {
    final next = _focus.hasFocus || _body.text.trim().isNotEmpty;
    if (next != _expanded && mounted) setState(() => _expanded = next);
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final strings = ref.read(socialStringsProvider);
    final result = await ref
        .read(socialComposerProvider.notifier)
        .publish(_body.text);
    if (!mounted) return;

    if (!result.isSuccess) {
      // The inline alert already carries the reason; nothing else to do.
      return;
    }

    _body.clear();
    _focus.unfocus();
    messenger?.showSnackBar(SnackBar(content: Text(strings.publishSuccess)));
    await widget.onPublished();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(socialStringsProvider);
    final state = ref.watch(socialComposerProvider);
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).user;

    final displayName = (user?.name?.trim().isNotEmpty ?? false)
        ? user!.name!.trim()
        : (user?.email ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spaceMd),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Semantics(
          container: true,
          label: strings.composerLabel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The auth session carries no avatar URL, so the composer
                  // identity always renders the initial — the web composer
                  // falls back to the same initial when there is no image.
                  SocialAvatar(name: displayName, imageUrl: null, radius: 18),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Text(
                      displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: AppTheme.weightBold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              TextField(
                key: const Key('socialComposerBody'),
                controller: _body,
                focusNode: _focus,
                enabled: !state.isSubmitting,
                minLines: 1,
                maxLines: _expanded ? 6 : 1,
                // `POST /doctors/me/posts` caps the body at 10000
                // characters; the field stops the user before the server
                // has to.
                maxLength: 10000,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: strings.composerPlaceholder,
                  labelText: strings.composerLabel,
                  counterText: '',
                ),
              ),
              if (state.error != null) ...[
                const SizedBox(height: AppTheme.spaceSm),
                _ComposerAlert(
                  message: state.error!.code == ApiException.codeValidationError
                      ? strings.composerBodyRequired
                      : strings.socialError(state.error!.code),
                ),
              ],
              if (_expanded || state.isSubmitting) ...[
                const SizedBox(height: AppTheme.spaceMd),
                // Wrap so the category selector and Publish button stack
                // instead of overflowing on a 320pt screen at 2x text.
                Wrap(
                  spacing: AppTheme.spaceMd,
                  runSpacing: AppTheme.spaceSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CategorySelector(
                      value: state.category,
                      strings: strings,
                      enabled: !state.isSubmitting,
                      onChanged: (category) => ref
                          .read(socialComposerProvider.notifier)
                          .selectCategory(category),
                    ),
                    Semantics(
                      button: true,
                      enabled: !state.isSubmitting,
                      label: state.isSubmitting
                          ? strings.publishing
                          : strings.publish,
                      child: FilledButton(
                        key: const Key('socialComposerPublish'),
                        onPressed: state.isSubmitting ? null : _publish,
                        child: ExcludeSemantics(
                          child: state.isSubmitting
                              ? const SizedBox.square(
                                  dimension: AppTheme.iconSm,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(strings.publish),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.value,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });

  final PostCategory value;
  final SocialStrings strings;
  final bool enabled;
  final ValueChanged<PostCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: strings.composerCategory,
      value: strings.categoryLabel(value),
      child: DropdownButton<PostCategory>(
        key: const Key('socialComposerCategory'),
        value: value,
        onChanged: enabled
            ? (next) {
                if (next != null) onChanged(next);
              }
            : null,
        items: [
          for (final category in PostCategory.composable)
            DropdownMenuItem(
              value: category,
              child: Text(strings.categoryLabel(category)),
            ),
        ],
      ),
    );
  }
}

class _ComposerAlert extends StatelessWidget {
  const _ComposerAlert({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon plus text: the failure is never signalled by color alone.
            Icon(
              Icons.error_outline_rounded,
              size: AppTheme.iconSm,
              color: colorScheme.error,
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
