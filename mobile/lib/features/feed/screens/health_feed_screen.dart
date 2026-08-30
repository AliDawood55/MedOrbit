import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/role_header_actions.dart';

/// Same authenticated feed operations as the web client: like, comment, and
/// follow. The backend keeps the final ownership and rate-limit checks.
class HealthFeedScreen extends ConsumerStatefulWidget {
  const HealthFeedScreen({super.key});
  @override
  ConsumerState<HealthFeedScreen> createState() => _HealthFeedScreenState();
}

class _HealthFeedScreenState extends ConsumerState<HealthFeedScreen> {
  late Future<List<Map<String, dynamic>>> _posts;
  @override
  void initState() {
    super.initState();
    _posts = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final role = ref.read(authControllerProvider).user?.role.toLowerCase();
    final isAdmin = role == 'admin' || role == 'super_admin';
    final response = await ref
        .read(dioProvider)
        .get<Map<String, dynamic>>(
          isAdmin ? '/admin/social/posts' : '/feed/posts',
          queryParameters: isAdmin ? null : const {'limit': 20},
        );
    final data = response.data?['data'];
    if (response.data?['success'] != true)
      throw DioException(requestOptions: RequestOptions(path: '/feed/posts'));
    // Public feed returns {items: [...]}; the protected admin moderation
    // endpoint intentionally returns the post list itself.
    final items = data is Map ? data['items'] : data;
    return items is List
        ? items
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : const [];
  }

  Future<void> _refresh() async => setState(() => _posts = _load());
  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final role = ref.watch(authControllerProvider).user?.role.toLowerCase();
    final isAdmin = role == 'admin' || role == 'super_admin';
    return AppScaffold(
      appBar: AppBar(
        title: Text(ar ? 'المنشورات الصحية' : 'Health feed'),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _posts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return ErrorRetryState(
              title: ar ? 'تعذر تحميل المنشورات' : 'Could not load the feed',
              message: ar ? 'حاول مرة أخرى.' : 'Please try again.',
              retryLabel: ar ? 'إعادة المحاولة' : 'Retry',
              onRetry: _refresh,
            );
          final posts = snapshot.data ?? const [];
          if (posts.isEmpty)
            return Center(
              child: Text(
                ar ? 'لا توجد منشورات صحية بعد.' : 'No health posts yet.',
              ),
            );
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              itemCount: posts.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppTheme.spaceMd),
              itemBuilder: (_, index) => _FeedCard(
                post: posts[index],
                isArabic: ar,
                isAdmin: isAdmin,
                onModerated: _refresh,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeedCard extends ConsumerStatefulWidget {
  const _FeedCard({
    required this.post,
    required this.isArabic,
    required this.isAdmin,
    required this.onModerated,
  });
  final Map<String, dynamic> post;
  final bool isArabic;
  final bool isAdmin;
  final Future<void> Function() onModerated;
  @override
  ConsumerState<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends ConsumerState<_FeedCard> {
  bool _busy = false;
  Map<String, dynamic> get post => widget.post;
  bool get ar => widget.isArabic;
  Dio get _dio => ref.read(dioProvider);
  Map<String, dynamic> get _doctor => post['doctor'] is Map
      ? Map<String, dynamic>.from(post['doctor'] as Map)
      : <String, dynamic>{
          'id': post['doctor_id'],
          'first_name_ar': post['first_name_ar'],
          'last_name_ar': post['last_name_ar'],
          'first_name_en': post['first_name_en'],
          'last_name_en': post['last_name_en'],
        };
  String get _title =>
      ((ar ? post['title_ar'] : post['title_en']) ?? post['title'] ?? '')
          .toString();

  Future<void> _like() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final liked = post['liked_by_me'] == true;
      final response = liked
          ? await _dio.delete<Map<String, dynamic>>(
              '/feed/posts/${post['id']}/like',
            )
          : await _dio.post<Map<String, dynamic>>(
              '/feed/posts/${post['id']}/like',
            );
      final data = response.data?['data'];
      if (!mounted) return;
      if (data is Map)
        setState(() {
          post['liked_by_me'] = data['liked'] == true;
          post['like_count'] = data['like_count'] ?? post['like_count'];
        });
    } catch (_) {
      if (mounted)
        _message(ar ? 'تعذر تحديث الإعجاب.' : 'Could not update the like.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _follow() async {
    if (_busy || post['is_own_doctor'] == true) return;
    final id = _doctor['id'];
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final following = post['following_doctor'] == true;
      if (following) {
        await _dio.delete<Map<String, dynamic>>('/doctors/$id/follow');
      } else {
        await _dio.post<Map<String, dynamic>>('/doctors/$id/follow');
      }
      if (!mounted) return;
      setState(() => post['following_doctor'] = !following);
    } catch (_) {
      if (mounted)
        _message(
          ar ? 'تعذر تحديث المتابعة.' : 'Could not update the follow status.',
        );
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _comment() async {
    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ar ? 'إضافة تعليق' : 'Add comment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: ar ? 'اكتب تعليقك' : 'Write your comment',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(ar ? 'إرسال' : 'Post'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (body == null || body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _dio.post<Map<String, dynamic>>(
        '/feed/posts/${post['id']}/comments',
        data: {'body': body},
      );
      if (!mounted) return;
      setState(
        () => post['comment_count'] =
            (post['comment_count'] is num
                ? (post['comment_count'] as num).toInt()
                : 0) +
            1,
      );
    } catch (_) {
      if (mounted)
        _message(ar ? 'تعذر إضافة التعليق.' : 'Could not add the comment.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _moderate(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _dio.post<Map<String, dynamic>>(
        '/admin/social/posts/${post['id']}/moderate',
        data: {'action': action},
      );
      if (!mounted) return;
      await widget.onModerated();
    } catch (_) {
      if (mounted)
        _message(
          ar ? 'تعذر تحديث حالة المنشور.' : 'Could not update the post status.',
        );
    }
    if (mounted) setState(() => _busy = false);
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final first = ar ? _doctor['first_name_ar'] : _doctor['first_name_en'];
    final last = ar ? _doctor['last_name_ar'] : _doctor['last_name_en'];
    final name = '${first ?? ''} ${last ?? ''}'.trim();
    final specialty = ar ? _doctor['specialty_ar'] : _doctor['specialty_en'];
    final liked = post['liked_by_me'] == true;
    final following = post['following_doctor'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty
                            ? (ar ? 'طبيب MedOrbit' : 'MedOrbit doctor')
                            : name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (specialty != null)
                        Text(
                          specialty.toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (!widget.isAdmin && post['is_own_doctor'] != true)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _follow,
                    icon: Icon(
                      following ? Icons.check : Icons.person_add_alt_1_outlined,
                    ),
                    label: Text(
                      following
                          ? (ar ? 'تتابع' : 'Following')
                          : (ar ? 'متابعة' : 'Follow'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),
            if (_title.isNotEmpty)
              Text(_title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTheme.spaceSm),
            Text(post['body']?.toString() ?? ''),
            const SizedBox(height: AppTheme.spaceSm),
            if (widget.isAdmin)
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _moderate('approve'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(ar ? 'قبول' : 'Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _moderate('hide'),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(ar ? 'إخفاء' : 'Hide'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _moderate('reject'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(ar ? 'رفض' : 'Reject'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _like,
                    tooltip: ar ? 'إعجاب' : 'Like',
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? Theme.of(context).colorScheme.error : null,
                    ),
                  ),
                  Text('${post['like_count'] ?? 0}'),
                  const SizedBox(width: AppTheme.spaceMd),
                  IconButton(
                    onPressed: _busy ? null : _comment,
                    tooltip: ar ? 'تعليق' : 'Comment',
                    icon: const Icon(Icons.mode_comment_outlined),
                  ),
                  Text('${post['comment_count'] ?? 0}'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
