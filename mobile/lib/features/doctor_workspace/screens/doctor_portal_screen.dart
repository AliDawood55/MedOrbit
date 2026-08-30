import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/doctor_portal_api.dart';

class DoctorPortalScreen extends ConsumerWidget {
  const DoctorPortalScreen({super.key, required this.initialSection});
  final String initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final title = switch (initialSection) {
      'posts' => ar ? 'منشوراتي' : 'My posts',
      'billing' => ar ? 'الاشتراك والفوترة' : 'Subscription & billing',
      _ => ar ? 'الملف المهني' : 'Professional profile',
    };
    if (ref.watch(authControllerProvider).user?.role != 'doctor') {
      return const AppScaffold(body: Center(child: Text('Doctor access required')));
    }
    return AppScaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go(RoutePaths.home)),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: switch (initialSection) {
        'posts' => const _Posts(),
        'billing' => const _Billing(),
        _ => const _Profile(),
      },
    );
  }
}

class _Profile extends ConsumerStatefulWidget {
  const _Profile();
  @override
  ConsumerState<_Profile> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<_Profile> {
  late Future<Map<String, dynamic>> _future;
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();
  final _fee = TextEditingController();
  bool _editing = false;
  bool _accepting = false;
  DoctorPortalApi get _api => DoctorPortalApi(ref.read(dioProvider));

  @override
  void initState() { super.initState(); _future = _load(); }
  @override
  void dispose() { _headline.dispose(); _bio.dispose(); _city.dispose(); _fee.dispose(); super.dispose(); }

  Future<Map<String, dynamic>> _load() async {
    final profile = await _api.professionalProfile();
    _headline.text = profile['professional_headline']?.toString() ?? '';
    _bio.text = profile['professional_bio']?.toString() ?? '';
    _city.text = profile['city']?.toString() ?? '';
    _fee.text = profile['consultation_fee']?.toString() ?? '';
    _accepting = profile['is_accepting_patients'] == true;
    return profile;
  }

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ErrorRetryState(title: ar ? 'تعذر تحميل الملف' : 'Could not load profile', message: ar ? 'حاول مرة أخرى.' : 'Please try again.', retryLabel: ar ? 'إعادة المحاولة' : 'Retry', onRetry: () => setState(() => _future = _load()));
        final profile = snapshot.data!;
        final specialty = (ar ? profile['specialty_ar'] : profile['specialty_en']) ?? profile['specialty_en'] ?? profile['specialty_ar'] ?? (ar ? 'طبيب معتمد' : 'Approved doctor');
        return ListView(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(specialty.toString(), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: AppTheme.spaceSm), Text(ar ? 'رقم الترخيص: ${profile['medical_license_number'] ?? '—'}' : 'Medical license: ${profile['medical_license_number'] ?? '—'}')]))) ,
            const SizedBox(height: AppTheme.spaceLg),
            TextField(controller: _headline, enabled: _editing, decoration: InputDecoration(labelText: ar ? 'العنوان المهني' : 'Professional headline')),
            const SizedBox(height: AppTheme.spaceMd),
            TextField(controller: _bio, enabled: _editing, maxLines: 5, decoration: InputDecoration(labelText: ar ? 'السيرة المهنية' : 'Professional bio')),
            const SizedBox(height: AppTheme.spaceMd),
            TextField(controller: _city, enabled: _editing, decoration: InputDecoration(labelText: ar ? 'المدينة' : 'City')),
            const SizedBox(height: AppTheme.spaceMd),
            TextField(controller: _fee, enabled: _editing, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ar ? 'رسوم الاستشارة' : 'Consultation fee')),
            SwitchListTile(value: _accepting, onChanged: _editing ? (value) => setState(() => _accepting = value) : null, title: Text(ar ? 'استقبال مرضى جدد' : 'Accept new patients')),
            FilledButton.icon(onPressed: _editing ? () => _save(ar) : () => setState(() => _editing = true), icon: Icon(_editing ? Icons.save_outlined : Icons.edit_outlined), label: Text(_editing ? (ar ? 'حفظ الملف' : 'Save profile') : (ar ? 'تعديل الملف المهني' : 'Edit professional profile'))),
          ],
        );
      },
    );
  }

  Future<void> _save(bool ar) async {
    try {
      await _api.updateProfessionalProfile({'professionalHeadline': _headline.text.trim(), 'bio': _bio.text.trim(), 'city': _city.text.trim(), 'consultationFee': num.tryParse(_fee.text.trim()) ?? 0, 'isAcceptingPatients': _accepting});
      if (mounted) { setState(() => _editing = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ar ? 'تم حفظ الملف المهني' : 'Professional profile saved'))); }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ar ? 'تعذر حفظ الملف.' : 'Could not save profile.'))); }
  }
}

class _Posts extends ConsumerStatefulWidget { const _Posts(); @override ConsumerState<_Posts> createState() => _PostsState(); }
class _PostsState extends ConsumerState<_Posts> {
  late Future<List<Map<String, dynamic>>> _future;
  DoctorPortalApi get _api => DoctorPortalApi(ref.read(dioProvider));
  @override void initState() { super.initState(); _future = _api.posts(); }
  void _reload() => setState(() => _future = _api.posts());

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ErrorRetryState(title: ar ? 'تعذر تحميل المنشورات' : 'Could not load posts', message: ar ? 'حاول مرة أخرى.' : 'Please try again.', retryLabel: ar ? 'إعادة المحاولة' : 'Retry', onRetry: _reload);
        final posts = snapshot.data!;
        return ListView(padding: const EdgeInsets.all(AppTheme.spaceLg), children: [
          FilledButton.icon(onPressed: () => _edit(ar), icon: const Icon(Icons.add), label: Text(ar ? 'منشور جديد' : 'New post')),
          const SizedBox(height: AppTheme.spaceMd),
          if (posts.isEmpty) Text(ar ? 'لا توجد منشورات بعد.' : 'No posts yet.'),
          ...posts.map((post) {
            final title = (ar ? post['title_ar'] : post['title_en']) ?? post['title_en'] ?? post['title_ar'] ?? '';
            return Card(child: ListTile(title: Text(title.toString()), subtitle: Text(post['body']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis), trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'edit') _edit(ar, post); if (value == 'delete') _delete(post['id'].toString()); }, itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(ar ? 'تعديل' : 'Edit')), PopupMenuItem(value: 'delete', child: Text(ar ? 'حذف' : 'Delete'))])));
          }),
        ]);
      },
    );
  }

  Future<void> _delete(String id) async { await _api.deletePost(id); if (mounted) _reload(); }
  Future<void> _edit(bool ar, [Map<String, dynamic>? current]) async {
    final title = TextEditingController(
      text: current == null
          ? ''
          : (ar ? current['title_ar'] : current['title_en'])?.toString() ?? '',
    );
    final body = TextEditingController(text: current?['body']?.toString() ?? '');
    var publish = current?['is_published'] == true;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(title: Text(current == null ? (ar ? 'منشور جديد' : 'New post') : (ar ? 'تعديل المنشور' : 'Edit post')), content: StatefulBuilder(builder: (context, setLocal) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: InputDecoration(labelText: ar ? 'العنوان' : 'Title')), TextField(controller: body, maxLines: 5, decoration: InputDecoration(labelText: ar ? 'المحتوى' : 'Content')), SwitchListTile(value: publish, onChanged: (value) => setLocal(() => publish = value), title: Text(ar ? 'نشر الآن' : 'Publish now'))]))), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(ar ? 'إلغاء' : 'Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(ar ? 'حفظ' : 'Save'))]));
    if (saved != true) return;
    final payload = {'title': title.text.trim(), 'body': body.text.trim(), 'category': 'health_tip', 'isPublished': publish};
    if (current == null) { await _api.createPost(payload); } else { await _api.updatePost(current['id'].toString(), payload); }
    if (mounted) _reload();
  }
}

class _Billing extends ConsumerStatefulWidget { const _Billing(); @override ConsumerState<_Billing> createState() => _BillingState(); }
class _BillingState extends ConsumerState<_Billing> {
  late Future<Map<String, dynamic>> _future;
  @override void initState() { super.initState(); _future = DoctorPortalApi(ref.read(dioProvider)).billing(); }
  @override Widget build(BuildContext context) { final ar = ref.watch(localeControllerProvider).languageCode == 'ar'; return FutureBuilder<Map<String, dynamic>>(future: _future, builder: (context, snapshot) { if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator()); if (snapshot.hasError) return ErrorRetryState(title: ar ? 'تعذر تحميل الاشتراك' : 'Could not load subscription', message: ar ? 'حاول مرة أخرى.' : 'Please try again.', retryLabel: ar ? 'إعادة المحاولة' : 'Retry', onRetry: () => setState(() => _future = DoctorPortalApi(ref.read(dioProvider)).billing())); final data = snapshot.data!; final plan = (ar ? data['plan_name_ar'] : data['plan_name_en']) ?? data['plan_code'] ?? 'FREE'; return ListView(padding: const EdgeInsets.all(AppTheme.spaceLg), children: [Card(child: ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: Text(plan.toString()), subtitle: Text(ar ? 'الحالة: ${data['status'] ?? 'Free'}' : 'Status: ${data['status'] ?? 'Free'}'))), const SizedBox(height: AppTheme.spaceLg), Text(ar ? 'تتطلب ترقية الخطة بوابة دفع مهيأة من مسؤول المنصة.' : 'Plan upgrades require a payment gateway configured by the platform administrator.'), if (data['current_period_end'] != null) Padding(padding: const EdgeInsets.only(top: AppTheme.spaceMd), child: Text(ar ? 'ينتهي في: ${data['current_period_end']}' : 'Current period ends: ${data['current_period_end']}'))]); }); }
}
