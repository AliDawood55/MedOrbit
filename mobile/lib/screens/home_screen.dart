import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          TextButton(
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            child: Text(l10n.switchLanguage),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.homeTitle, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(l10n.homeSubtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/doctors'),
              child: Text(l10n.findDoctor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: Text(l10n.navLogin),
                ),
                TextButton(
                  onPressed: () => context.go('/register'),
                  child: Text(l10n.navRegister),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
