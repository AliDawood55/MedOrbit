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
import '../../discovery/models/location_models.dart';
import '../../discovery/providers/location_provider.dart';
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
      if (widget.conversationId?.isNotEmpty == true)
        _load(widget.conversationId!);
    });
  }

  @override
  void didUpdateWidget(covariant ChatbotScreen old) {
    super.didUpdateWidget(old);
    if (widget.conversationId != old.conversationId &&
        widget.conversationId?.isNotEmpty == true)
      _load(widget.conversationId!);
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
    if (mounted)
      setState(() {
        _selectedResultId = null;
        _resultLocation = null;
      });
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
    if (!mounted) return;
    if (ok) {
      ref.read(locationControllerProvider.notifier).clearLocation();
      setState(() {
        _attachLocation = false;
        _resultLocation = location;
        _selectedResultId = null;
      });
    }
    if (_scroll.hasClients)
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
  }

  Future<void> _chooseLocation() async {
    final state = ref.read(locationControllerProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => LocationPickerSheet(
        permissionState: state.permissionState,
        errorMessage: state.errorMessage,
        isBusy: state.status != LocationControllerStatus.idle,
        onUseCurrentLocation: () async {
          Navigator.pop(sheet);
          final ok = await ref
              .read(locationControllerProvider.notifier)
              .resolveCurrentLocation();
          if (mounted && ok) setState(() => _attachLocation = true);
        },
        onSelectMapPoint: () {
          Navigator.pop(sheet);
          _mapPoint();
        },
        onSelectDistrict: (district) {
          Navigator.pop(sheet);
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
          Navigator.pop(sheet);
          ref.read(locationControllerProvider.notifier).clearLocation();
          setState(() => _attachLocation = false);
        },
        onCancel: () => Navigator.pop(sheet),
      ),
    );
  }

  Future<void> _mapPoint() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: DiscoveryMap(
            onMapTap: (point) {
              ref
                  .read(locationControllerProvider.notifier)
                  .selectManualMapPoint(point.latitude, point.longitude);
              Navigator.pop(sheet);
              if (mounted) setState(() => _attachLocation = true);
            },
          ),
        ),
      ),
    );
  }

  String _error(AppStrings s, ChatbotError e) => switch (e.kind) {
    ChatFailureKind.connectTimeout ||
    ChatFailureKind.receiveTimeout => s.chatErrTimeout,
    ChatFailureKind.unavailable => s.chatErrUnavailable,
    ChatFailureKind.invalidResponse => s.chatErrInvalidResponse,
    ChatFailureKind.backend => s.chatErrServer,
    ChatFailureKind.unknown => s.errorGeneric,
  };
  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatbotControllerProvider);
    final s = ref.watch(appStringsProvider);
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final location = _attachLocation
        ? ref.watch(locationControllerProvider).currentLocation
        : null;
    return AppScaffold(
      appBar: AppBar(
        title: Text(ar ? 'المحادثة الطبية' : 'Medical chat'),
        actions: [
          IconButton(
            tooltip: ar ? 'سجل المحادثات' : 'Conversation history',
            onPressed: () => context.push(RoutePaths.conversations),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: ar ? 'محادثة جديدة' : 'New conversation',
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
                  title: ar ? 'إرشاد طبي' : 'Medical guidance',
                  subtitle: ar
                      ? 'هذه الخدمة تقدم إرشاداً عاماً ولا تغني عن الرعاية الطبية المتخصصة.'
                      : 'This service provides general guidance and does not replace professional medical care.',
                  icon: Icons.chat_bubble_outline_rounded,
                ),
                const SizedBox(height: AppTheme.spaceMd),
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
                    title: ar ? 'ابدأ محادثة' : 'Start a conversation',
                    hint: ar
                        ? 'اكتب أعراضك أو اسأل عن رعاية قريبة.'
                        : 'Describe your symptoms or ask about nearby care.',
                    variant: EmptyStateVariant.compact,
                  )
                else ...[
                  for (final message in chat.messages)
                    ChatMessageBubble(message: message),
                ],
                if (chat.isSending) const ChatTypingIndicator(),
                if (chat.error != null)
                  ErrorRetryState(
                    title: s.chatErrTitle,
                    message: _error(s, chat.error!),
                    retryLabel: s.retry,
                    onRetry: () => ref
                        .read(chatbotControllerProvider.notifier)
                        .retryLastMessage(),
                    variant: ErrorRetryVariant.compact,
                  ),
                if (chat.places.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SectionHeader(title: ar ? 'أماكن' : 'Places'),
                  for (final item in chat.places)
                    PlaceResultCard(
                      place: item,
                      selected: _selectedResultId == 'place-${item.id}',
                      onSelect: () => setState(
                        () => _selectedResultId = 'place-${item.id}',
                      ),
                    ),
                ],
                if (chat.clinics.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SectionHeader(title: ar ? 'عيادات' : 'Clinics'),
                  for (final item in chat.clinics)
                    PlaceResultCard(
                      place: item,
                      isClinic: true,
                      selected: _selectedResultId == 'clinic-${item.id}',
                      onSelect: () => setState(
                        () => _selectedResultId = 'clinic-${item.id}',
                      ),
                    ),
                ],
                if (chat.doctors.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  SectionHeader(title: ar ? 'أطباء' : 'Doctors'),
                  for (final item in chat.doctors)
                    ChatDoctorResultCard(
                      doctor: item,
                      selected: _selectedResultId == 'doctor-${item.id}',
                      onSelect: () => setState(
                        () => _selectedResultId = 'doctor-${item.id}',
                      ),
                    ),
                ],
                if (chat.places.isNotEmpty ||
                    chat.clinics.isNotEmpty ||
                    chat.doctors.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      title: Text(ar ? 'خريطة النتائج' : 'Results map'),
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
                if (chat.route != null) ChatRouteCard(route: chat.route!),
                if (chat.suggestions.isNotEmpty)
                  SuggestionChips(
                    suggestions: chat.suggestions,
                    onSelected: (text) {
                      _input.text = text;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          ChatInput(
            controller: _input,
            enabled: !chat.isSending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}
