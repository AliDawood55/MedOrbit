import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../common/providers/admin_access_provider.dart';
import '../../common/widgets/admin_detail_rows.dart';
import '../providers/admin_invitations_provider.dart';

/// Mobile equivalent of the web `admin-invitation-accept.html` page.
///
/// Deliberately **not** administrator-gated: the account accepting an
/// invitation is a patient or doctor until the moment it succeeds. It is
/// session-gated only, mirroring `POST /admin/invitations/accept`'s
/// `authenticate`-only guard.
///
/// The invitee pastes the link (or the bare code) the super administrator sent
/// them. The app does not auto-open from the emailed URL: that link points at
/// the web deployment's `admin-invitation-accept.html`, and turning it into an
/// app link would require a production domain, an Android `assetlinks.json`
/// with real signing fingerprints, and an iOS `apple-app-site-association` —
/// none of which exist in this repository and none of which may be invented.
class AdminInvitationAcceptScreen extends ConsumerStatefulWidget {
  const AdminInvitationAcceptScreen({super.key, this.initialToken});

  /// Pre-fills the field when the route already carries a `token` query
  /// parameter, so a future deep link needs no extra plumbing here.
  final String? initialToken;

  @override
  ConsumerState<AdminInvitationAcceptScreen> createState() =>
      _AdminInvitationAcceptScreenState();
}

class _AdminInvitationAcceptScreenState
    extends ConsumerState<AdminInvitationAcceptScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _token;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit(AppStrings strings) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(adminInvitationAcceptControllerProvider.notifier)
        .accept(_token.text);
  }

  Future<void> _signOut() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (!mounted) return;
    context.go(RoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final access = ref.watch(adminAccessProvider);
    final state = ref.watch(adminInvitationAcceptControllerProvider);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.adminInvitationAcceptTitle)),
      useSafeArea: true,
      safeAreaTop: false,
      keyboardAware: true,
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.accepted)
                  _AcceptedCard(strings: strings, onSignOut: _signOut)
                else if (access.canUseAdminTools)
                  // An account that is already an administrator has nothing to
                  // accept; the backend answers `INVALID_TARGET` for it.
                  Card(
                    child: EmptyState(
                      key: const ValueKey('admin-invitation-already-admin'),
                      icon: Icons.verified_user_outlined,
                      title: strings.adminInvitationAcceptAlreadyAdminTitle,
                      hint: strings.adminInvitationAcceptAlreadyAdminBody,
                      variant: EmptyStateVariant.compact,
                    ),
                  )
                else
                  _AcceptForm(
                    formKey: _formKey,
                    controller: _token,
                    strings: strings,
                    state: state,
                    onSubmit: () => _submit(strings),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptForm extends StatelessWidget {
  const _AcceptForm({
    required this.formKey,
    required this.controller,
    required this.strings,
    required this.state,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final AppStrings strings;
  final AdminInvitationAcceptState state;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageIntro(
          title: strings.adminInvitationAcceptTitle,
          subtitle: strings.adminInvitationAcceptSubtitle,
          icon: Icons.admin_panel_settings_outlined,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        AdminSectionCard(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  key: const ValueKey('admin-invitation-accept-token'),
                  label: strings.adminInvitationAcceptTokenLabel,
                  hintText: strings.adminInvitationAcceptTokenHint,
                  helperText: strings.adminInvitationAcceptTokenHelper,
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !state.isSubmitting,
                  keyboardType: TextInputType.url,
                  semanticLabel: strings.adminInvitationAcceptTokenLabel,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                      ? strings.adminInvitationAcceptTokenRequired
                      : null,
                ),
                if (state.errorCode != null) ...[
                  InlineMessage(
                    message: strings.adminError(state.errorCode),
                    tone: InlineMessageTone.error,
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                ],
                PrimaryButton(
                  key: const ValueKey('admin-invitation-accept-submit'),
                  label: strings.adminInvitationAcceptSubmit,
                  icon: Icons.check_rounded,
                  isLoading: state.isSubmitting,
                  onPressed: onSubmit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AcceptedCard extends StatelessWidget {
  const _AcceptedCard({required this.strings, required this.onSignOut});

  final AppStrings strings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      title: strings.adminInvitationAcceptSuccessTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InlineMessage(
            message: strings.adminInvitationAcceptSuccessBody,
            tone: InlineMessageTone.success,
          ),
          const SizedBox(height: AppTheme.spaceLg),
          PrimaryButton(
            key: const ValueKey('admin-invitation-accept-sign-out'),
            label: strings.adminInvitationAcceptSignOut,
            icon: Icons.logout_rounded,
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}
