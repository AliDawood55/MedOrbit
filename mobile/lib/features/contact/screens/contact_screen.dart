import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/role_header_actions.dart';
import '../providers/contact_provider.dart';

class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});
  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(contactControllerProvider);
    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.contactTitle),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      keyboardAware: true,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(
                    title: strings.contactTitle,
                    subtitle: strings.contactSubtitle,
                    icon: Icons.support_agent_outlined,
                    color: AppTheme.violet,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppTextField(
                              label: strings.contactSubjectLabel,
                              controller: _subject,
                              textInputAction: TextInputAction.next,
                              prefixIcon: const Icon(Icons.subject_outlined),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? strings.contactSubjectRequired
                                  : null,
                            ),
                            const SizedBox(height: AppTheme.spaceMd),
                            AppTextField(
                              label: strings.contactMessageLabel,
                              controller: _message,
                              minLines: 5,
                              maxLines: 8,
                              textInputAction: TextInputAction.newline,
                              prefixIcon: const Icon(Icons.message_outlined),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? strings.contactMessageRequired
                                  : null,
                            ),
                            const SizedBox(height: AppTheme.spaceLg),
                            if (state.sent)
                              _Message(
                                text: strings.contactSentSuccess,
                                color: AppTheme.success,
                              ),
                            if (state.error != null)
                              _Message(
                                text: strings.contactSentError,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            if (state.sent || state.error != null)
                              const SizedBox(height: AppTheme.spaceLg),
                            PrimaryButton(
                              label: strings.contactSendAction,
                              isLoading: state.isSubmitting,
                              onPressed: _send,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final sent = await ref
        .read(contactControllerProvider.notifier)
        .submit(subject: _subject.text, message: _message.text);
    if (sent && mounted) {
      _subject.clear();
      _message.clear();
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    ),
  );
}
