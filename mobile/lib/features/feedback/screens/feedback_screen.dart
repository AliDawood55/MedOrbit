import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/feedback_provider.dart';
import '../widgets/star_rating.dart';

class FeedbackScreen extends ConsumerWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final status = ref.watch(
      feedbackControllerProvider.select((state) => state.status),
    );
    final controller = ref.read(feedbackControllerProvider.notifier);
    final success = status == FeedbackSubmitStatus.success;

    return AppScaffold(
      appBar: AppBar(title: Text(strings.feedbackTitle)),
      useSafeArea: true,
      safeAreaTop: false,
      keyboardAware: !success,
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsetsDirectional.only(
          top: AppTheme.spaceLg,
          bottom: AppTheme.space2xl,
        ),
        child: ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageIntro(
                title: strings.feedbackTitle,
                subtitle: strings.feedbackSubtitle,
                icon: Icons.rate_review_outlined,
                color: AppTheme.primary,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              AnimatedSwitcher(
                duration: AppTheme.motionDuration(
                  context,
                  AppTheme.motionBase,
                ),
                child: success
                    ? _ResultPanel(
                        key: const ValueKey('feedback-success'),
                        strings: strings,
                        onStartOver: controller.reset,
                      )
                    : _FeedbackForm(
                        key: const ValueKey('feedback-form'),
                        strings: strings,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackForm extends ConsumerStatefulWidget {
  const _FeedbackForm({super.key, required this.strings});

  final AppStrings strings;

  @override
  ConsumerState<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<_FeedbackForm> {
  late final TextEditingController _commentController;
  final _overallRatingKey = GlobalKey();
  bool _submissionLocked = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(
      text: ref.read(feedbackControllerProvider).comment,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit(FeedbackController controller) async {
    if (_submissionLocked) return;
    _submissionLocked = true;
    try {
      await controller.submit();
      if (!mounted) return;
      if (ref
          .read(feedbackControllerProvider)
          .showRatingRequiredError) {
        final target = _overallRatingKey.currentContext;
        if (target == null || !target.mounted) return;
        await Scrollable.ensureVisible(
          target,
          duration: AppTheme.motionDuration(
            context,
            AppTheme.motionBase,
          ),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
    } finally {
      _submissionLocked = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final viewState = ref.watch(
      feedbackControllerProvider.select(
        (state) => (
          overallRating: state.overallRating,
          chatbotRating: state.chatbotRating,
          clinicsRating: state.clinicsRating,
          bookingRating: state.bookingRating,
          designRating: state.designRating,
          wouldRecommend: state.wouldRecommend,
          status: state.status,
          showRatingRequiredError: state.showRatingRequiredError,
        ),
      ),
    );
    final controller = ref.read(feedbackControllerProvider.notifier);
    final submitting =
        viewState.status == FeedbackSubmitStatus.submitting;
    final networkError = viewState.status == FeedbackSubmitStatus.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeatureCard(
          key: _overallRatingKey,
          title: strings.overallRatingLabel,
          subtitle: strings.overallRatingHint,
          icon: Icons.star_outline_rounded,
          color: AppTheme.accent,
          trailing: Align(
            alignment: AlignmentDirectional.center,
            child: StarRating(
              value: viewState.overallRating,
              onChanged: controller.setOverallRating,
              semanticLabel: strings.overallRatingLabel,
              valueSemanticLabel: strings.ratingValue(
                viewState.overallRating,
              ),
              starSemanticLabelBuilder: strings.selectStarRating,
              hasError: viewState.showRatingRequiredError,
              alignment: WrapAlignment.center,
            ),
          ),
        ),
        if (viewState.showRatingRequiredError) ...[
          const SizedBox(height: AppTheme.spaceSm),
          InlineMessage(
            message: strings.errorRatingRequired,
            tone: InlineMessageTone.error,
          ),
        ],
        const SizedBox(height: AppTheme.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: strings.serviceRatingsTitle,
                  subtitle: strings.serviceRatingsHint,
                ),
                _CategoryRatingRow(
                  label: strings.categoryChatbot,
                  value: viewState.chatbotRating,
                  onChanged: controller.setChatbotRating,
                  strings: strings,
                ),
                const Divider(height: 1),
                _CategoryRatingRow(
                  label: strings.categoryClinics,
                  value: viewState.clinicsRating,
                  onChanged: controller.setClinicsRating,
                  strings: strings,
                ),
                const Divider(height: 1),
                _CategoryRatingRow(
                  label: strings.categoryBooking,
                  value: viewState.bookingRating,
                  onChanged: controller.setBookingRating,
                  strings: strings,
                ),
                const Divider(height: 1),
                _CategoryRatingRow(
                  label: strings.categoryDesign,
                  value: viewState.designRating,
                  onChanged: controller.setDesignRating,
                  strings: strings,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: strings.recommendQuestion,
                  subtitle: strings.recommendHint,
                ),
                _RecommendationControl(
                  value: viewState.wouldRecommend,
                  yesLabel: strings.yes,
                  noLabel: strings.no,
                  onChanged: controller.setRecommend,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: strings.commentLabel,
                ),
                AppTextField(
                  label: strings.commentLabel,
                  hintText: strings.commentHint,
                  controller: _commentController,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 500,
                  helperText: strings.commentHelper,
                  semanticLabel: strings.commentLabel,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: controller.setComment,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: strings.feedbackSubmissionTitle,
                  subtitle: strings.feedbackSubmissionHint,
                ),
                if (networkError) ...[
                  InlineMessage(
                    message:
                        '${strings.feedbackErrorTitle}. ${strings.feedbackErrorHint}',
                    tone: InlineMessageTone.error,
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      onPressed: () => _submit(controller),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(strings.retryFeedbackButton),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceMd),
                ],
                PrimaryButton(
                  label: strings.submitButton,
                  semanticLabel: submitting
                      ? strings.submittingFeedback
                      : strings.submitButton,
                  icon: Icons.send_rounded,
                  isLoading: submitting,
                  onPressed: submitting
                      ? null
                      : () => _submit(controller),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRatingRow extends StatelessWidget {
  const _CategoryRatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.strings,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: AppTheme.weightSemibold,
          ),
    );
    final rating = StarRating(
      value: value,
      onChanged: onChanged,
      semanticLabel: label,
      valueSemanticLabel: strings.ratingValue(value),
      starSemanticLabelBuilder: strings.selectStarRating,
      size: AppTheme.iconLg,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = AppTheme.usesLargeText(context);
          final stack = constraints.maxWidth < AppTheme.wideBreakpoint ||
              largeText;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelWidget,
                const SizedBox(height: AppTheme.spaceSm),
                rating,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: AppTheme.spaceMd),
              rating,
            ],
          );
        },
      ),
    );
  }
}

class _RecommendationControl extends StatelessWidget {
  const _RecommendationControl({
    required this.value,
    required this.yesLabel,
    required this.noLabel,
    required this.onChanged,
  });

  final bool? value;
  final String yesLabel;
  final String noLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = AppTheme.usesLargeText(context);
        final stack = constraints.maxWidth < AppTheme.wideBreakpoint ||
            largeText;
        final yes = _RecommendationButton(
          label: yesLabel,
          icon: Icons.thumb_up_alt_outlined,
          selected: value == true,
          onPressed: () => onChanged(true),
        );
        final no = _RecommendationButton(
          label: noLabel,
          icon: Icons.thumb_down_alt_outlined,
          selected: value == false,
          onPressed: () => onChanged(false),
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              yes,
              const SizedBox(height: AppTheme.spaceSm),
              no,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: yes),
            const SizedBox(width: AppTheme.spaceMd),
            Expanded(child: no),
          ],
        );
      },
    );
  }
}

class _RecommendationButton extends StatelessWidget {
  const _RecommendationButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    final color = selected
        ? selectedColor
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppTheme.iconMd),
        label: Text(label, textAlign: TextAlign.center),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: selected
              ? selectedColor.withValues(alpha: 0.11)
              : AppTheme.mutedSurfaceOf(context),
          side: BorderSide(
            color: selected ? selectedColor : theme.colorScheme.outline,
            width: selected ? 1.5 : 1,
          ),
          minimumSize: const Size(
            AppTheme.minTouchTarget,
            AppTheme.minTouchTarget,
          ),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    super.key,
    required this.strings,
    required this.onStartOver,
  });

  final AppStrings strings;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${strings.feedbackSuccessTitle}. ${strings.feedbackSuccessHint}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space2xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: AppTheme.iconXl,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              Text(
                strings.feedbackSuccessTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: AppTheme.weightExtraBold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                strings.feedbackSuccessHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppTheme.spaceXl),
              OutlinedButton.icon(
                onPressed: onStartOver,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.startOverButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
