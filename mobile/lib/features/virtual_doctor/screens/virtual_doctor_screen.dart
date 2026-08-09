import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/consultation_models.dart';
import '../providers/virtual_doctor_provider.dart';
import '../widgets/voice_orb.dart';

class VirtualDoctorScreen extends ConsumerStatefulWidget {
  const VirtualDoctorScreen({super.key});

  @override
  ConsumerState<VirtualDoctorScreen> createState() =>
      _VirtualDoctorScreenState();
}

class _VirtualDoctorScreenState extends ConsumerState<VirtualDoctorScreen> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  int _lastTranscriptLength = 0;
  ConsultState? _lastConsultState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.inactive || lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.detached) {
      final controller = ref.read(virtualDoctorControllerProvider.notifier);
      unawaited(controller.cancelRecording());
      unawaited(controller.skipSpeech());
    }
  }

  void _autoScroll() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final duration = AppTheme.motionDuration(
        context,
        AppTheme.motionBase,
      );
      if (duration == Duration.zero) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: duration,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic =
        ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(virtualDoctorControllerProvider);
    final controller = ref.read(virtualDoctorControllerProvider.notifier);

    final completedNow = state.state == ConsultState.complete &&
        _lastConsultState != ConsultState.complete;
    if (state.transcript.length != _lastTranscriptLength || completedNow) {
      _lastTranscriptLength = state.transcript.length;
      _autoScroll();
    }
    _lastConsultState = state.state;

    final body = switch (state.state) {
      ConsultState.idle => _StartView(
          strings: strings,
          onStart: () => controller.startConsultation(
            isArabic ? 'ar' : 'en',
          ),
        ),
      ConsultState.error => _FatalErrorView(
          state: state,
          strings: strings,
          onRetry: () => controller.startConsultation(
            isArabic ? 'ar' : 'en',
          ),
          onOpenSettings: controller.openMicSettings,
        ),
      _ => _ConsultationView(
          state: state,
          strings: strings,
          isArabic: isArabic,
          controller: controller,
          scrollController: _scrollController,
        ),
    };

    return AppScaffold(
      appBar: AppBar(
        title: Text(strings.virtualDoctorTitle),
        actions: [
          if (state.isActive)
            IconButton(
              tooltip: strings.endConsultation,
              onPressed: controller.endConsultation,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      useSafeArea: true,
      safeAreaTop: false,
      keyboardAware: true,
      resizeToAvoidBottomInset: false,
      body: body,
    );
  }
}

class _StartView extends StatelessWidget {
  const _StartView({required this.strings, required this.onStart});

  final AppStrings strings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(
        top: AppTheme.spaceLg,
        bottom: AppTheme.space2xl,
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageIntro(
              title: strings.virtualDoctorTitle,
              subtitle: strings.virtualDoctorTagline,
              icon: Icons.health_and_safety_outlined,
              color: AppTheme.violet,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceXl),
                child: Column(
                  children: [
                    VoiceOrb(
                      state: ConsultState.idle,
                      semanticLabel: strings.vdVoiceState(
                        strings.vdStateIdle,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    Text(
                      strings.vdWelcomeTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: AppTheme.weightExtraBold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    Text(
                      strings.vdWelcomeBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            FeatureCard(
              title: strings.vdSafetyTitle,
              subtitle: strings.vdSafetyHint,
              icon: Icons.health_and_safety_outlined,
              color: AppTheme.warning,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            FeatureCard(
              title: strings.vdPrivacyTitle,
              subtitle: strings.vdPrivacyHint,
              icon: Icons.privacy_tip_outlined,
              color: AppTheme.primary,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            FeatureCard(
              title: strings.vdQuietTitle,
              subtitle: strings.vdQuietHint,
              icon: Icons.volume_off_outlined,
              color: AppTheme.secondary,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            FeatureCard(
              title: strings.vdMicrophoneTitle,
              subtitle: strings.vdMicrophoneHint,
              icon: Icons.mic_none_rounded,
              color: AppTheme.accent,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            PrimaryButton(
              label: strings.startConsultation,
              semanticLabel: strings.startConsultation,
              icon: Icons.play_arrow_rounded,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _FatalErrorView extends StatelessWidget {
  const _FatalErrorView({
    required this.state,
    required this.strings,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final VirtualDoctorState state;
  final AppStrings strings;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final micDenied = state.errorMessage == 'mic_denied';
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(
        top: AppTheme.spaceLg,
        bottom: AppTheme.space2xl,
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageIntro(
              title: strings.virtualDoctorTitle,
              subtitle: strings.virtualDoctorTagline,
              icon: Icons.health_and_safety_outlined,
              color: AppTheme.violet,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: Column(
                  children: [
                    VoiceOrb(
                      state: ConsultState.error,
                      semanticLabel: strings.vdVoiceState(
                        micDenied
                            ? strings.vdMicDenied
                            : strings.vdErrGeneric,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    if (micDenied) ...[
                      SectionHeader(
                        title: strings.vdMicDenied,
                        subtitle: strings.vdMicDeniedHint,
                      ),
                      if (state.micPermanentlyDenied) ...[
                        PrimaryButton(
                          label: strings.vdOpenSettings,
                          icon: Icons.settings_outlined,
                          onPressed: onOpenSettings,
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(strings.vdRetryConsultation),
                        ),
                      ] else
                        PrimaryButton(
                          label: strings.vdRetryConsultation,
                          icon: Icons.refresh_rounded,
                          onPressed: onRetry,
                        ),
                    ] else
                      ErrorRetryState(
                        title: strings.vdSessionErrorTitle,
                        message: strings.vdError(
                          state.errorMessage ?? 'connect_failed',
                        ),
                        retryLabel: strings.vdRetryConsultation,
                        onRetry: onRetry,
                        variant: ErrorRetryVariant.compact,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsultationView extends StatelessWidget {
  const _ConsultationView({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.controller,
    required this.scrollController,
  });

  final VirtualDoctorState state;
  final AppStrings strings;
  final bool isArabic;
  final VirtualDoctorController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: AppTheme.spaceMd),
          child: ResponsiveContent(
            child: _StatusStrip(state: state, strings: strings),
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = AppTheme.pageHorizontalPadding(
                constraints.maxWidth,
              );
              final wide = constraints.maxWidth >= AppTheme.wideBreakpoint;
              final content = wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            child: _VoicePanel(
                              state: state,
                              strings: strings,
                              onDismissError: controller.clearError,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spaceMd),
                        Expanded(
                          flex: 3,
                          child: _TranscriptPanel(
                            state: state,
                            strings: strings,
                            isArabic: isArabic,
                            scrollController: scrollController,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * 0.45,
                          ),
                          child: SingleChildScrollView(
                            child: _VoicePanel(
                              state: state,
                              strings: strings,
                              onDismissError: controller.clearError,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        Expanded(
                          child: _TranscriptPanel(
                            state: state,
                            strings: strings,
                            isArabic: isArabic,
                            scrollController: scrollController,
                          ),
                        ),
                      ],
                    );

              return Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: horizontal,
                ),
                child: Align(
                  alignment: AlignmentDirectional.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppTheme.maxPhoneContentWidth,
                    ),
                    child: content,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height *
                (state.state == ConsultState.complete ? 0.42 : 0.26),
          ),
          child: SingleChildScrollView(
            child: ResponsiveContent(
              child: _ControlPanel(
                state: state,
                strings: strings,
                controller: controller,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
      ],
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.state, required this.strings});

  final VirtualDoctorState state;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final visual = _consultStateVisual(state.state, strings, context);
    final phase = state.phase?.trim();
    final reducedMotion = AppTheme.prefersReducedMotion(context);
    return FeatureCard(
      title: visual.label,
      subtitle: strings.vdConsultationStatus,
      icon: visual.icon,
      color: visual.color,
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppTheme.spaceSm,
        runSpacing: AppTheme.spaceSm,
        children: [
          if (visual.busy)
            reducedMotion
                ? Icon(
                    Icons.hourglass_top_rounded,
                    color: visual.color,
                    size: AppTheme.iconMd,
                  )
                : SizedBox.square(
                    dimension: AppTheme.iconMd,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: visual.color,
                    ),
                  ),
          if (phase?.isNotEmpty == true)
            Semantics(
              label:
                  '${strings.vdConsultationProgress}. ${strings.vdPhaseLabel(phase!)}',
              child: StatusBadge(
                label: strings.vdPhaseLabel(phase),
                color: AppTheme.violet,
              ),
            ),
          if (state.startedAt != null)
            _ElapsedTimer(
              startedAt: state.startedAt!,
              completedAt: state.completedAt,
              strings: strings,
            ),
        ],
      ),
    );
  }
}

class _VoicePanel extends StatelessWidget {
  const _VoicePanel({
    required this.state,
    required this.strings,
    required this.onDismissError,
  });

  final VirtualDoctorState state;
  final AppStrings strings;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final visual = _consultStateVisual(state.state, strings, context);
    final urgency = _urgencyVisual(state.urgencyLevel, strings);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: VoiceOrb(
                state: state.state,
                semanticLabel: strings.vdVoiceState(visual.label),
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              visual.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: visual.color,
                    fontWeight: AppTheme.weightBold,
                  ),
            ),
            if (state.state == ConsultState.thinking) ...[
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                strings.vdThinkingHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
            ],
            if (state.subtitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppTheme.spaceMd),
              _SubtitleCard(text: state.subtitle!.trim()),
            ],
            if (state.ttsUnavailable) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message: strings.vdTtsUnavailable,
                tone: InlineMessageTone.warning,
              ),
            ],
            if (state.recoveredSession) ...[
              const SizedBox(height: AppTheme.spaceMd),
              const InlineMessage(message: 'Recovered consultation session.', tone: InlineMessageTone.info),
            ],
            if (state.recordingRemainingSeconds != null && state.recordingRemainingSeconds! <= 5) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Directionality(textDirection: TextDirection.ltr, child: Text(Directionality.of(context) == TextDirection.rtl ? 'ينتهي التسجيل خلال ${state.recordingRemainingSeconds} ث' : 'Recording ends in ${state.recordingRemainingSeconds}s', textAlign: TextAlign.center)),
            ],
            if (urgency != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              _UrgencyCard(visual: urgency, strings: strings),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message: strings.vdError(state.errorMessage!),
                tone: InlineMessageTone.error,
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onDismissError,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(strings.vdDismissError),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubtitleCard extends StatelessWidget {
  const _SubtitleCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMutedDark.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: AppTheme.shadowSmOf(context),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.volume_up_rounded,
              color: Colors.white,
              size: AppTheme.iconMd,
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: AppTheme.weightMedium,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.scrollController,
  });

  final VirtualDoctorState state;
  final AppStrings strings;
  final bool isArabic;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final name = _profileValue(state.profileSnapshot, 'name');
    final age = _profileValue(state.profileSnapshot, 'age');
    final complaint = _firstValue([
      _profileValue(
        state.profileSnapshot,
        'chief_complaint_description',
      ),
      state.chiefComplaint,
    ]);
    final hasProfile = name != null || age != null;

    return Card(
      child: ListView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        children: [
          SectionHeader(
            title: strings.vdConversationTitle,
            subtitle: strings.vdConversationHint,
            trailing: state.phase?.trim().isNotEmpty == true
                ? StatusBadge(
                    label: strings.vdPhaseLabel(state.phase!.trim()),
                    color: AppTheme.violet,
                  )
                : null,
          ),
          if (hasProfile) ...[
            _PatientInfoCard(
              name: name,
              age: age,
              strings: strings,
            ),
            const SizedBox(height: AppTheme.spaceMd),
          ],
          if (complaint != null) ...[
            _ContextCard(
              title: strings.vdChiefComplaint,
              value: complaint,
              icon: Icons.medical_information_outlined,
              color: AppTheme.accent,
            ),
            const SizedBox(height: AppTheme.spaceMd),
          ],
          if (state.transcript.isEmpty)
            EmptyState(
              icon: Icons.forum_outlined,
              title: strings.vdNoMessages,
              variant: EmptyStateVariant.compact,
            )
          else
            for (final entry in state.transcript) ...[
              _ConversationBubble(
                entry: entry,
                strings: strings,
                language: state.language,
              ),
              const SizedBox(height: AppTheme.spaceSm),
            ],
          if (state.state == ConsultState.complete) ...[
            const SizedBox(height: AppTheme.spaceMd),
            _ConsultationSummary(
              state: state,
              strings: strings,
              isArabic: isArabic,
            ),
          ],
        ],
      ),
    );
  }
}

class _PatientInfoCard extends StatelessWidget {
  const _PatientInfoCard({
    required this.name,
    required this.age,
    required this.strings,
  });

  final String? name;
  final String? age;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return _ContextCard(
      title: strings.vdPatientInfoTitle,
      icon: Icons.person_outline_rounded,
      color: AppTheme.primary,
      child: Wrap(
        spacing: AppTheme.spaceMd,
        runSpacing: AppTheme.spaceSm,
        children: [
          if (name != null)
            _MetadataValue(
              label: strings.vdPatientName,
              value: name!,
            ),
          if (age != null)
            _MetadataValue(
              label: strings.vdPatientAge,
              value: age!,
              textDirection: TextDirection.ltr,
            ),
        ],
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.title,
    required this.icon,
    required this.color,
    this.value,
    this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: AppTheme.iconMd),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: AppTheme.weightBold,
                      ),
                ),
              ),
            ],
          ),
          if (value != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            Text(value!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (child != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            child!,
          ],
        ],
      ),
    );
  }
}

class _MetadataValue extends StatelessWidget {
  const _MetadataValue({
    required this.label,
    required this.value,
    this.textDirection,
  });

  final String label;
  final String value;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Directionality(
            textDirection: textDirection ?? Directionality.of(context),
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: AppTheme.weightSemibold,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationBubble extends StatelessWidget {
  const _ConversationBubble({
    required this.entry,
    required this.strings,
    required this.language,
  });

  final TranscriptEntry entry;
  final AppStrings strings;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doctor = entry.isDoctor;
    final accent = doctor ? theme.colorScheme.primary : AppTheme.secondary;
    final label = doctor ? strings.vdDoctor : strings.vdYou;
    return Semantics(
      container: true,
      label: '$label. ${entry.text}',
      child: Align(
        alignment: doctor
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: FractionallySizedBox(
          widthFactor: AppTheme.usesLargeText(context)
              ? 1
              : 0.88,
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            decoration: BoxDecoration(
              color: doctor
                  ? accent.withValues(alpha: 0.1)
                  : AppTheme.mutedSurfaceOf(context),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(AppTheme.radiusLg),
                topEnd: const Radius.circular(AppTheme.radiusLg),
                bottomStart: Radius.circular(
                  doctor ? AppTheme.radiusSm : AppTheme.radiusLg,
                ),
                bottomEnd: Radius.circular(
                  doctor ? AppTheme.radiusLg : AppTheme.radiusSm,
                ),
              ),
              border: Border.all(color: accent.withValues(alpha: 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: AppTheme.weightBold,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Directionality(
                  textDirection: language == 'ar'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Text(
                    entry.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsultationSummary extends StatelessWidget {
  const _ConsultationSummary({
    required this.state,
    required this.strings,
    required this.isArabic,
  });

  final VirtualDoctorState state;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final name = _profileValue(state.profileSnapshot, 'name');
    final age = _profileValue(state.profileSnapshot, 'age');
    final complaint = _firstValue([
      _profileValue(
        state.profileSnapshot,
        'chief_complaint_description',
      ),
      state.chiefComplaint,
    ]);
    final specialty = _firstValue(
      isArabic
          ? [state.specialtyAr, state.specialtyEn]
          : [state.specialtyEn, state.specialtyAr],
    );
    final urgency = _urgencyVisual(state.urgencyLevel, strings);
    final fields = <_SummaryField>[
      if (name != null)
        _SummaryField(label: strings.vdPatientName, value: name),
      if (age != null)
        _SummaryField(
          label: strings.vdPatientAge,
          value: age,
          textDirection: TextDirection.ltr,
        ),
      if (complaint != null)
        _SummaryField(label: strings.vdChiefComplaint, value: complaint),
      if (specialty != null)
        _SummaryField(
          label: strings.vdRecommendedSpecialty,
          value: specialty,
        ),
    ];

    return Semantics(
      container: true,
      liveRegion: true,
      label: strings.vdSummaryTitle,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        decoration: BoxDecoration(
          color: AppTheme.mutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.vdSummaryTitle,
              trailing: urgency == null
                  ? null
                  : StatusBadge(
                      label: urgency.label,
                      color: urgency.color,
                    ),
            ),
            if (fields.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final largeText = AppTheme.usesLargeText(context);
                  final columns = constraints.maxWidth >=
                              AppTheme.wideBreakpoint &&
                          !largeText
                      ? 2
                      : 1;
                  final width = (constraints.maxWidth -
                          AppTheme.spaceMd * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: AppTheme.spaceMd,
                    runSpacing: AppTheme.spaceMd,
                    children: [
                      for (final field in fields)
                        SizedBox(
                          width: width,
                          child: _SummaryFieldView(field: field),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryField {
  const _SummaryField({
    required this.label,
    required this.value,
    this.textDirection,
  });

  final String label;
  final String value;
  final TextDirection? textDirection;
}

class _SummaryFieldView extends StatelessWidget {
  const _SummaryFieldView({required this.field});

  final _SummaryField field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Directionality(
          textDirection: field.textDirection ?? Directionality.of(context),
          child: Text(
            field.value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: AppTheme.weightSemibold,
                ),
          ),
        ),
      ],
    );
  }
}

class _UrgencyCard extends StatelessWidget {
  const _UrgencyCard({required this.visual, required this.strings});

  final _UrgencyVisual visual;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${strings.vdUrgencyTitle}. ${visual.label}',
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: visual.color.withValues(alpha: 0.3)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heading = Row(
              children: [
                Icon(
                  visual.icon,
                  color: visual.color,
                  size: AppTheme.iconMd,
                ),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Text(
                    strings.vdUrgencyTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: AppTheme.weightBold,
                        ),
                  ),
                ),
              ],
            );
            final badge = StatusBadge(
              label: visual.label,
              color: visual.color,
            );
            if (constraints.maxWidth < AppTheme.compactBreakpoint ||
                AppTheme.usesLargeText(context)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  const SizedBox(height: AppTheme.spaceSm),
                  badge,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: AppTheme.spaceSm),
                badge,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.state,
    required this.strings,
    required this.controller,
  });

  final VirtualDoctorState state;
  final AppStrings strings;
  final VirtualDoctorController controller;

  Future<void> _handleReport() async {
    final path = await controller.generateReport();
    if (path != null) await OpenFilex.open(path);
  }

  @override
  Widget build(BuildContext context) {
    if (state.state == ConsultState.complete) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: strings.vdReportTitle,
                subtitle: strings.vdReportHint,
              ),
              if (state.isGeneratingReport) ...[
                InlineMessage(
                  message: strings.vdGeneratingReport,
                  tone: InlineMessageTone.info,
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              if (state.reportUnavailable) ...[
                InlineMessage(
                  message: strings.vdReportUnavailable,
                  tone: InlineMessageTone.warning,
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              if (state.reportPath != null) ...[
                InlineMessage(
                  message: strings.vdReportSaved,
                  tone: InlineMessageTone.success,
                ),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              PrimaryButton(
                label: state.reportPath != null
                    ? strings.vdOpenReport
                    : strings.vdDownloadReport,
                semanticLabel: state.isGeneratingReport
                    ? strings.vdGeneratingReport
                    : null,
                icon: Icons.picture_as_pdf_outlined,
                isLoading: state.isGeneratingReport,
                onPressed: state.isGeneratingReport ? null : _handleReport,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              OutlinedButton.icon(
                onPressed: controller.endConsultation,
                icon: const Icon(Icons.close_rounded),
                label: Text(strings.endConsultation),
              ),
            ],
          ),
        ),
      );
    }

    final recording = state.state == ConsultState.recording;
    final speaking = state.state == ConsultState.speaking;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: speaking
            ? OutlinedButton.icon(
                onPressed: controller.skipSpeech,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(strings.vdSkipSpeech),
              )
            : recording
                ? FilledButton.icon(
                    onPressed: controller.stopRecordingAndSubmit,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(strings.vdTapToStop),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      minimumSize: const Size(
                        AppTheme.minTouchTarget,
                        AppTheme.minTouchTarget,
                      ),
                    ),
                  )
                : PrimaryButton(
                    label: strings.vdTapToSpeak,
                    icon: Icons.mic_rounded,
                    onPressed: state.canRecord
                        ? controller.startRecording
                        : null,
                  ),
      ),
    );
  }
}

class _ElapsedTimer extends StatefulWidget {
  const _ElapsedTimer({
    required this.startedAt,
    required this.completedAt,
    required this.strings,
  });

  final DateTime startedAt;
  final DateTime? completedAt;
  final AppStrings strings;

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _ElapsedTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt ||
        oldWidget.completedAt != widget.completedAt) {
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.completedAt == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.completedAt ?? DateTime.now();
    final elapsed = end.isBefore(widget.startedAt)
        ? Duration.zero
        : end.difference(widget.startedAt);
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final value = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';

    return Semantics(
      label: widget.strings.vdElapsedValue(value),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppTheme.minTouchTarget,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceMd,
          ),
          decoration: BoxDecoration(
            color: AppTheme.mutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: AppTheme.weightBold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
      ),
    );
  }
}

class _ConsultStateVisual {
  const _ConsultStateVisual({
    required this.label,
    required this.color,
    required this.icon,
    required this.busy,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool busy;
}

_ConsultStateVisual _consultStateVisual(
  ConsultState state,
  AppStrings strings,
  BuildContext context,
) {
  return switch (state) {
    ConsultState.idle => _ConsultStateVisual(
        label: strings.vdStateIdle,
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.medical_services_outlined,
        busy: false,
      ),
    ConsultState.connecting => _ConsultStateVisual(
        label: strings.vdStateConnecting,
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.cloud_sync_outlined,
        busy: true,
      ),
    ConsultState.listening => _ConsultStateVisual(
        label: strings.vdStateListening,
        color: AppTheme.success,
        icon: Icons.hearing_rounded,
        busy: false,
      ),
    ConsultState.recording => _ConsultStateVisual(
        label: strings.vdStateRecording,
        color: AppTheme.danger,
        icon: Icons.mic_rounded,
        busy: false,
      ),
    ConsultState.transcribing => _ConsultStateVisual(
        label: strings.vdStateTranscribing,
        color: AppTheme.accent,
        icon: Icons.graphic_eq_rounded,
        busy: true,
      ),
    ConsultState.thinking => _ConsultStateVisual(
        label: strings.vdStateThinking,
        color: AppTheme.warning,
        icon: Icons.psychology_outlined,
        busy: true,
      ),
    ConsultState.speaking => _ConsultStateVisual(
        label: strings.vdStateSpeaking,
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.volume_up_rounded,
        busy: true,
      ),
    ConsultState.complete => _ConsultStateVisual(
        label: strings.vdStateComplete,
        color: AppTheme.success,
        icon: Icons.check_circle_outline_rounded,
        busy: false,
      ),
    ConsultState.error => _ConsultStateVisual(
        label: strings.vdErrGeneric,
        color: Theme.of(context).colorScheme.error,
        icon: Icons.error_outline_rounded,
        busy: false,
      ),
  };
}

class _UrgencyVisual {
  const _UrgencyVisual({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

_UrgencyVisual? _urgencyVisual(String? value, AppStrings strings) {
  return switch (value?.toLowerCase()) {
    'emergency' => _UrgencyVisual(
        label: strings.vdUrgencyEmergency,
        color: AppTheme.danger,
        icon: Icons.emergency_outlined,
      ),
    'urgent' => _UrgencyVisual(
        label: strings.vdUrgencyUrgent,
        color: AppTheme.warning,
        icon: Icons.warning_amber_rounded,
      ),
    'routine' => _UrgencyVisual(
        label: strings.vdUrgencyRoutine,
        color: AppTheme.success,
        icon: Icons.event_available_outlined,
      ),
    'unknown' => _UrgencyVisual(
        label: strings.vdUrgencyUnknown,
        color: AppTheme.info,
        icon: Icons.help_outline_rounded,
      ),
    _ => null,
  };
}

String? _profileValue(Map<String, dynamic> profile, String key) {
  final value = profile[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _firstValue(Iterable<String?> values) {
  for (final value in values) {
    final text = value?.trim();
    if (text?.isNotEmpty == true) return text;
  }
  return null;
}
