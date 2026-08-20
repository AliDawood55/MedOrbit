import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
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

class ChatbotScreen extends ConsumerStatefulWidget { const ChatbotScreen({super.key, this.conversationId}); final String? conversationId; @override ConsumerState<ChatbotScreen> createState() => _ChatbotScreenState(); }
class _ChatbotScreenState extends ConsumerState<ChatbotScreen> {
  final _input = TextEditingController(); final _scroll = ScrollController(); bool _attachLocation = false; AppLocation? _resultLocation; String? _selectedResultId;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { final id = widget.conversationId; if (id?.isNotEmpty == true) _load(id!); }); }
  @override void didUpdateWidget(covariant ChatbotScreen oldWidget) { super.didUpdateWidget(oldWidget); if (widget.conversationId != oldWidget.conversationId && widget.conversationId?.isNotEmpty == true) _load(widget.conversationId!); }
  @override void dispose() { _input.dispose(); _scroll.dispose(); super.dispose(); }
  Future<void> _load(String id) async { ref.read(conversationsControllerProvider.notifier).selectConversation(id); await ref.read(chatbotControllerProvider.notifier).loadConversation(id); if (mounted) setState(() { _selectedResultId = null; _resultLocation = null; }); }
  void _newConversation() { ref.read(chatbotControllerProvider.notifier).startNewConversation(); setState(() { _selectedResultId = null; _resultLocation = null; _attachLocation = false; }); }
  Future<void> _send() async { final text = _input.text.trim(); if (text.isEmpty) return; final location = _attachLocation ? ref.read(locationControllerProvider).currentLocation : null; _input.clear(); final ok = await ref.read(chatbotControllerProvider.notifier).sendMessage(text, latitude: location?.latitude, longitude: location?.longitude); if (mounted && ok) { ref.read(locationControllerProvider.notifier).clearLocation(); setState(() { _attachLocation = false; _resultLocation = location; _selectedResultId = null; }); } if (mounted) _scrollToEnd(); }
  void _scrollToEnd() { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }
  Future<void> _chooseLocation() async { final state = ref.read(locationControllerProvider); await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => LocationPickerSheet(permissionState: state.permissionState, errorMessage: state.errorMessage, isBusy: state.status == LocationControllerStatus.checking || state.status == LocationControllerStatus.requestingPermission || state.status == LocationControllerStatus.locating, onUseCurrentLocation: () async { Navigator.pop(context); final ok = await ref.read(locationControllerProvider.notifier).resolveCurrentLocation(); if (mounted && ok) setState(() => _attachLocation = true); }, onSelectMapPoint: () { Navigator.pop(context); _selectMapPoint(); }, onSelectDistrict: (district) { Navigator.pop(context); ref.read(locationControllerProvider.notifier).selectManualDistrict(district); setState(() => _attachLocation = true); }, onOpenAppSettings: () => ref.read(locationControllerProvider.notifier).openAppSettings(), onOpenLocationSettings: () => ref.read(locationControllerProvider.notifier).openLocationSettings(), onClear: () { Navigator.pop(context); ref.read(locationControllerProvider.notifier).clearLocation(); setState(() => _attachLocation = false); }, onCancel: () => Navigator.pop(context))); }
  Future<void> _selectMapPoint() async { await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .72, child: DiscoveryMap(onMapTap: (point) { ref.read(locationControllerProvider.notifier).selectManualMapPoint(point.latitude, point.longitude); Navigator.pop(context); if (mounted) setState(() => _attachLocation = true); })))); }
  /// Picks the message from the failure category rather than echoing the
  /// transport-layer text, so "took longer than expected" can only ever appear
  /// for a real timeout and never for an unreachable service.
  String _errorMessage(AppStrings strings, ChatbotError error) {
    return switch (error.kind) {
      ChatFailureKind.connectTimeout || ChatFailureKind.receiveTimeout => strings.chatErrTimeout,
      ChatFailureKind.unavailable => strings.chatErrUnavailable,
      ChatFailureKind.invalidResponse => strings.chatErrInvalidResponse,
      ChatFailureKind.backend => strings.chatErrServer,
      ChatFailureKind.unknown => strings.errorGeneric,
    };
  }

  @override Widget build(BuildContext context) { final chat = ref.watch(chatbotControllerProvider); final strings = ref.watch(appStringsProvider); final location = _attachLocation ? ref.watch(locationControllerProvider).currentLocation : null; return AppScaffold(appBar: AppBar(title: const Text('Medical chat'), actions: [IconButton(tooltip: 'Conversation history', onPressed: () => context.push(RoutePaths.conversations), icon: const Icon(Icons.history_rounded)), IconButton(tooltip: 'New conversation', onPressed: _newConversation, icon: const Icon(Icons.add_comment_outlined))]), useSafeArea: true, keyboardAware: true, body: Column(children: [Expanded(child: ListView(controller: _scroll, padding: const EdgeInsets.all(AppTheme.spaceMd), children: [const PageIntro(title: 'Medical guidance', subtitle: 'This service provides general guidance and does not replace professional medical care.', icon: Icons.chat_bubble_outline_rounded), const SizedBox(height: AppTheme.spaceMd), ChatLocationBanner(location: location, onAttach: _chooseLocation, onClear: () { ref.read(locationControllerProvider.notifier).clearLocation(); setState(() => _attachLocation = false); }), const SizedBox(height: AppTheme.spaceMd), if (chat.isInitialLoading) const Center(child: CircularProgressIndicator()) else if (!chat.hasMessages) const EmptyState(icon: Icons.chat_outlined, title: 'Start a conversation', hint: 'Describe your symptoms or ask about nearby care.', variant: EmptyStateVariant.compact) else ...[for (final message in chat.messages) ChatMessageBubble(message: message)], if (chat.isSending) const ChatTypingIndicator(), if (chat.error != null) ErrorRetryState(title: strings.chatErrTitle, message: _errorMessage(strings, chat.error!), retryLabel: strings.retry, onRetry: () => ref.read(chatbotControllerProvider.notifier).retryLastMessage(), variant: ErrorRetryVariant.compact), if (chat.places.isNotEmpty) ...[const SizedBox(height: AppTheme.spaceMd), const SectionHeader(title: 'Places'), for (final place in chat.places) PlaceResultCard(place: place, selected: _selectedResultId == 'place-${place.id}', onSelect: () => setState(() => _selectedResultId = 'place-${place.id}'))], if (chat.clinics.isNotEmpty) ...[const SizedBox(height: AppTheme.spaceMd), const SectionHeader(title: 'Clinics'), for (final clinic in chat.clinics) PlaceResultCard(place: clinic, isClinic: true, selected: _selectedResultId == 'clinic-${clinic.id}', onSelect: () => setState(() => _selectedResultId = 'clinic-${clinic.id}'))], if (chat.doctors.isNotEmpty) ...[const SizedBox(height: AppTheme.spaceMd), const SectionHeader(title: 'Doctors'), for (final doctor in chat.doctors) ChatDoctorResultCard(doctor: doctor, selected: _selectedResultId == 'doctor-${doctor.id}', onSelect: () => setState(() => _selectedResultId = 'doctor-${doctor.id}'))], if (chat.places.isNotEmpty || chat.clinics.isNotEmpty || chat.doctors.isNotEmpty) ...[const SizedBox(height: AppTheme.spaceMd), Card(child: ExpansionTile(key: ValueKey('chat-results-map-${_selectedResultId ?? 'closed'}'), initiallyExpanded: _selectedResultId != null, title: const Text('Results map'), children: [Padding(padding: const EdgeInsets.all(AppTheme.spaceMd), child: ChatResultsMap(places: chat.places, clinics: chat.clinics, doctors: chat.doctors, userLocation: _resultLocation, selectedId: _selectedResultId, onSelected: (id) => setState(() => _selectedResultId = id)))]) )], if (chat.route != null) ChatRouteCard(route: chat.route!), if (chat.suggestions.isNotEmpty) ...[const SizedBox(height: AppTheme.spaceMd), SuggestionChips(suggestions: chat.suggestions, onSelected: (text) { _input.text = text; setState(() {}); })]])), ChatInput(controller: _input, enabled: !chat.isSending, onSend: _send)])); }
}
