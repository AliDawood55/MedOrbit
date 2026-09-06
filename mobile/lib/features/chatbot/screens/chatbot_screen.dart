import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../billing/models/billing_models.dart';
import '../../billing/providers/billing_provider.dart';
import '../../billing/widgets/server_countdown.dart';
import '../../discovery/providers/location_provider.dart';
import '../../discovery/models/location_models.dart';
import '../../discovery/widgets/discovery_map.dart';
import '../../discovery/widgets/location_picker_sheet.dart';
import '../providers/chatbot_provider.dart';
import '../providers/conversations_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_location_banner.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_route_card.dart';
import '../widgets/chat_results_map.dart';
import '../widgets/chat_typing_indicator.dart';
import '../widgets/doctor_result_card.dart';
import '../widgets/place_result_card.dart';
import '../widgets/suggestion_chips.dart';

class ChatbotScreen extends ConsumerStatefulWidget {
  const ChatbotScreen({super.key, this.conversationId});
  final String? conversationId;
  @override
  ConsumerState<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends ConsumerState<ChatbotScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _attachLocation = false;
  AppLocation? _resultLocation;
  String? _selectedResultId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.conversationId;
      if (id?.isNotEmpty == true) {
        _load(id!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatbotScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != oldWidget.conversationId &&
        widget.conversationId?.isNotEmpty == true) {
      _load(widget.conversationId!);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(String id) async {
    ref.read(conversationsControllerProvider.notifier).selectConversation(id);
    await ref.read(chatbotControllerProvider.notifier).loadConversation(id);
    if (mounted) {
      setState(() {
        _selectedResultId = null;
        _resultLocation = null;
      });
    }
  }

  void _newConversation() {
    ref.read(chatbotControllerProvider.notifier).startNewConversation();
    setState(() {
      _selectedResultId = null;
      _resultLocation = null;
      _attachLocation = false;
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final location = _attachLocation
        ? ref.read(locationControllerProvider).currentLocation
        : null;
    _input.clear();
    final ok = await ref
        .read(chatbotControllerProvider.notifier)
        .sendMessage(
          text,
          latitude: location?.latitude,
          longitude: location?.longitude,
        );
    if (mounted && ok) {
      ref.read(locationControllerProvider.notifier).clearLocation();
      setState(() {
        _attachLocation = false;
        _resultLocation = location;
        _selectedResultId = null;
      });
    }
    if (mounted) _scrollToEnd();
  }

  void _scrollToEnd() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// True for suggestion text that clearly needs a location to answer, e.g.
  /// "أقرب صيدلية" / "nearest pharmacy" — mirrors the backend's default
  /// suggestion set in `chatbot.service.js#getSuggestions`.
  bool _needsLocation(String text) {
    final normalized = text.trim().toLowerCase();
    final hasArabicNearest = normalized.contains('أقرب');
    final hasEnglishNearest = normalized.contains('nearest') ||
        normalized.contains('near me');
    if (!hasArabicNearest && !hasEnglishNearest) return false;
    const placeKeywords = [
      'عيادة',
      'صيدلية',
      'مستشفى',
      'clinic',
      'pharmacy',
      'hospital',
    ];
    return placeKeywords.any(normalized.contains);
  }

  Future<void> _chooseLocation() async {
    final state = ref.read(locationControllerProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => LocationPickerSheet(
        permissionState: state.permissionState,
        errorMessage: state.errorMessage,
        isBusy:
            state.status == LocationControllerStatus.checking ||
            state.status == LocationControllerStatus.requestingPermission ||
            state.status == LocationControllerStatus.locating,
        onUseCurrentLocation: () async {
          Navigator.pop(context);
          final ok = await ref
              .read(locationControllerProvider.notifier)
              .resolveCurrentLocation();
          if (mounted && ok) setState(() => _attachLocation = true);
        },
        onSelectMapPoint: () {
          Navigator.pop(context);
          _selectMapPoint();
        },
        onSelectDistrict: (district) {
          Navigator.pop(context);
          ref
              .read(locationControllerProvider.notifier)
              .selectManualDistrict(district);
          setState(() => _attachLocation = true);
        },
        onOpenAppSettings: () =>
            ref.read(locationControllerProvider.notifier).openAppSettings(),
        onOpenLocationSettings: () => ref
            .read(locationControllerProvider.notifier)
            .openLocationSettings(),
        onClear: () {
          Navigator.pop(context);
          ref.read(locationControllerProvider.notifier).clearLocation();
          setState(() => _attachLocation = false);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _selectMapPoint() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: DiscoveryMap(
            onMapTap: (point) {
              ref
                  .read(locationControllerProvider.notifier)
                  .selectManualMapPoint(point.latitude, point.longitude);
              Navigator.pop(context);
              if (mounted) setState(() => _attachLocation = true);
            },
          ),
        ),
      ),
    );
  }

  /// Picks the message from the failure category rather than echoing the
  /// transport-layer text, so "took longer than expected" can only ever appear
  /// for a real timeout and never for an unreachable service.
  String _errorMessage(AppStrings strings, ChatbotError error) {
    return switch (error.kind) {
      ChatFailureKind.connectTimeout ||
      ChatFailureKind.receiveTimeout => strings.chatErrTimeout,
      ChatFailureKind.unavailable => strings.chatErrUnavailable,
      ChatFailureKind.invalidResponse => strings.chatErrInvalidResponse,
      ChatFailureKind.backend => strings.chatErrServer,
      ChatFailureKind.freeQuotaExhausted => strings.chatErrQuotaMessage,
      ChatFailureKind.duplicateInFlight => strings.chatErrDuplicateMessage,
      ChatFailureKind.entitlementUnavailable =>
        strings.chatErrEntitlementUnavailable,
      ChatFailureKind.subscriptionRequired =>
        strings.chatErrSubscriptionRequired,
      ChatFailureKind.subscriptionInactive =>
        strings.chatErrSubscriptionInactive,
      ChatFailureKind.rateLimited => strings.chatRateLimited,
      ChatFailureKind.unknown => strings.errorGeneric,
    };
  }

  /// Title to pair with [_errorMessage]. Entitlement failures get a title
  /// naming the actual limitation instead of the generic "could not send" —
  /// the patient did not fail to send a message, they hit a real quota or
  /// subscription rule.
  String _errorTitle(AppStrings strings, ChatbotError error) {
    return switch (error.kind) {
      ChatFailureKind.freeQuotaExhausted => strings.chatErrQuotaTitle,
      ChatFailureKind.duplicateInFlight => strings.chatErrDuplicateTitle,
      ChatFailureKind.subscriptionRequired =>
        strings.chatErrSubscriptionRequiredTitle,
      ChatFailureKind.subscriptionInactive =>
        strings.chatErrSubscriptionInactiveTitle,
      _ => strings.chatErrTitle,
    };
  }

  /// Non-retryable entitlement failures get a quiet inline notice instead of
  /// [ErrorRetryState]: the backend enforces the same denial server-side, so
  /// a prominent "Retry" action would just spend another round trip on a
  /// request that cannot succeed yet.
  Widget _errorWidget(AppStrings strings, ChatbotError error) {
    if (!error.retryable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineMessage(
            message:
                '${_errorTitle(strings, error)}. ${_errorMessage(strings, error)}',
            tone: InlineMessageTone.warning,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          OutlinedButton.icon(
            onPressed: () => context.push(RoutePaths.billing),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: Text(strings.entitlementUpgradeAction),
          ),
        ],
      );
    }

    return ErrorRetryState(
      title: _errorTitle(strings, error),
      message: _errorMessage(strings, error),
      retryLabel: strings.retry,
      onRetry: () =>
          ref.read(chatbotControllerProvider.notifier).retryLastMessage(),
      variant: ErrorRetryVariant.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatbotControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final isArabic =
        ref.watch(localeControllerProvider).languageCode == 'ar';
    final billing = ref.watch(billingControllerProvider);
    final quota = billing.entitlements?.chatbot ?? chat.quota;
    final quotaExhausted =
        quota != null &&
        !quota.unlimited &&
        !quota.allowed &&
        quota.remaining == 0;
    final location = _attachLocation
        ? ref.watch(locationControllerProvider).currentLocation
        : null;
    return AppScaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'المحادثة الطبية' : 'Medical chat'),
        actions: [
          IconButton(
            tooltip: isArabic ? 'سجل المحادثات' : 'Conversation history',
            onPressed: () => context.push(RoutePaths.conversations),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: isArabic ? 'محادثة جديدة' : 'New conversation',
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      useSafeArea: true,
      keyboardAware: true,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              children: [
                PageIntro(
                  title: isArabic ? 'إرشاد طبي' : 'Medical guidance',
                  subtitle: isArabic
                      ? 'هذه الخدمة تقدم إرشاداً عاماً ولا تغني عن الرعاية الطبية المتخصصة.'
                      : 'This service provides general guidance and does not replace professional medical care.',
                  icon: Icons.chat_bubble_outline_rounded,
                ),
                const SizedBox(height: AppTheme.spaceMd),
                if (quota != null && !quota.unlimited) ...[
                  _ChatQuotaCard(
                    quota: quota,
                    strings: strings,
                    serverTime: billing.entitlements?.serverTime,
                    onRefresh: ref
                        .read(billingControllerProvider.notifier)
                        .refreshEntitlements,
                    onUpgrade: () => context.push(RoutePaths.billing),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                ],
                ChatLocationBanner(
                  location: location,
                  onAttach: _chooseLocation,
                  onClear: () {
                    ref
                        .read(locationControllerProvider.notifier)
                        .clearLocation();
                    setState(() => _attachLocation = false);
                  },
                ),
                const SizedBox(height: AppTheme.spaceMd),
                if (chat.isInitialLoading)
                  const Center(child: CircularProgressIndicator())
                else if (!chat.hasMessages)
                  EmptyState(
                    icon: Icons.chat_outlined,
                    title: isArabic ? 'ابدأ محادثة' : 'Start a conversation',
                    hint: isArabic
                        ? 'اكتب أعراضك أو اسأل عن رعاية قريبة.'
                        : 'Describe your symptoms or ask about nearby care.',
                    variant: EmptyStateVariant.compact,
                  )
                else ...[
                  for (final message in chat.messages)
                    ChatMessageBubble(message: message),
                ],
                if (chat.isSending) const ChatTypingIndicator(),
                if (chat.error != null) _errorWidget(strings, chat.error!),
                if (chat.places.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SectionHeader(title: isArabic ? 'أماكن' : 'Places'),
                  for (final place in chat.places)
                    PlaceResultCard(
                      place: place,
                      selected: _selectedResultId == 'place-${place.id}',
                      onSelect: () => setState(
                        () => _selectedResultId = 'place-${place.id}',
                      ),
                    ),
                ],
                if (chat.clinics.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SectionHeader(title: isArabic ? 'عيادات' : 'Clinics'),
                  for (final clinic in chat.clinics)
                    PlaceResultCard(
                      place: clinic,
                      isClinic: true,
                      selected: _selectedResultId == 'clinic-${clinic.id}',
                      onSelect: () => setState(
                        () => _selectedResultId = 'clinic-${clinic.id}',
                      ),
                    ),
                ],
                if (chat.doctors.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SectionHeader(title: isArabic ? 'أطباء' : 'Doctors'),
                  for (final doctor in chat.doctors)
                    ChatDoctorResultCard(
                      doctor: doctor,
                      selected: _selectedResultId == 'doctor-${doctor.id}',
                      onSelect: () => setState(
                        () => _selectedResultId = 'doctor-${doctor.id}',
                      ),
                    ),
                ],
                if (chat.places.isNotEmpty ||
                    chat.clinics.isNotEmpty ||
                    chat.doctors.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  Card(
                    child: ExpansionTile(
                      key: ValueKey(
                        'chat-results-map-${_selectedResultId ?? 'closed'}',
                      ),
                      initiallyExpanded: _selectedResultId != null,
                      title: Text(
                        isArabic ? 'خريطة النتائج' : 'Results map',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppTheme.spaceMd),
                          child: ChatResultsMap(
                            places: chat.places,
                            clinics: chat.clinics,
                            doctors: chat.doctors,
                            userLocation: _resultLocation,
                            selectedId: _selectedResultId,
                            onSelected: (id) =>
                                setState(() => _selectedResultId = id),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (chat.route != null) ChatRouteCard(route: chat.route!),
                if (chat.suggestions.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SuggestionChips(
                    suggestions: chat.suggestions,
                    onSelected: (text) async {
                      // Backend's default suggestion set ("nearest clinic/
                      // pharmacy/hospital") always needs a location; sending
                      // without one just gets the "attach your location"
                      // fallback reply. Get the location up front instead.
                      if (_needsLocation(text) && !_attachLocation) {
                        await _chooseLocation();
                      }
                      if (!mounted) return;
                      _input.text = text;
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
          ChatInput(
            controller: _input,
            enabled: !chat.isSending && !quotaExhausted,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatQuotaCard extends StatelessWidget {
  const _ChatQuotaCard({
    required this.quota,
    required this.strings,
    required this.serverTime,
    required this.onRefresh,
    required this.onUpgrade,
  });

  final ChatEntitlement quota;
  final AppStrings strings;
  final DateTime? serverTime;
  final VoidCallback onRefresh;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final remaining = quota.remaining;
    final limit = quota.limit;
    final exhausted = !quota.allowed && remaining == 0;
    final label = remaining != null && limit != null
        ? strings.billingChatRemaining(remaining, limit)
        : strings.chatQuotaTitle;
    if (!exhausted) {
      return FeatureCard(
        title: label,
        icon: Icons.data_usage_rounded,
        color: AppTheme.info,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.chatErrQuotaTitle,
              subtitle: strings.chatQuotaExhaustedBody,
            ),
            if (quota.resetsAt != null && serverTime != null) ...[
              Row(
                children: [
                  Expanded(child: Text(strings.billingResetsAt)),
                  ServerCountdown(
                    target: quota.resetsAt!,
                    serverTime: serverTime!,
                    isArabic: strings.isArabic,
                    onElapsed: onRefresh,
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            FilledButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(strings.entitlementUpgradeAction),
            ),
          ],
        ),
      ),
    );
  }
}
