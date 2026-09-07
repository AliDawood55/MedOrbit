import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/billing_models.dart';
import '../providers/billing_provider.dart';
import '../widgets/billing_formatters.dart';

class SandboxCheckoutScreen extends ConsumerStatefulWidget {
  const SandboxCheckoutScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<SandboxCheckoutScreen> createState() =>
      _SandboxCheckoutScreenState();
}

class _SandboxCheckoutScreenState extends ConsumerState<SandboxCheckoutScreen> {
  SandboxCheckout? _checkout;
  ApiException? _error;
  bool _loading = true;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.token.trim().isEmpty) {
      setState(() {
        _loading = false;
        _error = const ApiException(
          message: 'Invalid checkout token.',
          code: 'CHECKOUT_NOT_FOUND',
        );
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(billingApiProvider);
      final config = await api.getConfig();
      if (!config.sandbox) {
        throw const ApiException(
          message: 'Sandbox is disabled.',
          code: 'SANDBOX_DISABLED',
        );
      }
      final checkout = await api.getSandboxCheckout(widget.token);
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(error);
        _loading = false;
      });
    }
  }

  Future<void> _complete(String outcome) async {
    if (_completing || _checkout?.isOpen != true) return;
    setState(() {
      _completing = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(billingApiProvider)
          .completeSandboxCheckout(widget.token, outcome);
      if (!mounted) return;
      await ref
          .read(billingControllerProvider.notifier)
          .refreshAfterSandboxCheckout(result.entitlements);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RoutePaths.billing);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _error = ApiException.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(strings.sandboxBillingTitle)),
      useSafeArea: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _checkout == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: ErrorRetryState(
                  title: strings.sandboxBillingTitle,
                  message: strings.billingError(_error?.code),
                  retryLabel: strings.retry,
                  onRetry: _load,
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
              child: ResponsiveContent(
                child: _checkoutContent(strings, _checkout!),
              ),
            ),
    );
  }

  Widget _checkoutContent(AppStrings strings, SandboxCheckout checkout) {
    final price = formatServerPrice(
      priceCents: checkout.priceCents,
      currency: checkout.currency,
      isArabic: strings.isArabic,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageIntro(
          title: strings.sandboxBillingTitle,
          subtitle: strings.sandboxBillingBanner,
          icon: Icons.science_outlined,
          color: AppTheme.warning,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        InlineMessage(
          message: strings.sandboxBillingBanner,
          tone: InlineMessageTone.warning,
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: checkout.localizedName(strings.isArabic),
                  subtitle:
                      '$price · ${strings.billingInterval(checkout.billingInterval, checkout.intervalCount)}',
                ),
                InlineMessage(
                  message: strings.sandboxNoCard,
                  tone: InlineMessageTone.info,
                ),
                if (!checkout.isOpen) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  InlineMessage(
                    message: strings.sandboxCheckoutClosed,
                    tone: InlineMessageTone.warning,
                  ),
                ] else ...[
                  const SizedBox(height: AppTheme.spaceLg),
                  PrimaryButton(
                    label: strings.sandboxSimulateSuccess,
                    icon: Icons.check_circle_outline_rounded,
                    isLoading: _completing,
                    onPressed: _completing ? null : () => _complete('success'),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  OutlinedButton.icon(
                    onPressed: _completing ? null : () => _complete('failure'),
                    icon: const Icon(Icons.error_outline_rounded),
                    label: Text(strings.sandboxSimulateFailure),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  TextButton.icon(
                    onPressed: _completing ? null : () => _complete('canceled'),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(strings.sandboxSimulateCancel),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  InlineMessage(
                    message: strings.billingError(_error!.code),
                    tone: InlineMessageTone.error,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
