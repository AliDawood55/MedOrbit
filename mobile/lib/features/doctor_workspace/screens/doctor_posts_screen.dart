import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/doctor_models.dart';
import '../providers/doctor_workspace_providers.dart';
import '../widgets/doctor_workspace_gate.dart';

class DoctorPostsScreen extends ConsumerWidget {
  const DoctorPostsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final async = ref.watch(doctorPostsProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(s.doctorPosts)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, s, null),
        icon: const Icon(Icons.add),
        label: Text(s.create),
      ),
      body: DoctorWorkspaceGate(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetryState(
            title: s.doctorPosts,
            message: doctorErrorMessage(s, e),
            retryLabel: s.retry,
            onRetry: () => ref.read(doctorPostsProvider.notifier).load(),
          ),
          data: (posts) => RefreshIndicator(
            onRefresh: () => ref.read(doctorPostsProvider.notifier).load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: AppTheme.spaceLg, bottom: 96),
              children: [
                ResponsiveContent(
                  child: posts.isEmpty
                      ? EmptyState(
                          icon: Icons.article_outlined,
                          title: s.noPosts,
                        )
                      : Column(
                          children: posts
                              .map((p) => _card(context, ref, s, p))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorPost p,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(p.title, style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 6,
                children: [
                  StatusBadge(
                    label: s.doctorStatus(p.status),
                    color: p.isPublished ? AppTheme.success : AppTheme.warning,
                  ),
                  StatusBadge(
                    label: s.doctorStatus(p.moderationStatus),
                    color: p.moderationStatus == 'approved'
                        ? AppTheme.info
                        : AppTheme.warning,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(s.doctorPostCategory(p.category)),
          const SizedBox(height: 8),
          Text(p.body, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(
            '♥ ${p.likeCount} · 💬 ${p.commentCount}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(context, ref, s, p),
                icon: const Icon(Icons.edit_outlined),
                label: Text(s.edit),
              ),
              OutlinedButton.icon(
                onPressed: () => _delete(context, ref, s, p),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.delete),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorPost? post,
  ) async {
    final form = GlobalKey<FormState>(),
        title = TextEditingController(text: post?.title),
        body = TextEditingController(text: post?.body);
    var category = post?.category ?? 'health_tip',
        publish = post?.isPublished ?? false;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(post == null ? s.create : s.edit),
          content: Form(
            key: form,
            child: SizedBox(
              width: 520,
              child: Column(
                children: [
                  TextFormField(
                    controller: title,
                    maxLength: 150,
                    decoration: InputDecoration(labelText: s.postTitle),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? s.doctorRequiredField
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(labelText: s.category),
                    items:
                        const [
                              'health_tip',
                              'announcement',
                              'clinic_news',
                              'article',
                            ]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(s.doctorPostCategory(v)),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => category = v ?? category,
                  ),
                  TextFormField(
                    controller: body,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: 10000,
                    decoration: InputDecoration(labelText: s.postBody),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? s.doctorRequiredField
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.publish),
                    value: publish,
                    onChanged: (v) => setLocal(() => publish = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState?.validate() ?? false) {
                  Navigator.pop(context, {
                    'title': title.text,
                    'body': body.text,
                    'category': category,
                    'publish': publish,
                  });
                }
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    body.dispose();
    if (payload == null || !context.mounted) return;
    final result = await ref
        .read(doctorPostsProvider.notifier)
        .save(
          id: post?.id,
          title: payload['title'] as String,
          category: payload['category'] as String,
          body: payload['body'] as String,
          publish: payload['publish'] as bool,
        );
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorPost p,
  ) async {
    final yes = await confirmDoctorAction(
      context,
      title: s.delete,
      body: s.deleteConfirmation,
      strings: s,
    );
    if (!yes || !context.mounted) return;
    final result = await ref.read(doctorPostsProvider.notifier).delete(p.id);
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }
}
